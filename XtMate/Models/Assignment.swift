import Foundation
import SwiftUI

// MARK: - Assignment Model

/// Represents an assignment within a claim (E, R, C, A, P, Z)
/// Each claim can have multiple assignments, each with its own scope of work
struct Assignment: Identifiable, Codable, Hashable {
    let id: UUID
    var estimateId: UUID

    // Assignment type
    var type: AssignmentType

    // Status workflow
    var status: AssignmentStatus

    // Totals for this assignment
    var subtotal: Double
    var overhead: Double
    var profit: Double
    var tax: Double
    var total: Double
    var depreciation: Double
    var acv: Double

    // Approval tracking
    var submittedAt: Date?
    var approvedAt: Date?
    var approvedBy: String?

    // Notes
    var notes: String

    // Ordering
    var order: Int

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        estimateId: UUID,
        type: AssignmentType,
        status: AssignmentStatus = .pending,
        subtotal: Double = 0,
        overhead: Double = 0,
        profit: Double = 0,
        tax: Double = 0,
        total: Double = 0,
        depreciation: Double = 0,
        acv: Double = 0,
        submittedAt: Date? = nil,
        approvedAt: Date? = nil,
        approvedBy: String? = nil,
        notes: String = "",
        order: Int = 0
    ) {
        self.id = id
        self.estimateId = estimateId
        self.type = type
        self.status = status
        self.subtotal = subtotal
        self.overhead = overhead
        self.profit = profit
        self.tax = tax
        self.total = total
        self.depreciation = depreciation
        self.acv = acv
        self.submittedAt = submittedAt
        self.approvedAt = approvedAt
        self.approvedBy = approvedBy
        self.notes = notes
        self.order = order
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Assignment Type

/// Assignment types for claims
/// - E: Emergency (Insurance) - Water extraction, demo, drying
/// - A: Emergency (Private) - Same as E but for private jobs
/// - R: Repairs (Insurance) - Rebuild/restoration work
/// - P: Repairs (Private) - Same as R but for private jobs
/// - C: Contents - Personal property restoration/replacement
/// - Z: Full Service - Combined E+R+C in one estimate
enum AssignmentType: String, Codable, CaseIterable, Identifiable {
    case emergency = "E"           // Insurance emergency/mitigation
    case emergencyPrivate = "A"    // Private emergency/mitigation
    case repairs = "R"             // Insurance repairs/rebuild
    case repairsPrivate = "P"      // Private repairs/rebuild
    case contents = "C"            // Contents (personal property)
    case fullService = "Z"         // Full service (all-in-one)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .emergency: return "Emergency"
        case .emergencyPrivate: return "Emergency"
        case .repairs: return "Repairs"
        case .repairsPrivate: return "Repairs"
        case .contents: return "Contents"
        case .fullService: return "Full Service"
        }
    }

    var fullDisplayName: String {
        switch self {
        case .emergency: return "Emergency (E)"
        case .emergencyPrivate: return "Emergency (A)"
        case .repairs: return "Repairs (R)"
        case .repairsPrivate: return "Repairs (P)"
        case .contents: return "Contents (C)"
        case .fullService: return "Full Service (Z)"
        }
    }

    var shortCode: String { rawValue }

    var icon: String {
        switch self {
        case .emergency, .emergencyPrivate: return "bolt.fill"
        case .repairs, .repairsPrivate: return "hammer.fill"
        case .contents: return "shippingbox.fill"
        case .fullService: return "square.stack.3d.up.fill"
        }
    }

    var color: Color {
        switch self {
        case .emergency, .emergencyPrivate: return .orange
        case .repairs, .repairsPrivate: return .blue
        case .contents: return .purple
        case .fullService: return .green
        }
    }

    /// Default order for display (E before R before C)
    var defaultOrder: Int {
        switch self {
        case .emergency, .emergencyPrivate: return 0
        case .repairs, .repairsPrivate: return 1
        case .contents: return 2
        case .fullService: return 0
        }
    }

    /// Whether this is a private job assignment type
    var isPrivate: Bool {
        switch self {
        case .emergencyPrivate, .repairsPrivate: return true
        default: return false
        }
    }

    /// Get the insurance equivalent type
    var insuranceEquivalent: AssignmentType {
        switch self {
        case .emergencyPrivate: return .emergency
        case .repairsPrivate: return .repairs
        default: return self
        }
    }

    /// Get the private equivalent type
    var privateEquivalent: AssignmentType {
        switch self {
        case .emergency: return .emergencyPrivate
        case .repairs: return .repairsPrivate
        default: return self
        }
    }

    /// Types available for insurance claims
    static var insuranceTypes: [AssignmentType] {
        [.emergency, .repairs, .contents, .fullService]
    }

    /// Types available for private jobs
    static var privateTypes: [AssignmentType] {
        [.emergencyPrivate, .repairsPrivate, .contents, .fullService]
    }
}

