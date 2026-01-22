import Foundation
import SwiftUI

// MARK: - Scope Line Item Model

/// Represents a scope line item for an estimate
struct ScopeLineItem: Identifiable, Codable, Hashable {
    let id: UUID

    // Item identification (matches web schema)
    var category: String           // WTR, DRY, DEM, etc.
    var selector: String           // Full code like "WTR EXTRT"
    var description: String

    // Quantities
    var quantity: Double
    var unit: String               // SF, LF, EA, SY, HR, CF

    // Pricing
    var unitPrice: Double
    var total: Double { quantity * unitPrice }

    // Linked entities
    var roomId: UUID?
    var annotationId: UUID?

    // Validation state
    var validationState: ValidationState
    var suggestions: [SelectorSuggestion]

    // Source tracking
    var source: LineItemSource
    var aiConfidence: Double?
    var isVerified: Bool

    var notes: String
    var order: Int

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        category: String,
        selector: String,
        description: String,
        quantity: Double,
        unit: String,
        unitPrice: Double = 0,
        roomId: UUID? = nil,
        annotationId: UUID? = nil,
        source: LineItemSource = .manual,
        notes: String = "",
        order: Int = 0
    ) {
        self.id = id
        self.category = category
        self.selector = selector
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.roomId = roomId
        self.annotationId = annotationId
        self.validationState = .pending
        self.suggestions = []
        self.source = source
        self.aiConfidence = nil
        self.isVerified = false
        self.notes = notes
        self.order = order
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Validation State

enum ValidationState: String, Codable {
    case pending = "pending"
    case valid = "valid"
    case invalid = "invalid"
    case validating = "validating"

    var icon: String {
        switch self {
        case .pending: return "questionmark.circle"
        case .valid: return "checkmark.circle.fill"
        case .invalid: return "exclamationmark.triangle.fill"
        case .validating: return "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .gray
        case .valid: return .green
        case .invalid: return .orange
        case .validating: return .blue
        }
    }
}

// MARK: - Line Item Source

enum LineItemSource: String, Codable {
    case manual = "manual"
    case aiGenerated = "ai_generated"
    case esxImport = "esx_import"

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .aiGenerated: return "AI Generated"
        case .esxImport: return "ESX Import"
        }
    }
}

// MARK: - Selector Suggestion

/// A suggested replacement for an invalid selector
struct SelectorSuggestion: Identifiable, Codable, Hashable {
    let id: UUID
    let selector: String
    let category: String
    let description: String
    let unit: String
    let totalRate: Double
    let similarity: Double

    init(
        id: UUID = UUID(),
        selector: String,
        category: String,
        description: String,
        unit: String,
        totalRate: Double,
        similarity: Double
    ) {
        self.id = id
        self.selector = selector
        self.category = category
        self.description = description
        self.unit = unit
        self.totalRate = totalRate
        self.similarity = similarity
    }

    /// Initialize from SuggestionInfo (API response)
    init(from info: SuggestionInfo) {
        self.id = UUID()
        self.selector = info.selector
        self.category = info.category
        self.description = info.description
        self.unit = info.unit
        self.totalRate = info.totalRate
        self.similarity = info.similarity ?? 0
    }
}

// MARK: - Common Units

enum LineItemUnit: String, CaseIterable {
    case sf = "SF"      // Square feet
    case lf = "LF"      // Linear feet
    case ea = "EA"      // Each
    case sy = "SY"      // Square yard
    case hr = "HR"      // Hour
    case cf = "CF"      // Cubic feet
    case da = "DA"      // Day

    var displayName: String {
        switch self {
        case .sf: return "Square Feet"
        case .lf: return "Linear Feet"
        case .ea: return "Each"
        case .sy: return "Square Yards"
        case .hr: return "Hours"
        case .cf: return "Cubic Feet"
        case .da: return "Days"
        }
    }
}

// MARK: - Common Categories

enum LineItemCategory: String, CaseIterable {
    case wtr = "WTR"    // Water mitigation
    case dry = "DRY"    // Drying equipment
    case dem = "DEM"    // Demolition
    case drw = "DRW"    // Drywall
    case flr = "FLR"    // Flooring
    case pnt = "PNT"    // Painting
    case cln = "CLN"    // Cleaning
    case con = "CON"    // Contents
    case hmr = "HMR"    // Hardware/miscellaneous
    case app = "APP"    // Appliances

    var displayName: String {
        switch self {
        case .wtr: return "Water Mitigation"
        case .dry: return "Drying Equipment"
        case .dem: return "Demolition"
        case .drw: return "Drywall"
        case .flr: return "Flooring"
        case .pnt: return "Painting"
        case .cln: return "Cleaning"
        case .con: return "Contents"
        case .hmr: return "Hardware/Misc"
        case .app: return "Appliances"
        }
    }

    var icon: String {
        switch self {
        case .wtr: return "drop.fill"
        case .dry: return "wind"
        case .dem: return "hammer.fill"
        case .drw: return "rectangle.3.group"
        case .flr: return "square.grid.3x3"
        case .pnt: return "paintbrush.fill"
        case .cln: return "sparkles"
        case .con: return "shippingbox.fill"
        case .hmr: return "wrench.and.screwdriver.fill"
        case .app: return "refrigerator.fill"
        }
    }
}
