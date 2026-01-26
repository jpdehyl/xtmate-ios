//
//  ESXReaderService.swift
//  XtMate
//
//  Service for reading and parsing Xactimate ESX files.
//  ESX files are ZIP archives containing FIF sketch XML and optionally
//  encrypted XACTDOC.ZIPXML estimate data.
//

import Foundation
import CoreGraphics

// MARK: - ESX Reader Service

/// Service for reading and parsing ESX files
class ESXReaderService {
    static let shared = ESXReaderService()

    // MARK: - Constants

    /// Conversion factor: microns to feet
    private let micronsToFeet: Double = 1.0 / 304_800

    /// Conversion factor: microns to inches
    private let micronsToInches: Double = 1.0 / 25_400

    /// XACTDOC magic header bytes
    private let xactdocMagic: [UInt8] = [0x04, 0x04, 0x0a]

    // MARK: - Public API

    /// Read and parse an ESX file
    /// - Parameter url: URL to the ESX file
    /// - Returns: Parsed ESX content
    func readESX(from url: URL) throws -> ESXContent {
        // Read ZIP archive
        let zipData = try Data(contentsOf: url)
        let files = try ZIPReader.extractFiles(from: zipData)

        var content = ESXContent(sourceURL: url)

        for (filename, fileData) in files {
            let upperName = filename.uppercased()

            if upperName.hasSuffix(".XML") && !upperName.contains("XACTDOC") {
                // FIF sketch file
                content.fifXML = String(data: fileData, encoding: .utf8)
                if let xml = content.fifXML {
                    content.sketchData = try parseFIFXML(xml)
                }
            } else if upperName == "XACTDOC.ZIPXML" {
                // Encrypted estimate data
                content.xactdocData = fileData
                content.xactdocAnalysis = analyzeXACTDOC(fileData)
            } else if upperName.hasSuffix(".JPG") || upperName.hasSuffix(".JPEG") {
                // Photo attachment (likely encrypted)
                let photo = ESXPhoto(filename: filename, data: fileData)
                content.photos.append(photo)
            }
        }

        return content
    }

    /// Import rooms from an ESX file into XtMate format
    /// - Parameter url: URL to the ESX file
    /// - Returns: Array of Room objects
    func importRooms(from url: URL) throws -> [Room] {
        let content = try readESX(from: url)

        guard let sketchData = content.sketchData else {
            throw ESXReaderError.noSketchData
        }

        var rooms: [Room] = []

        for level in sketchData.levels {
            let floorLevel = floorLevelFromName(level.name)

            for sketchRoom in level.rooms {
                // Calculate room dimensions from wall vertices
                let dimensions = calculateRoomDimensions(
                    room: sketchRoom,
                    walls: level.walls,
                    vertices: level.vertices,
                    coordinates: sketchData.coordinates
                )

                let room = Room(
                    name: sketchRoom.name,
                    category: categoryFromName(sketchRoom.name),
                    floor: floorLevel,
                    lengthIn: dimensions.length * 12,  // Convert feet to inches
                    widthIn: dimensions.width * 12,
                    heightIn: dimensions.height * 12,
                    wallCount: sketchRoom.wallIDs.count,
                    doorCount: countOpenings(type: 2, in: sketchRoom.wallIDs, walls: level.walls),
                    windowCount: countOpenings(type: 1, in: sketchRoom.wallIDs, walls: level.walls)
                )
                rooms.append(room)
            }
        }

        return rooms
    }

    // MARK: - FIF XML Parsing

    private func parseFIFXML(_ xml: String) throws -> ESXSketchData {
        guard let data = xml.data(using: .utf8) else {
            throw ESXReaderError.invalidXML
        }

        let parser = FIFXMLParser()
        return try parser.parse(data)
    }

    // MARK: - XACTDOC Analysis

    private func analyzeXACTDOC(_ data: Data) -> XACTDOCAnalysis {
        var analysis = XACTDOCAnalysis()

        guard data.count >= 4 else {
            analysis.isValid = false
            return analysis
        }

        // Check magic header
        let header = Array(data.prefix(4))
        analysis.hasMagicHeader = header[0] == 0x04 && header[1] == 0x04 && header[2] == 0x0a
        analysis.fileType = header[3]
        analysis.payloadSize = data.count - 4
        analysis.isValid = analysis.hasMagicHeader

        // Determine file type
        switch analysis.fileType {
        case 0x04:
            analysis.fileTypeDescription = "XACTDOC (Docusketch source)"
        case 0x07:
            analysis.fileTypeDescription = "XACTDOC (Native Xactimate)"
        case 0x0f:
            analysis.fileTypeDescription = "Encrypted JPG attachment"
        default:
            analysis.fileTypeDescription = "Unknown type: 0x\(String(format: "%02x", analysis.fileType))"
        }

        // Extract first bytes of payload for analysis
        if data.count > 4 {
            analysis.payloadPreview = Array(data[4..<min(40, data.count)])
        }

        return analysis
    }

