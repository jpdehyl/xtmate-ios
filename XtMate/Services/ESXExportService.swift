//
//  ESXExportService.swift
//  XtMate
//
//  Service for exporting room geometry to Xactimate ESX format.
//  ESX files are ZIP archives containing FIF sketch XML data.
//
//  Coordinate System:
//  - Xactimate uses microns (1 foot = 304,800 microns)
//  - XtMate stores dimensions in inches
//  - FloorPlan coordinates are in feet
//

import Foundation
import CoreGraphics
import Compression

// MARK: - ESX Export Service

/// Service for exporting estimates to Xactimate-compatible ESX format
class ESXExportService {
    static let shared = ESXExportService()

    // MARK: - Constants

    /// Conversion factor: 1 foot = 304,800 microns
    private let feetToMicrons: Double = 304_800

    /// Conversion factor: 1 inch = 25,400 microns
    private let inchesToMicrons: Double = 25_400

    /// Standard wall thickness in microns (~2 inches)
    private let wallThicknessMicrons: Int = 508

    /// Base elevation for main floor in microns (5 feet)
    private let mainFloorElevation: Double = 152_400

    /// Default ceiling height in the FIF format (appears to be a compressed value)
    /// 12192 = 8 feet in FIF format
    private let ceilingHeightScale: Double = 1524.0  // microns per foot in ceiling height

    // MARK: - ID Generation

    private var nextId: Int = 150

    private func generateId() -> Int {
        nextId += 1
        return nextId
    }

    private func resetIdCounter() {
        nextId = 150
    }

    // MARK: - Public API

    /// Export an estimate to ESX format
    /// - Parameters:
    ///   - estimate: The estimate containing rooms to export
    ///   - floorPlanData: Optional floor plan data with detailed geometry
    /// - Returns: URL to the generated ESX file
    func exportToESX(estimate: Estimate, floorPlanData: FloorPlanData? = nil) throws -> URL {
        resetIdCounter()

        // Generate FIF XML content
        let fifXML = generateFIFXML(estimate: estimate, floorPlanData: floorPlanData)

        // Create temporary directory for ESX contents
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write FIF XML file
        let timestamp = Int(Date().timeIntervalSince1970)
        let xmlFileName = "\(timestamp).XML"
        let xmlFileURL = tempDir.appendingPathComponent(xmlFileName)
        try fifXML.write(to: xmlFileURL, atomically: true, encoding: .utf8)

        // Create ESX (ZIP) file
        let esxFileName = "\(estimate.name.replacingOccurrences(of: " ", with: "_"))_\(timestamp).ESX"
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let esxFileURL = documentsDir.appendingPathComponent(esxFileName)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: esxFileURL)

        // Create ZIP archive using built-in ZIP writer
        let xmlData = try Data(contentsOf: xmlFileURL)
        let zipData = try ZIPWriter.createZipArchive(files: [(name: xmlFileName, data: xmlData)])
        try zipData.write(to: esxFileURL)

        // Cleanup temp directory
        try? FileManager.default.removeItem(at: tempDir)

