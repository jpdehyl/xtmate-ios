//
//  RoomBoundaryAnalyzer.swift
//  XtMate
//
//  Analyzes CapturedRoom geometry to automatically detect room boundaries
//  from a single LiDAR scan. Uses wall graph analysis, cycle detection,
//  and object clustering to identify separate rooms in open floor plans.
//
//  PRD: Room Capture Enhancements - US-RC-002
//

import Foundation
import CoreGraphics
import RoomPlan
import simd

/// Analyzes CapturedRoom to automatically detect separate room boundaries
@available(iOS 16.0, *)
final class RoomBoundaryAnalyzer {

    // MARK: - Configuration

    /// Minimum room area in square feet to be considered valid
    private let minimumRoomArea: Double = 20.0  // 20 SF minimum

    /// Maximum room area in square feet (anything larger is likely multiple rooms)
    private let maximumSingleRoomArea: Double = 400.0  // 400 SF before suggesting split

    /// Minimum confidence to auto-suggest a room
    private let minimumConfidence: Float = 0.5

    /// Tolerance for door detection (distance from wall in feet)
    private let doorTolerance: CGFloat = 2.0

    /// Meters to feet conversion
    private let metersToFeet: CGFloat = 3.28084

    // MARK: - Dependencies

    private let graphBuilder = WallGraphBuilder()

    // MARK: - Public Interface

    /// Analyze a CapturedRoom and return proposed room boundaries
    func analyze(_ capturedRoom: CapturedRoom) -> RoomBoundaryAnalysisResult {
        print("RoomBoundaryAnalyzer: Starting analysis")
        print("  - Walls: \(capturedRoom.walls.count)")
        print("  - Doors: \(capturedRoom.doors.count)")
        print("  - Windows: \(capturedRoom.windows.count)")
        print("  - Objects: \(capturedRoom.objects.count)")

        // Build wall graph
        let wallGraph = graphBuilder.buildGraph(from: capturedRoom)

        guard !wallGraph.nodes.isEmpty else {
            return RoomBoundaryAnalysisResult(
                wasSuccessful: false,
                failureReason: "No wall data found in scan"
            )
        }

        // Extract doors and windows
        let doors = extractDoors(from: capturedRoom)
        let windows = extractWindows(from: capturedRoom)
        let objects = extractObjects(from: capturedRoom)

        print("  - Extracted \(doors.count) doors, \(windows.count) windows, \(objects.count) objects")

        // Try multiple detection strategies
        var proposedRooms: [ProposedRoom] = []

        // Strategy 1: Door-based room separation
        let doorBasedRooms = detectRoomsByDoors(
            wallGraph: wallGraph,
            doors: doors,
            objects: objects,
            capturedRoom: capturedRoom
        )

        if !doorBasedRooms.isEmpty {
            proposedRooms = doorBasedRooms
            print("  - Door-based detection found \(doorBasedRooms.count) rooms")
        }

        // Strategy 2: Cycle-based detection (if door-based failed or found only 1 room)
        if proposedRooms.count <= 1 {
            let cycleBasedRooms = detectRoomsByCycles(
                wallGraph: wallGraph,
                objects: objects,
                capturedRoom: capturedRoom
            )

            if cycleBasedRooms.count > proposedRooms.count {
                proposedRooms = cycleBasedRooms
                print("  - Cycle-based detection found \(cycleBasedRooms.count) rooms")
            }
        }

        // Strategy 3: Object clustering (if other strategies found only 1 room)
        if proposedRooms.count <= 1 && objects.count >= 2 {
            let objectBasedRooms = detectRoomsByObjectClustering(
                wallGraph: wallGraph,
                objects: objects,
                capturedRoom: capturedRoom
            )

            if objectBasedRooms.count > proposedRooms.count {
                proposedRooms = objectBasedRooms
                print("  - Object clustering found \(objectBasedRooms.count) rooms")
            }
        }

        // Fallback: Create single room from entire scan
        if proposedRooms.isEmpty {
            let singleRoom = createSingleRoomFromScan(
                wallGraph: wallGraph,
                doors: doors,
                windows: windows,
                objects: objects,
                capturedRoom: capturedRoom
            )
            proposedRooms = [singleRoom]
            print("  - Fallback: Created single room")
        }

        // Assign doorways to rooms
        let doorways = assignDoorwaysToRooms(doors: doors, rooms: &proposedRooms)

        // Calculate overall confidence
        let overallConfidence = calculateOverallConfidence(
            rooms: proposedRooms,
            originalScan: capturedRoom
        )

        print("RoomBoundaryAnalyzer: Analysis complete")
        print("  - Proposed rooms: \(proposedRooms.count)")
        print("  - Overall confidence: \(String(format: "%.2f", overallConfidence))")

        return RoomBoundaryAnalysisResult(
            proposedRooms: proposedRooms,
            doorways: doorways,
            windows: windows,
            overallConfidence: overallConfidence,
            wasSuccessful: true
        )
    }

