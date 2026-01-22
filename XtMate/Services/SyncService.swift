import Foundation
import SwiftUI
import Combine

// MARK: - Sync Error Types

enum SyncError: Error, LocalizedError {
    case networkError
    case unauthorized
    case serverError(String)
    case encodingError
    case decodingError
    case invalidURL
    case noEstimateSelected
    case syncInProgress

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network error. Check your connection."
        case .unauthorized:
            return "Please sign in to sync."
        case .serverError(let message):
            return message
        case .encodingError:
            return "Failed to encode data for sync."
        case .decodingError:
            return "Failed to decode server response."
        case .invalidURL:
            return "Invalid server URL."
        case .noEstimateSelected:
            return "No estimate selected to sync."
        case .syncInProgress:
            return "Sync already in progress."
        }
    }
}

// MARK: - Sync Service

@MainActor
class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var isSyncing = false
    @Published var lastSyncError: String?
    @Published var lastSyncDate: Date?
    @Published var syncProgress: String = ""

    private var baseURL: String

    // Key for storing custom server URL
    private static let serverURLKey = "xtmate_server_url"

    /// Get or set the custom server URL for development
    var customServerURL: String? {
        get { UserDefaults.standard.string(forKey: Self.serverURLKey) }
        set {
            if let url = newValue, !url.isEmpty {
                UserDefaults.standard.set(url, forKey: Self.serverURLKey)
                baseURL = url
                print("🔄 SyncService: Using custom server URL: \(url)")
            } else {
                UserDefaults.standard.removeObject(forKey: Self.serverURLKey)
                baseURL = Self.defaultBaseURL
                print("🔄 SyncService: Reverted to default URL: \(baseURL)")
            }
        }
    }

    private static var defaultBaseURL: String {
        #if DEBUG
        // For simulator: localhost works
        // For physical device: user must set custom URL via settings
        return "http://localhost:3000/api"
        #else
        return "https://xtmate.vercel.app/api"
        #endif
    }

    /// Check if running on physical device (not simulator)
    static var isPhysicalDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    private init() {
        // Check for saved custom URL first
        if let savedURL = UserDefaults.standard.string(forKey: Self.serverURLKey), !savedURL.isEmpty {
            self.baseURL = savedURL
            print("🔄 SyncService: Loaded custom server URL: \(savedURL)")
        } else {
            self.baseURL = Self.defaultBaseURL
            #if DEBUG
            if Self.isPhysicalDevice {
                print("⚠️ SyncService: Running on physical device with localhost URL.")
                print("   Set a custom URL pointing to your Mac's IP address.")
                print("   Example: http://192.168.1.XXX:3000/api")
            }
            #endif
        }

        // Load last sync date from UserDefaults
        if let date = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date {
            self.lastSyncDate = date
        }
    }

    /// Get the current server URL (for display in settings)
    var currentServerURL: String {
        baseURL
    }

    // MARK: - Upload Estimate

    /// Upload a single estimate to the server
    func uploadEstimate(_ estimate: Estimate) async throws {
        guard !isSyncing else {
            throw SyncError.syncInProgress
        }

        isSyncing = true
        lastSyncError = nil
        syncProgress = "Preparing data..."

        defer {
            isSyncing = false
            syncProgress = ""
        }

        guard let url = URL(string: "\(baseURL)/sync/estimate") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token if available
        if let token = await AuthService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build sync payload
        syncProgress = "Encoding estimate..."
        let payload = buildSyncPayload(from: estimate)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let httpBody = try? encoder.encode(payload) else {
            throw SyncError.encodingError
        }
        request.httpBody = httpBody

        print("🔄 SyncService: Uploading estimate \(estimate.id)")
        print("   Rooms: \(estimate.rooms.count)")
        print("   Line Items: \(estimate.lineItems.count)")
        // Note: Assignments may not be on base Estimate model

        syncProgress = "Uploading to server..."

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SyncError.networkError
            }

            print("🔄 SyncService: Response status \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                throw SyncError.unauthorized
            }

            if !(200...299).contains(httpResponse.statusCode) {
                if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                    throw SyncError.serverError(errorResponse.error)
                }
                throw SyncError.serverError("Server error: \(httpResponse.statusCode)")
            }

            // Parse response
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            guard let syncResponse = try? decoder.decode(SyncUploadResponse.self, from: data) else {
                // Try to print response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("🔄 SyncService: Response body: \(responseString)")
                }
                throw SyncError.decodingError
            }

            lastSyncDate = ISO8601DateFormatter().date(from: syncResponse.syncedAt) ?? Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")

            print("🔄 SyncService: Upload complete at \(syncResponse.syncedAt)")

        } catch let error as SyncError {
            lastSyncError = error.localizedDescription
            throw error
        } catch {
            lastSyncError = error.localizedDescription
            throw SyncError.networkError
        }
    }

    // MARK: - Link Estimate by Job Number

    /// Link an estimate using a job number (e.g., "26-12345-E")
    /// Format: YY-#####-X where YY = year, ##### = claim number, X = assignment type
    func linkEstimateByCode(_ code: String) async throws -> DownloadedEstimate {
        guard !isSyncing else {
            throw SyncError.syncInProgress
        }

        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespaces)

        // Validate job number format: YY-####-X (exactly 4-digit claim number)
        let jobNumberPattern = #"^\d{2}-\d{4}-[EARPCZX]$"#
        guard let regex = try? NSRegularExpression(pattern: jobNumberPattern, options: .caseInsensitive),
              regex.firstMatch(in: normalizedCode, options: [], range: NSRange(normalizedCode.startIndex..., in: normalizedCode)) != nil else {
            throw SyncError.serverError("Invalid job number format. Expected: YY-####-X (e.g., 26-1234-E)")
        }

        isSyncing = true
        lastSyncError = nil
        syncProgress = "Looking up job number..."

        defer {
            isSyncing = false
            syncProgress = ""
        }

        // URL encode the job number in case of special characters
        guard let encodedCode = normalizedCode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/estimates/by-code/\(encodedCode)") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await AuthService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        print("🔗 SyncService: Looking up job number \(normalizedCode)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SyncError.networkError
            }

            print("🔗 SyncService: Response status \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                throw SyncError.unauthorized
            }

            if httpResponse.statusCode == 404 {
                throw SyncError.serverError("Job number not found. Check the number and try again.")
            }

            if httpResponse.statusCode == 403 {
                throw SyncError.serverError("You don't have access to this estimate.")
            }

            if !(200...299).contains(httpResponse.statusCode) {
                if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                    throw SyncError.serverError(errorResponse.error)
                }
                throw SyncError.serverError("Server error: \(httpResponse.statusCode)")
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            guard let downloadResponse = try? decoder.decode(DownloadedEstimate.self, from: data) else {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("🔗 SyncService: Response body: \(responseString)")
                }
                throw SyncError.decodingError
            }

            print("🔗 SyncService: Found estimate '\(downloadResponse.estimate.name)' with \(downloadResponse.rooms.count) rooms")
            return downloadResponse

        } catch let error as SyncError {
            lastSyncError = error.localizedDescription
            throw error
        } catch {
            lastSyncError = error.localizedDescription
            throw SyncError.networkError
        }
    }

    // MARK: - Download Estimate

    /// Download a single estimate from the server
    func downloadEstimate(_ estimateId: UUID) async throws -> DownloadedEstimate {
        guard !isSyncing else {
            throw SyncError.syncInProgress
        }

        isSyncing = true
        lastSyncError = nil
        syncProgress = "Downloading..."

        defer {
            isSyncing = false
            syncProgress = ""
        }

        guard let url = URL(string: "\(baseURL)/sync/estimate/\(estimateId.uuidString)") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await AuthService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        print("🔄 SyncService: Downloading estimate \(estimateId)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SyncError.networkError
            }

            if httpResponse.statusCode == 401 {
                throw SyncError.unauthorized
            }

            if httpResponse.statusCode == 404 {
                throw SyncError.serverError("Estimate not found on server")
            }

            if !(200...299).contains(httpResponse.statusCode) {
                throw SyncError.serverError("Server error: \(httpResponse.statusCode)")
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            guard let downloadResponse = try? decoder.decode(DownloadedEstimate.self, from: data) else {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("🔄 SyncService: Response body: \(responseString)")
                }
                throw SyncError.decodingError
            }

            print("🔄 SyncService: Downloaded estimate with \(downloadResponse.rooms.count) rooms")
            return downloadResponse

        } catch let error as SyncError {
            lastSyncError = error.localizedDescription
            throw error
        } catch {
            lastSyncError = error.localizedDescription
            throw SyncError.networkError
        }
    }

    // MARK: - Fetch Server Estimates List

    /// Fetch list of estimates from server for comparison
    func fetchServerEstimatesList() async throws -> [ServerEstimateSummary] {
        guard let url = URL(string: "\(baseURL)/sync/estimate") else {
            print("🔄 SyncService: Invalid URL")
            throw SyncError.invalidURL
        }

        print("🔄 SyncService: Fetching from \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = await AuthService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("🔄 SyncService: Added auth token")
        } else {
            print("🔄 SyncService: No auth token available")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("🔄 SyncService: Invalid response type")
                throw SyncError.networkError
            }

            print("🔄 SyncService: Response status \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                throw SyncError.unauthorized
            }

            if !(200...299).contains(httpResponse.statusCode) {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("🔄 SyncService: Error response: \(responseString)")
                }
                throw SyncError.serverError("Server error: \(httpResponse.statusCode)")
            }

            if let responseString = String(data: data, encoding: .utf8) {
                print("🔄 SyncService: Response: \(responseString.prefix(500))")
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let listResponse = try decoder.decode(EstimatesListResponse.self, from: data)
            return listResponse.estimates
        } catch let urlError as URLError {
            print("🔄 SyncService: URL Error: \(urlError.localizedDescription) code: \(urlError.code)")
            throw SyncError.networkError
        }
    }

    // MARK: - Sync All

    /// Sync all local estimates to server
    func syncAll(store: EstimateStore) async {
        guard !isSyncing else { return }

        isSyncing = true
        lastSyncError = nil

        defer {
            isSyncing = false
            syncProgress = ""
        }

        var successCount = 0
        var errorCount = 0

        for (index, estimate) in store.estimates.enumerated() {
            syncProgress = "Syncing \(index + 1) of \(store.estimates.count)..."

            do {
                // Reset syncing flag for each estimate since we set it in uploadEstimate
                isSyncing = true

                try await uploadEstimateInternal(estimate)
                successCount += 1

                // Mark as synced in store
                store.markSynced(estimate.id)

            } catch {
                errorCount += 1
                print("🔄 SyncService: Failed to sync estimate \(estimate.id): \(error)")
            }
        }

        if errorCount > 0 {
            lastSyncError = "Synced \(successCount) estimates, \(errorCount) failed"
        } else {
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
        }

        print("🔄 SyncService: Sync complete. Success: \(successCount), Errors: \(errorCount)")
    }

    // MARK: - Smart Bidirectional Sync

    /// Perform smart bidirectional sync - compares timestamps to determine direction
    func smartSync(store: EstimateStore) async {
        guard !isSyncing else { return }

        isSyncing = true
        lastSyncError = nil
        syncProgress = "Comparing with server..."

        defer {
            isSyncing = false
            syncProgress = ""
        }

        do {
            // Get list of server estimates with their timestamps
            let serverList = try await fetchServerEstimatesList()
            print("🔄 SyncService: Found \(serverList.count) estimates on server")

            var uploadedCount = 0
            var downloadedCount = 0
            var newFromServer = 0
            var newToServer = 0

            // Create lookup for server estimates
            var serverEstimates: [UUID: ServerEstimateSummary] = [:]
            for serverEst in serverList {
                if let id = UUID(uuidString: serverEst.id) {
                    serverEstimates[id] = serverEst
                }
            }

            // Process local estimates - upload if newer
            for (index, localEstimate) in store.estimates.enumerated() {
                syncProgress = "Processing \(index + 1) of \(store.estimates.count + serverList.count)..."

                if let serverEst = serverEstimates[localEstimate.id] {
                    // Exists on both sides - compare timestamps
                    let serverDate = parseISO8601(serverEst.updatedAt)

                    if localEstimate.updatedAt > serverDate {
                        // Local is newer - upload
                        print("🔄 SyncService: Local newer for \(localEstimate.name), uploading...")
                        try await uploadEstimateInternal(localEstimate)
                        uploadedCount += 1
                    } else if serverDate > localEstimate.updatedAt {
                        // Server is newer - download
                        print("🔄 SyncService: Server newer for \(localEstimate.name), downloading...")
                        let downloaded = try await downloadEstimateInternal(localEstimate.id)
                        if let updatedEstimate = convertToLocalEstimate(downloaded) {
                            store.estimates[index] = updatedEstimate
                            downloadedCount += 1
                        }
                    } else {
                        print("🔄 SyncService: \(localEstimate.name) is in sync")
                    }

                    // Remove from server list - we've processed it
                    serverEstimates.removeValue(forKey: localEstimate.id)
                } else {
                    // Only exists locally - upload to server
                    print("🔄 SyncService: New local estimate \(localEstimate.name), uploading...")
                    try await uploadEstimateInternal(localEstimate)
                    newToServer += 1
                }
            }

            // Download remaining server estimates (ones we don't have locally)
            for (estimateId, _) in serverEstimates {
                syncProgress = "Downloading new from server..."

                print("🔄 SyncService: New server estimate \(estimateId), downloading...")
                let downloaded = try await downloadEstimateInternal(estimateId)
                if let newEstimate = convertToLocalEstimate(downloaded) {
                    store.addEstimate(newEstimate)
                    newFromServer += 1
                }
            }

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")

            let summary = "Sync complete: ↑\(uploadedCount + newToServer) ↓\(downloadedCount + newFromServer)"
            print("🔄 SyncService: \(summary)")

        } catch {
            lastSyncError = error.localizedDescription
            print("🔄 SyncService: Sync failed: \(error)")
        }
    }

    /// Parse ISO8601 date string, returns distant past if invalid
    private func parseISO8601(_ dateString: String?) -> Date {
        guard let str = dateString else { return Date.distantPast }
        return ISO8601DateFormatter().date(from: str) ?? Date.distantPast
    }

    // MARK: - Download All from Server (Force Download)

    /// Force download all estimates from server (overwrites local)
    func downloadAllFromServer(store: EstimateStore) async {
        guard !isSyncing else { return }

        isSyncing = true
        lastSyncError = nil
        syncProgress = "Fetching from server..."

        defer {
            isSyncing = false
            syncProgress = ""
        }

        do {
            // Get list of server estimates
            let serverList = try await fetchServerEstimatesList()
            print("🔄 SyncService: Found \(serverList.count) estimates on server")

            var downloadedCount = 0
            var newCount = 0

            for (index, serverEstimate) in serverList.enumerated() {
                syncProgress = "Downloading \(index + 1) of \(serverList.count)..."

                guard let estimateId = UUID(uuidString: serverEstimate.id) else { continue }

                // Check if we already have this estimate locally
                let existsLocally = store.estimates.contains { $0.id == estimateId }

                // Download the full estimate
                let downloaded = try await downloadEstimateInternal(estimateId)

                // Convert to local Estimate model
                if let localEstimate = convertToLocalEstimate(downloaded) {
                    if existsLocally {
                        // Update existing - remove old and add new
                        if let index = store.estimates.firstIndex(where: { $0.id == estimateId }) {
                            store.estimates[index] = localEstimate
                        }
                        downloadedCount += 1
                    } else {
                        // Add new
                        store.addEstimate(localEstimate)
                        newCount += 1
                    }
                }
            }

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")

            print("🔄 SyncService: Downloaded \(downloadedCount) updates, \(newCount) new estimates")

        } catch {
            lastSyncError = error.localizedDescription
            print("🔄 SyncService: Download failed: \(error)")
        }
    }

    // MARK: - P3B-7: Photo Upload

    /// Upload an estimate photo to the server
    /// Returns PhotoUploadResponse with remote URL on success
    func uploadEstimatePhoto(
        estimateId: UUID,
        roomId: UUID?,
        annotationId: UUID?,
        photoId: UUID,
        photoType: String,
        caption: String,
        imageData: Data
    ) async throws -> PhotoUploadResponse {
        guard let url = URL(string: "\(baseURL)/photos/upload") else {
            throw SyncError.invalidURL
        }

        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = await AuthService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()

        // Add metadata fields
        let fields: [(String, String)] = [
            ("id", photoId.uuidString),
            ("estimateId", estimateId.uuidString),
            ("roomId", roomId?.uuidString ?? ""),
            ("annotationId", annotationId?.uuidString ?? ""),
            ("type", photoType),
            ("caption", caption),
            ("takenAt", ISO8601DateFormatter().string(from: Date()))
        ]

        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // Add image data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(photoId.uuidString).jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Final boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        print("📸 SyncService: Uploading photo \(photoId) for estimate \(estimateId)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw SyncError.unauthorized
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw SyncError.serverError(errorResponse.error)
            }
            throw SyncError.serverError("Photo upload failed: \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        guard let uploadResponse = try? decoder.decode(PhotoUploadResponse.self, from: data) else {
            throw SyncError.decodingError
        }

        print("📸 SyncService: Photo uploaded successfully, URL: \(uploadResponse.remoteUrl)")
        return uploadResponse
    }

    /// Internal download without state management
    private func downloadEstimateInternal(_ estimateId: UUID) async throws -> DownloadedEstimate {
        guard let url = URL(string: "\(baseURL)/sync/estimate/\(estimateId.uuidString)") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = await AuthService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SyncError.networkError
        }

        let decoder = JSONDecoder()
        return try decoder.decode(DownloadedEstimate.self, from: data)
    }

    /// Convert downloaded DTO to local Estimate model
    private func convertToLocalEstimate(_ downloaded: DownloadedEstimate) -> Estimate? {
        guard let id = UUID(uuidString: downloaded.estimate.id) else { return nil }

        // Convert rooms
        let rooms: [Room] = downloaded.rooms.compactMap { roomDTO in
            guard let roomId = UUID(uuidString: roomDTO.id) else { return nil }

            let annotations: [DamageAnnotation] = (roomDTO.annotations ?? []).compactMap { annDTO in
                guard let annId = UUID(uuidString: annDTO.id) else { return nil }
                return DamageAnnotation(
                    id: annId,
                    position: CGPoint(x: annDTO.positionX ?? 0.5, y: annDTO.positionY ?? 0.5),
                    damageType: DamageType(rawValue: annDTO.damageType) ?? .water,
                    severity: DamageSeverity(rawValue: annDTO.severity) ?? .moderate,
                    affectedSurfaces: Set(annDTO.affectedSurfaces.compactMap { AffectedSurface(rawValue: $0) }),
                    affectedHeightIn: annDTO.affectedHeightIn,
                    notes: annDTO.notes ?? ""
                )
            }

            return Room(
                id: roomId,
                name: roomDTO.name,
                category: RoomCategory(rawValue: roomDTO.category ?? "Other") ?? .other,
                floor: FloorLevel(rawValue: roomDTO.floor ?? "1") ?? .first,
                floorMaterial: roomDTO.floorMaterial.flatMap { FloorMaterial(rawValue: $0) },
                wallMaterial: roomDTO.wallMaterial.flatMap { WallMaterial(rawValue: $0) },
                ceilingMaterial: roomDTO.ceilingMaterial.flatMap { CeilingMaterial(rawValue: $0) },
                lengthIn: roomDTO.lengthIn ?? 0,
                widthIn: roomDTO.widthIn ?? 0,
                heightIn: roomDTO.heightIn ?? 0,
                annotations: annotations
            )
        }

        // Convert line items
        let lineItems: [ScopeLineItem] = downloaded.lineItems.compactMap { itemDTO in
            guard let itemId = UUID(uuidString: itemDTO.id) else { return nil }
            return ScopeLineItem(
                id: itemId,
                category: itemDTO.category,
                selector: itemDTO.selector,
                description: itemDTO.description,
                quantity: itemDTO.quantity,
                unit: itemDTO.unit,
                unitPrice: itemDTO.unitPrice ?? 0,
                roomId: itemDTO.roomId.flatMap { UUID(uuidString: $0) },
                annotationId: itemDTO.annotationId.flatMap { UUID(uuidString: $0) },
                source: LineItemSource(rawValue: itemDTO.source ?? "manual") ?? .manual,
                notes: itemDTO.notes ?? "",
                order: itemDTO.order ?? 0
            )
        }

        // Convert assignments
        let _: [Assignment] = downloaded.assignments.compactMap { assDTO in
            guard let assId = UUID(uuidString: assDTO.id) else { return nil }
            return Assignment(
                id: assId,
                estimateId: id,
                type: AssignmentType(rawValue: assDTO.type) ?? .emergency,
                status: AssignmentStatus(rawValue: assDTO.status ?? "pending") ?? .pending,
                subtotal: assDTO.subtotal ?? 0,
                overhead: assDTO.overhead ?? 0,
                profit: assDTO.profit ?? 0,
                tax: assDTO.tax ?? 0,
                total: assDTO.total ?? 0,
                notes: assDTO.notes ?? "",
                order: assDTO.order ?? 0
            )
        }

        // Create a basic estimate with the available properties
        // Note: This will need to be adjusted based on actual Estimate initializer
        // For now, create with minimal required fields
        let estimate = Estimate(
            id: id,
            name: downloaded.estimate.name,
            claimNumber: downloaded.estimate.claimNumber,
            policyNumber: downloaded.estimate.policyNumber,
            insuredName: downloaded.estimate.insuredName,
            propertyAddress: downloaded.estimate.propertyAddress,
            causeOfLoss: downloaded.estimate.causeOfLoss ?? "Water",
            status: EstimateStatus(rawValue: downloaded.estimate.status ?? "Draft") ?? .draft,
            rooms: rooms,
            lineItems: lineItems
        )
        
        // Set additional properties if available (using property setters if Estimate is mutable)
        // Note: Adjust based on actual Estimate property definitions
        return estimate
    }

    // MARK: - Private Helpers

    /// Internal upload without sync state management (for batch operations)
    private func uploadEstimateInternal(_ estimate: Estimate) async throws {
        guard let url = URL(string: "\(baseURL)/sync/estimate") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await AuthService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload = buildSyncPayload(from: estimate)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw SyncError.serverError(errorResponse.error)
            }
            throw SyncError.networkError
        }
    }

    /// Build sync payload from local Estimate
    private func buildSyncPayload(from estimate: Estimate) -> SyncPayload {
        let dateFormatter = ISO8601DateFormatter()

        let estimateDTO = EstimateDTO(
            id: estimate.id.uuidString,
            shortCode: nil,  // Generated on server
            name: estimate.name,
            claimNumber: estimate.claimNumber,
            policyNumber: estimate.policyNumber,
            insuredName: estimate.insuredName,
            insuredPhone: estimate.insuredPhone,
            insuredEmail: estimate.insuredEmail,
            propertyAddress: estimate.propertyAddress,
            propertyCity: estimate.propertyCity,
            propertyState: estimate.propertyState,
            propertyZip: estimate.propertyZip,
            causeOfLoss: estimate.causeOfLoss,
            status: estimate.status.rawValue,
            jobType: estimate.jobType.rawValue,
            xaId: estimate.xaId,
            dispatchType: estimate.dispatchType?.rawValue,
            dateOfLoss: estimate.dateOfLoss.map { dateFormatter.string(from: $0) },
            adjusterName: estimate.adjusterName,
            adjusterPhone: estimate.adjusterPhone,
            adjusterEmail: estimate.adjusterEmail,
            insuranceCompany: estimate.insuranceCompany,
            latitude: estimate.latitude,
            longitude: estimate.longitude,
            updatedAt: dateFormatter.string(from: estimate.updatedAt),
            createdAt: dateFormatter.string(from: estimate.createdAt)
        )

        let roomDTOs = estimate.rooms.enumerated().map { index, room in
            RoomDTO(
                id: room.id.uuidString,
                name: room.name,
                category: room.category.rawValue,
                floor: room.floor.rawValue,
                lengthIn: room.lengthIn,
                widthIn: room.widthIn,
                heightIn: room.heightIn,
                squareFeet: room.squareFeet,
                wallSf: room.wallSf,
                wallCount: room.wallCount,
                doorCount: room.doorCount,
                windowCount: room.windowCount,
                floorMaterial: room.floorMaterial?.rawValue,
                wallMaterial: room.wallMaterial?.rawValue,
                ceilingMaterial: room.ceilingMaterial?.rawValue,
                annotations: room.annotations.map { ann in
                    AnnotationDTO(
                        id: ann.id.uuidString,
                        damageType: ann.damageType.rawValue,
                        severity: ann.severity.rawValue,
                        affectedSurfaces: ann.affectedSurfaces.map { $0.rawValue },
                        affectedHeightIn: ann.affectedHeightIn,
                        notes: ann.notes,
                        positionX: ann.position.x,
                        positionY: ann.position.y
                    )
                },
                order: index
            )
        }

        let lineItemDTOs = estimate.lineItems.enumerated().map { index, item in
            LineItemDTO(
                id: item.id.uuidString,
                category: item.category,
                selector: item.selector,
                description: item.description,
                quantity: item.quantity,
                unit: item.unit,
                unitPrice: item.unitPrice,
                total: item.unitPrice * item.quantity,
                roomId: item.roomId?.uuidString,
                annotationId: item.annotationId?.uuidString,
                source: item.source.rawValue,
                notes: item.notes,
                order: index
            )
        }

        let assignmentDTOs = estimate.assignments.enumerated().map { index, assignment in
            AssignmentDTO(
                id: assignment.id.uuidString,
                type: assignment.type.rawValue,
                status: assignment.status.rawValue,
                subtotal: assignment.subtotal,
                overhead: assignment.overhead,
                profit: assignment.profit,
                tax: assignment.tax,
                total: assignment.total,
                notes: assignment.notes,
                order: index
            )
        }

        return SyncPayload(
            estimate: estimateDTO,
            rooms: roomDTOs,
            lineItems: lineItemDTOs,
            assignments: assignmentDTOs
        )
    }
}

