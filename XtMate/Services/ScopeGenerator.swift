import Foundation

// MARK: - Scope Generator: Damage Annotations → Xactimate Line Items

@available(iOS 16.0, *)
class ScopeGenerator {
    static let shared = ScopeGenerator()

    private init() {}

    // MARK: - Generate Scope from Room + Annotations

    func generateScope(
        room: Room,
        annotations: [DamageAnnotation],
        causeOfLoss: String = "Water"
    ) -> [GeneratedLineItem] {
        var lineItems: [GeneratedLineItem] = []

        // Group annotations by damage type
        let waterAnnotations = annotations.filter { $0.damageType == .water }
        let fireAnnotations = annotations.filter { $0.damageType == .fire }
        let smokeAnnotations = annotations.filter { $0.damageType == .smoke }
        let moldAnnotations = annotations.filter { $0.damageType == .mold }

        // Generate items based on damage type
        if !waterAnnotations.isEmpty {
            lineItems.append(contentsOf: generateWaterDamageItems(room: room, annotations: waterAnnotations))
        }

        if !fireAnnotations.isEmpty {
            lineItems.append(contentsOf: generateFireDamageItems(room: room, annotations: fireAnnotations))
        }

        if !smokeAnnotations.isEmpty {
            lineItems.append(contentsOf: generateSmokeDamageItems(room: room, annotations: smokeAnnotations))
        }

        if !moldAnnotations.isEmpty {
            lineItems.append(contentsOf: generateMoldDamageItems(room: room, annotations: moldAnnotations))
        }

        // Add general items based on room category
        lineItems.append(contentsOf: generateRoomSpecificItems(room: room, annotations: annotations))

        return lineItems
    }

    // MARK: - Water Damage Scope Generation

    private func generateWaterDamageItems(room: Room, annotations: [DamageAnnotation]) -> [GeneratedLineItem] {
        var items: [GeneratedLineItem] = []

        // Determine water class based on severity
        let maxSeverity = annotations.map { $0.severity }.max { s1, s2 in
            severityRank(s1) < severityRank(s2)
        } ?? .moderate

        let waterClass = determineWaterClass(severity: maxSeverity, annotations: annotations)
        let affectedFloor = annotations.contains { $0.affectedSurfaces.contains(.floor) }
        let affectedWalls = annotations.contains { $0.affectedSurfaces.contains(.wall) }
        _ = annotations.contains { $0.affectedSurfaces.contains(.ceiling) }

        // Water extraction
        if affectedFloor {
            items.append(GeneratedLineItem(
                category: "WTR",
                selector: "WTR EXTRT",
                description: "Extract water from floor - \(room.category.rawValue)",
                quantity: room.squareFeet,
                unit: "SF",
                notes: "Water extraction based on room square footage",
                confidence: 0.95,
                source: .aiGenerated
            ))
        }

        // Carpet removal if applicable
        if affectedFloor && room.floorMaterial == .carpet {
            items.append(GeneratedLineItem(
                category: "FLR",
                selector: "FLR CPT R&D",
                description: "Remove & dispose carpet - water damaged",
                quantity: room.squareFeet,
                unit: "SF",
                notes: "Carpet removal due to water damage",
                confidence: 0.9,
                source: .aiGenerated
            ))

            items.append(GeneratedLineItem(
                category: "FLR",
                selector: "FLR CPTPD R&D",
                description: "Remove & dispose carpet pad",
                quantity: room.squareFeet,
                unit: "SF",
                notes: "Pad removal with carpet",
                confidence: 0.9,
                source: .aiGenerated
            ))
        }

        // Laminate/LVP removal
        if affectedFloor && (room.floorMaterial == .laminate || room.floorMaterial == .lvp) {
            let selector = room.floorMaterial == .laminate ? "FLR LAM R&D" : "FLR LVP R&D"
            items.append(GeneratedLineItem(
                category: "FLR",
                selector: selector,
                description: "Remove & dispose \(room.floorMaterial?.displayName ?? "flooring") - water damaged",
                quantity: room.squareFeet,
                unit: "SF",
                notes: "Flooring removal due to water damage",
                confidence: 0.9,
                source: .aiGenerated
            ))
        }

        // Baseboard removal
        if affectedWalls {
            let maxWaterLine = annotations.compactMap { $0.affectedHeightIn }.max() ?? 24
            if maxWaterLine > 0 {
                items.append(GeneratedLineItem(
                    category: "BSBD",
                    selector: "BSBD DET",
                    description: "Detach baseboard for drying",
                    quantity: room.perimeterLf,
                    unit: "LF",
                    notes: "Baseboard detachment for wall drying access",
                    confidence: 0.85,
                    source: .aiGenerated
                ))
            }
        }

        // Drywall removal based on water line height
        if affectedWalls {
            let maxWaterLine = annotations.compactMap { $0.affectedHeightIn }.max() ?? 0
            if maxWaterLine > 24 {
                // Remove drywall to 2' above water line
                let cutHeight = min(maxWaterLine + 24, room.heightIn)
                let drywallSF = room.perimeterLf * (cutHeight / 12)

                items.append(GeneratedLineItem(
                    category: "DRW",
                    selector: "DRW 1/2 R&D",
                    description: "Remove & dispose drywall - water damaged",
                    quantity: drywallSF,
                    unit: "SF",
                    notes: "Drywall removal to \(Int(cutHeight))\" above floor (water line + 24\")",
                    confidence: 0.85,
                    source: .aiGenerated
                ))
            }
        }

        // Anti-microbial treatment
        items.append(GeneratedLineItem(
            category: "CLN",
            selector: "CLN ANTIM",
            description: "Apply anti-microbial treatment",
            quantity: calculateAffectedArea(room: room, annotations: annotations),
            unit: "SF",
            notes: "Anti-microbial application to all affected surfaces",
            confidence: 0.9,
            source: .aiGenerated
        ))

        // Drying equipment based on IICRC S500
        let dryingEquipment = calculateDryingEquipment(room: room, waterClass: waterClass)

        items.append(GeneratedLineItem(
            category: "DRY",
            selector: "DRY DEHU",
            description: "Dehumidifier - \(dryingEquipment.dehuCount) unit(s)",
            quantity: Double(dryingEquipment.dehuCount * dryingEquipment.days),
            unit: "EA/DAY",
            notes: "Based on \(Int(room.squareFeet * room.heightIn / 12)) CF affected area",
            confidence: 0.85,
            source: .aiGenerated
        ))

        items.append(GeneratedLineItem(
            category: "DRY",
            selector: "DRY AMVR",
            description: "Air mover - \(dryingEquipment.airMoverCount) unit(s)",
            quantity: Double(dryingEquipment.airMoverCount * dryingEquipment.days),
            unit: "EA/DAY",
            notes: "Based on \(Int(room.perimeterLf)) LF wall perimeter",
            confidence: 0.85,
            source: .aiGenerated
        ))

        return items
    }

