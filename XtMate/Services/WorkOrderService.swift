import Foundation
import Combine
import UIKit

// MARK: - Work Order Service

/// Service for managing work orders and communicating with the API
@MainActor
class WorkOrderService: ObservableObject {
    static let shared = WorkOrderService()

    // MARK: - Published State

    @Published var workOrders: [WorkOrder] = []
    @Published var currentWorkOrder: WorkOrder?
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Private Properties

    private let baseURL: String
    private let authService = AuthService.shared

    // MARK: - Init

    private init() {
        // Get base URL from environment or use default
        #if DEBUG
        self.baseURL = "http://localhost:3000"
        #else
        self.baseURL = "https://xtmate-v3.vercel.app"
        #endif
    }

    // MARK: - Computed Properties

    /// Work orders scheduled for today
    var todayOrders: [WorkOrder] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return workOrders.filter { order in
            guard let scheduledDate = order.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: today) &&
                   order.status != .completed && order.status != .cancelled
        }.sorted { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }
    }

    /// Work orders scheduled for future dates
    var upcomingOrders: [WorkOrder] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return workOrders.filter { order in
            guard let scheduledDate = order.scheduledDate else { return false }
            return scheduledDate > today &&
                   !calendar.isDate(scheduledDate, inSameDayAs: today) &&
                   order.status != .completed && order.status != .cancelled
        }.sorted { ($0.scheduledDate ?? Date.distantFuture) < ($1.scheduledDate ?? Date.distantFuture) }
    }

    /// Completed work orders
    var completedOrders: [WorkOrder] {
        workOrders.filter { $0.status == .completed }
            .sorted { ($0.updatedAt) > ($1.updatedAt) }
    }

    // MARK: - API Methods

    /// Fetch work orders assigned to current user
    func fetchMyWorkOrders() async {
        guard let userId = authService.userId else {
            error = "Not signed in"
            return
        }

        isLoading = true
        error = nil

        do {
            let orders = try await fetchWorkOrders(assignedTo: userId)
            workOrders = orders
        } catch {
            self.error = error.localizedDescription
            print("Error fetching work orders: \(error)")
        }

        isLoading = false
    }

    /// Fetch work orders with optional filters
    func fetchWorkOrders(estimateId: UUID? = nil, assignedTo: String? = nil, status: WorkOrderStatus? = nil) async throws -> [WorkOrder] {
        var urlComponents = URLComponents(string: "\(baseURL)/api/work-orders")!
        var queryItems: [URLQueryItem] = []

        if let estimateId = estimateId {
            queryItems.append(URLQueryItem(name: "estimateId", value: estimateId.uuidString))
        }
        if let assignedTo = assignedTo {
            queryItems.append(URLQueryItem(name: "assignedTo", value: assignedTo))
        }
        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }

        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }

        guard let url = urlComponents.url else {
            throw WorkOrderError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = await authService.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkOrderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw WorkOrderError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let dtos = try decoder.decode([WorkOrderDTO].self, from: data)
        return dtos.compactMap { $0.toWorkOrder() }
    }

    /// Fetch a single work order by ID
    func fetchWorkOrder(id: UUID) async throws -> WorkOrder {
        let url = URL(string: "\(baseURL)/api/work-orders/\(id.uuidString)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = await authService.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkOrderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw WorkOrderError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let dto = try decoder.decode(WorkOrderDTO.self, from: data)

        guard let workOrder = dto.toWorkOrder() else {
            throw WorkOrderError.invalidData
        }

        return workOrder
    }

    /// Clock in to a work order
    /// Falls back to offline queue if network is unavailable
    func clockIn(workOrderId: UUID) async throws -> WorkOrder {
        // Check network availability
        guard NetworkMonitor.shared.isConnected else {
            // Queue for later and return optimistic local update
            await OfflineQueueManager.shared.queueClockAction(workOrderId: workOrderId, action: .clockIn)

            // Update local state optimistically
            if var order = workOrders.first(where: { $0.id == workOrderId }) {
                order.clockIn = Date()
                order.status = .inProgress
                updateLocalWorkOrder(order)
                return order
            }
            throw WorkOrderError.invalidData
        }

        let url = URL(string: "\(baseURL)/api/work-orders/\(workOrderId.uuidString)/clock")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await authService.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkOrderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorBody["error"] {
                throw WorkOrderError.serverError(errorMessage)
            }
            throw WorkOrderError.httpError(httpResponse.statusCode)
        }

        let dto = try JSONDecoder().decode(WorkOrderDTO.self, from: data)

        guard let workOrder = dto.toWorkOrder() else {
            throw WorkOrderError.invalidData
        }

        // Update local state
        updateLocalWorkOrder(workOrder)

        return workOrder
    }

    /// Clock out of a work order
    /// Falls back to offline queue if network is unavailable
    func clockOut(workOrderId: UUID, breakMinutes: Int = 0) async throws -> WorkOrder {
        // Check network availability
        guard NetworkMonitor.shared.isConnected else {
            // Queue for later and return optimistic local update
            await OfflineQueueManager.shared.queueClockAction(
                workOrderId: workOrderId,
                action: .clockOut,
                breakMinutes: breakMinutes
            )

            // Update local state optimistically
            if var order = workOrders.first(where: { $0.id == workOrderId }) {
                order.clockOut = Date()
                order.breakMinutes = breakMinutes
                if let clockIn = order.clockIn {
                    let elapsed = Date().timeIntervalSince(clockIn) - Double(breakMinutes * 60)
                    order.totalHours = elapsed / 3600.0
                }
                updateLocalWorkOrder(order)
                return order
            }
            throw WorkOrderError.invalidData
        }

        let url = URL(string: "\(baseURL)/api/work-orders/\(workOrderId.uuidString)/clock")!

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await authService.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = ["breakMinutes": breakMinutes]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkOrderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorBody["error"] {
                throw WorkOrderError.serverError(errorMessage)
            }
            throw WorkOrderError.httpError(httpResponse.statusCode)
        }

        let dto = try JSONDecoder().decode(WorkOrderDTO.self, from: data)

        guard let workOrder = dto.toWorkOrder() else {
            throw WorkOrderError.invalidData
        }

        // Update local state
        updateLocalWorkOrder(workOrder)

        return workOrder
    }

    /// Update work order item status
    /// Falls back to offline queue if network is unavailable
    func updateItemStatus(workOrderId: UUID, itemId: UUID, status: WorkOrderItemStatus, notes: String? = nil) async throws -> WorkOrder {
        // Check network availability
        guard NetworkMonitor.shared.isConnected else {
            // Queue for later and return optimistic local update
            await OfflineQueueManager.shared.queueTaskCompletion(
                workOrderId: workOrderId,
                itemId: itemId,
                status: status.rawValue,
                notes: notes
            )

            // Update local state optimistically
            if var order = workOrders.first(where: { $0.id == workOrderId }) {
                if let index = order.items.firstIndex(where: { $0.id == itemId }) {
                    order.items[index].status = status
                    order.items[index].completedAt = status == .completed ? Date() : nil
                    order.items[index].completionNotes = notes
                }
                updateLocalWorkOrder(order)
                return order
            }
            throw WorkOrderError.invalidData
        }

        let url = URL(string: "\(baseURL)/api/work-orders/\(workOrderId.uuidString)/items")!

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await authService.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "itemId": itemId.uuidString,
            "status": status.rawValue
        ]

        if let notes = notes {
            body["completionNotes"] = notes
        }

        if status == .completed {
            body["completedAt"] = ISO8601DateFormatter().string(from: Date())
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkOrderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw WorkOrderError.httpError(httpResponse.statusCode)
        }

        // Fetch updated work order
        let updatedOrder = try await fetchWorkOrder(id: workOrderId)
        updateLocalWorkOrder(updatedOrder)

        return updatedOrder
    }

    /// Update work order (status, signature, etc.)
    func updateWorkOrder(id: UUID, updates: [String: Any]) async throws -> WorkOrder {
        let url = URL(string: "\(baseURL)/api/work-orders/\(id.uuidString)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await authService.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: updates)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkOrderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw WorkOrderError.httpError(httpResponse.statusCode)
        }

        let dto = try JSONDecoder().decode(WorkOrderDTO.self, from: data)

        guard let workOrder = dto.toWorkOrder() else {
            throw WorkOrderError.invalidData
        }

        updateLocalWorkOrder(workOrder)

        return workOrder
    }

    /// Complete work order with signature
    func completeWithSignature(workOrderId: UUID, signatureData: Data, signedName: String) async throws -> WorkOrder {
        // In a real implementation, you would:
        // 1. Upload signature image to cloud storage
        // 2. Get the URL back
        // 3. Update work order with URL

        // For now, we'll just update the work order status
        let updates: [String: Any] = [
            "status": WorkOrderStatus.completed.rawValue,
            "customerSignedName": signedName,
            "signedAt": ISO8601DateFormatter().string(from: Date())
            // "customerSignatureUrl": uploadedUrl
        ]

        return try await updateWorkOrder(id: workOrderId, updates: updates)
    }

    /// Upload a photo for a work order task
    func uploadTaskPhoto(workOrderId: UUID, itemId: UUID, image: UIImage) async throws -> WorkOrderPhotoUploadResponse {
        // Get the work order to find the estimateId
        let workOrder = try await fetchWorkOrder(id: workOrderId)

        let url = URL(string: "\(baseURL)/api/photos")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = await authService.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()

        // Add estimateId field
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"estimateId\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(workOrder.estimateId.uuidString)\r\n".data(using: .utf8)!)

        // Add workOrderItemId field (custom field we'll use to link photo to task)
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"workOrderItemId\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(itemId.uuidString)\r\n".data(using: .utf8)!)

        // Add caption field
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
        data.append("Task completion photo\r\n".data(using: .utf8)!)

        // Add image file
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            let filename = "\(UUID().uuidString).jpg"
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            data.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            data.append(imageData)
            data.append("\r\n".data(using: .utf8)!)
        }

        data.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkOrderError.invalidResponse
        }

        guard httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: responseData),
               let errorMessage = errorBody["error"] {
                throw WorkOrderError.serverError(errorMessage)
            }
            throw WorkOrderError.httpError(httpResponse.statusCode)
        }

        let photoResponse = try JSONDecoder().decode(WorkOrderPhotoUploadResponse.self, from: responseData)
        return photoResponse
    }

    // MARK: - Local State Management

    private func updateLocalWorkOrder(_ workOrder: WorkOrder) {
        if let index = workOrders.firstIndex(where: { $0.id == workOrder.id }) {
            workOrders[index] = workOrder
        }

        if currentWorkOrder?.id == workOrder.id {
            currentWorkOrder = workOrder
        }
    }

    /// Refresh current work order
    func refreshCurrentWorkOrder() async {
        guard let current = currentWorkOrder else { return }

        do {
            let updated = try await fetchWorkOrder(id: current.id)
            currentWorkOrder = updated
            updateLocalWorkOrder(updated)
        } catch {
            print("Error refreshing work order: \(error)")
        }
    }
}

// MARK: - Work Order Errors

enum WorkOrderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData
    case httpError(Int)
    case serverError(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .invalidData:
            return "Invalid data format"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return message
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}

// MARK: - Photo Upload Response

/// Response from work order photo upload API
struct WorkOrderPhotoUploadResponse: Codable {
    let id: String
    let url: String
    let filename: String?
    let mimeType: String?
    let sizeBytes: Int?
    let caption: String?
    let createdAt: String?
}