    // MARK: - Strategy 1: Door-Based Detection

    /// Detect rooms by using doors as separators
    private func detectRoomsByDoors(
        wallGraph: WallGraphBuilder.WallGraph,
        doors: [Doorway],
        objects: [DetectedObject],
        capturedRoom: CapturedRoom
    ) -> [ProposedRoom] {
        guard doors.count >= 1 else { return [] }

        var proposedRooms: [ProposedRoom] = []

        // For each door, try to find the rooms it connects
        // This is done by flood-filling from each side of the door

        // Create regions by flood-filling from door positions
        let regions = floodFillFromDoors(
            doors: doors,
            boundingBox: wallGraph.boundingBox,
            wallSegments: wallGraph.edges.map { $0.wallSegment }
        )

        for (index, region) in regions.enumerated() {
            // Find objects in this region
            let regionObjects = objects.filter { obj in
                isPointInPolygon(obj.position, polygon: region)
            }

            // Classify room based on objects
            let (name, category, confidence) = classifyRoom(
                objects: regionObjects,
                area: calculatePolygonArea(region)
            )

            // Calculate bounding box
            let boundingBox = calculateBoundingBox(for: region)

            // Get wall segments for this region
            let wallSegments = wallGraph.edges.compactMap { edge -> WallSegment? in
                let segment = edge.wallSegment
                if isSegmentInRegion(segment, region: region) {
                    return segment
                }
                return nil
            }

            // Count doors for this region
            let doorCount = doors.filter { door in
                isPointNearPolygon(door.position, polygon: region, tolerance: doorTolerance)
            }.count

            // Count windows for this region
            let windowCount = countWindowsInRegion(region, capturedRoom: capturedRoom)

            // Average wall height
            let avgHeight = wallSegments.isEmpty ? 8.0 :
                wallSegments.reduce(0.0) { $0 + $1.heightFt } / CGFloat(wallSegments.count)

            let room = ProposedRoom(
                suggestedName: name,
                suggestedCategory: category,
                confidence: confidence,
                boundary: region,
                boundingBox: boundingBox,
                detectedObjects: regionObjects,
                doorwayCount: doorCount,
                windowCount: windowCount,
                wallSegments: wallSegments,
                isClosed: isPolygonClosed(region),
                avgHeightFt: Double(avgHeight)
            )

            // Only add if area is reasonable
            if room.squareFeet >= minimumRoomArea {
                proposedRooms.append(room)
            }
        }

        return proposedRooms
    }

    /// Flood fill from door positions to create regions
    private func floodFillFromDoors(
        doors: [Doorway],
        boundingBox: CGRect,
        wallSegments: [WallSegment]
    ) -> [[CGPoint]] {
        var regions: [[CGPoint]] = []

        // Simple approach: create convex hulls around door entry points
        // For each door, sample points on either side and grow regions

        for door in doors {
            // Get perpendicular direction to door
            let perpAngle = door.rotation + .pi / 2
            let offset = door.width / 2 + 1.0  // 1 foot past door

            // Sample points on either side of door
            let sideA = CGPoint(
                x: door.position.x + cos(perpAngle) * offset,
                y: door.position.y + sin(perpAngle) * offset
            )
            let sideB = CGPoint(
                x: door.position.x - cos(perpAngle) * offset,
                y: door.position.y - sin(perpAngle) * offset
            )

            // For now, use simple rectangular regions based on door positions
            // A more sophisticated approach would trace walls
            let regionSize: CGFloat = 10.0  // 10 feet default region

            for seedPoint in [sideA, sideB] {
                // Create a simple rectangular region around the seed point
                let region = [
                    CGPoint(x: seedPoint.x - regionSize/2, y: seedPoint.y - regionSize/2),
                    CGPoint(x: seedPoint.x + regionSize/2, y: seedPoint.y - regionSize/2),
                    CGPoint(x: seedPoint.x + regionSize/2, y: seedPoint.y + regionSize/2),
                    CGPoint(x: seedPoint.x - regionSize/2, y: seedPoint.y + regionSize/2)
                ]

                // Check if this region overlaps with existing regions
                var isUnique = true
                for existingRegion in regions {
                    if regionsOverlap(region, existingRegion) {
                        isUnique = false
                        break
                    }
                }

                if isUnique && isRegionInBounds(region, boundingBox: boundingBox) {
                    regions.append(region)
                }
            }
        }

        return regions
    }

