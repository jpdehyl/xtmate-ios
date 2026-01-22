//
//  FloorPlanView.swift
//  XtMate
//
//  2D floor plan view with walls, doors, windows, gesture support, and annotations.
//  Provides an alternative to the 3D isometric view for precise damage annotation.
//

import SwiftUI

/// View that renders a 2D floor plan from FloorPlanData with annotation support
struct FloorPlanAnnotationView: View {
    let floorPlanData: FloorPlanData
    var annotations: [FloorPlanAnnotationDTO] = []
    var isAnnotationModeEnabled: Bool = false
    var onTapToAnnotate: ((AnnotationPosition) -> Void)?
    var onAnnotationTapped: ((FloorPlanAnnotationDTO) -> Void)?

    // Gesture state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var tapLocation: CGPoint?

    // Display options
    @State private var showDimensions: Bool = true
    @State private var showAnnotations: Bool = true

    // Colors
    private let wallColor = Color.primary
    private let doorColor = Color.brown
    private let windowColor = Color.blue
    private let objectColor = Color.gray.opacity(0.5)
    private let dimensionColor = Color.secondary
    private let gridColor = Color.gray.opacity(0.2)

    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let floorPlanSize = floorPlanData.boundingBox.size
            let baseScale = calculateBaseScale(viewSize: viewSize, floorPlanSize: floorPlanSize)