    // MARK: - Dimension Calculation

    private func calculateRoomDimensions(
        room: ESXRoom,
        walls: [ESXWall],
        vertices: [ESXVertex],
        coordinates: [Double]
    ) -> (length: Double, width: Double, height: Double) {
        // Get all vertex coordinates for this room's walls
        var minX = Double.infinity
        var maxX = -Double.infinity
        var minZ = Double.infinity
        var maxZ = -Double.infinity

        let roomWalls = walls.filter { room.wallIDs.contains($0.id) }

        for wall in roomWalls {
            for vertexID in wall.vertexIDs {
                if let vertex = vertices.first(where: { $0.id == vertexID }) {
                    let coordIndex = vertex.coordIndex * 3
                    if coordIndex + 2 < coordinates.count {
                        let x = coordinates[coordIndex] * micronsToFeet
                        let z = coordinates[coordIndex + 2] * micronsToFeet

                        minX = min(minX, x)
                        maxX = max(maxX, x)
                        minZ = min(minZ, z)
                        maxZ = max(maxZ, z)
                    }
                }
            }
        }

        // Calculate dimensions
        let length = maxX - minX
        let width = maxZ - minZ

        // Height from ceiling height (convert from Xactimate's compressed format)
        // 12192 in FIF = 8 feet, so scale is 1524 per foot
        let height = Double(room.ceilingHeight) / 1524.0

        return (
            length: max(length, 1.0),
            width: max(width, 1.0),
            height: max(height, 6.0)
        )
    }

    private func countOpenings(type: Int, in wallIDs: [Int], walls: [ESXWall]) -> Int {
        var count = 0
        for wallID in wallIDs {
            if let wall = walls.first(where: { $0.id == wallID }) {
                count += wall.openings.filter { $0.type == type }.count
            }
        }
        return count
    }

    // MARK: - Category Detection

    private func categoryFromName(_ name: String) -> RoomCategory {
        let lowercased = name.lowercased()

        if lowercased.contains("kitchen") { return .kitchen }
        if lowercased.contains("bath") { return .bathroom }
        if lowercased.contains("bed") { return .bedroom }
        if lowercased.contains("living") { return .livingRoom }
        if lowercased.contains("dining") { return .diningRoom }
        if lowercased.contains("office") || lowercased.contains("study") { return .office }
        if lowercased.contains("laundry") { return .laundry }
        if lowercased.contains("garage") { return .garage }
        if lowercased.contains("basement") { return .basement }
        if lowercased.contains("hall") { return .hallway }
        if lowercased.contains("closet") { return .closet }

        return .other
    }

    private func floorLevelFromName(_ name: String) -> FloorLevel {
        let lowercased = name.lowercased()

        if lowercased.contains("basement") || lowercased.contains("lower") { return .basement }
        if lowercased.contains("attic") || lowercased.contains("upper") { return .attic }
        if lowercased.contains("second") || lowercased.contains("2nd") { return .second }
        if lowercased.contains("third") || lowercased.contains("3rd") { return .third }

        return .first
    }
}

// MARK: - FIF XML Parser

private class FIFXMLParser: NSObject, XMLParserDelegate {
    private var sketchData = ESXSketchData()
    private var currentLevel: ESXLevel?
    private var currentRoom: ESXRoom?
    private var currentWall: ESXWall?
    private var currentOpening: ESXWallOpening?
    private var currentVertex: ESXVertex?
    private var currentElement = ""
    private var characterBuffer = ""

