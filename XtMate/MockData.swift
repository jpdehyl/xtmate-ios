import Foundation
import SwiftUI

// MARK: - Room Extension for Mock Data
extension Room {
    /// Manual initializer for creating mock rooms without RoomPlan capture
    /// P3-013: Added divisionLines and subRooms parameters
    init(
        id: UUID = UUID(),
        name: String,
        category: RoomCategory,
        floor: FloorLevel = .first,
        floorMaterial: FloorMaterial? = nil,
        wallMaterial: WallMaterial? = nil,
        ceilingMaterial: CeilingMaterial? = nil,
        lengthIn: Double,
        widthIn: Double,
        heightIn: Double = 96,
        wallCount: Int = 4,
        doorCount: Int = 1,
        windowCount: Int = 0,
        divisionLines: [DivisionLine]? = nil,
        subRooms: [SubRoom]? = nil,
        annotations: [DamageAnnotation] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.floor = floor
        self.floorMaterial = floorMaterial
        self.wallMaterial = wallMaterial
        self.ceilingMaterial = ceilingMaterial
        self.lengthIn = lengthIn
        self.widthIn = widthIn
        self.heightIn = heightIn
        self.wallCount = wallCount
        self.doorCount = doorCount
        self.windowCount = windowCount
        self.divisionLines = divisionLines
        self.subRooms = subRooms
        self.annotations = annotations
        self.createdAt = Date()
    }
}

// MARK: - Mock Data Generator
struct MockDataGenerator {

    /// Generate a complete set of mock estimates for testing
    static func generateMockEstimates() -> [Estimate] {
        return [
            createWaterDamageClaim(),
            createFireDamageClaim(),
            createStormDamageClaim(),
            createPrivateJobEstimate()
        ]
    }

    // MARK: - Water Damage Claim (Most Common)
    private static func createWaterDamageClaim() -> Estimate {
        let estimateId = UUID()

        // Create rooms with water damage annotations
        let kitchenAnnotation = DamageAnnotation(
            position: CGPoint(x: 0.3, y: 0.5),
            damageType: .water,
            severity: .heavy,
            affectedSurfaces: [.floor, .wall],
            affectedHeightIn: 18,
            notes: "Water line visible at 18\" on walls. Supply line burst under sink."
        )

        let hallwayAnnotation = DamageAnnotation(
            position: CGPoint(x: 0.5, y: 0.5),
            damageType: .water,
            severity: .moderate,
            affectedSurfaces: [.floor],
            affectedHeightIn: 6,
            notes: "Water migrated from kitchen. Carpet saturated."
        )

        let kitchenRoom = Room(
            name: "Kitchen",
            category: .kitchen,
            floor: .first,
            floorMaterial: .lvp,
            wallMaterial: .orangePeel,
            ceilingMaterial: .smoothDrywall,
            lengthIn: 168, // 14'
            widthIn: 144,  // 12'
            heightIn: 108, // 9'
            wallCount: 4,
            doorCount: 2,
            windowCount: 1,
            annotations: [kitchenAnnotation]
        )

        let hallwayRoom = Room(
            name: "Hallway",
            category: .hallway,
            floor: .first,
            floorMaterial: .carpet,
            wallMaterial: .smooth,
            ceilingMaterial: .smoothDrywall,
            lengthIn: 180, // 15'
            widthIn: 48,   // 4'
            heightIn: 96,  // 8'
            wallCount: 2,
            doorCount: 3,
            windowCount: 0,
            annotations: [hallwayAnnotation]
        )

        let livingRoom = Room(
            name: "Living Room",
            category: .livingRoom,
            floor: .first,
            floorMaterial: .carpet,
            wallMaterial: .orangePeel,
            ceilingMaterial: .smoothDrywall,
            lengthIn: 216, // 18'
            widthIn: 180,  // 15'
            heightIn: 108, // 9'
            wallCount: 4,
            doorCount: 1,
            windowCount: 3
        )

        let masterBedroom = Room(
            name: "Master Bedroom",
            category: .bedroom,
            floor: .first,
            floorMaterial: .carpet,
            wallMaterial: .smooth,
            ceilingMaterial: .smoothDrywall,
            lengthIn: 168, // 14'
            widthIn: 144,  // 12'
            heightIn: 96,
            wallCount: 4,
            doorCount: 2,
            windowCount: 2
        )

        // Create assignments
        let emergencyAssignment = Assignment(
            estimateId: estimateId,
            type: .emergency,
            status: .inProgress,
            subtotal: 3245.00,
            overhead: 324.50,
            profit: 324.50,
            total: 3894.00,
            order: 0
        )

        let repairsAssignment = Assignment(
            estimateId: estimateId,
            type: .repairs,
            status: .pending,
            order: 1
        )

        // Create line items
        let lineItems = [
            ScopeLineItem(
                category: "WTR",
                selector: "WTREXTRT",
                description: "Extract water from floor - wet vacuum",
                quantity: 168.0,
                unit: "SF",
                unitPrice: 0.85,
                roomId: kitchenRoom.id,
                source: .aiGenerated
            ),
            ScopeLineItem(
                category: "DRY",
                selector: "DRYAIRM",
                description: "Air mover (per 24 hour period)",
                quantity: 3.0,
                unit: "EA",
                unitPrice: 45.00,
                roomId: kitchenRoom.id,
                source: .aiGenerated
            ),
            ScopeLineItem(
                category: "DRY",
                selector: "DRYDEHUM",
                description: "Dehumidifier (per 24 hour period)",
                quantity: 1.0,
                unit: "EA",
                unitPrice: 125.00,
                roomId: kitchenRoom.id,
                source: .aiGenerated
            ),
            ScopeLineItem(
                category: "DEM",
                selector: "DEMBASE",
                description: "Remove baseboard - wood",
                quantity: 52.0,
                unit: "LF",
                unitPrice: 1.25,
                roomId: kitchenRoom.id,
                source: .aiGenerated
            ),
            ScopeLineItem(
                category: "DEM",
                selector: "DEMDRY18",
                description: "Remove drywall - to 18 inches",
                quantity: 52.0,
                unit: "LF",
                unitPrice: 2.50,
                roomId: kitchenRoom.id,
                source: .aiGenerated
            )
        ]

        return Estimate(
            id: estimateId,
            name: "1423 Maple Street Water Loss",
            claimNumber: "WC-2025-00847",
            policyNumber: "HO-789456123",
            insuredName: "Johnson, Michael & Sarah",
            insuredPhone: "(512) 555-0147",
            insuredEmail: "mjohnson@email.com",
            propertyAddress: "1423 Maple Street",
            propertyCity: "Austin",
            propertyState: "TX",
            propertyZip: "78704",
            causeOfLoss: "Water",
            status: .inProgress,
            rooms: [kitchenRoom, hallwayRoom, livingRoom, masterBedroom],
            assignments: [emergencyAssignment, repairsAssignment],
            lineItems: lineItems,
            jobType: .insurance,
            xaId: "06PJV6Y",
            dispatchType: .rush,
            dateOfLoss: Calendar.current.date(byAdding: .day, value: -3, to: Date()),
            adjusterName: "Tom Harrison",
            adjusterPhone: "(512) 555-9821",
            adjusterEmail: "tharrison@stateins.com",
            insuranceCompany: "State Insurance Co."
        )
    }