            ZStack {
                // Background
                Color(.systemBackground)

                // Floor plan canvas
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

                    // Draw objects
                    for object in floorPlanData.objects {
                        drawObject(context: context, object: object)
                    }

                    // Draw dimensions if enabled
                    if showDimensions {
                        drawDimensions(context: context)
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
                .onTapGesture(count: 2) {
                    // Double tap to reset view
                    withAnimation(.spring()) {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
                .onTapGesture(count: 1) { location in
                    if isAnnotationModeEnabled {
                        // Convert tap location to floor plan coordinates
                        let position = convertToFloorPlanPosition(
                            tapPoint: location,
                            viewSize: viewSize,
                            baseScale: baseScale
                        )
                        onTapToAnnotate?(position)
                    }
                }

                // Annotation markers overlay
                if showAnnotations {
                    ForEach(annotations) { annotation in
                        FloorPlanAnnotationMarkerView(
                            annotation: annotation,
                            position: convertToViewPosition(
                                floorPlanPosition: annotation.position,
                                viewSize: viewSize,
                                baseScale: baseScale
                            ),
                            onTap: {
                                onAnnotationTapped?(annotation)
                            }
                        )
                    }
                }

                // Overlay controls
                VStack {
                    HStack {
                        Spacer()

                        // Annotation toggle
                        if !annotations.isEmpty {
                            Button(action: { showAnnotations.toggle() }) {
                                Image(systemName: showAnnotations ? "mappin.circle.fill" : "mappin.circle")
                                    .padding(10)
                                    .background(Color(.systemBackground).opacity(0.9))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                        }

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

                    // Scale indicator
                    HStack {
                        Text(String(format: "%.0f%%", scale * 100))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemBackground).opacity(0.9))
                            .cornerRadius(4)

                        Spacer()

                        // Legend
                        HStack(spacing: 12) {
                            FloorPlanLegendItem(color: wallColor, label: "Wall")
                            FloorPlanLegendItem(color: doorColor, label: "Door")
                            FloorPlanLegendItem(color: windowColor, label: "Window")
                            if !annotations.isEmpty {
                                FloorPlanLegendItem(color: .red, label: "\(annotations.count) Annotations")
                            }
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemBackground).opacity(0.9))
                        .cornerRadius(4)
                    }
                    .padding()
                }

                // Annotation mode indicator
                if isAnnotationModeEnabled {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Label("Tap to add annotation", systemImage: "hand.tap")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.9))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                            Spacer()
                        }
                        .padding(.bottom, 80)
                    }
                }
            }
        }
    }

    // MARK: - Coordinate Conversion

    private func convertToFloorPlanPosition(
        tapPoint: CGPoint,
        viewSize: CGSize,
        baseScale: CGFloat
    ) -> AnnotationPosition {
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2

        // Reverse the transforms
        let floorPlanCenter = CGPoint(
            x: floorPlanData.boundingBox.midX,
            y: floorPlanData.boundingBox.midY
        )

        // Calculate position in floor plan coordinates
        let adjustedX = (tapPoint.x - centerX - offset.width) / (scale * baseScale) + floorPlanCenter.x
        let adjustedY = (tapPoint.y - centerY - offset.height) / (scale * baseScale) + floorPlanCenter.y

        // Normalize to bounding box (0-1 range)
        let normalizedX = (adjustedX - floorPlanData.boundingBox.minX) / floorPlanData.boundingBox.width
        let normalizedY = (adjustedY - floorPlanData.boundingBox.minY) / floorPlanData.boundingBox.height

        return AnnotationPosition(
            x: max(0, min(1, normalizedX)),
            y: max(0, min(1, normalizedY))
        )
    }

    private func convertToViewPosition(
        floorPlanPosition: AnnotationPosition,
        viewSize: CGSize,
        baseScale: CGFloat
    ) -> CGPoint {
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2

        let floorPlanCenter = CGPoint(
            x: floorPlanData.boundingBox.midX,
            y: floorPlanData.boundingBox.midY
        )

        // Convert from normalized to floor plan coordinates
        let floorPlanX = floorPlanPosition.x * floorPlanData.boundingBox.width + floorPlanData.boundingBox.minX
        let floorPlanY = floorPlanPosition.y * floorPlanData.boundingBox.height + floorPlanData.boundingBox.minY

        // Apply transforms to get view coordinates
        let viewX = centerX + (floorPlanX - floorPlanCenter.x) * scale * baseScale + offset.width
        let viewY = centerY + (floorPlanY - floorPlanCenter.y) * scale * baseScale + offset.height

        return CGPoint(x: viewX, y: viewY)
    }

    // MARK: - Scale Calculation

    private func calculateBaseScale(viewSize: CGSize, floorPlanSize: CGSize) -> CGFloat {
        guard floorPlanSize.width > 0, floorPlanSize.height > 0 else {
            return 20.0  // Default pixels per foot
        }

        let scaleX = (viewSize.width * 0.85) / floorPlanSize.width
        let scaleY = (viewSize.height * 0.85) / floorPlanSize.height

        return min(scaleX, scaleY)
    }

    // MARK: - Drawing Functions

    private func drawGrid(context: GraphicsContext, boundingBox: CGRect) {
        let gridSpacing: CGFloat = 1.0  // 1 foot grid

        var path = Path()

        // Vertical lines
        var x = floor(boundingBox.minX)
        while x <= boundingBox.maxX {
            path.move(to: CGPoint(x: x, y: boundingBox.minY))
            path.addLine(to: CGPoint(x: x, y: boundingBox.maxY))
            x += gridSpacing
        }

        // Horizontal lines
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
        // Door is represented as a gap with an arc swing
        let halfWidth = door.width / 2

        context.drawLayer { ctx in
            ctx.translateBy(x: door.position.x, y: door.position.y)
            ctx.rotate(by: Angle(radians: door.rotation))

            // Door opening (gap in wall)
            var gapPath = Path()
            gapPath.move(to: CGPoint(x: -halfWidth, y: 0))
            gapPath.addLine(to: CGPoint(x: halfWidth, y: 0))
            ctx.stroke(gapPath, with: .color(doorColor), style: StrokeStyle(lineWidth: 0.15))

            // Door swing arc
            var arcPath = Path()
            arcPath.addArc(
                center: CGPoint(x: -halfWidth, y: 0),
                radius: door.width,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            ctx.stroke(arcPath, with: .color(doorColor), style: StrokeStyle(lineWidth: 0.05, dash: [0.1, 0.1]))

            // Door panel
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

            // Window frame
            let rect = CGRect(x: -halfWidth, y: -thickness/2, width: window.width, height: thickness)
            ctx.stroke(Path(rect), with: .color(windowColor), lineWidth: 0.1)

            // Window panes (center lines)
            var panePath = Path()
            panePath.move(to: CGPoint(x: 0, y: -thickness/2))
            panePath.addLine(to: CGPoint(x: 0, y: thickness/2))
            ctx.stroke(panePath, with: .color(windowColor), lineWidth: 0.05)
        }
    }

    private func drawObject(context: GraphicsContext, object: FloorPlanObject) {
        context.drawLayer { ctx in
            ctx.translateBy(x: object.position.x, y: object.position.y)
            ctx.rotate(by: Angle(radians: object.rotation))

            let rect = CGRect(
                x: -object.width/2,
                y: -object.depth/2,
                width: object.width,
                height: object.depth
            )

            ctx.fill(Path(rect), with: .color(objectColor))
            ctx.stroke(Path(rect), with: .color(.gray), lineWidth: 0.05)
        }
    }

    private func drawDimensions(context: GraphicsContext) {
        // Draw dimension labels for each wall
        for wall in floorPlanData.walls {
            let midPoint = CGPoint(
                x: (wall.startPoint.x + wall.endPoint.x) / 2,
                y: (wall.startPoint.y + wall.endPoint.y) / 2
            )

            // Calculate perpendicular offset for label
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

            // Draw dimension text
            let text = Text(String(format: "%.1f'", wall.length))
                .font(.system(size: 0.4))
                .foregroundColor(dimensionColor)

            context.draw(text, at: labelPoint, anchor: .center)
        }
    }
}