    // MARK: - Fire Damage Scope Generation

    private func generateFireDamageItems(room: Room, annotations: [DamageAnnotation]) -> [GeneratedLineItem] {
        var items: [GeneratedLineItem] = []

        let affectedFloor = annotations.contains { $0.affectedSurfaces.contains(.floor) }
        let affectedWalls = annotations.contains { $0.affectedSurfaces.contains(.wall) }
        let affectedCeiling = annotations.contains { $0.affectedSurfaces.contains(.ceiling) }

        // Content manipulation
        items.append(GeneratedLineItem(
            category: "CON",
            selector: "CON MANP",
            description: "Contents manipulation - move out for repairs",
            quantity: room.squareFeet,
            unit: "SF",
            notes: "Move contents to allow for fire restoration work",
            confidence: 0.8,
            source: .aiGenerated
        ))

        // Demolition based on severity
        let maxSeverity = annotations.map { $0.severity }.max { s1, s2 in
            severityRank(s1) < severityRank(s2)
        } ?? .moderate

        if maxSeverity == .heavy {
            // Full demo for heavy fire damage
            if affectedWalls {
                items.append(GeneratedLineItem(
                    category: "DEM",
                    selector: "DRW 1/2 R&D",
                    description: "Remove & dispose fire-damaged drywall",
                    quantity: room.wallSf,
                    unit: "SF",
                    notes: "Full wall demolition due to heavy fire damage",
                    confidence: 0.85,
                    source: .aiGenerated
                ))
            }

            if affectedCeiling {
                items.append(GeneratedLineItem(
                    category: "DEM",
                    selector: "DRW 1/2 R&D",
                    description: "Remove & dispose fire-damaged ceiling drywall",
                    quantity: room.ceilingSf,
                    unit: "SF",
                    notes: "Ceiling demolition due to fire damage",
                    confidence: 0.85,
                    source: .aiGenerated
                ))
            }

            if affectedFloor {
                items.append(GeneratedLineItem(
                    category: "FLR",
                    selector: "FLR \(floorSelector(for: room.floorMaterial)) R&D",
                    description: "Remove & dispose fire-damaged flooring",
                    quantity: room.squareFeet,
                    unit: "SF",
                    notes: "Flooring removal due to fire damage",
                    confidence: 0.85,
                    source: .aiGenerated
                ))
            }
        }

        // Sealant for smoke odor
        if affectedWalls || affectedCeiling {
            let sealArea = (affectedWalls ? room.wallSf : 0) + (affectedCeiling ? room.ceilingSf : 0)
            items.append(GeneratedLineItem(
                category: "PNT",
                selector: "PNT SEAL",
                description: "Apply odor sealer - fire/smoke",
                quantity: sealArea,
                unit: "SF",
                notes: "Sealer application before paint",
                confidence: 0.8,
                source: .aiGenerated
            ))
        }

        return items
    }

