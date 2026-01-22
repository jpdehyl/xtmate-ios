//
//  SubRoomNamingView.swift
//  XtMate
//
//  View for naming and categorizing sub-rooms after drawing division lines.
//  Shows detected sub-rooms with calculated square footage and allows
//  user to name each area and assign room category.
//
//  P3-015: Sub-room naming and categorization
//

import SwiftUI

/// View for naming and categorizing detected sub-rooms after division
struct SubRoomNamingView: View {
    @Environment(\.dismiss) private var dismiss

    let parentRoom: Room
    let divisionLines: [DivisionLine]
    let floorPlanData: FloorPlanData
    var onSave: (([SubRoom]) -> Void)?

    @State private var subRooms: [SubRoom] = []
    @State private var editingSubRoomId: UUID?
    @State private var showingSuggestions = false

    // Fixture detection for auto-suggest (from FloorPlanData objects)
    private var detectedFixtures: [String: [FloorPlanObject]] {
        var fixtures: [String: [FloorPlanObject]] = [:]
        for object in floorPlanData.objects {
            let category = object.category.lowercased()
            if fixtures[category] == nil {
                fixtures[category] = []
            }
            fixtures[category]?.append(object)
        }
        return fixtures
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mini floor plan preview showing division
                MiniFloorPlanPreview(
                    floorPlanData: floorPlanData,
                    divisionLines: divisionLines,
                    subRooms: subRooms
                )
                .frame(height: 200)
                .background(Color(.systemGray6))

                Divider()

                // Sub-rooms list
                if subRooms.isEmpty {
                    ContentUnavailableView(
                        "No Sub-Rooms Detected",
                        systemImage: "square.split.2x1",
                        description: Text("Draw division lines to create sub-rooms")
                    )
                } else {
                    List {
                        Section {
                            ForEach($subRooms) { $subRoom in
                                SubRoomRow(
                                    subRoom: $subRoom,
                                    isEditing: editingSubRoomId == subRoom.id,
                                    suggestedCategory: suggestCategory(for: subRoom),
                                    onTap: {
                                        withAnimation {
                                            editingSubRoomId = editingSubRoomId == subRoom.id ? nil : subRoom.id
                                        }
                                    }
                                )
                            }
                        } header: {
                            HStack {
                                Text("Sub-Rooms (\(subRooms.count))")
                                Spacer()
                                Text("Total: \(Int(totalSquareFeet)) SF")
                                    .foregroundColor(.secondary)
                            }
                        } footer: {
                            if let variance = squareFootageVariance, abs(variance) > 5 {
                                Label(
                                    "Area variance: \(Int(variance)) SF from original room",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption)
                                .foregroundColor(.orange)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Name Sub-Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave?(subRooms)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(subRooms.isEmpty || hasUnnamedRooms)
                }
            }
        }
        .onAppear {
            generateSubRooms()
        }
    }

    // MARK: - Computed Properties

    private var totalSquareFeet: Double {
        subRooms.reduce(0) { $0 + $1.squareFeet }
    }

    private var squareFootageVariance: Double? {
        guard !subRooms.isEmpty else { return nil }
        return totalSquareFeet - parentRoom.squareFeet
    }

    private var hasUnnamedRooms: Bool {
        subRooms.contains { $0.name.isEmpty || $0.name.hasPrefix("Area ") }
    }

    // MARK: - Sub-Room Generation

    private func generateSubRooms() {
        guard !divisionLines.isEmpty else {
            subRooms = []
            return
        }

        var generatedSubRooms: [SubRoom] = []

        // For simplicity, handle single line division (creates 2 sub-rooms)
        // Multiple lines would require more complex polygon math
        if divisionLines.count == 1 {
            let line = divisionLines[0]

            // Determine if line is more horizontal or vertical
            let dx = abs(line.endPoint.x - line.startPoint.x)
            let dy = abs(line.endPoint.y - line.startPoint.y)
            let isHorizontal = dx > dy

            if isHorizontal {
                // Line divides room into top/bottom regions
                let splitY = (line.startPoint.y + line.endPoint.y) / 2

                let topHeight = parentRoom.lengthIn * splitY
                let bottomHeight = parentRoom.lengthIn * (1 - splitY)

                generatedSubRooms.append(SubRoom(
                    name: "Area A",
                    category: suggestCategoryForRegion(yRange: 0..<splitY),
                    lengthIn: max(topHeight, 1),
                    widthIn: parentRoom.widthIn,
                    heightIn: parentRoom.heightIn
                ))

                generatedSubRooms.append(SubRoom(
                    name: "Area B",
                    category: suggestCategoryForRegion(yRange: splitY..<1.0),
                    lengthIn: max(bottomHeight, 1),
                    widthIn: parentRoom.widthIn,
                    heightIn: parentRoom.heightIn
                ))
            } else {
                // Line divides room into left/right regions
                let splitX = (line.startPoint.x + line.endPoint.x) / 2

                let leftWidth = parentRoom.widthIn * splitX
                let rightWidth = parentRoom.widthIn * (1 - splitX)

                generatedSubRooms.append(SubRoom(
                    name: "Area A",
                    category: suggestCategoryForRegion(xRange: 0..<splitX),
                    lengthIn: parentRoom.lengthIn,
                    widthIn: max(leftWidth, 1),
                    heightIn: parentRoom.heightIn
                ))

                generatedSubRooms.append(SubRoom(
                    name: "Area B",
                    category: suggestCategoryForRegion(xRange: splitX..<1.0),
                    lengthIn: parentRoom.lengthIn,
                    widthIn: max(rightWidth, 1),
                    heightIn: parentRoom.heightIn
                ))
            }
        } else {
            // Multiple lines: create one sub-room per region
            // For now, create n+1 sub-rooms for n lines (simplified)
            for i in 0...divisionLines.count {
                let areaFraction = 1.0 / Double(divisionLines.count + 1)
                generatedSubRooms.append(SubRoom(
                    name: "Area \(Character(UnicodeScalar(65 + i)!))", // A, B, C, etc.
                    category: .other,
                    lengthIn: parentRoom.lengthIn * areaFraction,
                    widthIn: parentRoom.widthIn,
                    heightIn: parentRoom.heightIn
                ))
            }
        }

        subRooms = generatedSubRooms
    }

    // MARK: - Category Suggestion

    private func suggestCategory(for subRoom: SubRoom) -> RoomCategory? {
        // Check if there are detected fixtures that suggest a room type
        // This is based on objects detected during LiDAR scan
        for (category, objects) in detectedFixtures {
            // Check if any fixture is in this sub-room's area
            // (simplified - doesn't account for actual region bounds)
            if !objects.isEmpty {
                switch category {
                case "toilet", "bathtub", "shower":
                    return .bathroom
                case "refrigerator", "stove", "oven", "sink", "dishwasher":
                    return .kitchen
                case "bed":
                    return .bedroom
                case "sofa", "couch", "tv":
                    return .livingRoom
                case "table" where objects.count >= 4, "chair" where objects.count >= 4:
                    return .diningRoom
                case "washer", "dryer":
                    return .laundry
                case "desk", "computer":
                    return .office
                default:
                    break
                }
            }
        }
        return nil
    }

    private func suggestCategoryForRegion(xRange: Range<Double>? = nil, yRange: Range<Double>? = nil) -> RoomCategory {
        // Check objects in the floor plan that fall within this region
        for object in floorPlanData.objects {
            // Convert object position to normalized coordinates
            let normalizedX = (object.position.x - floorPlanData.boundingBox.minX) / floorPlanData.boundingBox.width
            let normalizedY = (object.position.y - floorPlanData.boundingBox.minY) / floorPlanData.boundingBox.height

            let inXRange = xRange?.contains(normalizedX) ?? true
            let inYRange = yRange?.contains(normalizedY) ?? true

            if inXRange && inYRange {
                let category = object.category.lowercased()
                switch category {
                case "toilet", "bathtub", "shower":
                    return .bathroom
                case "refrigerator", "stove", "oven", "sink", "dishwasher":
                    return .kitchen
                case "bed":
                    return .bedroom
                case "sofa", "couch", "tv":
                    return .livingRoom
                case "washer", "dryer":
                    return .laundry
                case "desk", "computer":
                    return .office
                default:
                    break
                }
            }
        }
        return .other
    }
}

// MARK: - Sub-Room Row

struct SubRoomRow: View {
    @Binding var subRoom: SubRoom
    let isEditing: Bool
    let suggestedCategory: RoomCategory?
    var onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack {
                // Category icon
                Image(systemName: subRoom.category.icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    if isEditing {
                        TextField("Room Name", text: $subRoom.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.headline)
                    } else {
                        Text(subRoom.name.isEmpty ? "Tap to name" : subRoom.name)
                            .font(.headline)
                            .foregroundColor(subRoom.name.isEmpty ? .secondary : .primary)
                    }

                    Text("\(Int(subRoom.squareFeet)) SF")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Expand/collapse indicator
                Image(systemName: isEditing ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }

            // Expanded editing section
            if isEditing {
                VStack(alignment: .leading, spacing: 12) {
                    // Category picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Room Type")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Category", selection: $subRoom.category) {
                            ForEach(RoomCategory.allCases, id: \.self) { category in
                                Label(category.rawValue, systemImage: category.icon)
                                    .tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Suggestion badge
                    if let suggested = suggestedCategory, suggested != subRoom.category {
                        Button(action: {
                            withAnimation {
                                subRoom.category = suggested
                                if subRoom.name.hasPrefix("Area ") {
                                    subRoom.name = suggested.rawValue
                                }
                            }
                        }) {
                            Label("Suggested: \(suggested.rawValue)", systemImage: "lightbulb")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.yellow.opacity(0.2))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }

                    // Dimensions info
                    HStack(spacing: 16) {
                        DimensionLabel(label: "Length", value: subRoom.lengthIn / 12, unit: "ft")
                        DimensionLabel(label: "Width", value: subRoom.widthIn / 12, unit: "ft")
                        DimensionLabel(label: "Height", value: subRoom.heightIn / 12, unit: "ft")
                    }
                    .padding(.top, 4)
                }
                .padding(.leading, 40)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
}

// MARK: - Dimension Label

struct DimensionLabel: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f %@", value, unit))
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Mini Floor Plan Preview

struct MiniFloorPlanPreview: View {
    let floorPlanData: FloorPlanData
    let divisionLines: [DivisionLine]
    let subRooms: [SubRoom]

    private let wallColor = Color.primary
    private let divisionLineColor = Color.orange
    private let labelColors: [Color] = [.blue, .green, .purple, .pink, .orange, .cyan]

    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let scale = calculateScale(viewSize: viewSize)

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                context.translateBy(x: center.x, y: center.y)
                context.scaleBy(x: scale, y: scale)

                let floorPlanCenter = CGPoint(
                    x: floorPlanData.boundingBox.midX,
                    y: floorPlanData.boundingBox.midY
                )
                context.translateBy(x: -floorPlanCenter.x, y: -floorPlanCenter.y)

                // Draw walls
                for wall in floorPlanData.walls {
                    var path = Path()
                    path.move(to: wall.startPoint)
                    path.addLine(to: wall.endPoint)
                    context.stroke(path, with: .color(wallColor), style: StrokeStyle(lineWidth: 0.2, lineCap: .round))
                }

                // Draw division lines
                for line in divisionLines {
                    let startX = floorPlanData.boundingBox.minX + line.startPoint.x * floorPlanData.boundingBox.width
                    let startY = floorPlanData.boundingBox.minY + line.startPoint.y * floorPlanData.boundingBox.height
                    let endX = floorPlanData.boundingBox.minX + line.endPoint.x * floorPlanData.boundingBox.width
                    let endY = floorPlanData.boundingBox.minY + line.endPoint.y * floorPlanData.boundingBox.height

                    var path = Path()
                    path.move(to: CGPoint(x: startX, y: startY))
                    path.addLine(to: CGPoint(x: endX, y: endY))
                    context.stroke(path, with: .color(divisionLineColor), style: StrokeStyle(lineWidth: 0.15, dash: [0.3, 0.15]))
                }

                // Draw sub-room labels
                if !subRooms.isEmpty {
                    drawSubRoomLabels(context: context, in: floorPlanData.boundingBox)
                }
            }
        }
    }

    private func calculateScale(viewSize: CGSize) -> CGFloat {
        let padding: CGFloat = 20
        let availableWidth = viewSize.width - padding * 2
        let availableHeight = viewSize.height - padding * 2

        let scaleX = availableWidth / floorPlanData.boundingBox.width
        let scaleY = availableHeight / floorPlanData.boundingBox.height

        return min(scaleX, scaleY)
    }

    private func drawSubRoomLabels(context: GraphicsContext, in boundingBox: CGRect) {
        // Simple label placement - divide bounding box based on division lines
        guard !divisionLines.isEmpty, divisionLines.count == 1 else {
            // For multiple lines or no lines, place labels evenly
            for (index, subRoom) in subRooms.enumerated() {
                let fraction = Double(index) / Double(max(subRooms.count - 1, 1))
                let x = boundingBox.minX + boundingBox.width * (0.25 + fraction * 0.5)
                let y = boundingBox.midY

                let text = Text(subRoom.name)
                    .font(.system(size: 0.8))
                    .foregroundColor(labelColors[index % labelColors.count])
                context.draw(text, at: CGPoint(x: x, y: y), anchor: .center)
            }
            return
        }

        let line = divisionLines[0]
        let dx = abs(line.endPoint.x - line.startPoint.x)
        let dy = abs(line.endPoint.y - line.startPoint.y)
        let isHorizontal = dx > dy

        for (index, subRoom) in subRooms.enumerated() {
            let labelPoint: CGPoint

            if isHorizontal {
                let splitY = (line.startPoint.y + line.endPoint.y) / 2
                let regionY = index == 0 ? splitY / 2 : (1 + splitY) / 2
                labelPoint = CGPoint(
                    x: boundingBox.midX,
                    y: boundingBox.minY + boundingBox.height * regionY
                )
            } else {
                let splitX = (line.startPoint.x + line.endPoint.x) / 2
                let regionX = index == 0 ? splitX / 2 : (1 + splitX) / 2
                labelPoint = CGPoint(
                    x: boundingBox.minX + boundingBox.width * regionX,
                    y: boundingBox.midY
                )
            }

            let text = Text(subRoom.name.isEmpty ? "?" : subRoom.name)
                .font(.system(size: 0.8))
                .foregroundColor(labelColors[index % labelColors.count])
            context.draw(text, at: labelPoint, anchor: .center)
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleRoom = Room(
        name: "Open Living Space",
        category: .livingRoom,
        floor: .first,
        lengthIn: 240,
        widthIn: 180,
        heightIn: 96
    )

    let sampleDivisionLines = [
        DivisionLine(startPoint: CGPoint(x: 0.5, y: 0.1), endPoint: CGPoint(x: 0.5, y: 0.9))
    ]

    let sampleWalls = [
        FloorPlanWall(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 20, y: 0), length: 20, height: 8),
        FloorPlanWall(startPoint: CGPoint(x: 20, y: 0), endPoint: CGPoint(x: 20, y: 15), length: 15, height: 8),
        FloorPlanWall(startPoint: CGPoint(x: 20, y: 15), endPoint: CGPoint(x: 0, y: 15), length: 20, height: 8),
        FloorPlanWall(startPoint: CGPoint(x: 0, y: 15), endPoint: CGPoint(x: 0, y: 0), length: 15, height: 8)
    ]

    let sampleData = FloorPlanData(
        walls: sampleWalls,
        doors: [],
        windows: [],
        objects: [],
        boundingBox: CGRect(x: -2, y: -2, width: 24, height: 19),
        squareFootage: 300,
        linearFeet: 70
    )

    SubRoomNamingView(
        parentRoom: sampleRoom,
        divisionLines: sampleDivisionLines,
        floorPlanData: sampleData
    ) { subRooms in
        print("Saved \(subRooms.count) sub-rooms")
    }
}