    // MARK: - Strategy 2: Cycle-Based Detection

    /// Detect rooms by finding cycles in the wall graph
    private func detectRoomsByCycles(
        wallGraph: WallGraphBuilder.WallGraph,
        objects: [DetectedObject],
        capturedRoom: CapturedRoom
    ) -> [ProposedRoom] {
        // Find all cycles in the graph
        let cycles = graphBuilder.findCycles(in: wallGraph)

        var proposedRooms: [ProposedRoom] = []

        for cycle in cycles {
            // Convert cycle to polygon
            let polygon = graphBuilder.cycleToPolygon(cycle, graph: wallGraph)

            guard polygon.count >= 3 else { continue }

            let area = abs(calculatePolygonArea(polygon))

            // Skip if area is too small or too large
            guard area >= minimumRoomArea else { continue }

            // Find objects in this polygon
            let regionObjects = objects.filter { obj in
                isPointInPolygon(obj.position, polygon: polygon)
            }

            // Classify room
            let (name, category, confidence) = classifyRoom(
                objects: regionObjects,
                area: area
            )

            // Get wall segments from cycle edges
            let wallSegments = cycle.enumerated().compactMap { index, nodeId -> WallSegment? in
                let nextIndex = (index + 1) % cycle.count
                let nextNodeId = cycle[nextIndex]

                // Find the edge connecting these nodes
                if let edge = wallGraph.edges.first(where: {
                    ($0.startNode == nodeId && $0.endNode == nextNodeId) ||
                    ($0.endNode == nodeId && $0.startNode == nextNodeId)
                }) {
                    return edge.wallSegment
                }
                return nil
            }

            let avgHeight = wallSegments.isEmpty ? 8.0 :
                wallSegments.reduce(0.0) { $0 + $1.heightFt } / CGFloat(wallSegments.count)

            let room = ProposedRoom(
                suggestedName: name,
                suggestedCategory: category,
                confidence: confidence,
                boundary: polygon,
                boundingBox: calculateBoundingBox(for: polygon),
                detectedObjects: regionObjects,
                doorwayCount: 0,  // Will be assigned later
                windowCount: countWindowsInRegion(polygon, capturedRoom: capturedRoom),
                wallSegments: wallSegments,
                isClosed: true,
                avgHeightFt: Double(avgHeight)
            )

            proposedRooms.append(room)
        }

        // Remove overlapping rooms (keep larger ones)
        proposedRooms = removeOverlappingRooms(proposedRooms)

        return proposedRooms
    }

    // MARK: - Strategy 3: Object Clustering

    /// Detect rooms by clustering objects (e.g., bathroom fixtures together)
    private func detectRoomsByObjectClustering(
        wallGraph: WallGraphBuilder.WallGraph,
        objects: [DetectedObject],
        capturedRoom: CapturedRoom
    ) -> [ProposedRoom] {
        // Group objects by category affinity
        let clusters = clusterObjectsByAffinity(objects)

        guard clusters.count > 1 else { return [] }

        var proposedRooms: [ProposedRoom] = []

        for (clusterObjects, suggestedCategory) in clusters {
            // Create bounding polygon around cluster
            let positions = clusterObjects.map { $0.position }
            let convexHull = calculateConvexHull(positions)

            guard convexHull.count >= 3 else { continue }

            // Expand hull slightly
            let expandedHull = expandPolygon(convexHull, by: 3.0)  // 3 feet expansion

            let (name, category, confidence) = classifyRoom(
                objects: clusterObjects,
                area: calculatePolygonArea(expandedHull)
            )

            // Find wall segments near this region
            let wallSegments = wallGraph.edges.compactMap { edge -> WallSegment? in
                let segment = edge.wallSegment
                if isSegmentNearRegion(segment, region: expandedHull, tolerance: 2.0) {
                    return segment
                }
                return nil
            }

            let room = ProposedRoom(
                suggestedName: name,
                suggestedCategory: suggestedCategory,
                confidence: confidence * 0.7,  // Lower confidence for object-based detection
                boundary: expandedHull,
                boundingBox: calculateBoundingBox(for: expandedHull),
                detectedObjects: clusterObjects,
                doorwayCount: 0,
                windowCount: 0,
                wallSegments: wallSegments,
                isClosed: false,
                avgHeightFt: 8.0
            )

            if room.squareFeet >= minimumRoomArea {
                proposedRooms.append(room)
            }
        }

        return proposedRooms
    }