// MARK: - API Response Types

struct SyncUploadResponse: Codable {
    let success: Bool
    let syncedAt: String
}

/// P3B-7: Photo upload response from server
struct PhotoUploadResponse: Codable {
    let success: Bool
    let photoId: String
    let remoteUrl: String
}

struct EstimatesListResponse: Codable {
    let estimates: [ServerEstimateSummary]
}

struct ServerEstimateSummary: Codable {
    let id: String
    let name: String
    let updatedAt: String?
    let status: String?
}

// MARK: - Sync Payload DTOs

struct SyncPayload: Codable {
    let estimate: EstimateDTO
    let rooms: [RoomDTO]
    let lineItems: [LineItemDTO]
    let assignments: [AssignmentDTO]
}

struct EstimateDTO: Codable {
    let id: String
    let shortCode: String?
    let name: String
    let claimNumber: String?
    let policyNumber: String?
    let insuredName: String?
    let insuredPhone: String?
    let insuredEmail: String?
    let propertyAddress: String?
    let propertyCity: String?
    let propertyState: String?
    let propertyZip: String?
    let causeOfLoss: String?
    let status: String?
    let jobType: String?
    let xaId: String?
    let dispatchType: String?
    let dateOfLoss: String?
    let adjusterName: String?
    let adjusterPhone: String?
    let adjusterEmail: String?
    let insuranceCompany: String?
    let latitude: Double?
    let longitude: Double?
    let updatedAt: String?  // ISO8601 timestamp for sync conflict resolution
    let createdAt: String?
}

