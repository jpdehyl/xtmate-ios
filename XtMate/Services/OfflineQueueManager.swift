import Foundation
import UIKit
import Combine

// MARK: - Offline Queue Manager

/// Manages queuing of failed requests for later retry when connectivity returns
/// Persists queue to disk to survive app restarts
@MainActor
class OfflineQueueManager: ObservableObject {
    static let shared = OfflineQueueManager()

    // Allow objectWillChange to be accessed from any context
    nonisolated let objectWillChange = ObservableObjectPublisher()

    // MARK: - Published State

    @Published var pendingItems: [QueuedItem] = [] {
        willSet { objectWillChange.send() }
    }
    @Published var isSyncing = false {
        willSet { objectWillChange.send() }
    }
    @Published var lastSyncError: String? {
        willSet { objectWillChange.send() }
    }

    // MARK: - Private Properties

    private let queueKey = "xtmate_offline_queue"
    private let photosDirectory: URL
    private var networkMonitor: NetworkMonitor?

    // MARK: - Init

    private init() {
        // Create photos directory for offline storage
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        photosDirectory = documentsPath.appendingPathComponent("OfflinePhotos", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create offline photos directory: \(error)")
        }

        // Load persisted queue
        loadQueue()

        // Start network monitoring
        setupNetworkMonitoring()
    }

    // MARK: - Queue Management

    /// Queue a photo upload for later
    func queuePhotoUpload(workOrderId: UUID, itemId: UUID, photos: [UIImage]) async {
        for (index, photo) in photos.enumerated() {
            // Save photo to disk
            let photoId = UUID()
            let photoPath = photosDirectory.appendingPathComponent("\(photoId.uuidString).jpg")

            if let data = photo.jpegData(compressionQuality: 0.8) {
                do {
                    try data.write(to: photoPath)

                    let item = QueuedItem(
                        id: UUID(),
                        type: .photoUpload,
                        workOrderId: workOrderId,
                        itemId: itemId,
                        localPhotoPath: photoPath.path,
                        createdAt: Date(),
                        retryCount: 0
                    )

                    pendingItems.append(item)
                    print("Queued photo \(index + 1) for offline upload: \(photoId)")
                } catch {
                    print("Failed to save photo for offline queue: \(error)")
                }
            }
        }

        saveQueue()
    }

    /// Queue a work order status update
    func queueStatusUpdate(workOrderId: UUID, status: String, additionalData: [String: Any]? = nil) {
        let item = QueuedItem(
            id: UUID(),
            type: .statusUpdate,
            workOrderId: workOrderId,
            status: status,
            additionalData: additionalData,
            createdAt: Date(),
            retryCount: 0
        )

        pendingItems.append(item)
        saveQueue()
        print("Queued status update for offline sync: \(workOrderId)")
    }

    /// Queue a clock in/out action
    func queueClockAction(workOrderId: UUID, action: ClockAction, breakMinutes: Int? = nil) {
        var additionalData: [String: Any]? = nil
        if let breakMinutes = breakMinutes {
            additionalData = ["breakMinutes": breakMinutes]
        }

        let item = QueuedItem(
            id: UUID(),
            type: action == .clockIn ? .clockIn : .clockOut,
            workOrderId: workOrderId,
            additionalData: additionalData,
            createdAt: Date(),
            retryCount: 0
        )

        pendingItems.append(item)
        saveQueue()
        print("Queued clock action for offline sync: \(action)")
    }

    /// Queue a task completion
    func queueTaskCompletion(workOrderId: UUID, itemId: UUID, status: String, notes: String? = nil) {
        var additionalData: [String: Any] = ["status": status]
        if let notes = notes {
            additionalData["completionNotes"] = notes
        }

        let item = QueuedItem(
            id: UUID(),
            type: .taskUpdate,
            workOrderId: workOrderId,
            itemId: itemId,
            additionalData: additionalData,
            createdAt: Date(),
            retryCount: 0
        )

        pendingItems.append(item)
        saveQueue()
        print("Queued task completion for offline sync: \(itemId)")
    }