// MARK: - Assignment Status

/// Status workflow for assignments
enum AssignmentStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case inProgress = "in_progress"
    case submitted = "submitted"
    case approved = "approved"
    case completed = "completed"

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .submitted: return "Submitted"
        case .approved: return "Approved"
        case .completed: return "Completed"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .submitted: return "paperplane.fill"
        case .approved: return "checkmark.seal.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .gray
        case .inProgress: return .orange
        case .submitted: return .blue
        case .approved: return .green
        case .completed: return .green
        }
    }

    /// Whether the assignment can be edited
    var isEditable: Bool {
        switch self {
        case .pending, .inProgress: return true
        case .submitted, .approved, .completed: return false
        }
    }

    /// Next status in the workflow
    var nextStatus: AssignmentStatus? {
        switch self {
        case .pending: return .inProgress
        case .inProgress: return .submitted
        case .submitted: return .approved
        case .approved: return .completed
        case .completed: return nil
        }
    }
}

// MARK: - Job Type

/// Type of job: insurance claim or private
enum JobType: String, Codable, CaseIterable {
    case insurance = "insurance"
    case privateJob = "private"

    var displayName: String {
        switch self {
        case .insurance: return "Insurance Claim"
        case .privateJob: return "Private Job"
        }
    }

    var icon: String {
        switch self {
        case .insurance: return "building.columns.fill"
        case .privateJob: return "person.fill"
        }
    }
}

// MARK: - Dispatch Type

/// Type of dispatch urgency from XactAnalysis
enum DispatchType: String, Codable, CaseIterable {
    case normal = "Normal"
    case rush = "Rush"
    case emergency = "Emergency"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .normal: return "clock"
        case .rush: return "hare.fill"
        case .emergency: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .normal: return .gray
        case .rush: return .orange
        case .emergency: return .red
        }
    }
}

// MARK: - Loss Type

/// Type of loss/damage
enum LossType: String, Codable, CaseIterable {
    case water = "WATERDMG"
    case fire = "FIREDMG"
    case storm = "STORMDMG"
    case wind = "WINDDMG"
    case mold = "MOLDDMG"
    case vandalism = "VANDALISM"
    case other = "OTHER"

    var displayName: String {
        switch self {
        case .water: return "Water Damage"
        case .fire: return "Fire Damage"
        case .storm: return "Storm Damage"
        case .wind: return "Wind Damage"
        case .mold: return "Mold Damage"
        case .vandalism: return "Vandalism"
        case .other: return "Other"
        }
    }

    var shortName: String {
        switch self {
        case .water: return "Water"
        case .fire: return "Fire"
        case .storm: return "Storm"
        case .wind: return "Wind"
        case .mold: return "Mold"
        case .vandalism: return "Vandalism"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .water: return "drop.fill"
        case .fire: return "flame.fill"
        case .storm: return "cloud.bolt.rain.fill"
        case .wind: return "wind"
        case .mold: return "allergens"
        case .vandalism: return "exclamationmark.shield.fill"
        case .other: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .water: return .blue
        case .fire: return .red
        case .storm: return .purple
        case .wind: return .teal
        case .mold: return .green
        case .vandalism: return .orange
        case .other: return .gray
        }
    }

    /// Initialize from XactAnalysis loss type code
    init(fromCode code: String) {
        switch code.uppercased() {
        case "WATERDMG", "WATER": self = .water
        case "FIREDMG", "FIRE": self = .fire
        case "STORMDMG", "STORM": self = .storm
        case "WINDDMG", "WIND": self = .wind
        case "MOLDDMG", "MOLD": self = .mold
        case "VANDALISM": self = .vandalism
        default: self = .other
        }
    }
}