    // MARK: - Fire Damage Claim
    private static func createFireDamageClaim() -> Estimate {
        let estimateId = UUID()

        let kitchenAnnotation = DamageAnnotation(
            position: CGPoint(x: 0.4, y: 0.6),
            damageType: .fire,
            severity: .heavy,
            affectedSurfaces: [.wall, .ceiling],
            notes: "Significant charring on cabinets. Ceiling has burn damage."
        )

        let smokeAnnotation = DamageAnnotation(
            position: CGPoint(x: 0.5, y: 0.3),
            damageType: .smoke,
            severity: .moderate,
            affectedSurfaces: [.wall, .ceiling],
            notes: "Heavy smoke residue throughout. Ceiling needs cleaning."
        )

        let kitchenRoom = Room(
            name: "Kitchen",
            category: .kitchen,
            floor: .first,
            floorMaterial: .tile,
            wallMaterial: .smooth,
            ceilingMaterial: .smoothDrywall,
            lengthIn: 156, // 13'
            widthIn: 132,  // 11'
            heightIn: 96,
            wallCount: 4,
            doorCount: 2,
            windowCount: 2,
            annotations: [kitchenAnnotation]
        )

        let diningRoom = Room(
            name: "Dining Room",
            category: .diningRoom,
            floor: .first,
            floorMaterial: .hardwood,
            wallMaterial: .smooth,
            ceilingMaterial: .smoothDrywall,
            lengthIn: 144, // 12'
            widthIn: 120,  // 10'
            heightIn: 96,
            wallCount: 4,
            doorCount: 1,
            windowCount: 1,
            annotations: [smokeAnnotation]
        )

        let livingRoom = Room(
            name: "Living Room",
            category: .livingRoom,
            floor: .first,
            floorMaterial: .hardwood,
            wallMaterial: .smooth,
            ceilingMaterial: .textured,
            lengthIn: 192, // 16'
            widthIn: 168,  // 14'
            heightIn: 108,
            wallCount: 4,
            doorCount: 2,
            windowCount: 2
        )

        let emergencyAssignment = Assignment(
            estimateId: estimateId,
            type: .emergency,
            status: .submitted,
            subtotal: 5680.00,
            overhead: 568.00,
            profit: 568.00,
            total: 6816.00,
            order: 0
        )

        let repairsAssignment = Assignment(
            estimateId: estimateId,
            type: .repairs,
            status: .pending,
            order: 1
        )

        let contentsAssignment = Assignment(
            estimateId: estimateId,
            type: .contents,
            status: .pending,
            order: 2
        )

        return Estimate(
            id: estimateId,
            name: "892 Oak Drive Fire Loss",
            claimNumber: "FC-2025-00234",
            policyNumber: "HO-456789012",
            insuredName: "Williams, Robert",
            insuredPhone: "(512) 555-0298",
            insuredEmail: "rwilliams@gmail.com",
            propertyAddress: "892 Oak Drive",
            propertyCity: "Round Rock",
            propertyState: "TX",
            propertyZip: "78664",
            causeOfLoss: "Fire",
            status: .inProgress,
            rooms: [kitchenRoom, diningRoom, livingRoom],
            assignments: [emergencyAssignment, repairsAssignment, contentsAssignment],
            lineItems: [],
            jobType: .insurance,
            xaId: "07KRTM2",
            dispatchType: .emergency,
            dateOfLoss: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            adjusterName: "Jennifer Adams",
            adjusterPhone: "(512) 555-7743",
            adjusterEmail: "jadams@nationalins.com",
            insuranceCompany: "National Insurance Corp."
        )
    }