    // MARK: - P3B-7: Estimate Photo Queue

    /// Queue an estimate photo for upload
    /// This is for photos attached to estimates/rooms/annotations, not work orders
    func queueEstimatePhoto(
        estimateId: UUID,
        roomId: UUID?,
        annotationId: UUID?,
        photo: Photo,
        localPhotoPath: String
    ) async {
        // Build additional data with photo metadata
        var additionalData: [String: Any] = [
            "photoId": photo.id.uuidString,
            "photoType": photo.type.rawValue,
            "caption": photo.caption,
            "takenAt": ISO8601DateFormatter().string(from: photo.takenAt)
        ]

        if let roomId = roomId {
            additionalData["roomId"] = roomId.uuidString
        }
        if let annotationId = annotationId {
            additionalData["annotationId"] = annotationId.uuidString
        }
        if let lat = photo.latitude {
            additionalData["latitude"] = lat
        }
        if let lon = photo.longitude {
            additionalData["longitude"] = lon
        }

        let item = QueuedItem(
            id: UUID(),
            type: .estimatePhoto,
            workOrderId: estimateId,  // Repurposing workOrderId for estimateId
            itemId: photo.id,
            localPhotoPath: localPhotoPath,
            additionalData: additionalData,
            createdAt: Date(),
            retryCount: 0
        )

        pendingItems.append(item)
        saveQueue()
        print("📸 OfflineQueue: Queued estimate photo for sync - estimateId: \(estimateId), photoId: \(photo.id)")
    }

    // MARK: - Sync

    /// Process all queued items
    func processQueue() async {
        guard !isSyncing else { return }
        guard !pendingItems.isEmpty else { return }
        guard NetworkMonitor.shared.isConnected else {
            print("Network not available, skipping queue processing")
            return
        }

        isSyncing = true
        lastSyncError = nil

        let workOrderService = WorkOrderService.shared
        var processedItems: [UUID] = []
        var failedItems: [(UUID, String)] = []

        for item in pendingItems {
            do {
                switch item.type {
                case .photoUpload:
                    try await processPhotoUpload(item, service: workOrderService)
                    processedItems.append(item.id)

                case .statusUpdate:
                    try await processStatusUpdate(item, service: workOrderService)
                    processedItems.append(item.id)

                case .clockIn:
                    _ = try await workOrderService.clockIn(workOrderId: item.workOrderId)
                    processedItems.append(item.id)

                case .clockOut:
                    let breakMinutes = item.additionalData?["breakMinutes"] as? Int ?? 0
                    _ = try await workOrderService.clockOut(workOrderId: item.workOrderId, breakMinutes: breakMinutes)
                    processedItems.append(item.id)

                case .taskUpdate:
                    try await processTaskUpdate(item, service: workOrderService)
                    processedItems.append(item.id)

                case .estimatePhoto:
                    try await processEstimatePhotoUpload(item)
                    processedItems.append(item.id)
                }

                print("Successfully processed queued item: \(item.id)")
            } catch {
                // Increment retry count
                if let index = pendingItems.firstIndex(where: { $0.id == item.id }) {
                    pendingItems[index].retryCount += 1

                    // Remove items that have failed too many times
                    if pendingItems[index].retryCount >= 5 {
                        failedItems.append((item.id, error.localizedDescription))
                        processedItems.append(item.id) // Remove from queue
                        print("Giving up on queued item after 5 retries: \(item.id)")
                    }
                }

                print("Failed to process queued item: \(error)")
            }
        }

        // Remove processed items
        pendingItems.removeAll { processedItems.contains($0.id) }

        // Clean up photo files for processed items
        for itemId in processedItems {
            if let item = pendingItems.first(where: { $0.id == itemId }),
               let photoPath = item.localPhotoPath {
                try? FileManager.default.removeItem(atPath: photoPath)
            }
        }

        saveQueue()
        isSyncing = false

        if !failedItems.isEmpty {
            lastSyncError = "Failed to sync \(failedItems.count) items"
        }

        // Provide haptic feedback
        if !processedItems.isEmpty {
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(failedItems.isEmpty ? .success : .warning)
        }
    }