    // MARK: - Smoke Damage Scope Generation

    private func generateSmokeDamageItems(room: Room, annotations: [DamageAnnotation]) -> [GeneratedLineItem] {
        var items: [GeneratedLineItem] = []

        let affectedWalls = annotations.contains { $0.affectedSurfaces.contains(.wall) }
        let affectedCeiling = annotations.contains { $0.affectedSurfaces.contains(.ceiling) }
        let maxSeverity = annotations.map { $0.severity }.max { s1, s2 in
            severityRank(s1) < severityRank(s2)
        } ?? .moderate

        // Cleaning based on severity
        let cleaningSelector: String
        switch maxSeverity {
        case .light:
            cleaningSelector = "CLN LITE"
        case .moderate:
            cleaningSelector = "CLN MED"
        case .heavy, .destroyed:
            cleaningSelector = "CLN HEVY"
        }

        if affectedWalls {
            items.append(GeneratedLineItem(
                category: "CLN",
                selector: cleaningSelector,
                description: "Clean smoke from walls - \(maxSeverity.rawValue.lowercased())",
                quantity: room.wallSf,
                unit: "SF",
                notes: "Smoke cleaning intensity based on severity",
                confidence: 0.85,
                source: .aiGenerated
            ))
        }

        if affectedCeiling {
            items.append(GeneratedLineItem(
                category: "CLN",
                selector: cleaningSelector,
                description: "Clean smoke from ceiling - \(maxSeverity.rawValue.lowercased())",
                quantity: room.ceilingSf,
                unit: "SF",
                notes: "Smoke cleaning intensity based on severity",
                confidence: 0.85,
                source: .aiGenerated
            ))
        }

        // Ozone treatment for odor
        items.append(GeneratedLineItem(
            category: "CLN",
            selector: "CLN OZON",
            description: "Ozone treatment for smoke odor",
            quantity: room.squareFeet * (room.heightIn / 12), // Cubic feet
            unit: "CF",
            notes: "Ozone treatment based on room volume",
            confidence: 0.75,
            source: .aiGenerated
        ))

        // Sealer and paint if heavy
        if maxSeverity == .heavy {
            let totalArea = room.wallSf + room.ceilingSf
            items.append(GeneratedLineItem(
                category: "PNT",
                selector: "PNT SEAL",
                description: "Apply odor sealer",
                quantity: totalArea,
                unit: "SF",
                notes: "Required for heavy smoke damage",
                confidence: 0.8,
                source: .aiGenerated
            ))

            items.append(GeneratedLineItem(
                category: "PNT",
                selector: "PNT 2CT",
                description: "Paint walls and ceiling - 2 coats",
                quantity: totalArea,
                unit: "SF",
                notes: "Repaint after sealer",
                confidence: 0.8,
                source: .aiGenerated
            ))
        }

        return items
    }

    // MARK: - Mold Damage Scope Generation