    // MARK: - Storm Damage Claim
    private static func createStormDamageClaim() -> Estimate {
        let estimateId = UUID()

        let roofAnnotation = DamageAnnotation(
            position: CGPoint(x: 0.5, y: 0.2),
            damageType: .wind,
            severity: .heavy,
            affectedSurfaces: [.ceiling],
            notes: "Multiple shingles missing. Water intrusion visible on ceiling."
        )

        let bedroom1 = Room(
            name: "Master Bedroom",
            category: .bedroom,
            floor: .second,
            floorMaterial: .carpet,
            wallMaterial: .knockdown,
            ceilingMaterial: .textured,
            lengthIn: 180, // 15'
            widthIn: 156,  // 13'
            heightIn: 96,
            wallCount: 4,
            doorCount: 2,
            windowCount: 2,
            annotations: [roofAnnotation]
        )

        let bedroom2 = Room(
            name: "Bedroom 2",
            category: .bedroom,
            floor: .second,
            floorMaterial: .carpet,
            wallMaterial: .knockdown,
            ceilingMaterial: .textured,
            lengthIn: 132, // 11'
            widthIn: 120,  // 10'
            heightIn: 96,
            wallCount: 4,
            doorCount: 1,
            windowCount: 1
        )

        let hallway = Room(
            name: "Upstairs Hallway",
            category: .hallway,
            floor: .second,
            floorMaterial: .carpet,
            wallMaterial: .knockdown,
            ceilingMaterial: .textured,
            lengthIn: 144, // 12'
            widthIn: 48,   // 4'
            heightIn: 96,
            wallCount: 2,
            doorCount: 4,
            windowCount: 0
        )

        let repairsAssignment = Assignment(
            estimateId: estimateId,
            type: .repairs,
            status: .pending,
            order: 0
        )

        return Estimate(
            id: estimateId,
            name: "2156 Pecan Lane Storm Damage",
            claimNumber: "SD-2025-00567",
            policyNumber: "HO-321654987",
            insuredName: "Garcia, Maria",
            insuredPhone: "(512) 555-0456",
            insuredEmail: "mgarcia@yahoo.com",
            propertyAddress: "2156 Pecan Lane",
            propertyCity: "Cedar Park",
            propertyState: "TX",
            propertyZip: "78613",
            causeOfLoss: "Storm",
            status: .draft,
            rooms: [bedroom1, bedroom2, hallway],
            assignments: [repairsAssignment],
            lineItems: [],
            jobType: .insurance,
            xaId: "08LPQR5",
            dispatchType: .normal,
            dateOfLoss: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
            adjusterName: "David Chen",
            adjusterPhone: "(512) 555-3344",
            adjusterEmail: "dchen@texasins.com",
            insuranceCompany: "Texas Insurance Group"
        )
    }

