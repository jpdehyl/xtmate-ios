//
//  WallGraphBuilder.swift
//  XtMate
//
//  Builds a graph representation from wall segments extracted from RoomPlan CapturedRoom data.
//  The graph is used for detecting enclosed polygon regions (rooms) through cycle detection.
//
//  PRD: Room Capture Enhancements - US-RC-002
//

import Foundation
import CoreGraphics
import RoomPlan
import simd

/// Builds a graph from wall segments for room boundary detection
@available(iOS 16.0, *)
final class WallGraphBuilder {

    // MARK: - Configuration

    /// Tolerance for connecting wall endpoints (in feet)
    private let connectionTolerance: CGFloat = 1.0  // 12 inches

    /// Minimum wall length to include (in feet)
    private let minimumWallLength: CGFloat = 0.5  // 6 inches

    /// Meters to feet conversion
    private let metersToFeet: CGFloat = 3.28084

    // MARK: - Types

    /// Represents a node in the wall graph (an intersection or endpoint)
    struct GraphNode: Hashable {
        let id: UUID
        let position: CGPoint

        init(id: UUID = UUID(), position: CGPoint) {
            self.id = id
            self.position = position
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// Represents an edge in the wall graph (a wall segment)
    struct GraphEdge: Hashable {
        let id: UUID
        let startNode: UUID
        let endNode: UUID
        let wallSegment: WallSegment

        init(id: UUID = UUID(), startNode: UUID, endNode: UUID, wallSegment: WallSegment) {
            self.id = id
            self.startNode = startNode
            self.endNode = endNode
            self.wallSegment = wallSegment
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: GraphEdge, rhs: GraphEdge) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// The complete wall graph
    struct WallGraph {
        var nodes: [UUID: GraphNode]
        var edges: [GraphEdge]
        var adjacencyList: [UUID: [UUID]]  // Node ID -> Connected node IDs
        let boundingBox: CGRect

        init(nodes: [UUID: GraphNode] = [:], edges: [GraphEdge] = [], adjacencyList: [UUID: [UUID]] = [:], boundingBox: CGRect = .zero) {
            self.nodes = nodes
            self.edges = edges
            self.adjacencyList = adjacencyList
            self.boundingBox = boundingBox
        }
    }

    // MARK: - Public Interface

    /// Build a wall graph from a CapturedRoom
    func buildGraph(from capturedRoom: CapturedRoom) -> WallGraph {
        // Extract wall segments from CapturedRoom
        let wallSegments = extractWallSegments(from: capturedRoom)

        guard !wallSegments.isEmpty else {
            print("WallGraphBuilder: No wall segments found")
            return WallGraph()
        }

        // Build the graph from wall segments
        return buildGraphFromSegments(wallSegments)
    }

    /// Build a wall graph from existing FloorPlanData
    func buildGraph(from floorPlanData: FloorPlanData) -> WallGraph {
        let wallSegments = floorPlanData.walls.map { wall in
            WallSegment(
                start: wall.startPoint,
                end: wall.endPoint,
                thickness: 6,
                heightFt: wall.height
            )
        }

        guard !wallSegments.isEmpty else {
            return WallGraph()
        }

        return buildGraphFromSegments(wallSegments)
    }

    // MARK: - Wall Extraction

    /// Extract wall segments from CapturedRoom
    private func extractWallSegments(from capturedRoom: CapturedRoom) -> [WallSegment] {
        var segments: [WallSegment] = []

        for wall in capturedRoom.walls {
            let transform = wall.transform
            let dimensions = wall.dimensions

            // Extract position from transform matrix (column 3)
            let x = CGFloat(transform.columns.3.x) * metersToFeet
            let z = CGFloat(transform.columns.3.z) * metersToFeet

            // Wall dimensions (in meters, convert to feet)
            let wallLength = CGFloat(dimensions.x) * metersToFeet
            let wallHeight = CGFloat(dimensions.y) * metersToFeet

            // Skip very short walls
            guard wallLength >= minimumWallLength else { continue }

            // Calculate wall direction from rotation matrix (column 0)
            let dirX = CGFloat(transform.columns.0.x)
            let dirZ = CGFloat(transform.columns.0.z)

            // Calculate start and end points
            let halfLength = wallLength / 2
            let startPoint = CGPoint(
                x: x - dirX * halfLength,
                y: z - dirZ * halfLength
            )
            let endPoint = CGPoint(
                x: x + dirX * halfLength,
                y: z + dirZ * halfLength
            )

            let segment = WallSegment(
                start: startPoint,
                end: endPoint,
                thickness: 6,  // Default 6 inches
                heightFt: wallHeight
            )

            segments.append(segment)
        }

        print("WallGraphBuilder: Extracted \(segments.count) wall segments from CapturedRoom")
        return segments
    }

    // MARK: - Graph Building

    /// Build graph from wall segments
    private func buildGraphFromSegments(_ segments: [WallSegment]) -> WallGraph {
        var nodes: [UUID: GraphNode] = [:]
        var edges: [GraphEdge] = []
        var adjacencyList: [UUID: [UUID]] = [:]

        // Collect all endpoints
        var endpoints: [(CGPoint, WallSegment, Bool)] = []  // (point, segment, isStart)
        for segment in segments {
            endpoints.append((segment.start, segment, true))
            endpoints.append((segment.end, segment, false))
        }

        // Merge nearby endpoints into nodes
        for (point, _, _) in endpoints {
            // Check if there's already a nearby node
            var hasNearbyNode = false

            for (_, existingNode) in nodes {
                if distance(point, existingNode.position) <= connectionTolerance {
                    hasNearbyNode = true
                    break
                }
            }

            if !hasNearbyNode {
                // Create new node
                let node = GraphNode(position: point)
                nodes[node.id] = node
                adjacencyList[node.id] = []
            }
        }

        // Create edges from segments
        for segment in segments {
            // Find the nodes for this segment
            guard let startNodeId = findNearestNode(to: segment.start, in: nodes),
                  let endNodeId = findNearestNode(to: segment.end, in: nodes),
                  startNodeId != endNodeId else {
                continue
            }

            // Create edge
            let edge = GraphEdge(
                startNode: startNodeId,
                endNode: endNodeId,
                wallSegment: segment
            )
            edges.append(edge)

            // Update adjacency list (bidirectional)
            adjacencyList[startNodeId, default: []].append(endNodeId)
            adjacencyList[endNodeId, default: []].append(startNodeId)
        }

        // Calculate bounding box
        let boundingBox = calculateBoundingBox(for: segments)

        print("WallGraphBuilder: Built graph with \(nodes.count) nodes and \(edges.count) edges")

        return WallGraph(
            nodes: nodes,
            edges: edges,
            adjacencyList: adjacencyList,
            boundingBox: boundingBox
        )
    }

    /// Find the nearest node to a point
    private func findNearestNode(to point: CGPoint, in nodes: [UUID: GraphNode]) -> UUID? {
        var nearestId: UUID? = nil
        var nearestDistance = CGFloat.infinity

        for (id, node) in nodes {
            let dist = distance(point, node.position)
            if dist < nearestDistance && dist <= connectionTolerance {
                nearestDistance = dist
                nearestId = id
            }
        }

        return nearestId
    }

    // MARK: - Cycle Detection

    /// Find all cycles (enclosed polygons) in the graph
    func findCycles(in graph: WallGraph) -> [[UUID]] {
        var allCycles: [[UUID]] = []
        var visited: Set<UUID> = []

        // Use DFS to find cycles
        for startNodeId in graph.nodes.keys {
            let cycles = findCyclesFromNode(
                startNodeId,
                graph: graph,
                visited: &visited
            )
            allCycles.append(contentsOf: cycles)
        }

        // Filter out duplicate cycles and very small cycles
        let uniqueCycles = filterUniqueCycles(allCycles)

        print("WallGraphBuilder: Found \(uniqueCycles.count) unique cycles")

        return uniqueCycles
    }

    /// Find cycles starting from a specific node using DFS
    private func findCyclesFromNode(
        _ startNode: UUID,
        graph: WallGraph,
        visited: inout Set<UUID>
    ) -> [[UUID]] {
        var cycles: [[UUID]] = []
        var stack: [(UUID, [UUID], Set<String>)] = [(startNode, [startNode], Set())]  // (current, path, visitedEdges)

        while !stack.isEmpty {
            let (current, path, visitedEdges) = stack.removeLast()

            guard let neighbors = graph.adjacencyList[current] else { continue }

            for neighbor in neighbors {
                // Create edge key (bidirectional)
                let edgeKey = [current.uuidString, neighbor.uuidString].sorted().joined(separator: "-")

                // Skip if edge already visited in this path
                if visitedEdges.contains(edgeKey) { continue }

                // Found a cycle back to start
                if neighbor == startNode && path.count >= 3 {
                    cycles.append(path)
                    continue
                }

                // Skip if node already in path (but not start)
                if path.contains(neighbor) { continue }

                // Continue DFS
                var newVisitedEdges = visitedEdges
                newVisitedEdges.insert(edgeKey)
                stack.append((neighbor, path + [neighbor], newVisitedEdges))
            }
        }

        return cycles
    }

    /// Filter out duplicate and invalid cycles
    private func filterUniqueCycles(_ cycles: [[UUID]]) -> [[UUID]] {
        var uniqueCycles: [[UUID]] = []
        var seenSignatures: Set<String> = []

        for cycle in cycles {
            // Skip very small cycles
            if cycle.count < 3 { continue }

            // Create a signature that's the same regardless of starting point or direction
            let signature = createCycleSignature(cycle)

            if !seenSignatures.contains(signature) {
                seenSignatures.insert(signature)
                uniqueCycles.append(cycle)
            }
        }

        return uniqueCycles
    }

    /// Create a canonical signature for a cycle
    private func createCycleSignature(_ cycle: [UUID]) -> String {
        let strings = cycle.map { $0.uuidString }

        // Find all rotations and reverse
        var allVersions: [String] = []

        for i in 0..<strings.count {
            let rotated = Array(strings[i...]) + Array(strings[..<i])
            allVersions.append(rotated.joined(separator: "-"))
            allVersions.append(rotated.reversed().joined(separator: "-"))
        }

        // Return the lexicographically smallest version
        return allVersions.min() ?? ""
    }

    /// Convert a cycle of node IDs to a polygon of points
    func cycleToPolygon(_ cycle: [UUID], graph: WallGraph) -> [CGPoint] {
        return cycle.compactMap { nodeId in
            graph.nodes[nodeId]?.position
        }
    }

    // MARK: - Helpers

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }

    private func hashPoint(_ point: CGPoint) -> Int {
        // Hash with tolerance (round to nearest 0.1 feet)
        let x = Int(round(point.x * 10))
        let y = Int(round(point.y * 10))
        return x * 100000 + y
    }

    private func calculateBoundingBox(for segments: [WallSegment]) -> CGRect {
        guard !segments.isEmpty else { return .zero }

        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity

        for segment in segments {
            minX = min(minX, segment.start.x, segment.end.x)
            maxX = max(maxX, segment.start.x, segment.end.x)
            minY = min(minY, segment.start.y, segment.end.y)
            maxY = max(maxY, segment.start.y, segment.end.y)
        }

        let padding: CGFloat = 2.0  // 2 feet padding
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + padding * 2,
            height: (maxY - minY) + padding * 2
        )
    }
}

// MARK: - Graph Analysis Extensions

@available(iOS 16.0, *)
extension WallGraphBuilder.WallGraph {

    /// Get all edges connected to a node
    func edges(for nodeId: UUID) -> [WallGraphBuilder.GraphEdge] {
        return edges.filter { $0.startNode == nodeId || $0.endNode == nodeId }
    }

    /// Get the degree (number of connections) for a node
    func degree(of nodeId: UUID) -> Int {
        return adjacencyList[nodeId]?.count ?? 0
    }

    /// Find nodes that are likely room corners (degree >= 2)
    var cornerNodes: [UUID] {
        return nodes.keys.filter { degree(of: $0) >= 2 }
    }

    /// Find leaf nodes (dead ends, degree == 1)
    var leafNodes: [UUID] {
        return nodes.keys.filter { degree(of: $0) == 1 }
    }
}
