//
//  PreliminaryReport.swift
//  XtMate
//
//  Created by XtMate on 2026-01-17.
//

import Foundation

// MARK: - Preliminary Report Model

/// A preliminary report provides a quick account to insurance companies
/// while the full scope and estimate are being built. It includes:
/// - Claim timeline (received, contacted, inspected dates)
/// - Emergency services performed
/// - Cause of loss description
/// - Room-by-room structural damage summary
/// - Supporting photos grouped by room
/// - Preliminary repair cost estimates
struct PreliminaryReport: Identifiable, Codable {
    let id: UUID
    var estimateId: UUID

    // MARK: - Claim Log
    var claimReceivedDate: Date?
    var insuredContactedDate: Date?
    var siteInspectedDate: Date?

    // MARK: - Emergency Services
    var emergencyServicesCompleted: Bool = false
    var emergencyServicesDescription: String = ""
    var emergencyServicesByOther: Bool = false  // "Emergency work completed by another contractor"

    // MARK: - Cause of Loss
    var causeOfLoss: String = ""
    var causeOfLossType: CauseOfLossType = .water

    // MARK: - Structural Damage by Room
    var roomDamage: [RoomDamageEntry] = []

    // MARK: - Photos
    var photos: [PreliminaryReportPhoto] = []

    // MARK: - Repair Cost Estimates
    var repairCostMin: Double?
    var repairCostMax: Double?
    var contentsCostMin: Double?
    var contentsCostMax: Double?
    var emergencyCost: Double?

    // MARK: - Additional Notes
    var additionalNotes: String = ""

    // MARK: - Metadata
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var createdBy: String = ""
    var status: ReportStatus = .draft

    init(id: UUID = UUID(), estimateId: UUID) {
        self.id = id
        self.estimateId = estimateId
    }
}

// MARK: - Cause of Loss Type

enum CauseOfLossType: String, Codable, CaseIterable {
    case water = "Water"
    case fire = "Fire"
    case smoke = "Smoke"
    case mold = "Mold"
    case wind = "Wind"
    case impact = "Impact"
    case freezing = "Freezing"
    case other = "Other"

    var icon: String {
        switch self {
        case .water: return "drop.fill"
        case .fire: return "flame.fill"
        case .smoke: return "smoke.fill"
        case .mold: return "allergens"
        case .wind: return "wind"
        case .impact: return "bolt.fill"
        case .freezing: return "snowflake"
        case .other: return "questionmark.circle"
        }
    }
}

// MARK: - Report Status

enum ReportStatus: String, Codable, CaseIterable {
    case draft = "Draft"
    case pendingReview = "Pending Review"
    case submitted = "Submitted"
    case approved = "Approved"

    var color: String {
        switch self {
        case .draft: return "gray"
        case .pendingReview: return "orange"
        case .submitted: return "blue"
        case .approved: return "green"
        }
    }
}

// MARK: - Room Damage Entry

/// Describes the structural damage observed in a specific room
struct RoomDamageEntry: Identifiable, Codable {
    let id: UUID
    var roomName: String
    var roomCategory: RoomCategory
    var affectedMaterials: [AffectedMaterial] = []
    var notes: String = ""
    var order: Int = 0

    init(id: UUID = UUID(), roomName: String, roomCategory: RoomCategory) {
        self.id = id
        self.roomName = roomName
        self.roomCategory = roomCategory
    }

    /// Generates a summary string like "carpet and carpet pad" or "drywall, carpet, carpet pad and baseboards"
    var materialsSummary: String {
        let names = affectedMaterials.map { $0.material.displayName }
        guard !names.isEmpty else { return "No damage recorded" }

        if names.count == 1 {
            return names[0]
        } else if names.count == 2 {
            return "\(names[0]) and \(names[1])"
        } else {
            let allButLast = names.dropLast().joined(separator: ", ")
            return "\(allButLast) and \(names.last!)"
        }
    }

    /// Full description like "Master bedroom: carpet and carpet pad"
    var fullDescription: String {
        "\(roomName): \(materialsSummary)"
    }
}

// MARK: - Affected Material

struct AffectedMaterial: Identifiable, Codable {
    let id: UUID
    var material: MaterialType
    var severity: DamageSeverity = .moderate
    var notes: String = ""

    init(id: UUID = UUID(), material: MaterialType, severity: DamageSeverity = .moderate) {
        self.id = id
        self.material = material
        self.severity = severity
    }
}

// MARK: - Material Type

enum MaterialType: String, Codable, CaseIterable {
    // Flooring
    case carpet = "carpet"
    case carpetPad = "carpet_pad"
    case hardwood = "hardwood"
    case laminate = "laminate"
    case lvp = "lvp"
    case tile = "tile"
    case vinyl = "vinyl"
    case concrete = "concrete"

    // Walls
    case drywall = "drywall"
    case plaster = "plaster"
    case paneling = "paneling"
    case wallpaper = "wallpaper"

    // Trim
    case baseboards = "baseboards"
    case casings = "casings"
    case crownMolding = "crown_molding"