    func parse(_ data: Data) throws -> ESXSketchData {
        let parser = XMLParser(data: data)
        parser.delegate = self
        if parser.parse() {
            return sketchData
        } else if let error = parser.parserError {
            throw error
        }
        throw ESXReaderError.parseError
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        characterBuffer = ""

        switch elementName {
        case "SKETCHLEVEL":
            currentLevel = ESXLevel(
                id: parseID(attributes["id"]),
                name: attributes["name"] ?? "Unknown",
                floorElevation: Double(attributes["floorElevation"] ?? "0") ?? 0
            )

        case "SKETCHLEVELVERTEX":
            let vertex = ESXVertex(
                id: parseID(attributes["id"]),
                coordIndex: Int(attributes["vertex"] ?? "0") ?? 0,
                wallIDs: parseIDList(attributes["wallIDs"])
            )
            currentLevel?.vertices.append(vertex)

        case "SKETCHROOM":
            currentRoom = ESXRoom(
                id: parseID(attributes["id"]),
                name: "",
                ceilingHeight: Int(attributes["ceilingHeight"] ?? "12192") ?? 12192,
                wallIDs: parseIDList(attributes["wallIDs"])
            )

        case "SKETCHWALL":
            currentWall = ESXWall(
                id: parseID(attributes["id"]),
                roomIDs: parseIDList(attributes["roomIDs"]),
                thickness: Int(attributes["thickness"] ?? "508") ?? 508,
                vertexIDs: parseIDList(attributes["vertexIDs"])
            )

        case "SKETCHWALLOPENING":
            let opening = ESXWallOpening(
                id: parseID(attributes["id"]),
                type: Int(attributes["type"] ?? "0") ?? 0,
                doorType: Int(attributes["doorType"] ?? "0") ?? 0,
                coordIndices: parseIntList(attributes["coordIndex"]),
                flags: Int(attributes["flags"] ?? "0") ?? 0
            )
            currentWall?.openings.append(opening)

        case "COORDINATE3":
            break  // Will capture in characters

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterBuffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            characterBuffer += text
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "SKETCHLEVEL":
            if let level = currentLevel {
                sketchData.levels.append(level)
            }
            currentLevel = nil

        case "SKETCHROOM":
            if var room = currentRoom {
                room.name = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if room.name.isEmpty {
                    room.name = "Room"
                }
                currentLevel?.rooms.append(room)
            }
            currentRoom = nil

        case "SKETCHWALL":
            if let wall = currentWall {
                currentLevel?.walls.append(wall)
            }
            currentWall = nil

        case "SKETCHCDATACHILD":
            // Room name is in CDATA
            if currentRoom != nil {
                currentRoom?.name = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            }

        case "COORDINATE3":
            let coords = characterBuffer
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .compactMap { Double($0) }
            sketchData.coordinates = coords

        default:
            break
        }

        characterBuffer = ""
    }

    private func parseID(_ str: String?) -> Int {
        guard let str = str else { return 0 }
        // IDs are like "SKT123" - extract the number
        let digits = str.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    private func parseIDList(_ str: String?) -> [Int] {
        guard let str = str else { return [] }
        return str.split(separator: " ").map { parseID(String($0)) }
    }

    private func parseIntList(_ str: String?) -> [Int] {
        guard let str = str else { return [] }
        return str.split(separator: " ").compactMap { Int($0) }
    }
}

// MARK: - ZIP Reader

private struct ZIPReader {
    static func extractFiles(from data: Data) throws -> [(name: String, data: Data)] {
        var files: [(name: String, data: Data)] = []
        var offset = 0

        while offset < data.count - 4 {
            // Look for local file header signature (PK\x03\x04)
            guard data[offset] == 0x50 && data[offset + 1] == 0x4B else {
                offset += 1
                continue
            }

            // Check if it's a local file header or end of central directory
            if data[offset + 2] == 0x03 && data[offset + 3] == 0x04 {
                // Local file header
                guard offset + 30 <= data.count else { break }

                let compressionMethod = UInt16(data[offset + 8]) | (UInt16(data[offset + 9]) << 8)
                let compressedSize = UInt32(data[offset + 18]) | (UInt32(data[offset + 19]) << 8) |
                                     (UInt32(data[offset + 20]) << 16) | (UInt32(data[offset + 21]) << 24)
                let uncompressedSize = UInt32(data[offset + 22]) | (UInt32(data[offset + 23]) << 8) |
                                       (UInt32(data[offset + 24]) << 16) | (UInt32(data[offset + 25]) << 24)
                let fileNameLength = UInt16(data[offset + 26]) | (UInt16(data[offset + 27]) << 8)
                let extraFieldLength = UInt16(data[offset + 28]) | (UInt16(data[offset + 29]) << 8)

                let headerSize = 30
                let fileNameStart = offset + headerSize
                let fileNameEnd = fileNameStart + Int(fileNameLength)

                guard fileNameEnd <= data.count else { break }

                let fileNameData = data[fileNameStart..<fileNameEnd]
                let fileName = String(data: fileNameData, encoding: .utf8) ?? "unknown"

                let dataStart = fileNameEnd + Int(extraFieldLength)
                let dataEnd = dataStart + Int(compressedSize)

                guard dataEnd <= data.count else { break }

                let fileData = data[dataStart..<dataEnd]

                // Decompress if needed
                let finalData: Data
                if compressionMethod == 8 {
                    // DEFLATE compression
                    finalData = try decompressDeflate(Data(fileData), expectedSize: Int(uncompressedSize))
                } else {
                    // Stored (no compression)
                    finalData = Data(fileData)
                }

                files.append((name: fileName, data: finalData))
                offset = dataEnd
            } else if data[offset + 2] == 0x01 && data[offset + 3] == 0x02 {
                // Central directory header - we're done with file data
                break
            } else if data[offset + 2] == 0x05 && data[offset + 3] == 0x06 {
                // End of central directory - we're done
                break
            } else {
                offset += 1
            }
        }

        return files
    }

