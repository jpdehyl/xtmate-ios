//
//  FloorPlanModels.swift
//  XtMate
//
//  Models for parsing and rendering 2D floor plan data.
//  Ported from MobileSketchCapture for 2D floor plan visualization.
//

import Foundation
import CoreGraphics

// MARK: - Parsed Geometry Models

/// Represents a wall in 2D floor plan coordinates
struct FloorPlanWall: Identifiable {
    let id = UUID()
    let startPoint: CGPoint
    let endPoint: CGPoint
    let length: CGFloat  // in feet
    let height: CGFloat  // in feet
}

/// Represents a door in 2D floor plan coordinates
struct FloorPlanDoor: Identifiable {
    let id = UUID()
    let position: CGPoint
    let width: CGFloat   // in feet
    let rotation: CGFloat // in radians
}

/// Represents a window in 2D floor plan coordinates
struct FloorPlanWindow: Identifiable {
    let id = UUID()
    let position: CGPoint
    let width: CGFloat   // in feet
    let rotation: CGFloat // in radians
}

/// Represents a detected object (cabinet, fixture, etc.)
struct FloorPlanObject: Identifiable {
    let id = UUID()
    let category: String
    let position: CGPoint
    let width: CGFloat
    let depth: CGFloat
    let rotation: CGFloat
}

// MARK: - Floor Plan Data Container

/// Contains all parsed floor plan geometry
struct FloorPlanData {
    let walls: [FloorPlanWall]
    let doors: [FloorPlanDoor]
    let windows: [FloorPlanWindow]
    let objects: [FloorPlanObject]
    let boundingBox: CGRect
    let squareFootage: Double
    let linearFeet: Double

    /// Create empty floor plan data
    static var empty: FloorPlanData {
        FloorPlanData(
            walls: [],
            doors: [],
            windows: [],
            objects: [],
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            squareFootage: 0,
            linearFeet: 0
        )
    }
}

// MARK: - JSON Parsing

/// Parser for converting stored JSON geometry to floor plan models
struct FloorPlanParser {

    /// Meters to feet conversion
    private static let metersToFeet: CGFloat = 3.28084

    /// Parse floor plan data from JSON geometry strings
    static func parse(
        wallsJSON: String?,
        doorsJSON: String?,
        windowsJSON: String?,
        objectsJSON: String?,
        squareFootage: Double,
        linearFeet: Double
    ) -> FloorPlanData {
        let walls = parseWalls(from: wallsJSON)
        let doors = parseDoors(from: doorsJSON)
        let windows = parseWindows(from: windowsJSON)
        let objects = parseObjects(from: objectsJSON)

        // Calculate bounding box from walls
        let boundingBox = calculateBoundingBox(walls: walls, doors: doors, windows: windows)

        return FloorPlanData(
            walls: walls,
            doors: doors,
            windows: windows,
            objects: objects,
            boundingBox: boundingBox,
            squareFootage: squareFootage,
            linearFeet: linearFeet
        )
    }