    // MARK: - Private Helpers

    private func processPhotoUpload(_ item: QueuedItem, service: WorkOrderService) async throws {
        guard let photoPath = item.localPhotoPath,
              let itemId = item.itemId else {
            throw OfflineQueueError.invalidItem
        }

        let photoURL = URL(fileURLWithPath: photoPath)
        guard let imageData = try? Data(contentsOf: photoURL),
              let image = UIImage(data: imageData) else {
            throw OfflineQueueError.photoNotFound
        }

        _ = try await service.uploadTaskPhoto(
            workOrderId: item.workOrderId,
            itemId: itemId,
            image: image
        )

        // Clean up the local file after successful upload
        try? FileManager.default.removeItem(at: photoURL)
    }

    private func processStatusUpdate(_ item: QueuedItem, service: WorkOrderService) async throws {
        guard let status = item.status else {
            throw OfflineQueueError.invalidItem
        }

        var updates: [String: Any] = ["status": status]
        if let additionalData = item.additionalData {
            for (key, value) in additionalData {
                updates[key] = value
            }
        }

        _ = try await service.updateWorkOrder(id: item.workOrderId, updates: updates)
    }

    private func processTaskUpdate(_ item: QueuedItem, service: WorkOrderService) async throws {
        guard let itemId = item.itemId,
              let statusString = item.additionalData?["status"] as? String,
              let status = WorkOrderItemStatus(rawValue: statusString) else {
            throw OfflineQueueError.invalidItem
        }

        let notes = item.additionalData?["completionNotes"] as? String

        _ = try await service.updateItemStatus(
            workOrderId: item.workOrderId,
            itemId: itemId,
            status: status,
            notes: notes
        )
    }

