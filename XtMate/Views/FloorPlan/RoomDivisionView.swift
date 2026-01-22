//
//  RoomDivisionView.swift
//  XtMate
//
//  Interactive view for drawing division lines on a floor plan to split
//  a captured room into multiple sub-rooms (e.g., splitting an open floor plan
//  into Kitchen, Living Room, Dining Room).
//
//  P3-014: Create RoomDivisionView with floor plan
//

import SwiftUI

/// Main view for room division with floor plan and line drawing
struct RoomDivisionView: View {
    @Environment(\.dismiss) private var dismiss

    let room: Room
    let floorPlanData: FloorPlanData
    var onSave: (([DivisionLine]) -> Void)?
    var onSaveSubRooms: (([SubRoom]) -> Void)?

    // Division lines state
    @State private var divisionLines: [DivisionLine] = []
    @State private var currentLineStart: CGPoint?
    @State private var currentLineEnd: CGPoint?
    @State private var isDragging = false

    // View state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showDimensions = true
    @State private var isDrawingMode = true
    @State private var showingNamingView = false

    // Snap angles (in degrees)
    private let snapAngles: [Double] = [0, 45, 90, 135, 180, 225, 270, 315]
    private let snapThreshold: Double = 15 // degrees tolerance for snapping

    // Colors
    private let wallColor = Color.primary
    private let doorColor = Color.brown
    private let windowColor = Color.blue
    private let divisionLineColor = Color.orange
    private let currentLineColor = Color.red
    private let gridColor = Color.gray.opacity(0.2)
    private let dimensionColor = Color.secondary

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let viewSize = geometry.size
                let floorPlanSize = floorPlanData.boundingBox.size
                let baseScale = calculateBaseScale(viewSize: viewSize, floorPlanSize: floorPlanSize)