    /// Cluster objects by their affinity (e.g., bathroom fixtures together)
    private func clusterObjectsByAffinity(_ objects: [DetectedObject]) -> [([DetectedObject], RoomCategory)] {
        var clusters: [([DetectedObject], RoomCategory)] = []

        // Group by room type affinity
        var bathroomObjects: [DetectedObject] = []
        var kitchenObjects: [DetectedObject] = []
        var bedroomObjects: [DetectedObject] = []
        var livingRoomObjects: [DetectedObject] = []
        var laundryObjects: [DetectedObject] = []
        var otherObjects: [DetectedObject] = []

        for obj in objects {
            let category = obj.category.lowercased()

            switch category {
            case "toilet", "bathtub", "shower", "sink":
                // Sink could be kitchen or bathroom - check proximity
                if bathroomObjects.isEmpty || isNearObjects(obj, bathroomObjects, threshold: 6.0) {
                    bathroomObjects.append(obj)
                } else if kitchenObjects.isEmpty || isNearObjects(obj, kitchenObjects, threshold: 6.0) {
                    kitchenObjects.append(obj)
                } else {
                    bathroomObjects.append(obj)
                }

            case "refrigerator", "stove", "oven", "dishwasher", "microwave":
                kitchenObjects.append(obj)

            case "bed":
                bedroomObjects.append(obj)

            case "sofa", "couch", "tv", "television":
                livingRoomObjects.append(obj)

            case "washer", "dryer", "washerdryer":
                laundryObjects.append(obj)

            default:
                otherObjects.append(obj)
            }
        }

        if !bathroomObjects.isEmpty { clusters.append((bathroomObjects, .bathroom)) }
        if !kitchenObjects.isEmpty { clusters.append((kitchenObjects, .kitchen)) }
        if !bedroomObjects.isEmpty { clusters.append((bedroomObjects, .bedroom)) }
        if !livingRoomObjects.isEmpty { clusters.append((livingRoomObjects, .livingRoom)) }
        if !laundryObjects.isEmpty { clusters.append((laundryObjects, .laundry)) }
        if !otherObjects.isEmpty { clusters.append((otherObjects, .other)) }

        return clusters
    }

    /// Check if an object is near other objects
    private func isNearObjects(_ obj: DetectedObject, _ others: [DetectedObject], threshold: CGFloat) -> Bool {
        for other in others {
            let dx = obj.position.x - other.position.x
            let dy = obj.position.y - other.position.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance <= threshold {
                return true
            }
        }
        return false
    }

    // MARK: - Fallback: Single Room

    /// Create a single room from the entire scan (fallback)
    private func createSingleRoomFromScan(
        wallGraph: WallGraphBuilder.WallGraph,
        doors: [Doorway],
        windows: [FloorPlanWindow],
        objects: [DetectedObject],
        capturedRoom: CapturedRoom
    ) -> ProposedRoom {
        // Use bounding box as boundary
        let bbox = wallGraph.boundingBox
        let boundary = [
            CGPoint(x: bbox.minX, y: bbox.minY),
            CGPoint(x: bbox.maxX, y: bbox.minY),
            CGPoint(x: bbox.maxX, y: bbox.maxY),
            CGPoint(x: bbox.minX, y: bbox.maxY)
        ]

        // Classify based on objects
        let (name, category, confidence) = classifyRoom(
            objects: objects,
            area: Double(bbox.width * bbox.height)
        )

        // Get all wall segments
        let wallSegments = wallGraph.edges.map { $0.wallSegment }

        let avgHeight = wallSegments.isEmpty ? 8.0 :
            wallSegments.reduce(0.0) { $0 + $1.heightFt } / CGFloat(wallSegments.count)

        return ProposedRoom(
            suggestedName: name.isEmpty ? "Open Space" : name,
            suggestedCategory: category,
            confidence: confidence * 0.5,  // Lower confidence for single room
            boundary: boundary,
            boundingBox: bbox,
            detectedObjects: objects,
            doorwayCount: doors.count,
            windowCount: windows.count,
            wallSegments: wallSegments,
            isClosed: wallGraph.cornerNodes.count >= 4,
            avgHeightFt: Double(avgHeight)
        )
    }