    /// P3B-7: Process estimate photo upload with exponential backoff
    private func processEstimatePhotoUpload(_ item: QueuedItem) async throws {
        guard let photoPath = item.localPhotoPath,
              let photoIdString = item.additionalData?["photoId"]?.value as? String,
              let photoId = UUID(uuidString: photoIdString) else {
            throw OfflineQueueError.invalidItem
        }

        let photoURL = URL(fileURLWithPath: photoPath)
        guard let imageData = try? Data(contentsOf: photoURL) else {
            throw OfflineQueueError.photoNotFound
        }

        // Calculate exponential backoff delay
        if item.retryCount > 0 {
            let delay = pow(2.0, Double(item.retryCount))
            print("📸 OfflineQueue: Waiting \(delay)s before retry (attempt \(item.retryCount + 1))")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        // Upload via SyncService
        let estimateId = item.workOrderId // We repurposed workOrderId for estimateId
        let roomIdString = item.additionalData?["roomId"]?.value as? String
        let annotationIdString = item.additionalData?["annotationId"]?.value as? String
        let photoType = item.additionalData?["photoType"]?.value as? String ?? "DAMAGE"
        let caption = item.additionalData?["caption"]?.value as? String ?? ""

        let response = try await SyncService.shared.uploadEstimatePhoto(
            estimateId: estimateId,
            roomId: roomIdString.flatMap { UUID(uuidString: $0) },
            annotationId: annotationIdString.flatMap { UUID(uuidString: $0) },
            photoId: photoId,
            photoType: photoType,
            caption: caption,
            imageData: imageData
        )

        // Update PhotoService with remote URL
        await PhotoService.shared.markAsUploaded(photoId, remoteUrl: response.remoteUrl)

        // Clean up the local file after successful upload
        try? FileManager.default.removeItem(at: photoURL)

        print("📸 OfflineQueue: Successfully uploaded estimate photo: \(photoId)")
    }

    // MARK: - Persistence

    private func saveQueue() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(pendingItems)
            UserDefaults.standard.set(data, forKey: queueKey)
            print("Saved \(pendingItems.count) items to offline queue")
        } catch {
            print("Failed to save offline queue: \(error)")
        }
    }

    private func loadQueue() {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            pendingItems = try decoder.decode([QueuedItem].self, from: data)
            print("Loaded \(pendingItems.count) items from offline queue")
        } catch {
            print("Failed to load offline queue: \(error)")
        }
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        // Observe network changes
        Task {
            for await isConnected in NetworkMonitor.shared.$isConnected.values {
                if isConnected && !pendingItems.isEmpty {
                    print("Network restored, processing offline queue...")
                    await processQueue()
                }
            }
        }
    }

    /// Clear the entire queue (for testing/debugging)
    func clearQueue() {
        pendingItems.removeAll()

        // Remove all offline photos
        if let files = try? FileManager.default.contentsOfDirectory(at: photosDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }

        saveQueue()
        print("Cleared offline queue")
    }

    /// Get queue status summary
    var statusSummary: String {
        guard !pendingItems.isEmpty else { return "No pending items" }

        let photoCount = pendingItems.filter { $0.type == .photoUpload }.count
        let statusCount = pendingItems.filter { $0.type == .statusUpdate }.count
        let clockCount = pendingItems.filter { $0.type == .clockIn || $0.type == .clockOut }.count
        let taskCount = pendingItems.filter { $0.type == .taskUpdate }.count

        var parts: [String] = []
        if photoCount > 0 { parts.append("\(photoCount) photos") }
        if statusCount > 0 { parts.append("\(statusCount) status updates") }
        if clockCount > 0 { parts.append("\(clockCount) clock actions") }
        if taskCount > 0 { parts.append("\(taskCount) task updates") }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Queue Item Model

struct QueuedItem: Identifiable, Codable {
    let id: UUID
    let type: QueuedItemType
    let workOrderId: UUID
    var itemId: UUID?
    var status: String?
    var localPhotoPath: String?
    var additionalData: [String: AnyCodable]?
    let createdAt: Date
    var retryCount: Int
}

enum QueuedItemType: String, Codable {
    case photoUpload
    case statusUpdate
    case clockIn
    case clockOut
    case taskUpdate
    case estimatePhoto  // P3B-7: Photo upload for estimates (not work orders)
}

enum ClockAction {
    case clockIn
    case clockOut
}

// MARK: - AnyCodable for flexible additional data

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal.map { $0.value }
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let arrayVal = value as? [Any] {
            try container.encode(arrayVal.map { AnyCodable($0) })
        } else if let dictVal = value as? [String: Any] {
            try container.encode(dictVal.mapValues { AnyCodable($0) })
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// MARK: - Offline Queue Errors

enum OfflineQueueError: LocalizedError {
    case invalidItem
    case photoNotFound
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidItem:
            return "Invalid queue item"
        case .photoNotFound:
            return "Photo file not found"
        case .networkUnavailable:
            return "Network unavailable"
        }
    }
}

// MARK: - QueuedItem Extension for additionalData

extension QueuedItem {
    init(
        id: UUID,
        type: QueuedItemType,
        workOrderId: UUID,
        itemId: UUID? = nil,
        status: String? = nil,
        localPhotoPath: String? = nil,
        additionalData: [String: Any]? = nil,
        createdAt: Date,
        retryCount: Int
    ) {
        self.id = id
        self.type = type
        self.workOrderId = workOrderId
        self.itemId = itemId
        self.status = status
        self.localPhotoPath = localPhotoPath
        self.additionalData = additionalData?.mapValues { AnyCodable($0) }
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}