    // MARK: - Private Job (Non-Insurance)
    private static func createPrivateJobEstimate() -> Estimate {
        let estimateId = UUID()

        let bathroomAnnotation = DamageAnnotation(
            position: CGPoint(x: 0.5, y: 0.5),
            damageType: .water,
            severity: .moderate,
            affectedSurfaces: [.floor, .wall],
            affectedHeightIn: 12,
            notes: "Shower pan leak. Subfloor may need replacement."
        )

        let masterBath = Room(
            name: "Master Bathroom",
            category: .bathroom,
            floor: .first,
            floorMaterial: .tile,
            wallMaterial: .smooth,
            ceilingMaterial: .smoothDrywall,
            lengthIn: 120, // 10'
            widthIn: 96,   // 8'
            heightIn: 96,
            wallCount: 4,
            doorCount: 1,
            windowCount: 1,
            annotations: [bathroomAnnotation]
        )

        let closet = Room(
            name: "Walk-in Closet",
            category: .closet,
            floor: .first,
            floorMaterial: .carpet,
            wallMaterial: .smooth,
            ceilingMaterial: .smoothDrywall,
            lengthIn: 84,  // 7'
            widthIn: 72,   // 6'
            heightIn: 96,
            wallCount: 4,
            doorCount: 1,
            windowCount: 0
        )

        let emergencyAssignment = Assignment(
            estimateId: estimateId,
            type: .emergencyPrivate,
            status: .inProgress,
            subtotal: 1850.00,
            overhead: 185.00,
            profit: 185.00,
            total: 2220.00,
            order: 0
        )

        let repairsAssignment = Assignment(
            estimateId: estimateId,
            type: .repairsPrivate,
            status: .pending,
            order: 1
        )

        let lineItems = [
            ScopeLineItem(
                category: "WTR",
                selector: "WTREXTRT",
                description: "Extract water from floor - wet vacuum",
                quantity: 80.0,
                unit: "SF",
                unitPrice: 0.85,
                roomId: masterBath.id,
                source: .manual
            ),
            ScopeLineItem(
                category: "DEM",
                selector: "DEMTILE",
                description: "Remove ceramic tile flooring",
                quantity: 80.0,
                unit: "SF",
                unitPrice: 2.75,
                roomId: masterBath.id,
                source: .manual
            )
        ]

        return Estimate(
            id: estimateId,
            name: "Private - Thompson Bathroom Repair",
            claimNumber: nil,
            policyNumber: nil,
            insuredName: "Thompson, James",
            insuredPhone: "(512) 555-8899",
            insuredEmail: "jthompson@email.com",
            propertyAddress: "445 Birch Street",
            propertyCity: "Austin",
            propertyState: "TX",
            propertyZip: "78745",
            causeOfLoss: "Water",
            status: .inProgress,
            rooms: [masterBath, closet],
            assignments: [emergencyAssignment, repairsAssignment],
            lineItems: lineItems,
            jobType: .privateJob
        )
    }
}

// MARK: - EstimateStore Extension for Mock Data
extension EstimateStore {
    /// Load mock data for simulator testing
    /// Call this in development/preview environments
    func loadMockData() {
        // Only load if estimates are empty
        guard estimates.isEmpty else { return }

        estimates = MockDataGenerator.generateMockEstimates()
        currentEstimate = estimates.first
    }

    /// Force reload mock data (replaces existing data)
    func resetWithMockData() {
        estimates = MockDataGenerator.generateMockEstimates()
        currentEstimate = estimates.first
        // Note: This does NOT persist to UserDefaults, so closing the app will restore saved data
    }

    /// Create a sample estimate store pre-populated with mock data (for previews)
    static var preview: EstimateStore {
        let store = EstimateStore()
        store.estimates = MockDataGenerator.generateMockEstimates()
        store.currentEstimate = store.estimates.first
        return store
    }
}

// MARK: - Preview Helpers
#if DEBUG
struct MockData_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            List {
                ForEach(MockDataGenerator.generateMockEstimates()) { estimate in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(estimate.displayName)
                            .font(.headline)

                        HStack {
                            ForEach(estimate.assignments.sorted { $0.order < $1.order }) { assignment in
                                Text(assignment.type.shortCode)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(assignment.type.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(assignment.type.color.opacity(0.15))
                                    .cornerRadius(4)
                            }

                            Spacer()

                            Text("\(estimate.rooms.count) rooms")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let claim = estimate.claimNumber {
                            Text("#\(claim)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Mock Estimates")
        }
    }
}
#endif