    private func generateMoldDamageItems(room: Room, annotations: [DamageAnnotation]) -> [GeneratedLineItem] {
        var items: [GeneratedLineItem] = []

        _ = annotations.contains { $0.affectedSurfaces.contains(.floor) }
        let affectedWalls = annotations.contains { $0.affectedSurfaces.contains(.wall) }
        let maxSeverity = annotations.map { $0.severity }.max { s1, s2 in
            severityRank(s1) < severityRank(s2)
        } ?? .moderate

        // Containment setup
        items.append(GeneratedLineItem(
            category: "HAZ",
            selector: "HAZ CONT",
            description: "Setup containment for mold remediation",
            quantity: room.perimeterLf,
            unit: "LF",
            notes: "Containment required per IICRC S520",
            confidence: 0.9,
            source: .aiGenerated
        ))

        // Negative air / air scrubber
        items.append(GeneratedLineItem(
            category: "HAZ",
            selector: "HAZ NEGAIR",
            description: "Negative air machine / air scrubber",
            quantity: 3, // 3 days typical
            unit: "DAY",
            notes: "Air filtration during remediation",
            confidence: 0.85,
            source: .aiGenerated
        ))

        // HEPA vacuum affected areas
        let affectedArea = calculateAffectedArea(room: room, annotations: annotations)
        items.append(GeneratedLineItem(
            category: "CLN",
            selector: "CLN HEPA",
            description: "HEPA vacuum mold-affected surfaces",
            quantity: affectedArea,
            unit: "SF",
            notes: "HEPA vacuuming of visible mold",
            confidence: 0.85,
            source: .aiGenerated
        ))

        // Drywall removal for mold
        if affectedWalls && (maxSeverity == .moderate || maxSeverity == .heavy) {
            items.append(GeneratedLineItem(
                category: "DRW",
                selector: "DRW 1/2 R&D",
                description: "Remove & dispose mold-affected drywall",
                quantity: room.wallSf * 0.5, // Estimate 50% affected
                unit: "SF",
                notes: "Drywall removal with mold, bag and dispose",
                confidence: 0.75,
                source: .aiGenerated
            ))
        }

        // Anti-microbial treatment
        items.append(GeneratedLineItem(
            category: "CLN",
            selector: "CLN ANTIM",
            description: "Apply fungicidal anti-microbial",
            quantity: affectedArea,
            unit: "SF",
            notes: "EPA-registered fungicide application",
            confidence: 0.9,
            source: .aiGenerated
        ))

        // Clearance testing
        items.append(GeneratedLineItem(
            category: "HAZ",
            selector: "HAZ TEST",
            description: "Post-remediation clearance testing",
            quantity: 1,
            unit: "EA",
            notes: "Third-party clearance testing",
            confidence: 0.7,
            source: .aiGenerated
        ))

        return items
    }

    // MARK: - Room-Specific Items

    private func generateRoomSpecificItems(room: Room, annotations: [DamageAnnotation]) -> [GeneratedLineItem] {
        var items: [GeneratedLineItem] = []

        switch room.category {
        case .kitchen:
            // Check for appliance-related damage
            if annotations.contains(where: { $0.notes.lowercased().contains("refrigerator") || $0.notes.lowercased().contains("fridge") }) {
                items.append(GeneratedLineItem(
                    category: "APL",
                    selector: "APL REF R&R",
                    description: "Remove & reset refrigerator",
                    quantity: 1,
                    unit: "EA",
                    notes: "Move appliance for floor/wall work",
                    confidence: 0.7,
                    source: .aiGenerated
                ))
            }

            if annotations.contains(where: { $0.notes.lowercased().contains("dishwasher") }) {
                items.append(GeneratedLineItem(
                    category: "APL",
                    selector: "APL DW R&R",
                    description: "Remove & reset dishwasher",
                    quantity: 1,
                    unit: "EA",
                    notes: "Move appliance for floor work",
                    confidence: 0.7,
                    source: .aiGenerated
                ))
            }

            // Cabinet toe kick
            if annotations.contains(where: { $0.affectedSurfaces.contains(.floor) }) {
                items.append(GeneratedLineItem(
                    category: "CAB",
                    selector: "CAB TOE DET",
                    description: "Detach cabinet toe kick",
                    quantity: 10, // Estimate 10 LF
                    unit: "LF",
                    notes: "Detach toe kick for floor drying/replacement",
                    confidence: 0.6,
                    source: .aiGenerated
                ))
            }

        case .bathroom:
            // Toilet removal if floor affected
            if annotations.contains(where: { $0.affectedSurfaces.contains(.floor) }) {
                items.append(GeneratedLineItem(
                    category: "PLB",
                    selector: "PLB TOI R&R",
                    description: "Remove & reset toilet",
                    quantity: 1,
                    unit: "EA",
                    notes: "Move toilet for floor work",
                    confidence: 0.75,
                    source: .aiGenerated
                ))
            }

            // Vanity if applicable
            if annotations.contains(where: { $0.notes.lowercased().contains("vanity") }) {
                items.append(GeneratedLineItem(
                    category: "CAB",
                    selector: "CAB VAN R&R",
                    description: "Remove & reset vanity",
                    quantity: 1,
                    unit: "EA",
                    notes: "Move vanity for wall work",
                    confidence: 0.6,
                    source: .aiGenerated
                ))
            }

        case .laundry:
            if annotations.contains(where: { $0.affectedSurfaces.contains(.floor) }) {
                items.append(GeneratedLineItem(
                    category: "APL",
                    selector: "APL W/D R&R",
                    description: "Remove & reset washer/dryer",
                    quantity: 2, // Washer + dryer
                    unit: "EA",
                    notes: "Move appliances for floor work",
                    confidence: 0.7,
                    source: .aiGenerated
                ))
            }

        default:
            break
        }

        // General site protection
        items.insert(GeneratedLineItem(
            category: "GEN",
            selector: "GEN PROT",
            description: "Site protection - floor covering",
            quantity: room.squareFeet,
            unit: "SF",
            notes: "Protect unaffected areas during work",
            confidence: 0.8,
            source: .aiGenerated
        ), at: 0)

        return items
    }

