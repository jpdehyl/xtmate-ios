import Foundation

// MARK: - Work Order Models

/// Represents a work order assigned to field staff
struct WorkOrder: Identifiable, Codable, Hashable {
    let id: UUID
    let estimateId: UUID
    let assignedTo: String
    var status: WorkOrderStatus
    var scheduledDate: Date?
    var scheduledStartTime: String?
    var scheduledEndTime: String?
    var clockIn: Date?
    var clockOut: Date?
    var totalHours: Double?
    var breakMinutes: Int
    var priority: WorkOrderPriority
    var notes: String?
    var completionNotes: String?
    var customerSignatureUrl: String?
    var customerSignedName: String?
    var signedAt: Date?
    var items: [WorkOrderItem]
    let createdAt: Date
    var updatedAt: Date

    // Computed from estimate (populated from API response)
    var estimate: EstimateSummary?

    // MARK: - Computed Properties

    /// Property address from estimate
    var propertyAddress: String {
        estimate?.propertyAddress ?? "Address unavailable"
    }

    /// Number of completed items
    var completedItems: Int {
        items.filter { $0.status == .completed }.count
    }

    /// Total number of items
    var totalItems: Int {
        items.count
    }

    /// Whether all items are complete
    var allItemsComplete: Bool {
        !items.isEmpty && items.allSatisfy { $0.status == .completed }
    }

    /// Scheduled time for display
    var scheduledTime: Date? {
        guard let dateStr = scheduledStartTime, let date = scheduledDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let time = formatter.date(from: dateStr) else { return nil }

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
                            minute: timeComponents.minute ?? 0,
                            second: 0,
                            of: date)
    }

    /// Whether currently clocked in
    var isClockedIn: Bool {
        clockIn != nil && clockOut == nil
    }

    /// Elapsed time since clock in
    var elapsedTime: TimeInterval {
        guard let clockIn = clockIn else { return 0 }
        if let clockOut = clockOut {
            return clockOut.timeIntervalSince(clockIn) - Double(breakMinutes * 60)
        }
        return Date().timeIntervalSince(clockIn) - Double(breakMinutes * 60)
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id, estimateId, assignedTo, status
        case scheduledDate, scheduledStartTime, scheduledEndTime
        case clockIn, clockOut, totalHours, breakMinutes
        case priority, notes, completionNotes
        case customerSignatureUrl, customerSignedName, signedAt
        case items, createdAt, updatedAt, estimate
    }
}

// MARK: - Work Order Item

/// Individual task within a work order
struct WorkOrderItem: Identifiable, Codable, Hashable {
    let id: UUID
    let workOrderId: UUID
    let lineItemId: UUID?
    var status: WorkOrderItemStatus
    var completedAt: Date?
    var completionNotes: String?
    var completionPhotoId: UUID?
    var order: Int
    let createdAt: Date

    // Joined from lineItem (populated from API)
    var lineItem: LineItemSummary?

    /// Description from line item or fallback
    var description: String {
        lineItem?.description ?? "Task \(order + 1)"
    }

    enum CodingKeys: String, CodingKey {
        case id, workOrderId, lineItemId, status
        case completedAt, completionNotes, completionPhotoId
        case order, createdAt, lineItem
    }
}

// MARK: - Status Enums

/// Work order status workflow
enum WorkOrderStatus: String, Codable, CaseIterable, Hashable {
    case assigned
    case enRoute = "en_route"
    case inProgress = "in_progress"
    case completed
    case cancelled

    var displayName: String {
        switch self {
        case .assigned: return "Assigned"
        case .enRoute: return "En Route"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var icon: String {
        switch self {
        case .assigned: return "clock"
        case .enRoute: return "car.fill"
        case .inProgress: return "wrench.fill"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .assigned: return "gray"
        case .enRoute: return "blue"
        case .inProgress: return "orange"
        case .completed: return "green"
        case .cancelled: return "red"
        }
    }
}

/// Work order item status
enum WorkOrderItemStatus: String, Codable, CaseIterable, Hashable {
    case pending
    case inProgress = "in_progress"
    case completed
    case blocked
    case skipped

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .blocked: return "Blocked"
        case .skipped: return "Skipped"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        case .blocked: return "exclamationmark.circle.fill"
        case .skipped: return "arrow.right.circle"
        }
    }
}

/// Work order priority
enum WorkOrderPriority: String, Codable, CaseIterable, Hashable {
    case low
    case normal
    case high
    case urgent

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    var icon: String {
        switch self {
        case .low: return "chevron.down"
        case .normal: return "minus"
        case .high: return "chevron.up"
        case .urgent: return "exclamationmark.2"
        }
    }

    var color: String {
        switch self {
        case .low: return "gray"
        case .normal: return "blue"
        case .high: return "orange"
        case .urgent: return "red"
        }
    }
}

// MARK: - Summary Types (from API joins)