    private static func decompressDeflate(_ data: Data, expectedSize: Int) throws -> Data {
        // Add zlib header for decompression (raw DEFLATE needs this)
        var zlibData = Data([0x78, 0x9C])  // Default compression header
        zlibData.append(data)

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = zlibData.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                expectedSize,
                sourcePtr.assumingMemoryBound(to: UInt8.self),
                zlibData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            // If zlib decompression fails, try returning raw data
            return data
        }

        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
}

// MARK: - Data Models

/// Parsed content from an ESX file
struct ESXContent {
    let sourceURL: URL
    var fifXML: String?
    var sketchData: ESXSketchData?
    var xactdocData: Data?
    var xactdocAnalysis: XACTDOCAnalysis?
    var photos: [ESXPhoto] = []

    var hasSketch: Bool { sketchData != nil }
    var hasXACTDOC: Bool { xactdocData != nil }
    var hasPhotos: Bool { !photos.isEmpty }

    var summary: String {
        var parts: [String] = []
        if let sketch = sketchData {
            let roomCount = sketch.levels.reduce(0) { $0 + $1.rooms.count }
            parts.append("\(roomCount) room(s) in \(sketch.levels.count) level(s)")
        }
        if let analysis = xactdocAnalysis, analysis.isValid {
            parts.append("XACTDOC (\(analysis.fileTypeDescription))")
        }
        if !photos.isEmpty {
            parts.append("\(photos.count) photo(s)")
        }
        return parts.isEmpty ? "Empty ESX" : parts.joined(separator: ", ")
    }
}

/// Analysis of XACTDOC.ZIPXML encryption
struct XACTDOCAnalysis {
    var isValid = false
    var hasMagicHeader = false
    var fileType: UInt8 = 0
    var fileTypeDescription = ""
    var payloadSize = 0
    var payloadPreview: [UInt8] = []

    var isEncrypted: Bool {
        // XACTDOC files with magic header are encrypted
        return hasMagicHeader
    }
}

/// Photo attachment in ESX
struct ESXPhoto {
    let filename: String
    let data: Data

    var isEncrypted: Bool {
        // Check for XACTDOC-style encryption header
        guard data.count >= 4 else { return false }
        return data[0] == 0x04 && data[1] == 0x04 && data[2] == 0x0a
    }
}

/// Parsed sketch data from FIF XML
struct ESXSketchData {
    var levels: [ESXLevel] = []
    var coordinates: [Double] = []
}

/// Floor level in sketch
struct ESXLevel {
    let id: Int
    let name: String
    let floorElevation: Double
    var vertices: [ESXVertex] = []
    var rooms: [ESXRoom] = []
    var walls: [ESXWall] = []
}

/// Vertex in sketch
struct ESXVertex {
    let id: Int
    let coordIndex: Int
    let wallIDs: [Int]
}

/// Room in sketch
struct ESXRoom {
    let id: Int
    var name: String
    let ceilingHeight: Int
    let wallIDs: [Int]
}

/// Wall in sketch
struct ESXWall {
    let id: Int
    let roomIDs: [Int]
    let thickness: Int
    let vertexIDs: [Int]
    var openings: [ESXWallOpening] = []
}

/// Wall opening (door/window)
struct ESXWallOpening {
    let id: Int
    let type: Int  // 0=opening, 1=window, 2=door
    let doorType: Int
    let coordIndices: [Int]
    let flags: Int
}

// MARK: - Errors

enum ESXReaderError: Error, LocalizedError {
    case fileNotFound
    case invalidZip
    case invalidXML
    case noSketchData
    case parseError
    case encryptedContent

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "ESX file not found."
        case .invalidZip:
            return "Invalid ESX archive format."
        case .invalidXML:
            return "Invalid FIF XML content."
        case .noSketchData:
            return "No sketch data found in ESX file."
        case .parseError:
            return "Failed to parse ESX content."
        case .encryptedContent:
            return "ESX content is encrypted and cannot be read."
        }
    }
}