    // Ceiling
    case ceilingDrywall = "ceiling_drywall"
    case ceilingTiles = "ceiling_tiles"
    case popcornCeiling = "popcorn_ceiling"

    // Other
    case insulation = "insulation"
    case subfloor = "subfloor"
    case cabinets = "cabinets"
    case countertops = "countertops"

    var displayName: String {
        switch self {
        case .carpet: return "carpet"
        case .carpetPad: return "carpet pad"
        case .hardwood: return "hardwood flooring"
        case .laminate: return "laminate flooring"
        case .lvp: return "LVP flooring"
        case .tile: return "tile"
        case .vinyl: return "vinyl flooring"
        case .concrete: return "concrete"
        case .drywall: return "drywall"
        case .plaster: return "plaster"
        case .paneling: return "paneling"
        case .wallpaper: return "wallpaper"
        case .baseboards: return "baseboards"
        case .casings: return "door/window casings"
        case .crownMolding: return "crown molding"
        case .ceilingDrywall: return "ceiling drywall"
        case .ceilingTiles: return "ceiling tiles"
        case .popcornCeiling: return "popcorn ceiling"
        case .insulation: return "insulation"
        case .subfloor: return "subfloor"
        case .cabinets: return "cabinets"
        case .countertops: return "countertops"
        }
    }

    var category: MaterialCategory {
        switch self {
        case .carpet, .carpetPad, .hardwood, .laminate, .lvp, .tile, .vinyl, .concrete, .subfloor:
            return .flooring
        case .drywall, .plaster, .paneling, .wallpaper:
            return .walls
        case .baseboards, .casings, .crownMolding:
            return .trim
        case .ceilingDrywall, .ceilingTiles, .popcornCeiling:
            return .ceiling
        case .insulation, .cabinets, .countertops:
            return .other
        }
    }
}

enum MaterialCategory: String, Codable {
    case flooring = "Flooring"
    case walls = "Walls"
    case trim = "Trim"
    case ceiling = "Ceiling"
    case other = "Other"
}

// MARK: - Preliminary Report Photo
// Note: DamageSeverity is defined in ContentView.swift (use that enum)

/// A photo extracted from video walkthrough or captured manually for the preliminary report
struct PreliminaryReportPhoto: Identifiable, Codable {
    let id: UUID
    var imageData: Data?  // For local storage
    var imageUrl: String? // For remote storage
    var thumbnailData: Data?

    var roomName: String = ""
    var roomCategory: RoomCategory = .other
    var caption: String = ""

    var damageType: CauseOfLossType?
    var showsDamage: Bool = true

    // Source tracking
    var source: PhotoSource = .manual
    var extractedFromVideoAt: TimeInterval?  // Timestamp in video
    var transitionType: String?  // If extracted at a transition point

    var takenAt: Date = Date()
    var order: Int = 0

    // AI analysis results
    var aiAnalysis: PhotoAIAnalysis?

    init(id: UUID = UUID()) {
        self.id = id
    }
}

enum PhotoSource: String, Codable {
    case manual = "Manual"
    case videoExtraction = "Video Extraction"
    case lidarCapture = "LiDAR Capture"
}

// MARK: - Photo AI Analysis

/// AI-generated analysis of a photo for damage detection and room identification
struct PhotoAIAnalysis: Codable {
    var identifiedRoom: String?
    var identifiedRoomCategory: RoomCategory?
    var confidence: Double = 0.0

    var detectedDamage: [DetectedDamageArea] = []
    var detectedMaterials: [String] = []
    var detectedObjects: [String] = []

    var suggestedCaption: String?
    var analysisNotes: String?
}

struct DetectedDamageArea: Codable {
    var damageType: CauseOfLossType
    var severity: DamageSeverity
    var affectedMaterial: MaterialType?
    var description: String
    var confidence: Double
}

// MARK: - Room Category Extension

extension RoomCategory {
    /// Common materials found in this room type
    var typicalMaterials: [MaterialType] {
        switch self {
        case .kitchen:
            return [.tile, .vinyl, .drywall, .baseboards, .cabinets, .countertops]
        case .bathroom:
            return [.tile, .vinyl, .drywall, .baseboards, .ceilingDrywall]
        case .bedroom:
            return [.carpet, .carpetPad, .drywall, .baseboards]
        case .livingRoom:
            return [.carpet, .carpetPad, .hardwood, .drywall, .baseboards]
        case .diningRoom:
            return [.hardwood, .carpet, .drywall, .baseboards]
        case .laundry:
            return [.tile, .vinyl, .drywall, .baseboards]
        case .garage:
            return [.concrete, .drywall]
        case .basement:
            return [.concrete, .carpet, .drywall, .insulation]
        case .hallway:
            return [.carpet, .hardwood, .drywall, .baseboards]
        case .closet:
            return [.carpet, .drywall]
        case .office:
            return [.carpet, .hardwood, .drywall, .baseboards]
        case .other:
            return [.drywall, .carpet, .baseboards]
        }
    }
}
