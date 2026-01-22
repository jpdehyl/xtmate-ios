//
//  ProposedRoomsReviewView.swift
//  XtMate
//
//  UI for reviewing and adjusting automatically detected room boundaries.
//  PMs can confirm, merge, split, or rename proposed rooms before saving.
//
//  PRD: Room Capture Enhancements - US-RC-002
//

import SwiftUI
import RoomPlan

/// Main view for reviewing proposed rooms from automatic detection
@available(iOS 16.0, *)
struct ProposedRoomsReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let capturedRoom: CapturedRoom
    let analysisResult: RoomBoundaryAnalysisResult
    var onSaveRooms: (([Room]) -> Void)?
    var onSaveSingleRoom: ((Room) -> Void)?
    var onCancel: (() -> Void)?

    @State private var proposedRooms: [ProposedRoom]
    @State private var selectedRoomId: UUID?
    @State private var editingRoom: ProposedRoom?
    @State private var showingMergeSheet = false
    @State private var mergeTargetId: UUID?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    // Colors for room boundaries
    private let roomColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .yellow, .mint
    ]

    init(
        capturedRoom: CapturedRoom,
        analysisResult: RoomBoundaryAnalysisResult,
        onSaveRooms: (([Room]) -> Void)? = nil,
        onSaveSingleRoom: ((Room) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.capturedRoom = capturedRoom
        self.analysisResult = analysisResult
        self.onSaveRooms = onSaveRooms
        self.onSaveSingleRoom = onSaveSingleRoom
        self.onCancel = onCancel
        _proposedRooms = State(initialValue: analysisResult.proposedRooms)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with stats
                analysisHeader

                Divider()

                // Main content: floor plan with room boundaries
                GeometryReader { geometry in
                    ZStack {
                        Color(.systemGray6)

                        // Floor plan canvas
                        FloorPlanWithRoomsCanvas(
                            proposedRooms: proposedRooms,
                            doorways: analysisResult.doorways,
                            windows: analysisResult.windows,
                            boundingBox: calculateBoundingBox(),
                            selectedRoomId: selectedRoomId,
                            roomColors: roomColors,
                            scale: $scale,
                            offset: $offset,
                            onRoomTapped: { room in
                                withAnimation(.spring(response: 0.3)) {
                                    selectedRoomId = selectedRoomId == room.id ? nil : room.id
                                }
                            }
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)

                        // Room labels overlay
                        roomLabelsOverlay(in: geometry.size)
                    }
                }

                // Bottom panel: room list and actions
                VStack(spacing: 0) {
                    Divider()

                    // Room list (horizontal scroll)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(proposedRooms.enumerated()), id: \.element.id) { index, room in
                                RoomChip(
                                    room: room,
                                    color: roomColors[index % roomColors.count],
                                    isSelected: selectedRoomId == room.id,
                                    onTap: {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedRoomId = selectedRoomId == room.id ? nil : room.id
                                        }
                                    },
                                    onEdit: {
                                        editingRoom = room
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                    .frame(height: 100)

                    Divider()

                    // Action buttons
                    HStack(spacing: 16) {
                        // Use single room
                        if proposedRooms.count > 1 {
                            Button(action: useSingleRoom) {
                                Label("Use as One Room", systemImage: "rectangle")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()

                        // Merge selected rooms
                        if selectedRoomId != nil && proposedRooms.count > 1 {
                            Button(action: { showingMergeSheet = true }) {
                                Label("Merge", systemImage: "arrow.triangle.merge")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }

                        // Save all rooms
                        Button(action: saveAllRooms) {
                            Text("Save \(proposedRooms.count) Room\(proposedRooms.count == 1 ? "" : "s")")
                                .font(.headline)
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle("Review Detected Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: resetToOriginal) {
                            Label("Reset to Original", systemImage: "arrow.counterclockwise")
                        }

                        if proposedRooms.count > 1 {
                            Button(action: useSingleRoom) {
                                Label("Use as Single Room", systemImage: "rectangle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $editingRoom) { room in
                EditProposedRoomSheet(
                    room: room,
                    onSave: { updatedRoom in
                        if let index = proposedRooms.firstIndex(where: { $0.id == room.id }) {
                            proposedRooms[index] = updatedRoom
                        }
                        editingRoom = nil
                    },
                    onDelete: {
                        proposedRooms.removeAll { $0.id == room.id }
                        editingRoom = nil
                        selectedRoomId = nil
                    }
                )
            }
            .sheet(isPresented: $showingMergeSheet) {
                if let selectedId = selectedRoomId,
                   let selectedRoom = proposedRooms.first(where: { $0.id == selectedId }) {
                    MergeRoomsSheet(
                        sourceRoom: selectedRoom,
                        availableRooms: proposedRooms.filter { $0.id != selectedId },
                        onMerge: { targetRoom in
                            mergeRooms(source: selectedRoom, target: targetRoom)
                            showingMergeSheet = false
                        }
                    )
                }
            }
        }
    }

    // MARK: - Components

    private var analysisHeader: some View {
        HStack(spacing: 16) {
            // Confidence badge
            VStack(alignment: .leading, spacing: 2) {
                Text("Confidence")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f%%", analysisResult.overallConfidence * 100))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(confidenceColor)
            }

            Divider()
                .frame(height: 40)

            // Room count
            VStack(alignment: .leading, spacing: 2) {
                Text("Detected Rooms")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(proposedRooms.count)")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Divider()
                .frame(height: 40)

            // Total area
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Area")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(Int(totalSquareFeet)) SF")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Spacer()
        }
        .padding()
    }

    private var confidenceColor: Color {
        if analysisResult.overallConfidence >= 0.8 {
            return .green
        } else if analysisResult.overallConfidence >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }

    private var totalSquareFeet: Double {
        proposedRooms.reduce(0) { $0 + $1.squareFeet }
    }

    private func roomLabelsOverlay(in size: CGSize) -> some View {
        let bbox = calculateBoundingBox()
        let baseScale = calculateBaseScale(viewSize: size, boundingBox: bbox)

        return ZStack {
            ForEach(Array(proposedRooms.enumerated()), id: \.element.id) { index, room in
                let viewPos = convertToViewPosition(
                    floorPlanPoint: room.centroid,
                    viewSize: size,
                    boundingBox: bbox,
                    scale: scale * baseScale,
                    offset: offset
                )

                VStack(spacing: 2) {
                    Text(room.suggestedName)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("\(Int(room.squareFeet)) SF")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(roomColors[index % roomColors.count].opacity(0.9))
                .foregroundColor(.white)
                .cornerRadius(6)
                .shadow(radius: 2)
                .position(viewPos)
                .opacity(selectedRoomId == nil || selectedRoomId == room.id ? 1 : 0.3)
            }
        }
    }

    // MARK: - Actions

    private func saveAllRooms() {
        // Convert ProposedRooms to Rooms
        let rooms = proposedRooms.map { proposed -> Room in
            createRoom(from: proposed)
        }

        if rooms.count == 1 {
            onSaveSingleRoom?(rooms[0])
        } else {
            onSaveRooms?(rooms)
        }

        dismiss()
    }

    private func useSingleRoom() {
        // Merge all rooms into one
        guard let first = proposedRooms.first else { return }

        let mergedBoundary = proposedRooms.flatMap { $0.boundary }
        let mergedObjects = proposedRooms.flatMap { $0.detectedObjects }
        let totalDoors = proposedRooms.reduce(0) { $0 + $1.doorwayCount }
        let totalWindows = proposedRooms.reduce(0) { $0 + $1.windowCount }

        let (name, category, confidence) = classifyMergedRoom(objects: mergedObjects)

        let singleRoom = ProposedRoom(
            suggestedName: name,
            suggestedCategory: category,
            confidence: confidence,
            boundary: calculateConvexHull(mergedBoundary),
            boundingBox: calculateBoundingBox(),
            detectedObjects: mergedObjects,
            doorwayCount: totalDoors,
            windowCount: totalWindows,
            wallSegments: proposedRooms.flatMap { $0.wallSegments },
            isClosed: true,
            avgHeightFt: first.avgHeightFt
        )

        proposedRooms = [singleRoom]
        selectedRoomId = nil
    }

    private func mergeRooms(source: ProposedRoom, target: ProposedRoom) {
        // Combine boundaries
        let mergedBoundary = source.boundary + target.boundary
        let mergedObjects = source.detectedObjects + target.detectedObjects

        let (name, category, _) = classifyMergedRoom(objects: mergedObjects)

        let merged = ProposedRoom(
            suggestedName: name,
            suggestedCategory: category,
            confidence: min(source.confidence, target.confidence),
            boundary: calculateConvexHull(mergedBoundary),
            boundingBox: source.boundingBox.union(target.boundingBox),
            detectedObjects: mergedObjects,
            doorwayCount: source.doorwayCount + target.doorwayCount,
            windowCount: source.windowCount + target.windowCount,
            wallSegments: source.wallSegments + target.wallSegments,
            isClosed: source.isClosed && target.isClosed,
            avgHeightFt: (source.avgHeightFt + target.avgHeightFt) / 2
        )

        // Remove source and target, add merged
        proposedRooms.removeAll { $0.id == source.id || $0.id == target.id }
        proposedRooms.append(merged)
        selectedRoomId = merged.id
    }

    private func resetToOriginal() {
        proposedRooms = analysisResult.proposedRooms
        selectedRoomId = nil
    }

    // MARK: - Helpers

    private func createRoom(from proposed: ProposedRoom) -> Room {
        Room(
            name: proposed.suggestedName,
            category: proposed.suggestedCategory,
            floor: .first,
            lengthIn: proposed.boundingBox.width * 12,  // Convert feet to inches
            widthIn: proposed.boundingBox.height * 12,
            heightIn: proposed.avgHeightFt * 12,
            wallCount: proposed.wallSegments.count,
            doorCount: proposed.doorwayCount,
            windowCount: proposed.windowCount
        )
    }

    private func calculateBoundingBox() -> CGRect {
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity

        for room in proposedRooms {
            for point in room.boundary {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
        }

        let padding: CGFloat = 2.0
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + padding * 2,
            height: (maxY - minY) + padding * 2
        )
    }

    private func calculateBaseScale(viewSize: CGSize, boundingBox: CGRect) -> CGFloat {
        let scaleX = (viewSize.width * 0.9) / boundingBox.width
        let scaleY = (viewSize.height * 0.9) / boundingBox.height
        return min(scaleX, scaleY, 30.0)  // Max 30x scale
    }

    private func convertToViewPosition(
        floorPlanPoint: CGPoint,
        viewSize: CGSize,
        boundingBox: CGRect,
        scale: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2

        let floorPlanCenter = CGPoint(x: boundingBox.midX, y: boundingBox.midY)

        let x = centerX + offset.width + (floorPlanPoint.x - floorPlanCenter.x) * scale
        let y = centerY + offset.height + (floorPlanPoint.y - floorPlanCenter.y) * scale

        return CGPoint(x: x, y: y)
    }

    private func classifyMergedRoom(objects: [DetectedObject]) -> (String, RoomCategory, Float) {
        var hasKitchen = false
        var hasBathroom = false
        var hasLiving = false

        for obj in objects {
            let cat = obj.category.lowercased()
            if ["refrigerator", "stove", "oven", "dishwasher"].contains(cat) {
                hasKitchen = true
            }
            if ["toilet", "bathtub", "shower"].contains(cat) {
                hasBathroom = true
            }
            if ["sofa", "couch", "tv"].contains(cat) {
                hasLiving = true
            }
        }

        if hasKitchen && hasLiving {
            return ("Kitchen/Living", .livingRoom, 0.7)
        } else if hasKitchen {
            return ("Kitchen", .kitchen, 0.8)
        } else if hasBathroom {
            return ("Bathroom", .bathroom, 0.8)
        } else if hasLiving {
            return ("Living Room", .livingRoom, 0.7)
        }

        return ("Open Space", .other, 0.5)
    }

    private func calculateConvexHull(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        var sorted = points.sorted { $0.y < $1.y || ($0.y == $1.y && $0.x < $1.x) }
        let origin = sorted.removeFirst()

        sorted.sort { p1, p2 in
            let angle1 = atan2(p1.y - origin.y, p1.x - origin.x)
            let angle2 = atan2(p2.y - origin.y, p2.x - origin.x)
            return angle1 < angle2
        }

        var hull: [CGPoint] = [origin]

        for point in sorted {
            while hull.count > 1 {
                let a = hull[hull.count - 2]
                let b = hull[hull.count - 1]
                let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
                if cross <= 0 {
                    hull.removeLast()
                } else {
                    break
                }
            }
            hull.append(point)
        }

        return hull
    }
}

// MARK: - Room Chip

@available(iOS 16.0, *)
struct RoomChip: View {
    let room: ProposedRoom
    let color: Color
    let isSelected: Bool
    var onTap: (() -> Void)?
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // Color indicator
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            // Room info
            VStack(alignment: .leading, spacing: 2) {
                Text(room.suggestedName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text("\(Int(room.squareFeet)) SF")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Confidence indicator
                    Image(systemName: confidenceIcon)
                        .font(.caption2)
                        .foregroundColor(confidenceColor)
                }
            }

            // Edit button
            Button(action: { onEdit?() }) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? color.opacity(0.2) : Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? color : Color.clear, lineWidth: 2)
        )
        .onTapGesture { onTap?() }
    }

    private var confidenceIcon: String {
        if room.confidence >= 0.8 { return "checkmark.circle.fill" }
        if room.confidence >= 0.5 { return "questionmark.circle" }
        return "exclamationmark.circle"
    }

    private var confidenceColor: Color {
        if room.confidence >= 0.8 { return .green }
        if room.confidence >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - Floor Plan Canvas with Rooms

@available(iOS 16.0, *)
struct FloorPlanWithRoomsCanvas: View {
    let proposedRooms: [ProposedRoom]
    let doorways: [Doorway]
    let windows: [FloorPlanWindow]
    let boundingBox: CGRect
    let selectedRoomId: UUID?
    let roomColors: [Color]

    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    var onRoomTapped: ((ProposedRoom) -> Void)?

    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let baseScale = calculateBaseScale(viewSize: viewSize)

            Canvas { context, size in
                let centerOffset = CGSize(
                    width: size.width / 2,
                    height: size.height / 2
                )

                context.translateBy(x: centerOffset.width + offset.width, y: centerOffset.height + offset.height)
                context.scaleBy(x: scale * baseScale, y: scale * baseScale)

                let floorPlanCenter = CGPoint(x: boundingBox.midX, y: boundingBox.midY)
                context.translateBy(x: -floorPlanCenter.x, y: -floorPlanCenter.y)

                // Draw grid
                drawGrid(context: context)

                // Draw room boundaries (filled)
                for (index, room) in proposedRooms.enumerated() {
                    let color = roomColors[index % roomColors.count]
                    let isSelected = selectedRoomId == room.id
                    drawRoomBoundary(context: context, room: room, color: color, isSelected: isSelected)
                }

                // Draw wall segments
                for room in proposedRooms {
                    for segment in room.wallSegments {
                        drawWallSegment(context: context, segment: segment)
                    }
                }

                // Draw doorways
                for doorway in doorways {
                    drawDoorway(context: context, doorway: doorway)
                }

                // Draw windows
                for window in windows {
                    drawWindow(context: context, window: window)
                }

                // Draw detected objects
                for room in proposedRooms {
                    for obj in room.detectedObjects {
                        drawObject(context: context, object: obj)
                    }
                }
            }
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, 0.5), 5.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        },
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            )
            .onTapGesture { location in
                // Find tapped room
                let floorPlanPoint = convertToFloorPlanPoint(
                    viewPoint: location,
                    viewSize: viewSize,
                    baseScale: baseScale
                )

                for room in proposedRooms {
                    if room.contains(floorPlanPoint) {
                        onRoomTapped?(room)
                        return
                    }
                }
            }
        }
    }

    // MARK: - Drawing

    private func drawGrid(context: GraphicsContext) {
        let gridSpacing: CGFloat = 1.0  // 1 foot grid
        let gridColor = Color.gray.opacity(0.15)

        var path = Path()

        var x = floor(boundingBox.minX)
        while x <= boundingBox.maxX {
            path.move(to: CGPoint(x: x, y: boundingBox.minY))
            path.addLine(to: CGPoint(x: x, y: boundingBox.maxY))
            x += gridSpacing
        }

        var y = floor(boundingBox.minY)
        while y <= boundingBox.maxY {
            path.move(to: CGPoint(x: boundingBox.minX, y: y))
            path.addLine(to: CGPoint(x: boundingBox.maxX, y: y))
            y += gridSpacing
        }

        context.stroke(path, with: .color(gridColor), lineWidth: 0.02)
    }

    private func drawRoomBoundary(context: GraphicsContext, room: ProposedRoom, color: Color, isSelected: Bool) {
        guard room.boundary.count >= 3 else { return }

        var path = Path()
        path.move(to: room.boundary[0])
        for i in 1..<room.boundary.count {
            path.addLine(to: room.boundary[i])
        }
        path.closeSubpath()

        // Fill
        let fillOpacity: Double = isSelected ? 0.3 : 0.15
        context.fill(path, with: .color(color.opacity(fillOpacity)))

        // Stroke
        let strokeWidth: CGFloat = isSelected ? 0.15 : 0.08
        context.stroke(path, with: .color(color), lineWidth: strokeWidth)
    }

    private func drawWallSegment(context: GraphicsContext, segment: WallSegment) {
        var path = Path()
        path.move(to: segment.start)
        path.addLine(to: segment.end)

        context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 0.15, lineCap: .round))
    }

    private func drawDoorway(context: GraphicsContext, doorway: Doorway) {
        let halfWidth = doorway.width / 2

        context.drawLayer { ctx in
            ctx.translateBy(x: doorway.position.x, y: doorway.position.y)
            ctx.rotate(by: Angle(radians: doorway.rotation))

            // Door gap
            var gapPath = Path()
            gapPath.move(to: CGPoint(x: -halfWidth, y: 0))
            gapPath.addLine(to: CGPoint(x: halfWidth, y: 0))
            ctx.stroke(gapPath, with: .color(.brown), style: StrokeStyle(lineWidth: 0.1))

            // Door swing arc
            var arcPath = Path()
            arcPath.addArc(
                center: CGPoint(x: -halfWidth, y: 0),
                radius: doorway.width,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            ctx.stroke(arcPath, with: .color(.brown), style: StrokeStyle(lineWidth: 0.03, dash: [0.1, 0.05]))
        }
    }

    private func drawWindow(context: GraphicsContext, window: FloorPlanWindow) {
        let halfWidth = window.width / 2

        context.drawLayer { ctx in
            ctx.translateBy(x: window.position.x, y: window.position.y)
            ctx.rotate(by: Angle(radians: window.rotation))

            let rect = CGRect(x: -halfWidth, y: -0.15, width: window.width, height: 0.3)
            ctx.stroke(Path(rect), with: .color(.blue), lineWidth: 0.08)

            var panePath = Path()
            panePath.move(to: CGPoint(x: 0, y: -0.15))
            panePath.addLine(to: CGPoint(x: 0, y: 0.15))
            ctx.stroke(panePath, with: .color(.blue), lineWidth: 0.03)
        }
    }

    private func drawObject(context: GraphicsContext, object: DetectedObject) {
        let size: CGFloat = max(object.width, object.depth, 1.0)

        let rect = CGRect(
            x: object.position.x - size / 2,
            y: object.position.y - size / 2,
            width: size,
            height: size
        )

        context.fill(Path(ellipseIn: rect), with: .color(.gray.opacity(0.3)))
        context.stroke(Path(ellipseIn: rect), with: .color(.gray), lineWidth: 0.03)

        // Label
        let label = Text(object.category.prefix(4).uppercased())
            .font(.system(size: 0.4))
            .foregroundColor(.secondary)
        context.draw(label, at: object.position, anchor: .center)
    }

    // MARK: - Helpers

    private func calculateBaseScale(viewSize: CGSize) -> CGFloat {
        let scaleX = (viewSize.width * 0.9) / boundingBox.width
        let scaleY = (viewSize.height * 0.9) / boundingBox.height
        return min(scaleX, scaleY, 30.0)
    }

    private func convertToFloorPlanPoint(viewPoint: CGPoint, viewSize: CGSize, baseScale: CGFloat) -> CGPoint {
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2

        let floorPlanCenter = CGPoint(x: boundingBox.midX, y: boundingBox.midY)

        let x = (viewPoint.x - centerX - offset.width) / (scale * baseScale) + floorPlanCenter.x
        let y = (viewPoint.y - centerY - offset.height) / (scale * baseScale) + floorPlanCenter.y

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Edit Room Sheet

@available(iOS 16.0, *)
struct EditProposedRoomSheet: View {
    @Environment(\.dismiss) private var dismiss

    let room: ProposedRoom
    var onSave: ((ProposedRoom) -> Void)?
    var onDelete: (() -> Void)?

    @State private var roomName: String
    @State private var roomCategory: RoomCategory

    init(room: ProposedRoom, onSave: ((ProposedRoom) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.room = room
        self.onSave = onSave
        self.onDelete = onDelete
        _roomName = State(initialValue: room.suggestedName)
        _roomCategory = State(initialValue: room.suggestedCategory)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Room Name", text: $roomName)

                    Picker("Room Type", selection: $roomCategory) {
                        ForEach(RoomCategory.allCases, id: \.self) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                }

                Section("Measurements") {
                    LabeledContent("Area", value: "\(Int(room.squareFeet)) SF")
                    LabeledContent("Perimeter", value: String(format: "%.1f LF", room.perimeterLf))
                    LabeledContent("Wall Height", value: String(format: "%.1f ft", room.avgHeightFt))
                }

                Section("Detection") {
                    LabeledContent("Confidence", value: String(format: "%.0f%%", room.confidence * 100))
                    LabeledContent("Doors", value: "\(room.doorwayCount)")
                    LabeledContent("Windows", value: "\(room.windowCount)")
                    LabeledContent("Objects", value: "\(room.detectedObjects.count)")
                }

                if !room.detectedObjects.isEmpty {
                    Section("Detected Objects") {
                        ForEach(room.detectedObjects) { obj in
                            Text(obj.category.capitalized)
                        }
                    }
                }

                Section {
                    Button(role: .destructive, action: { onDelete?() }) {
                        Label("Remove Room", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = room
                        updated.suggestedName = roomName
                        updated.suggestedCategory = roomCategory
                        onSave?(updated)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Merge Rooms Sheet

@available(iOS 16.0, *)
struct MergeRoomsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sourceRoom: ProposedRoom
    let availableRooms: [ProposedRoom]
    var onMerge: ((ProposedRoom) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: sourceRoom.suggestedCategory.icon)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text(sourceRoom.suggestedName)
                                .font(.headline)
                            Text("\(Int(sourceRoom.squareFeet)) SF")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Merge From")
                }

                Section {
                    ForEach(availableRooms) { room in
                        Button(action: { onMerge?(room) }) {
                            HStack {
                                Image(systemName: room.suggestedCategory.icon)
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(room.suggestedName)
                                        .font(.headline)
                                    Text("\(Int(room.squareFeet)) SF")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.triangle.merge")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                } header: {
                    Text("Merge Into")
                } footer: {
                    Text("Select a room to merge with \(sourceRoom.suggestedName). The merged room will combine both areas.")
                }
            }
            .navigationTitle("Merge Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    // Note: This preview won't work properly without a real CapturedRoom
    // In actual use, this view is shown after LiDAR capture
    Text("Preview not available - requires CapturedRoom")
}