                ZStack {
                    // Background
                    Color(.systemBackground)

                    // Floor plan canvas with division lines
                    Canvas { context, size in
                        let centerOffset = CGSize(
                            width: size.width / 2,
                            height: size.height / 2
                        )

                        // Apply transforms
                        context.translateBy(x: centerOffset.width + offset.width, y: centerOffset.height + offset.height)
                        context.scaleBy(x: scale * baseScale, y: scale * baseScale)

                        // Center the floor plan
                        let floorPlanCenter = CGPoint(
                            x: floorPlanData.boundingBox.midX,
                            y: floorPlanData.boundingBox.midY
                        )
                        context.translateBy(x: -floorPlanCenter.x, y: -floorPlanCenter.y)

                        // Draw grid
                        drawGrid(context: context, boundingBox: floorPlanData.boundingBox)

                        // Draw walls
                        for wall in floorPlanData.walls {
                            drawWall(context: context, wall: wall)
                        }

                        // Draw doors
                        for door in floorPlanData.doors {
                            drawDoor(context: context, door: door)
                        }

                        // Draw windows
                        for window in floorPlanData.windows {
                            drawWindow(context: context, window: window)
                        }

                        // Draw existing division lines
                        for line in divisionLines {
                            drawDivisionLine(
                                context: context,
                                line: line,
                                boundingBox: floorPlanData.boundingBox,
                                color: divisionLineColor
                            )
                        }

                        // Draw current line being drawn
                        if let start = currentLineStart, let end = currentLineEnd {
                            let line = DivisionLine(startPoint: start, endPoint: end)
                            drawDivisionLine(
                                context: context,
                                line: line,
                                boundingBox: floorPlanData.boundingBox,
                                color: currentLineColor
                            )
                        }

                        // Draw dimensions if enabled
                        if showDimensions {
                            drawDimensions(context: context)
                        }
                    }
                    .gesture(divisionGesture(viewSize: viewSize, baseScale: baseScale))
                    .gesture(
                        // Only allow pan/zoom when not in drawing mode
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    guard !isDrawingMode else { return }
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 0.5), 5.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                },
                            DragGesture()
                                .onChanged { value in
                                    guard !isDrawingMode else { return }
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
                    .onTapGesture(count: 2) {
                        // Double tap to reset view
                        withAnimation(.spring()) {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    }

                    // Overlay controls
                    VStack {
                        // Top controls
                        HStack {
                            // Mode toggle
                            Picker("Mode", selection: $isDrawingMode) {
                                Label("Draw", systemImage: "pencil.line")
                                    .tag(true)
                                Label("Pan/Zoom", systemImage: "hand.draw")
                                    .tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)

                            Spacer()

                            // Dimension toggle
                            Button(action: { showDimensions.toggle() }) {
                                Image(systemName: showDimensions ? "ruler.fill" : "ruler")
                                    .padding(10)
                                    .background(Color(.systemBackground).opacity(0.9))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }

                            // Reset view button
                            Button(action: {
                                withAnimation(.spring()) {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .padding(10)
                                    .background(Color(.systemBackground).opacity(0.9))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                        }
                        .padding()

                        Spacer()

                        // Bottom info and controls
                        VStack(spacing: 12) {
                            // Room info
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(room.name)
                                        .font(.headline)
                                    Text("\(Int(room.squareFeet)) SF")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                // Lines count
                                if !divisionLines.isEmpty {
                                    Label("\(divisionLines.count) division line\(divisionLines.count == 1 ? "" : "s")", systemImage: "line.diagonal")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)

                            // Undo button
                            if !divisionLines.isEmpty {
                                Button(action: {
                                    withAnimation {
                                        _ = divisionLines.popLast()
                                    }
                                }) {
                                    Label("Undo Last Line", systemImage: "arrow.uturn.backward")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)
                            }

                            // Instructions
                            if isDrawingMode {
                                Label(
                                    isDragging ? "Release to place line (snaps to 0\u{00B0}, 45\u{00B0}, 90\u{00B0})" : "Drag to draw division line",
                                    systemImage: "hand.draw"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemBackground).opacity(0.9))
                                .cornerRadius(20)
                            }

                            // Scale indicator
                            Text(String(format: "%.0f%%", scale * 100))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground).opacity(0.95))
                    }
                }
            }
            .navigationTitle("Divide Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") {
                        showingNamingView = true
                    }
                    .fontWeight(.semibold)
                    .disabled(divisionLines.isEmpty)
                }
            }
            .sheet(isPresented: $showingNamingView) {
                SubRoomNamingView(
                    parentRoom: room,
                    divisionLines: divisionLines,
                    floorPlanData: floorPlanData
                ) { subRooms in
                    onSave?(divisionLines)
                    onSaveSubRooms?(subRooms)
                    dismiss()
                }
            }
        }
        .onAppear {
            // Load existing division lines if any
            if let existingLines = room.divisionLines {
                divisionLines = existingLines
            }
        }
    }

    // MARK: - Gesture Handling

    private func divisionGesture(viewSize: CGSize, baseScale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard isDrawingMode else { return }
                isDragging = true

                // Convert start position to normalized coordinates
                if currentLineStart == nil {
                    currentLineStart = convertToNormalizedPosition(
                        viewPoint: value.startLocation,
                        viewSize: viewSize,
                        baseScale: baseScale
                    )
                }

                // Convert current position and apply snapping
                let rawEnd = convertToNormalizedPosition(
                    viewPoint: value.location,
                    viewSize: viewSize,
                    baseScale: baseScale
                )

                if let start = currentLineStart {
                    currentLineEnd = snapLineEnd(start: start, end: rawEnd)
                }
            }
            .onEnded { _ in
                guard isDrawingMode else { return }
                isDragging = false

                // Add the line if valid
                if let start = currentLineStart, let end = currentLineEnd {
                    let newLine = DivisionLine(startPoint: start, endPoint: end)
                    withAnimation(.spring(response: 0.3)) {
                        divisionLines.append(newLine)
                    }
                }

                // Reset drawing state
                currentLineStart = nil
                currentLineEnd = nil
            }
    }

    // MARK: - Coordinate Conversion

    private func convertToNormalizedPosition(
        viewPoint: CGPoint,
        viewSize: CGSize,
        baseScale: CGFloat
    ) -> CGPoint {
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2

        let floorPlanCenter = CGPoint(
            x: floorPlanData.boundingBox.midX,
            y: floorPlanData.boundingBox.midY
        )

        // Reverse transforms to get floor plan coordinates
        let floorPlanX = (viewPoint.x - centerX - offset.width) / (scale * baseScale) + floorPlanCenter.x
        let floorPlanY = (viewPoint.y - centerY - offset.height) / (scale * baseScale) + floorPlanCenter.y

        // Normalize to 0-1 range within bounding box
        let normalizedX = (floorPlanX - floorPlanData.boundingBox.minX) / floorPlanData.boundingBox.width
        let normalizedY = (floorPlanY - floorPlanData.boundingBox.minY) / floorPlanData.boundingBox.height

        return CGPoint(
            x: max(0, min(1, normalizedX)),
            y: max(0, min(1, normalizedY))
        )
    }

    // MARK: - Angle Snapping

    private func snapLineEnd(start: CGPoint, end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)

        guard length > 0.01 else { return end }

        // Calculate current angle in degrees
        let currentAngle = atan2(dy, dx) * 180 / .pi

        // Find nearest snap angle
        var nearestAngle = currentAngle
        var minDiff = Double.infinity

        for snapAngle in snapAngles {
            let diff = abs(angleDifference(currentAngle, snapAngle))
            if diff < minDiff {
                minDiff = diff
                nearestAngle = snapAngle
            }
        }

        // Only snap if within threshold
        if minDiff <= snapThreshold {
            let snappedRadians = nearestAngle * .pi / 180
            return CGPoint(
                x: start.x + length * cos(snappedRadians),
                y: start.y + length * sin(snappedRadians)
            )
        }

        return end
    }

    private func angleDifference(_ a: Double, _ b: Double) -> Double {
        var diff = a - b
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        return diff
    }

    // MARK: - Scale Calculation

    private func calculateBaseScale(viewSize: CGSize, floorPlanSize: CGSize) -> CGFloat {
        guard floorPlanSize.width > 0, floorPlanSize.height > 0 else {
            return 20.0
        }

        let scaleX = (viewSize.width * 0.85) / floorPlanSize.width
        let scaleY = (viewSize.height * 0.7) / floorPlanSize.height // Leave room for controls

        return min(scaleX, scaleY)
    }

    // MARK: - Drawing Functions

    private func drawGrid(context: GraphicsContext, boundingBox: CGRect) {
        let gridSpacing: CGFloat = 1.0

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

    private func drawWall(context: GraphicsContext, wall: FloorPlanWall) {
        var path = Path()
        path.move(to: wall.startPoint)
        path.addLine(to: wall.endPoint)

        context.stroke(path, with: .color(wallColor), style: StrokeStyle(lineWidth: 0.3, lineCap: .round))
    }

    private func drawDoor(context: GraphicsContext, door: FloorPlanDoor) {
        let halfWidth = door.width / 2

        context.drawLayer { ctx in
            ctx.translateBy(x: door.position.x, y: door.position.y)
            ctx.rotate(by: Angle(radians: door.rotation))

            var gapPath = Path()
            gapPath.move(to: CGPoint(x: -halfWidth, y: 0))
            gapPath.addLine(to: CGPoint(x: halfWidth, y: 0))
            ctx.stroke(gapPath, with: .color(doorColor), style: StrokeStyle(lineWidth: 0.15))

            var arcPath = Path()
            arcPath.addArc(
                center: CGPoint(x: -halfWidth, y: 0),
                radius: door.width,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            ctx.stroke(arcPath, with: .color(doorColor), style: StrokeStyle(lineWidth: 0.05, dash: [0.1, 0.1]))

            var panelPath = Path()
            panelPath.move(to: CGPoint(x: -halfWidth, y: 0))
            panelPath.addLine(to: CGPoint(x: -halfWidth, y: door.width))
            ctx.stroke(panelPath, with: .color(doorColor), style: StrokeStyle(lineWidth: 0.1))
        }
    }

    private func drawWindow(context: GraphicsContext, window: FloorPlanWindow) {
        let halfWidth = window.width / 2
        let thickness: CGFloat = 0.25

        context.drawLayer { ctx in
            ctx.translateBy(x: window.position.x, y: window.position.y)
            ctx.rotate(by: Angle(radians: window.rotation))

            let rect = CGRect(x: -halfWidth, y: -thickness/2, width: window.width, height: thickness)
            ctx.stroke(Path(rect), with: .color(windowColor), lineWidth: 0.1)

            var panePath = Path()
            panePath.move(to: CGPoint(x: 0, y: -thickness/2))
            panePath.addLine(to: CGPoint(x: 0, y: thickness/2))
            ctx.stroke(panePath, with: .color(windowColor), lineWidth: 0.05)
        }
    }

    private func drawDivisionLine(
        context: GraphicsContext,
        line: DivisionLine,
        boundingBox: CGRect,
        color: Color
    ) {
        // Convert normalized coordinates back to floor plan coordinates
        let startX = boundingBox.minX + line.startPoint.x * boundingBox.width
        let startY = boundingBox.minY + line.startPoint.y * boundingBox.height
        let endX = boundingBox.minX + line.endPoint.x * boundingBox.width
        let endY = boundingBox.minY + line.endPoint.y * boundingBox.height

        var path = Path()
        path.move(to: CGPoint(x: startX, y: startY))
        path.addLine(to: CGPoint(x: endX, y: endY))

        // Draw with dashed style
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 0.15, lineCap: .round, dash: [0.3, 0.15])
        )

        // Draw endpoints
        let endpointRadius: CGFloat = 0.2

        let startCircle = Path(ellipseIn: CGRect(
            x: startX - endpointRadius,
            y: startY - endpointRadius,
            width: endpointRadius * 2,
            height: endpointRadius * 2
        ))
        context.fill(startCircle, with: .color(color))

        let endCircle = Path(ellipseIn: CGRect(
            x: endX - endpointRadius,
            y: endY - endpointRadius,
            width: endpointRadius * 2,
            height: endpointRadius * 2
        ))
        context.fill(endCircle, with: .color(color))
    }

    private func drawDimensions(context: GraphicsContext) {
        for wall in floorPlanData.walls {
            let midPoint = CGPoint(
                x: (wall.startPoint.x + wall.endPoint.x) / 2,
                y: (wall.startPoint.y + wall.endPoint.y) / 2
            )

            let dx = wall.endPoint.x - wall.startPoint.x
            let dy = wall.endPoint.y - wall.startPoint.y
            let length = sqrt(dx*dx + dy*dy)

            guard length > 0 else { continue }

            let perpX = -dy / length * 0.5
            let perpY = dx / length * 0.5

            let labelPoint = CGPoint(
                x: midPoint.x + perpX,
                y: midPoint.y + perpY
            )

            let text = Text(String(format: "%.1f'", wall.length))
                .font(.system(size: 0.4))
                .foregroundColor(dimensionColor)

            context.draw(text, at: labelPoint, anchor: .center)
        }
    }
}