        return esxFileURL
    }

    /// Export rooms with detailed geometry from ProposedRooms
    /// - Parameters:
    ///   - proposedRooms: Array of proposed rooms with boundary polygons
    ///   - doorways: Doorway connections between rooms
    ///   - windows: Windows in the floor plan
    ///   - estimateName: Name for the export file
    /// - Returns: URL to the generated ESX file
    @available(iOS 16.0, *)
    func exportProposedRooms(
        _ proposedRooms: [ProposedRoom],
        doorways: [Doorway],
        windows: [FloorPlanWindow],
        estimateName: String
    ) throws -> URL {
        resetIdCounter()

        // Generate FIF XML from proposed rooms
        let fifXML = generateFIFXMLFromProposedRooms(
            proposedRooms,
            doorways: doorways,
            windows: windows
        )

        // Create temporary directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write FIF XML file
        let timestamp = Int(Date().timeIntervalSince1970)
        let xmlFileName = "\(timestamp).XML"
        let xmlFileURL = tempDir.appendingPathComponent(xmlFileName)
        try fifXML.write(to: xmlFileURL, atomically: true, encoding: .utf8)

        // Create ESX file
        let esxFileName = "\(estimateName.replacingOccurrences(of: " ", with: "_"))_\(timestamp).ESX"
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let esxFileURL = documentsDir.appendingPathComponent(esxFileName)

        try? FileManager.default.removeItem(at: esxFileURL)

        // Create ZIP archive using built-in ZIP writer
        let xmlData = try Data(contentsOf: xmlFileURL)
        let zipData = try ZIPWriter.createZipArchive(files: [(name: xmlFileName, data: xmlData)])
        try zipData.write(to: esxFileURL)

        // Cleanup temp directory
        try? FileManager.default.removeItem(at: tempDir)

        return esxFileURL
    }

    // MARK: - FIF XML Generation

    /// Generate FIF XML from estimate data
    private func generateFIFXML(estimate: Estimate, floorPlanData: FloorPlanData?) -> String {
        let documentId = generateId()

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FIF>
          <SKETCH_FILES>
            <SKETCHDOCUMENT id="SKT\(documentId)" minorVersion="27">

        """

        // Group rooms by floor level
        let roomsByFloor = Dictionary(grouping: estimate.rooms) { $0.floor }

        for (floor, rooms) in roomsByFloor.sorted(by: { $0.key.sortOrder < $1.key.sortOrder }) {
            let floorElevation = elevationForFloor(floor)
            let levelId = generateId()

            // Track all coordinates for this level
            var levelCoordinates: [Double] = []
            var vertexCoordIndices: [Int: Int] = [:]  // vertex ID -> coordinate index

            // Generate geometry for each room on this floor
            var allVertices: [(id: Int, point: CGPoint, wallIds: [Int], coordIndex: Int)] = []
            var allWalls: [(id: Int, vertexIds: [Int], roomIds: [Int], thickness: Int, openings: [WallOpening])] = []
            var allRooms: [(id: Int, name: String, wallIds: [Int], ceilingHeight: Int)] = []

            var roomOffset = CGPoint.zero
            for room in rooms {
                let geometry = generateRoomGeometryWithCoords(
                    room: room,
                    offset: roomOffset,
                    startCoordIndex: levelCoordinates.count / 3,
                    floorElevation: floorElevation
                )

                // Map vertex IDs to coordinate indices
                for vertex in geometry.vertices {
                    vertexCoordIndices[vertex.id] = vertex.coordIndex
                }

                allVertices.append(contentsOf: geometry.vertices)
                allWalls.append(contentsOf: geometry.walls)
                allRooms.append((
                    id: geometry.roomId,
                    name: room.name,
                    wallIds: geometry.walls.map { $0.id },
                    ceilingHeight: Int(room.heightIn / 12.0 * ceilingHeightScale)
                ))
                levelCoordinates.append(contentsOf: geometry.coordinates)

                // Offset next room to avoid overlap
                roomOffset.x += room.lengthIn / 12.0 + 2.0
            }

            xml += """
                  <SKETCHLEVEL floorElevation="\(floorElevation)" id="SKT\(levelId)" name="\(floor.displayName)">

            """

            // Write vertices with correct coordinate indices
            for vertex in allVertices {
                let wallIdsStr = vertex.wallIds.map { String($0) }.joined(separator: " ")
                xml += """
                        <SKETCHLEVELVERTEX id="SKT\(vertex.id)" vertex="\(vertex.coordIndex)" wallIDs="\(wallIdsStr)" />

                """
            }

            // Write rooms
            for room in allRooms {
                let wallIdsStr = room.wallIds.map { String($0) }.joined(separator: " ")
                xml += """
                        <SKETCHROOM ceilingHeight="\(room.ceilingHeight)" id="SKT\(room.id)" wallIDs="\(wallIdsStr)">
                          <SKETCHLABEL flags="3" id="" multiline="0" namePosition="52">
                            <SKETCHCDATACHILD><![CDATA[\(room.name)]]></SKETCHCDATACHILD>
                          </SKETCHLABEL>
                        </SKETCHROOM>

                """
            }

            // Write walls with openings
            for wall in allWalls {
                let vertexIdsStr = wall.vertexIds.map { String($0) }.joined(separator: " ")
                let roomIdsStr = wall.roomIds.map { String($0) }.joined(separator: " ")

                if wall.openings.isEmpty {
                    xml += """
                            <SKETCHWALL id="SKT\(wall.id)" roomIDs="\(roomIdsStr)" thickness="\(wall.thickness)" vertexIDs="\(vertexIdsStr)" jsonId="\(UUID().uuidString)" />

                    """
                } else {
                    xml += """
                            <SKETCHWALL id="SKT\(wall.id)" roomIDs="\(roomIdsStr)" thickness="\(wall.thickness)" vertexIDs="\(vertexIdsStr)" jsonId="\(UUID().uuidString)">

                    """
                    for opening in wall.openings {
                        let coordIndexStr = opening.coordIndices.map { String($0) }.joined(separator: " ")
                        xml += """
                              <SKETCHWALLOPENING id="SKT\(opening.id)" coordIndex="\(coordIndexStr)" type="\(opening.type)" doorType="\(opening.doorType)" flags="\(opening.flags)" />

                        """
                    }
                    xml += """
                            </SKETCHWALL>

                    """
                }
            }

            // Write COORDINATE3 array
            let coordString = levelCoordinates.map { String(Int($0)) }.joined(separator: " ")
            xml += """
                    <COORDINATE3>\(coordString)</COORDINATE3>
                  </SKETCHLEVEL>

            """
        }

        // Close document
        xml += """
            </SKETCHDOCUMENT>
          </SKETCH_FILES>
        </FIF>
        """

        return xml
    }

    /// Generate FIF XML from proposed rooms with detailed geometry
    @available(iOS 16.0, *)
    private func generateFIFXMLFromProposedRooms(
        _ proposedRooms: [ProposedRoom],
        doorways: [Doorway],
        windows: [FloorPlanWindow]
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FIF>
          <SKETCH_FILES>
            <SKETCHDOCUMENT id="SKT\(generateId())" minorVersion="27">
              <SKETCHLEVEL floorElevation="\(mainFloorElevation)" id="SKT\(generateId())" name="Main Floor">

        """

        // Collect all unique vertices and build wall connectivity
        var vertexMap: [String: Int] = [:]  // "x,y" -> vertex ID
        var vertices: [(id: Int, point: CGPoint, wallIds: [Int])] = []
        var walls: [(id: Int, vertexIds: [Int], roomId: Int, thickness: Int, openings: [WallOpening])] = []
        var rooms: [(id: Int, name: String, wallIds: [Int], ceilingHeight: Int)] = []
        var coordinates: [Double] = []

        // Build vertex index from coordinates
        func getOrCreateVertex(_ point: CGPoint) -> Int {
            let key = "\(Int(point.x * 1000)),\(Int(point.y * 1000))"
            if let existingId = vertexMap[key] {
                return existingId
            }
            let id = generateId()
            vertexMap[key] = id
            vertices.append((id: id, point: point, wallIds: []))

            // Add coordinates (microns)
            let xMicrons = point.x * feetToMicrons
            let yMicrons = 0.0  // Floor level
            let zMicrons = point.y * feetToMicrons  // Y in 2D -> Z in 3D
            coordinates.append(contentsOf: [xMicrons, yMicrons, zMicrons])

            return id
        }

        // Process each room
        for proposedRoom in proposedRooms {
            let roomId = generateId()
            var roomWallIds: [Int] = []
            let ceilingHeight = Int(proposedRoom.avgHeightFt * ceilingHeightScale)

            // Create walls from boundary polygon
            let boundary = proposedRoom.boundary
            guard boundary.count >= 3 else { continue }

            for i in 0..<boundary.count {
                let startPoint = boundary[i]
                let endPoint = boundary[(i + 1) % boundary.count]

                let startVertexId = getOrCreateVertex(startPoint)
                let endVertexId = getOrCreateVertex(endPoint)

                let wallId = generateId()
                roomWallIds.append(wallId)

                // Check for openings (doors/windows) on this wall segment
                var openings: [WallOpening] = []

                // Find doors on this wall
                for doorway in doorways {
                    if isPointOnSegment(doorway.position, start: startPoint, end: endPoint) {
                        let opening = WallOpening(
                            id: generateId(),
                            type: 2,  // Door
                            doorType: 0,  // Standard door
                            width: doorway.width * feetToMicrons,
                            height: 6.67 * feetToMicrons,  // Standard 6'8" door height
                            position: doorway.position,
                            flags: 16
                        )
                        openings.append(opening)
                    }
                }

                // Find windows on this wall
                for window in windows {
                    if isPointOnSegment(window.position, start: startPoint, end: endPoint) {
                        let opening = WallOpening(
                            id: generateId(),
                            type: 1,  // Window
                            doorType: 0,
                            width: window.width * feetToMicrons,
                            height: 4.0 * feetToMicrons,  // Standard 4' window height
                            position: window.position,
                            flags: 16
                        )
                        openings.append(opening)
                    }
                }

                walls.append((
                    id: wallId,
                    vertexIds: [startVertexId, endVertexId],
                    roomId: roomId,
                    thickness: wallThicknessMicrons,
                    openings: openings
                ))

                // Update vertex wall references
                if let idx = vertices.firstIndex(where: { $0.id == startVertexId }) {
                    var vertex = vertices[idx]
                    vertex.wallIds.append(wallId)
                    vertices[idx] = vertex
                }
                if let idx = vertices.firstIndex(where: { $0.id == endVertexId }) {
                    var vertex = vertices[idx]
                    vertex.wallIds.append(wallId)
                    vertices[idx] = vertex
                }
            }

            rooms.append((
                id: roomId,
                name: proposedRoom.suggestedName,
                wallIds: roomWallIds,
                ceilingHeight: ceilingHeight
            ))
        }

        // Write vertices
        for vertex in vertices {
            let wallIdsStr = vertex.wallIds.map { String($0) }.joined(separator: " ")
            xml += """
                    <SKETCHLEVELVERTEX id="SKT\(vertex.id)" vertex="\(vertices.firstIndex(where: { $0.id == vertex.id }) ?? 0)" wallIDs="\(wallIdsStr)" />

            """
        }

        // Write rooms
        for room in rooms {
            let wallIdsStr = room.wallIds.map { String($0) }.joined(separator: " ")
            xml += """
                    <SKETCHROOM ceilingHeight="\(room.ceilingHeight)" id="SKT\(room.id)" wallIDs="\(wallIdsStr)">
                      <SKETCHLABEL flags="3" id="" multiline="0" namePosition="52">
                        <SKETCHCDATACHILD><![CDATA[\(room.name)]]></SKETCHCDATACHILD>
                      </SKETCHLABEL>
                    </SKETCHROOM>

            """
        }

        // Write walls with openings
        for wall in walls {
            let vertexIdsStr = wall.vertexIds.map { String($0) }.joined(separator: " ")

            if wall.openings.isEmpty {
                xml += """
                        <SKETCHWALL id="SKT\(wall.id)" roomIDs="\(wall.roomId)" thickness="\(wall.thickness)" vertexIDs="\(vertexIdsStr)" jsonId="\(UUID().uuidString)" />

                """
            } else {
                xml += """
                        <SKETCHWALL id="SKT\(wall.id)" roomIDs="\(wall.roomId)" thickness="\(wall.thickness)" vertexIDs="\(vertexIdsStr)" jsonId="\(UUID().uuidString)">

                """
                for opening in wall.openings {
                    xml += """
                          <SKETCHWALLOPENING id="SKT\(opening.id)" type="\(opening.type)" doorType="0" flags="16" />

                """
                }
                xml += """
                        </SKETCHWALL>

                """
            }
        }

        // Write coordinates
        let coordString = coordinates.map { String(Int($0)) }.joined(separator: " ")

        xml += """
                <COORDINATE3>\(coordString)</COORDINATE3>
              </SKETCHLEVEL>
            </SKETCHDOCUMENT>
          </SKETCH_FILES>
        </FIF>
        """

        return xml
    }

    // MARK: - Room Geometry Generation

    private struct RoomGeometry {
        let roomId: Int
        let vertices: [(id: Int, point: CGPoint, wallIds: [Int], coordIndex: Int)]
        let walls: [(id: Int, vertexIds: [Int], roomIds: [Int], thickness: Int, openings: [WallOpening])]
        let coordinates: [Double]
    }

    private struct WallOpening {
        let id: Int
        let type: Int  // 0=opening, 1=window, 2=door
        let doorType: Int  // 0=standard, 1=pocket, 2=bifold, 3=sliding, 4=french
        let width: Double
        let height: Double
        let position: CGPoint
        var coordIndices: [Int] = []  // 4 coordinate indices for opening polygon
        let flags: Int  // 16 = standard flags
    }

    /// Generate geometry for a rectangular room with proper coordinate tracking
    private func generateRoomGeometryWithCoords(
        room: Room,
        offset: CGPoint,
        startCoordIndex: Int,
        floorElevation: Double
    ) -> RoomGeometry {
        let roomId = generateId()

        // Convert dimensions from inches to feet
        let lengthFt = room.lengthIn / 12.0
        let widthFt = room.widthIn / 12.0
        let heightFt = room.heightIn / 12.0

        // Generate 4 corners (clockwise from origin) with offset
        let corners: [CGPoint] = [
            CGPoint(x: offset.x, y: offset.y),
            CGPoint(x: offset.x + lengthFt, y: offset.y),
            CGPoint(x: offset.x + lengthFt, y: offset.y + widthFt),
            CGPoint(x: offset.x, y: offset.y + widthFt)
        ]

        // Create vertices with coordinate indices
        var vertices: [(id: Int, point: CGPoint, wallIds: [Int], coordIndex: Int)] = []
        var coordinates: [Double] = []
        var coordIndex = startCoordIndex

        for corner in corners {
            let vertexId = generateId()
            vertices.append((id: vertexId, point: corner, wallIds: [], coordIndex: coordIndex))

            // Convert to microns for coordinate array (X, Y=elevation, Z)
            coordinates.append(corner.x * feetToMicrons)
            coordinates.append(floorElevation)  // Y is floor elevation
            coordinates.append(corner.y * feetToMicrons)  // 2D Y -> 3D Z

            coordIndex += 1
        }

        // Create 4 walls connecting vertices
        var walls: [(id: Int, vertexIds: [Int], roomIds: [Int], thickness: Int, openings: [WallOpening])] = []

        // Generate openings based on door/window counts
        let doorsPerWall = room.doorCount > 0 ? max(1, room.doorCount / 4) : 0
        let windowsPerWall = room.windowCount > 0 ? max(1, room.windowCount / 4) : 0

        for i in 0..<4 {
            let wallId = generateId()
            let startVertex = vertices[i].id
            let endVertex = vertices[(i + 1) % 4].id

            var wallOpenings: [WallOpening] = []

            // Add door to first wall if room has doors
            if i == 0 && room.doorCount > 0 {
                // Calculate opening position (center of wall)
                let wallStart = corners[i]
                let wallEnd = corners[(i + 1) % 4]
                let doorWidth = 3.0  // 3 feet standard door
                let doorHeight = 6.67  // 6'8" standard door

                // Add coordinates for door opening (4 corners of opening)
                let doorStartCoord = coordIndex
                let doorCenterX = (wallStart.x + wallEnd.x) / 2
                let doorCenterZ = (wallStart.y + wallEnd.y) / 2

                // Door opening corners (bottom-left, bottom-right, top-right, top-left)
                let doorHalfWidth = doorWidth / 2
                if wallStart.y == wallEnd.y {
                    // Horizontal wall
                    coordinates.append(contentsOf: [
                        (doorCenterX - doorHalfWidth) * feetToMicrons, floorElevation, doorCenterZ * feetToMicrons,
                        (doorCenterX + doorHalfWidth) * feetToMicrons, floorElevation, doorCenterZ * feetToMicrons,
                        (doorCenterX + doorHalfWidth) * feetToMicrons, floorElevation + doorHeight * feetToMicrons, doorCenterZ * feetToMicrons,
                        (doorCenterX - doorHalfWidth) * feetToMicrons, floorElevation + doorHeight * feetToMicrons, doorCenterZ * feetToMicrons
                    ])
                } else {
                    // Vertical wall
                    coordinates.append(contentsOf: [
                        doorCenterX * feetToMicrons, floorElevation, (doorCenterZ - doorHalfWidth) * feetToMicrons,
                        doorCenterX * feetToMicrons, floorElevation, (doorCenterZ + doorHalfWidth) * feetToMicrons,
                        doorCenterX * feetToMicrons, floorElevation + doorHeight * feetToMicrons, (doorCenterZ + doorHalfWidth) * feetToMicrons,
                        doorCenterX * feetToMicrons, floorElevation + doorHeight * feetToMicrons, (doorCenterZ - doorHalfWidth) * feetToMicrons
                    ])
                }

                var opening = WallOpening(
                    id: generateId(),
                    type: 2,  // Door
                    doorType: 0,
                    width: doorWidth * feetToMicrons,
                    height: doorHeight * feetToMicrons,
                    position: CGPoint(x: doorCenterX, y: doorCenterZ),
                    flags: 16
                )
                opening.coordIndices = [doorStartCoord, doorStartCoord + 1, doorStartCoord + 2, doorStartCoord + 3]
                coordIndex += 4
                wallOpenings.append(opening)
            }

            // Add window to second and third walls if room has windows
            if (i == 1 || i == 2) && room.windowCount > 0 && i <= room.windowCount {
                let wallStart = corners[i]
                let wallEnd = corners[(i + 1) % 4]
                let windowWidth = 3.0  // 3 feet standard window
                let windowHeight = 4.0  // 4 feet standard window
                let windowSillHeight = 3.0  // 3 feet from floor

                let windowStartCoord = coordIndex
                let windowCenterX = (wallStart.x + wallEnd.x) / 2
                let windowCenterZ = (wallStart.y + wallEnd.y) / 2
                let windowHalfWidth = windowWidth / 2

                if wallStart.y == wallEnd.y {
                    coordinates.append(contentsOf: [
                        (windowCenterX - windowHalfWidth) * feetToMicrons, floorElevation + windowSillHeight * feetToMicrons, windowCenterZ * feetToMicrons,
                        (windowCenterX + windowHalfWidth) * feetToMicrons, floorElevation + windowSillHeight * feetToMicrons, windowCenterZ * feetToMicrons,
                        (windowCenterX + windowHalfWidth) * feetToMicrons, floorElevation + (windowSillHeight + windowHeight) * feetToMicrons, windowCenterZ * feetToMicrons,
                        (windowCenterX - windowHalfWidth) * feetToMicrons, floorElevation + (windowSillHeight + windowHeight) * feetToMicrons, windowCenterZ * feetToMicrons
                    ])
                } else {
                    coordinates.append(contentsOf: [
                        windowCenterX * feetToMicrons, floorElevation + windowSillHeight * feetToMicrons, (windowCenterZ - windowHalfWidth) * feetToMicrons,
                        windowCenterX * feetToMicrons, floorElevation + windowSillHeight * feetToMicrons, (windowCenterZ + windowHalfWidth) * feetToMicrons,
                        windowCenterX * feetToMicrons, floorElevation + (windowSillHeight + windowHeight) * feetToMicrons, (windowCenterZ + windowHalfWidth) * feetToMicrons,
                        windowCenterX * feetToMicrons, floorElevation + (windowSillHeight + windowHeight) * feetToMicrons, (windowCenterZ - windowHalfWidth) * feetToMicrons
                    ])
                }

                var opening = WallOpening(
                    id: generateId(),
                    type: 1,  // Window
                    doorType: 0,
                    width: windowWidth * feetToMicrons,
                    height: windowHeight * feetToMicrons,
                    position: CGPoint(x: windowCenterX, y: windowCenterZ),
                    flags: 16
                )
                opening.coordIndices = [windowStartCoord, windowStartCoord + 1, windowStartCoord + 2, windowStartCoord + 3]
                coordIndex += 4
                wallOpenings.append(opening)
            }

            walls.append((
                id: wallId,
                vertexIds: [startVertex, endVertex],
                roomIds: [roomId],
                thickness: wallThicknessMicrons,
                openings: wallOpenings
            ))

            // Update vertex wall references
            vertices[i].wallIds.append(wallId)
            vertices[(i + 1) % 4].wallIds.append(wallId)
        }

        return RoomGeometry(
            roomId: roomId,
            vertices: vertices,
            walls: walls,
            coordinates: coordinates
        )
    }

    // MARK: - Helpers

    /// Get floor elevation in microns based on floor level
    private func elevationForFloor(_ floor: FloorLevel) -> Double {
        switch floor {
        case .basement:
            return 0
        case .first:
            return mainFloorElevation
        case .second:
            return mainFloorElevation * 2
        case .third:
            return mainFloorElevation * 3
        case .attic:
            return mainFloorElevation * 4
        }
    }

    /// Check if a point lies on a line segment (with tolerance)
    private func isPointOnSegment(_ point: CGPoint, start: CGPoint, end: CGPoint, tolerance: CGFloat = 0.5) -> Bool {
        let d1 = distance(point, start)
        let d2 = distance(point, end)
        let lineLength = distance(start, end)

        return abs(d1 + d2 - lineLength) < tolerance
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Floor Level Sort Order

extension FloorLevel {
    var sortOrder: Int {
        switch self {
        case .basement: return 0
        case .first: return 1
        case .second: return 2
        case .third: return 3
        case .attic: return 4
        }
    }
}

// MARK: - ESX Export Errors

enum ESXExportError: Error, LocalizedError {
    case zipCreationFailed
    case invalidRoomGeometry
    case noRoomsToExport
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .zipCreationFailed:
            return "Failed to create ESX archive."
        case .invalidRoomGeometry:
            return "Room geometry is invalid for export."
        case .noRoomsToExport:
            return "No rooms available to export."
        case .fileWriteFailed:
            return "Failed to write export file."
        }
    }
}