struct RoomDTO: Codable {
    let id: String
    let name: String
    let category: String?
    let floor: String?
    let lengthIn: Double?
    let widthIn: Double?
    let heightIn: Double?
    let squareFeet: Double?
    let wallSf: Double?
    let wallCount: Int?
    let doorCount: Int?
    let windowCount: Int?
    let floorMaterial: String?
    let wallMaterial: String?
    let ceilingMaterial: String?
    let annotations: [AnnotationDTO]?
    let order: Int?
}

struct AnnotationDTO: Codable {
    let id: String
    let damageType: String
    let severity: String
    let affectedSurfaces: [String]
    let affectedHeightIn: Double?
    let notes: String?
    let positionX: Double?
    let positionY: Double?
}

struct LineItemDTO: Codable {
    let id: String
    let category: String
    let selector: String
    let description: String
    let quantity: Double
    let unit: String
    let unitPrice: Double?
    let total: Double?
    let roomId: String?
    let annotationId: String?
    let source: String?
    let notes: String?
    let order: Int?
}

struct AssignmentDTO: Codable {
    let id: String
    let type: String
    let status: String?
    let subtotal: Double?
    let overhead: Double?
    let profit: Double?
    let tax: Double?
    let total: Double?
    let notes: String?
    let order: Int?
}

// MARK: - Download Response Types

struct DownloadedEstimate: Codable {
    let estimate: EstimateDTO
    let rooms: [RoomDTO]
    let lineItems: [LineItemDTO]
    let assignments: [AssignmentDTO]
}