    // MARK: - Room Classification

    /// Classify a room based on its objects and size
    private func classifyRoom(
        objects: [DetectedObject],
        area: Double
    ) -> (name: String, category: RoomCategory, confidence: Float) {
        var confidence: Float = 0.3  // Base confidence

        // Check for identifying objects
        for obj in objects {
            let category = obj.category.lowercased()

            switch category {
            case "toilet", "bathtub", "shower":
                confidence += 0.3
                return ("Bathroom", .bathroom, min(confidence, 0.95))

            case "refrigerator", "stove", "oven", "dishwasher":
                confidence += 0.3
                return ("Kitchen", .kitchen, min(confidence, 0.95))

            case "bed":
                confidence += 0.2
                return ("Bedroom", .bedroom, min(confidence, 0.9))

            case "sofa", "couch":
                confidence += 0.2
                return ("Living Room", .livingRoom, min(confidence, 0.9))

            case "washer", "dryer", "washerdryer":
                confidence += 0.3
                return ("Laundry", .laundry, min(confidence, 0.95))

            case "desk", "computer":
                confidence += 0.2
                return ("Office", .office, min(confidence, 0.85))

            default:
                break
            }
        }

        // Check for combinations
        let categories = Set(objects.map { $0.category.lowercased() })

        if categories.contains("refrigerator") || categories.contains("stove") {
            return ("Kitchen", .kitchen, 0.85)
        }

        if categories.contains("toilet") || categories.contains("bathtub") {
            return ("Bathroom", .bathroom, 0.85)
        }

        // Guess based on size
        if area < 50 {
            return ("Closet", .closet, 0.4)
        } else if area < 80 {
            return ("Room", .other, 0.3)
        } else if area < 150 {
            return ("Room", .other, 0.3)
        } else if area < 300 {
            return ("Living Area", .livingRoom, 0.25)
        } else {
            return ("Open Space", .other, 0.2)
        }
    }

    // MARK: - Doorway Assignment

    /// Assign doorways to rooms they connect
    private func assignDoorwaysToRooms(doors: [Doorway], rooms: inout [ProposedRoom]) -> [Doorway] {
        var assignedDoorways: [Doorway] = []

        for door in doors {
            var connectsRooms: [UUID] = []

            for room in rooms {
                if isPointNearPolygon(door.position, polygon: room.boundary, tolerance: doorTolerance) {
                    connectsRooms.append(room.id)
                }
            }

            let assignedDoor = Doorway(
                id: door.id,
                position: door.position,
                width: door.width,
                rotation: door.rotation,
                connectsRooms: connectsRooms
            )

            assignedDoorways.append(assignedDoor)
        }

        return assignedDoorways
    }

    // MARK: - Confidence Calculation

    /// Calculate overall analysis confidence
    private func calculateOverallConfidence(
        rooms: [ProposedRoom],
        originalScan: CapturedRoom
    ) -> Float {
        guard !rooms.isEmpty else { return 0 }

        var confidence: Float = 0

        // Average room confidence
        let avgRoomConfidence = rooms.reduce(0.0) { $0 + $1.confidence } / Float(rooms.count)
        confidence += avgRoomConfidence * 0.4

        // Bonus for closed polygons
        let closedRatio = Float(rooms.filter { $0.isClosed }.count) / Float(rooms.count)
        confidence += closedRatio * 0.2

        // Bonus for having identifying objects
        let roomsWithObjects = rooms.filter { !$0.detectedObjects.isEmpty }.count
        let objectRatio = Float(roomsWithObjects) / Float(rooms.count)
        confidence += objectRatio * 0.2

        // Bonus for reasonable sizes
        let reasonableSizeRooms = rooms.filter {
            $0.squareFeet >= minimumRoomArea && $0.squareFeet <= maximumSingleRoomArea
        }.count
        let sizeRatio = Float(reasonableSizeRooms) / Float(rooms.count)
        confidence += sizeRatio * 0.2

        return min(confidence, 1.0)
    }