// MARK: - Legend Item

struct FloorPlanLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 12, height: 3)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Annotation Marker View

struct FloorPlanAnnotationMarkerView: View {
    let annotation: FloorPlanAnnotationDTO
    let position: CGPoint
    var onTap: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack {
                // Outer ring with severity color
                Circle()
                    .fill(annotation.severity.color.opacity(0.3))
                    .frame(width: 36, height: 36)

                // Inner circle with damage type color
                Circle()
                    .fill(annotation.damageType.color)
                    .frame(width: 28, height: 28)

                // Damage type icon
                Image(systemName: annotation.damageType.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                // Height marker badge (for wall damage)
                if annotation.affectedSurface == .wall, let height = annotation.heightMarker, height > 0 {
                    Text(String(format: "%.0f'", height))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .offset(y: 22)
                }
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .position(position)
        .animation(.spring(response: 0.3), value: isPressed)
    }
}

// MARK: - Preview

#Preview {
    // Create sample floor plan data for preview
    let sampleWalls = [
        FloorPlanWall(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 15, y: 0), length: 15, height: 9),
        FloorPlanWall(startPoint: CGPoint(x: 15, y: 0), endPoint: CGPoint(x: 15, y: 12), length: 12, height: 9),
        FloorPlanWall(startPoint: CGPoint(x: 15, y: 12), endPoint: CGPoint(x: 0, y: 12), length: 15, height: 9),
        FloorPlanWall(startPoint: CGPoint(x: 0, y: 12), endPoint: CGPoint(x: 0, y: 0), length: 12, height: 9)
    ]

    let sampleDoors = [
        FloorPlanDoor(position: CGPoint(x: 7, y: 0), width: 3, rotation: 0)
    ]

    let sampleWindows = [
        FloorPlanWindow(position: CGPoint(x: 15, y: 6), width: 4, rotation: .pi/2),
        FloorPlanWindow(position: CGPoint(x: 5, y: 12), width: 5, rotation: 0)
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

    return FloorPlanAnnotationView(floorPlanData: sampleData)
}