// MARK: - ZIP Archive Writer

/// Simple ZIP file writer for creating ESX archives without external dependencies.
/// Uses the standard ZIP format with DEFLATE compression.
private struct ZIPWriter {

    /// Create a ZIP archive containing the specified files
    /// - Parameter files: Array of (filename, data) tuples
    /// - Returns: Data containing the complete ZIP archive
    static func createZipArchive(files: [(name: String, data: Data)]) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var localHeaderOffsets: [UInt32] = []

        for (filename, fileData) in files {
            let localHeaderOffset = UInt32(archive.count)
            localHeaderOffsets.append(localHeaderOffset)

            // Compress file data using DEFLATE
            let compressedData = try compressData(fileData)
            let useCompression = compressedData.count < fileData.count

            let dataToWrite = useCompression ? compressedData : fileData
            let compressionMethod: UInt16 = useCompression ? 8 : 0  // 8 = DEFLATE, 0 = stored

            // CRC-32 of uncompressed data
            let crc = crc32(fileData)

            // Get current time for file timestamp
            let (dosDate, dosTime) = currentDOSDateTime()

            // Local file header
            var localHeader = Data()
            localHeader.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])  // Local file header signature
            localHeader.append(littleEndian: UInt16(20))              // Version needed (2.0)
            localHeader.append(littleEndian: UInt16(0))               // General purpose flags
            localHeader.append(littleEndian: compressionMethod)        // Compression method
            localHeader.append(littleEndian: dosTime)                  // Last mod time
            localHeader.append(littleEndian: dosDate)                  // Last mod date
            localHeader.append(littleEndian: crc)                      // CRC-32
            localHeader.append(littleEndian: UInt32(dataToWrite.count)) // Compressed size
            localHeader.append(littleEndian: UInt32(fileData.count))   // Uncompressed size
            localHeader.append(littleEndian: UInt16(filename.utf8.count)) // Filename length
            localHeader.append(littleEndian: UInt16(0))                // Extra field length
            localHeader.append(contentsOf: filename.utf8)              // Filename

            archive.append(localHeader)
            archive.append(dataToWrite)

            // Central directory entry
            var centralEntry = Data()
            centralEntry.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])  // Central directory signature
            centralEntry.append(littleEndian: UInt16(20))              // Version made by
            centralEntry.append(littleEndian: UInt16(20))              // Version needed
            centralEntry.append(littleEndian: UInt16(0))               // General purpose flags
            centralEntry.append(littleEndian: compressionMethod)        // Compression method
            centralEntry.append(littleEndian: dosTime)                  // Last mod time
            centralEntry.append(littleEndian: dosDate)                  // Last mod date
            centralEntry.append(littleEndian: crc)                      // CRC-32
            centralEntry.append(littleEndian: UInt32(dataToWrite.count)) // Compressed size
            centralEntry.append(littleEndian: UInt32(fileData.count))   // Uncompressed size
            centralEntry.append(littleEndian: UInt16(filename.utf8.count)) // Filename length
            centralEntry.append(littleEndian: UInt16(0))                // Extra field length
            centralEntry.append(littleEndian: UInt16(0))                // Comment length
            centralEntry.append(littleEndian: UInt16(0))                // Disk number start
            centralEntry.append(littleEndian: UInt16(0))                // Internal attributes
            centralEntry.append(littleEndian: UInt32(0))                // External attributes
            centralEntry.append(littleEndian: localHeaderOffset)        // Offset of local header
            centralEntry.append(contentsOf: filename.utf8)              // Filename

            centralDirectory.append(centralEntry)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        // End of central directory record
        var endRecord = Data()
        endRecord.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])        // End signature
        endRecord.append(littleEndian: UInt16(0))                      // Disk number
        endRecord.append(littleEndian: UInt16(0))                      // Disk with central dir
        endRecord.append(littleEndian: UInt16(files.count))            // Entries on this disk
        endRecord.append(littleEndian: UInt16(files.count))            // Total entries
        endRecord.append(littleEndian: UInt32(centralDirectory.count)) // Central dir size
        endRecord.append(littleEndian: centralDirectoryOffset)         // Central dir offset
        endRecord.append(littleEndian: UInt16(0))                      // Comment length

        archive.append(endRecord)

        return archive
    }

    /// Compress data using DEFLATE algorithm
    private static func compressData(_ data: Data) throws -> Data {
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                data.count,
                sourcePtr.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else {
            throw ESXExportError.zipCreationFailed
        }

        // ZLIB format includes header bytes we need to strip for raw DEFLATE
        // Skip 2-byte zlib header and 4-byte checksum at end
        if compressedSize > 6 {
            return Data(bytes: destinationBuffer + 2, count: compressedSize - 6)
        }

        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    /// Calculate CRC-32 checksum
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF

        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }

        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }

        return crc ^ 0xFFFFFFFF
    }

    /// Get current date/time in DOS format
    private static func currentDOSDateTime() -> (date: UInt16, time: UInt16) {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)

        let year = max(0, (components.year ?? 1980) - 1980)
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0

        let dosDate = UInt16((year << 9) | (month << 5) | day)
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))

        return (dosDate, dosTime)
    }
}

// MARK: - Data Extension for Little-Endian Writing

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
}