    // MARK: - Extraction Helpers

    /// Extract doors from CapturedRoom
    private func extractDoors(from capturedRoom: CapturedRoom) -> [Doorway] {
        return capturedRoom.doors.map { door in
            let transform = door.transform
            let dimensions = door.dimensions

            let x = CGFloat(transform.columns.3.x) * metersToFeet
            let z = CGFloat(transform.columns.3.z) * metersToFeet
            let width = CGFloat(dimensions.x) * metersToFeet
            let rotation = atan2(CGFloat(transform.columns.0.z), CGFloat(transform.columns.0.x))

            return Doorway(
                position: CGPoint(x: x, y: z),
                width: width,
                rotation: rotation
            )
        }
    }

    /// Extract windows from CapturedRoom
    private func extractWindows(from capturedRoom: CapturedRoom) -> [FloorPlanWindow] {
        return capturedRoom.windows.map { window in
            let transform = window.transform
            let dimensions = window.dimensions

            let x = CGFloat(transform.columns.3.x) * metersToFeet
            let z = CGFloat(transform.columns.3.z) * metersToFeet
            let width = CGFloat(dimensions.x) * metersToFeet
            let rotation = atan2(CGFloat(transform.columns.0.z), CGFloat(transform.columns.0.x))

            return FloorPlanWindow(
                position: CGPoint(x: x, y: z),
                width: width,
                rotation: rotation
            )
        }
    }

    /// Extract objects from CapturedRoom
    private func extractObjects(from capturedRoom: CapturedRoom) -> [DetectedObject] {
        return capturedRoom.objects.map { obj in
            let transform = obj.transform
            let dimensions = obj.dimensions

            let x = CGFloat(transform.columns.3.x) * metersToFeet
            let z = CGFloat(transform.columns.3.z) * metersToFeet
            let width = CGFloat(dimensions.x) * metersToFeet
            let depth = CGFloat(dimensions.z) * metersToFeet

            return DetectedObject(
                category: objectCategoryToString(obj.category),
                position: CGPoint(x: x, y: z),
                width: width,
                depth: depth
            )
        }
    }