    // MARK: - Helper Functions

    private func severityRank(_ severity: DamageSeverity) -> Int {
        switch severity {
        case .light: return 1
        case .moderate: return 2
        case .heavy: return 3
        case .destroyed: return 4
        }
    }

    private func determineWaterClass(severity: DamageSeverity, annotations: [DamageAnnotation]) -> Int {
        let affectsCeiling = annotations.contains { $0.affectedSurfaces.contains(.ceiling) }
        let maxWaterLine = annotations.compactMap { $0.affectedHeightIn }.max() ?? 0

        if affectsCeiling || maxWaterLine > 48 {
            return 3 // Class 3: walls > 24", ceiling affected
        } else if maxWaterLine > 24 {
            return 2 // Class 2: entire room, walls < 24"
        } else {
            return 1 // Class 1: part of room
        }
    }

    private func calculateAffectedArea(room: Room, annotations: [DamageAnnotation]) -> Double {
        var totalArea: Double = 0

        for annotation in annotations {
            if annotation.affectedSurfaces.contains(.floor) {
                totalArea += room.squareFeet
            }
            if annotation.affectedSurfaces.contains(.wall) {
                let wallHeight = annotation.affectedHeightIn ?? room.heightIn
                totalArea += room.perimeterLf * (wallHeight / 12)
            }
            if annotation.affectedSurfaces.contains(.ceiling) {
                totalArea += room.ceilingSf
            }
        }

        return totalArea
    }

    private func calculateDryingEquipment(room: Room, waterClass: Int) -> (dehuCount: Int, airMoverCount: Int, days: Int) {
        let cubicFeet = room.squareFeet * (room.heightIn / 12)

        // Per IICRC S500:
        // Dehumidifiers: 1 per 1000-1200 CF
        // Air movers: 1 per 10-16 LF of wall (Class 2)

        let dehuCount = max(1, Int(ceil(cubicFeet / 1000)))

        let airMoverRatio: Double
        switch waterClass {
        case 1: airMoverRatio = 16
        case 2: airMoverRatio = 13
        case 3: airMoverRatio = 10
        default: airMoverRatio = 13
        }
        let airMoverCount = max(2, Int(ceil(room.perimeterLf / airMoverRatio)))

        // Days based on class
        let days: Int
        switch waterClass {
        case 1: days = 3
        case 2: days = 4
        case 3: days = 5
        default: days = 3
        }

        return (dehuCount, airMoverCount, days)
    }

    private func floorSelector(for material: FloorMaterial?) -> String {
        switch material {
        case .carpet: return "CPT"
        case .laminate: return "LAM"
        case .lvp: return "LVP"
        case .hardwood: return "HWD"
        case .tile: return "TLE"
        case .vinyl: return "VNL"
        case .concrete: return "CONC"
        default: return "GEN"
        }
    }
}

// MARK: - Generated Line Item Model

struct GeneratedLineItem: Identifiable {
    let id = UUID()
    let category: String
    let selector: String
    let description: String
    let quantity: Double
    let unit: String
    let notes: String
    let confidence: Double
    let source: LineItemSource

    enum LineItemSource: String {
        case manual
        case aiGenerated
        case templateBased
    }
}