/// Minimal estimate data for work order display
struct EstimateSummary: Codable, Hashable {
    let id: UUID
    let name: String?
    let propertyAddress: String?
    let propertyCity: String?
    let propertyState: String?
    let insuredName: String?
    let claimNumber: String?
}

/// Minimal line item data for work order task display
struct LineItemSummary: Codable, Hashable {
    let id: UUID
    let description: String
    let category: String?
    let selector: String?
    let quantity: Double?
    let unit: String?
}

// MARK: - API DTOs

/// DTO for work order from API (handles nested JSON)
struct WorkOrderDTO: Codable {
    let id: String
    let estimateId: String
    let assignedTo: String
    let status: String?
    let scheduledDate: String?
    let scheduledStartTime: String?
    let scheduledEndTime: String?
    let clockIn: String?
    let clockOut: String?
    let totalHours: Double?
    let breakMinutes: Int?
    let priority: String?
    let notes: String?
    let completionNotes: String?
    let customerSignatureUrl: String?
    let customerSignedName: String?
    let signedAt: String?
    let createdAt: String
    let updatedAt: String
    let estimate: EstimateSummaryDTO?
    let items: [WorkOrderItemDTO]?

    func toWorkOrder() -> WorkOrder? {
        guard let id = UUID(uuidString: id),
              let estimateId = UUID(uuidString: estimateId) else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        func parseDate(_ str: String?) -> Date? {
            guard let str = str else { return nil }
            return isoFormatter.date(from: str) ?? fallbackFormatter.date(from: str)
        }

        return WorkOrder(
            id: id,
            estimateId: estimateId,
            assignedTo: assignedTo,
            status: WorkOrderStatus(rawValue: status ?? "assigned") ?? .assigned,
            scheduledDate: parseDate(scheduledDate),
            scheduledStartTime: scheduledStartTime,
            scheduledEndTime: scheduledEndTime,
            clockIn: parseDate(clockIn),
            clockOut: parseDate(clockOut),
            totalHours: totalHours,
            breakMinutes: breakMinutes ?? 0,
            priority: WorkOrderPriority(rawValue: priority ?? "normal") ?? .normal,
            notes: notes,
            completionNotes: completionNotes,
            customerSignatureUrl: customerSignatureUrl,
            customerSignedName: customerSignedName,
            signedAt: parseDate(signedAt),
            items: items?.compactMap { $0.toWorkOrderItem() } ?? [],
            createdAt: parseDate(createdAt) ?? Date(),
            updatedAt: parseDate(updatedAt) ?? Date(),
            estimate: estimate?.toEstimateSummary()
        )
    }
}

struct WorkOrderItemDTO: Codable {
    let id: String
    let workOrderId: String
    let lineItemId: String?
    let status: String?
    let completedAt: String?
    let completionNotes: String?
    let completionPhotoId: String?
    let order: Double?
    let createdAt: String
    let lineItem: LineItemSummaryDTO?

    func toWorkOrderItem() -> WorkOrderItem? {
        guard let id = UUID(uuidString: id),
              let workOrderId = UUID(uuidString: workOrderId) else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        func parseDate(_ str: String?) -> Date? {
            guard let str = str else { return nil }
            return isoFormatter.date(from: str) ?? fallbackFormatter.date(from: str)
        }

        return WorkOrderItem(
            id: id,
            workOrderId: workOrderId,
            lineItemId: lineItemId.flatMap { UUID(uuidString: $0) },
            status: WorkOrderItemStatus(rawValue: status ?? "pending") ?? .pending,
            completedAt: parseDate(completedAt),
            completionNotes: completionNotes,
            completionPhotoId: completionPhotoId.flatMap { UUID(uuidString: $0) },
            order: Int(order ?? 0),
            createdAt: parseDate(createdAt) ?? Date(),
            lineItem: lineItem?.toLineItemSummary()
        )
    }
}

struct EstimateSummaryDTO: Codable {
    let id: String
    let name: String?
    let propertyAddress: String?
    let propertyCity: String?
    let propertyState: String?
    let insuredName: String?
    let claimNumber: String?

    func toEstimateSummary() -> EstimateSummary? {
        guard let id = UUID(uuidString: id) else { return nil }
        return EstimateSummary(
            id: id,
            name: name,
            propertyAddress: propertyAddress,
            propertyCity: propertyCity,
            propertyState: propertyState,
            insuredName: insuredName,
            claimNumber: claimNumber
        )
    }
}

struct LineItemSummaryDTO: Codable {
    let id: String
    let description: String
    let category: String?
    let selector: String?
    let quantity: Double?
    let unit: String?

    func toLineItemSummary() -> LineItemSummary? {
        guard let id = UUID(uuidString: id) else { return nil }
        return LineItemSummary(
            id: id,
            description: description,
            category: category,
            selector: selector,
            quantity: quantity,
            unit: unit
        )
    }
}