// MARK: - Preview

#Preview {
    // Create sample room using MockData extension initializer
    let sampleRoom = Room(
        name: "Living Area",
        category: .livingRoom,
        floor: .first,
        lengthIn: 180,
        widthIn: 144,
        heightIn: 96
    )

    // Create sample floor plan data
    let sampleWalls = [
        FloorPlanWall(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 15, y: 0), length: 15, height: 8),
        FloorPlanWall(startPoint: CGPoint(x: 15, y: 0), endPoint: CGPoint(x: 15, y: 12), length: 12, height: 8),
        FloorPlanWall(startPoint: CGPoint(x: 15, y: 12), endPoint: CGPoint(x: 0, y: 12), length: 15, height: 8),
        FloorPlanWall(startPoint: CGPoint(x: 0, y: 12), endPoint: CGPoint(x: 0, y: 0), length: 12, height: 8)
    ]

    let sampleDoors = [
        FloorPlanDoor(position: CGPoint(x: 7, y: 0), width: 3, rotation: 0)
    ]

    let sampleWindows = [
        FloorPlanWindow(position: CGPoint(x: 15, y: 6), width: 4, rotation: .pi/2)
    ]

    let sampleData = FloorPlanData(
        walls: sampleWalls,
        doors: sampleDoors,
        windows: sampleWindows,
        objects: [],
        boundingBox: CGRect(x: -2, y: -2, width: 19, height: 16),
        squareFootage: 180,
        linearFeet: 54
    )

    RoomDivisionView(
        room: sampleRoom,
        floorPlanData: sampleData,
        onSave: { lines in
            print("Saved \(lines.count) division lines")
        },
        onSaveSubRooms: { subRooms in
            print("Saved \(subRooms.count) sub-rooms")
        }
    )
}