    /// Convert RoomPlan object category to string
    private func objectCategoryToString(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .storage: return "cabinet"
        case .refrigerator: return "refrigerator"
        case .stove: return "stove"
        case .bed: return "bed"
        case .sink: return "sink"
        case .washerDryer: return "washerDryer"
        case .toilet: return "toilet"
        case .bathtub: return "bathtub"
        case .oven: return "oven"
        case .dishwasher: return "dishwasher"
        case .table: return "table"
        case .sofa: return "sofa"
        case .chair: return "chair"
        case .fireplace: return "fireplace"
        case .television: return "tv"
        case .stairs: return "stairs"
        default: return "unknown"
        }
    }

    /// Count windows in a region
    private func countWindowsInRegion(_ region: [CGPoint], capturedRoom: CapturedRoom) -> Int {
        let windows = extractWindows(from: capturedRoom)
        return windows.filter { window in
            isPointNearPolygon(window.position, polygon: region, tolerance: 2.0)
        }.count
    }

    // MARK: - Geometry Helpers

    private func calculatePolygonArea(_ polygon: [CGPoint]) -> Double {
        guard polygon.count >= 3 else { return 0 }

        var area: Double = 0
        let n = polygon.count

        for i in 0..<n {
            let j = (i + 1) % n
            area += Double(polygon[i].x * polygon[j].y)
            area -= Double(polygon[j].x * polygon[i].y)
        }

        return abs(area / 2.0)
    }

    private func calculateBoundingBox(for polygon: [CGPoint]) -> CGRect {
        guard !polygon.isEmpty else { return .zero }

        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity

        for point in polygon {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func isPointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var inside = false
        let n = polygon.count

        var j = n - 1
        for i in 0..<n {
            let xi = polygon[i].x, yi = polygon[i].y
            let xj = polygon[j].x, yj = polygon[j].y

            if ((yi > point.y) != (yj > point.y)) &&
                (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) {
                inside = !inside
            }
            j = i
        }

        return inside
    }

    private func isPointNearPolygon(_ point: CGPoint, polygon: [CGPoint], tolerance: CGFloat) -> Bool {
        // Check if point is inside polygon
        if isPointInPolygon(point, polygon: polygon) { return true }

        // Check if point is near any edge
        let n = polygon.count
        for i in 0..<n {
            let j = (i + 1) % n
            let dist = pointToSegmentDistance(point, polygon[i], polygon[j])
            if dist <= tolerance { return true }
        }

        return false
    }

    private func pointToSegmentDistance(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            // a and b are the same point
            return sqrt(pow(point.x - a.x, 2) + pow(point.y - a.y, 2))
        }

        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))

        let closestX = a.x + t * dx
        let closestY = a.y + t * dy

        return sqrt(pow(point.x - closestX, 2) + pow(point.y - closestY, 2))
    }

    private func isSegmentInRegion(_ segment: WallSegment, region: [CGPoint]) -> Bool {
        let midpoint = segment.midpoint
        return isPointInPolygon(midpoint, polygon: region) ||
               isPointInPolygon(segment.start, polygon: region) ||
               isPointInPolygon(segment.end, polygon: region)
    }

    private func isSegmentNearRegion(_ segment: WallSegment, region: [CGPoint], tolerance: CGFloat) -> Bool {
        return isPointNearPolygon(segment.midpoint, polygon: region, tolerance: tolerance) ||
               isPointNearPolygon(segment.start, polygon: region, tolerance: tolerance) ||
               isPointNearPolygon(segment.end, polygon: region, tolerance: tolerance)
    }

    private func isPolygonClosed(_ polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }

        let first = polygon.first!
        let last = polygon.last!

        let dx = last.x - first.x
        let dy = last.y - first.y
        let distance = sqrt(dx * dx + dy * dy)

        return distance < 1.0  // Within 1 foot
    }

    private func regionsOverlap(_ r1: [CGPoint], _ r2: [CGPoint]) -> Bool {
        // Simple check: see if any point of r1 is in r2 or vice versa
        for point in r1 {
            if isPointInPolygon(point, polygon: r2) { return true }
        }
        for point in r2 {
            if isPointInPolygon(point, polygon: r1) { return true }
        }
        return false
    }

    private func isRegionInBounds(_ region: [CGPoint], boundingBox: CGRect) -> Bool {
        for point in region {
            if !boundingBox.contains(point) { return false }
        }
        return true
    }

    private func removeOverlappingRooms(_ rooms: [ProposedRoom]) -> [ProposedRoom] {
        var result: [ProposedRoom] = []

        for room in rooms.sorted(by: { $0.squareFeet > $1.squareFeet }) {
            var overlaps = false

            for existing in result {
                if regionsOverlap(room.boundary, existing.boundary) {
                    overlaps = true
                    break
                }
            }

            if !overlaps {
                result.append(room)
            }
        }

        return result
    }

    /// Calculate convex hull of points
    private func calculateConvexHull(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        // Graham scan algorithm
        var sorted = points.sorted { $0.y < $1.y || ($0.y == $1.y && $0.x < $1.x) }
        let origin = sorted.removeFirst()

        sorted.sort { p1, p2 in
            let angle1 = atan2(p1.y - origin.y, p1.x - origin.x)
            let angle2 = atan2(p2.y - origin.y, p2.x - origin.x)
            return angle1 < angle2
        }

        var hull: [CGPoint] = [origin]

        for point in sorted {
            while hull.count > 1 && !isCounterClockwise(hull[hull.count - 2], hull[hull.count - 1], point) {
                hull.removeLast()
            }
            hull.append(point)
        }

        return hull
    }

    private func isCounterClockwise(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) > 0
    }

    /// Expand a polygon by a given amount
    private func expandPolygon(_ polygon: [CGPoint], by amount: CGFloat) -> [CGPoint] {
        guard polygon.count >= 3 else { return polygon }

        // Simple expansion: move each point away from centroid
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0

        for point in polygon {
            sumX += point.x
            sumY += point.y
        }

        let centroid = CGPoint(x: sumX / CGFloat(polygon.count), y: sumY / CGFloat(polygon.count))

        return polygon.map { point in
            let dx = point.x - centroid.x
            let dy = point.y - centroid.y
            let distance = sqrt(dx * dx + dy * dy)

            guard distance > 0 else { return point }

            let scale = (distance + amount) / distance
            return CGPoint(
                x: centroid.x + dx * scale,
                y: centroid.y + dy * scale
            )
        }
    }
}