    /// Parse walls from JSON string
    private static func parseWalls(from json: String?) -> [FloorPlanWall] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let wallsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return wallsArray.compactMap { wallDict -> FloorPlanWall? in
            guard let dimensions = wallDict["dimensions"] as? [String: Double],
                  let transform = wallDict["transform"] as? [[Double]] else {
                return nil
            }

            let width = CGFloat(dimensions["x"] ?? 0) * metersToFeet
            let height = CGFloat(dimensions["y"] ?? 0) * metersToFeet

            // Extract position from transform matrix (column 3)
            let x = CGFloat(transform[3][0]) * metersToFeet
            let z = CGFloat(transform[3][2]) * metersToFeet

            // Calculate wall direction from rotation matrix
            let dirX = CGFloat(transform[0][0])
            let dirZ = CGFloat(transform[0][2])

            // Calculate start and end points
            let halfWidth = width / 2
            let startPoint = CGPoint(x: x - dirX * halfWidth, y: z - dirZ * halfWidth)
            let endPoint = CGPoint(x: x + dirX * halfWidth, y: z + dirZ * halfWidth)

            return FloorPlanWall(
                startPoint: startPoint,
                endPoint: endPoint,
                length: width,
                height: height
            )
        }
    }

    /// Parse doors from JSON string
    private static func parseDoors(from json: String?) -> [FloorPlanDoor] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let doorsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return doorsArray.compactMap { doorDict -> FloorPlanDoor? in
            guard let dimensions = doorDict["dimensions"] as? [String: Double],
                  let transform = doorDict["transform"] as? [[Double]] else {
                return nil
            }

            let width = CGFloat(dimensions["x"] ?? 0) * metersToFeet

            // Extract position from transform matrix
            let x = CGFloat(transform[3][0]) * metersToFeet
            let z = CGFloat(transform[3][2]) * metersToFeet

            // Calculate rotation from transform matrix
            let rotation = atan2(CGFloat(transform[0][2]), CGFloat(transform[0][0]))

            return FloorPlanDoor(
                position: CGPoint(x: x, y: z),
                width: width,
                rotation: rotation
            )
        }
    }

    /// Parse windows from JSON string
    private static func parseWindows(from json: String?) -> [FloorPlanWindow] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let windowsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return windowsArray.compactMap { windowDict -> FloorPlanWindow? in
            guard let dimensions = windowDict["dimensions"] as? [String: Double],
                  let transform = windowDict["transform"] as? [[Double]] else {
                return nil
            }

            let width = CGFloat(dimensions["x"] ?? 0) * metersToFeet

            // Extract position from transform matrix
            let x = CGFloat(transform[3][0]) * metersToFeet
            let z = CGFloat(transform[3][2]) * metersToFeet

            // Calculate rotation from transform matrix
            let rotation = atan2(CGFloat(transform[0][2]), CGFloat(transform[0][0]))

            return FloorPlanWindow(
                position: CGPoint(x: x, y: z),
                width: width,
                rotation: rotation
            )
        }
    }

    /// Parse objects from JSON string
    private static func parseObjects(from json: String?) -> [FloorPlanObject] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let objectsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return objectsArray.compactMap { objectDict -> FloorPlanObject? in
            guard let dimensions = objectDict["dimensions"] as? [String: Double],
                  let transform = objectDict["transform"] as? [[Double]],
                  let category = objectDict["category"] as? String else {
                return nil
            }

            let width = CGFloat(dimensions["x"] ?? 0) * metersToFeet
            let depth = CGFloat(dimensions["z"] ?? 0) * metersToFeet

            // Extract position from transform matrix
            let x = CGFloat(transform[3][0]) * metersToFeet
            let z = CGFloat(transform[3][2]) * metersToFeet

            // Calculate rotation from transform matrix
            let rotation = atan2(CGFloat(transform[0][2]), CGFloat(transform[0][0]))

            return FloorPlanObject(
                category: category,
                position: CGPoint(x: x, y: z),
                width: width,
                depth: depth,
                rotation: rotation
            )
        }
    }

    /// Calculate bounding box that contains all elements
    private static func calculateBoundingBox(
        walls: [FloorPlanWall],
        doors: [FloorPlanDoor],
        windows: [FloorPlanWindow]
    ) -> CGRect {
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity

        // Include wall points
        for wall in walls {
            minX = min(minX, wall.startPoint.x, wall.endPoint.x)
            maxX = max(maxX, wall.startPoint.x, wall.endPoint.x)
            minY = min(minY, wall.startPoint.y, wall.endPoint.y)
            maxY = max(maxY, wall.startPoint.y, wall.endPoint.y)
        }

        // Include door positions
        for door in doors {
            minX = min(minX, door.position.x - door.width/2)
            maxX = max(maxX, door.position.x + door.width/2)
            minY = min(minY, door.position.y - door.width/2)
            maxY = max(maxY, door.position.y + door.width/2)
        }

        // Include window positions
        for window in windows {
            minX = min(minX, window.position.x - window.width/2)
            maxX = max(maxX, window.position.x + window.width/2)
            minY = min(minY, window.position.y - window.width/2)
            maxY = max(maxY, window.position.y + window.width/2)
        }

        // Handle empty case
        if minX == .infinity {
            return CGRect(x: 0, y: 0, width: 20, height: 20)
        }

        // Add padding
        let padding: CGFloat = 2.0  // 2 feet padding
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + padding * 2,
            height: (maxY - minY) + padding * 2
        )
    }
}
