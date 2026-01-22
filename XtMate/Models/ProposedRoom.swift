//
//  ProposedRoom.swift
//  XtMate
//
//  Model representing a room detected by the automatic room boundary analyzer.
//  Used as an intermediate representation before the PM confirms and creates final Room objects.
//
//  PRD: Room Capture Enhancements - US-RC-002
//

import Foundation
import CoreGraphics

/// Represents a proposed room detected from automatic boundary analysis
/// This is an intermediate model before PM confirmation
@available(iOS 16.0, *)
struct ProposedRoom: Identifiable, Hashable {
    let id: UUID

    /// Suggested name based on detected objects (e.g., "Kitchen", "Bathroom")
    var suggestedName: String

    /// Suggested category based on detected objects
    var suggestedCategory: RoomCategory

    /// Confidence score (0-1) based on boundary quality and object detection
    var confidence: Float

    /// Boundary polygon in floor plan coordinates (feet)
    let boundary: [CGPoint]

    /// Bounding box of this room in floor plan coordinates (feet)
    let boundingBox: CGRect

    /// Objects detected within this room's boundary
    let detectedObjects: [DetectedObject]

    /// Doors/openings that connect to this room
    let doorwayCount: Int

    /// Windows in this room
    let windowCount: Int

    /// Wall segments that form this room's boundary
    let wallSegments: [WallSegment]

    /// Whether the boundary forms a closed polygon
    let isClosed: Bool

    /// Calculated area in square feet
    var squareFeet: Double {
        abs(calculatePolygonArea(boundary))
    }

    /// Calculated perimeter in linear feet
    var perimeterLf: Double {
        calculatePolygonPerimeter(boundary)
    }

    /// Average wall height in feet
    let avgHeightFt: Double

    /// Whether this proposed room should be merged with another
    var mergeWith: UUID?

    /// Whether the PM has confirmed this room
    var isConfirmed: Bool = false

    init(
        id: UUID = UUID(),
        suggestedName: String,
        suggestedCategory: RoomCategory,
        confidence: Float,
        boundary: [CGPoint],
        boundingBox: CGRect,
        detectedObjects: [DetectedObject] = [],
        doorwayCount: Int = 0,
        windowCount: Int = 0,
        wallSegments: [WallSegment] = [],
        isClosed: Bool = true,
        avgHeightFt: Double = 8.0
    ) {
        self.id = id
        self.suggestedName = suggestedName
        self.suggestedCategory = suggestedCategory
        self.confidence = confidence
        self.boundary = boundary
        self.boundingBox = boundingBox
        self.detectedObjects = detectedObjects
        self.doorwayCount = doorwayCount
        self.windowCount = windowCount
        self.wallSegments = wallSegments
        self.isClosed = isClosed
        self.avgHeightFt = avgHeightFt
    }

    /// Calculate the centroid of the boundary polygon
    var centroid: CGPoint {
        guard !boundary.isEmpty else {
            return CGPoint(x: boundingBox.midX, y: boundingBox.midY)
        }
        let sumX = boundary.reduce(0.0) { $0 + $1.x }
        let sumY = boundary.reduce(0.0) { $0 + $1.y }
        return CGPoint(x: sumX / CGFloat(boundary.count), y: sumY / CGFloat(boundary.count))
    }

    /// Check if a point is inside this room's boundary
    func contains(_ point: CGPoint) -> Bool {
        guard boundary.count >= 3 else { return false }
        return isPointInPolygon(point, polygon: boundary)
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

        return area / 2.0
    }

    private func calculatePolygonPerimeter(_ polygon: [CGPoint]) -> Double {
        guard polygon.count >= 2 else { return 0 }

        var perimeter: Double = 0
        let n = polygon.count

        for i in 0..<n {
            let j = (i + 1) % n
            let dx = polygon[j].x - polygon[i].x
            let dy = polygon[j].y - polygon[i].y
            perimeter += sqrt(Double(dx * dx + dy * dy))
        }

        return perimeter
    }

    private func isPointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
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

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ProposedRoom, rhs: ProposedRoom) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents an object detected within a room
struct DetectedObject: Identifiable, Hashable {
    let id: UUID
    let category: String
    let position: CGPoint  // In floor plan coordinates (feet)
    let width: CGFloat
    let depth: CGFloat

    init(id: UUID = UUID(), category: String, position: CGPoint, width: CGFloat = 0, depth: CGFloat = 0) {
        self.id = id
        self.category = category
        self.position = position
        self.width = width
        self.depth = depth
    }
}

/// Represents a wall segment in 2D floor plan coordinates
struct WallSegment: Identifiable, Hashable {
    let id: UUID
    let start: CGPoint  // In floor plan coordinates (feet)
    let end: CGPoint    // In floor plan coordinates (feet)
    let thickness: CGFloat  // Wall thickness in inches
    let heightFt: CGFloat

    var length: CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt(dx * dx + dy * dy)
    }

    var midpoint: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    /// Angle of the wall segment in radians
    var angle: CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }

    init(id: UUID = UUID(), start: CGPoint, end: CGPoint, thickness: CGFloat = 6, heightFt: CGFloat = 8) {
        self.id = id
        self.start = start
        self.end = end
        self.thickness = thickness
        self.heightFt = heightFt
    }
}

/// Represents a doorway/opening between rooms
struct Doorway: Identifiable, Hashable {
    let id: UUID
    let position: CGPoint  // In floor plan coordinates (feet)
    let width: CGFloat     // Door width in feet
    let rotation: CGFloat  // Rotation in radians
    let connectsRooms: [UUID]  // IDs of rooms this doorway connects

    init(id: UUID = UUID(), position: CGPoint, width: CGFloat, rotation: CGFloat = 0, connectsRooms: [UUID] = []) {
        self.id = id
        self.position = position
        self.width = width
        self.rotation = rotation
        self.connectsRooms = connectsRooms
    }
}

/// Result of room boundary analysis
@available(iOS 16.0, *)
struct RoomBoundaryAnalysisResult {
    /// All proposed rooms detected
    let proposedRooms: [ProposedRoom]

    /// Doorways that connect rooms
    let doorways: [Doorway]

    /// Windows detected
    let windows: [FloorPlanWindow]

    /// Overall confidence of the analysis
    let overallConfidence: Float

    /// Whether automatic detection was successful
    let wasSuccessful: Bool

    /// Reason for failure if not successful
    let failureReason: String?

    /// Total square footage of all proposed rooms
    var totalSquareFeet: Double {
        proposedRooms.reduce(0) { $0 + $1.squareFeet }
    }

    init(
        proposedRooms: [ProposedRoom] = [],
        doorways: [Doorway] = [],
        windows: [FloorPlanWindow] = [],
        overallConfidence: Float = 0,
        wasSuccessful: Bool = false,
        failureReason: String? = nil
    ) {
        self.proposedRooms = proposedRooms
        self.doorways = doorways
        self.windows = windows
        self.overallConfidence = overallConfidence
        self.wasSuccessful = wasSuccessful
        self.failureReason = failureReason
    }
}
