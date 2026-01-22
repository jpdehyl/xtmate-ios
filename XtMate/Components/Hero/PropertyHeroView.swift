import SwiftUI

// MARK: - Property Hero View

/// Hero section showing 3D/2D floor plan of the property
struct PropertyHeroView: View {
    let rooms: [RoomListItem]
    @Binding var selectedRoomId: UUID?
    var viewMode: ViewMode = .isometric
    var onToggleViewMode: (() -> Void)?
    var onCaptureRoom: (() -> Void)?
    var onSelectRoom: ((RoomListItem) -> Void)?

    enum ViewMode {
        case floorPlan  // 2D top-down view
        case isometric  // 3D isometric view
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                AppTheme.Colors.background

                if rooms.isEmpty {
                    // Empty state
                    EmptyHeroView(onCapture: onCaptureRoom)
                } else {
                    // Floor plan visualization
                    FloorPlanVisualization(
                        rooms: rooms,
                        selectedRoomId: selectedRoomId,
                        viewMode: viewMode,
                        onSelectRoom: { room in
                            selectedRoomId = room.id
                            onSelectRoom?(room)
                        }
                    )
                }

                // Controls overlay
                VStack {
                    HStack {
                        Spacer()

                        // View mode toggle
                        ViewModeToggle(
                            mode: viewMode,
                            onToggle: onToggleViewMode
                        )
                    }
                    .padding(AppTheme.Spacing.md)

                    Spacer()

                    // Room count badge
                    if !rooms.isEmpty {
                        HStack {
                            RoomCountBadge(count: rooms.count)
                            Spacer()
                        }
                        .padding(AppTheme.Spacing.md)
                    }
                }
            }
        }
        .frame(height: 280)
        .background(AppTheme.Colors.background)
        .continuousCornerRadius(AppTheme.Radius.lg)
        .appShadow(AppTheme.Shadow.md)
    }
}

// MARK: - Empty Hero View

private struct EmptyHeroView: View {
    var onCapture: (() -> Void)?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Illustration
            ZStack {
                // House outline
                Image(systemName: "house.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.quaternary)

                // Scan icon
                Image(systemName: "viewfinder")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: AppTheme.Spacing.xs) {
                Text("Scan Your First Room")
                    .font(.headline)

                Text("Use your device's LiDAR to capture room dimensions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.xl)
            }

            Button(action: { onCapture?() }) {
                HStack {
                    Image(systemName: AppTheme.Icons.scan)
                    Text("Start Capture")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(AppTheme.Colors.primary)
                .continuousCornerRadius(AppTheme.Radius.md)
            }
        }
    }
}

// MARK: - Floor Plan Visualization

private struct FloorPlanVisualization: View {
    let rooms: [RoomListItem]
    let selectedRoomId: UUID?
    let viewMode: PropertyHeroView.ViewMode
    var onSelectRoom: ((RoomListItem) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let availableSize = geometry.size
            let roomSize = calculateRoomSize(for: availableSize, roomCount: rooms.count)

            ZStack {
                // Simple grid layout of rooms
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                        GridItem(.flexible(), spacing: AppTheme.Spacing.sm)
                    ],
                    spacing: AppTheme.Spacing.sm
                ) {
                    ForEach(rooms) { room in
                        RoomTile(
                            room: room,
                            isSelected: room.id == selectedRoomId,
                            size: roomSize,
                            viewMode: viewMode,
                            onTap: { onSelectRoom?(room) }
                        )
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
    }

    private func calculateRoomSize(for availableSize: CGSize, roomCount: Int) -> CGSize {
        let columns: CGFloat = 2
        let padding: CGFloat = AppTheme.Spacing.lg * 2
        let spacing: CGFloat = AppTheme.Spacing.sm

        let width = (availableSize.width - padding - spacing) / columns
        let rows = ceil(CGFloat(roomCount) / columns)
        let height = (availableSize.height - padding - (rows - 1) * spacing) / max(rows, 2)

        return CGSize(width: min(width, 160), height: min(height, 100))
    }
}

// MARK: - Room Tile

private struct RoomTile: View {
    let room: RoomListItem
    let isSelected: Bool
    let size: CGSize
    let viewMode: PropertyHeroView.ViewMode
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack {
                // Room shape
                if viewMode == .isometric {
                    IsometricRoomShape()
                        .fill(roomColor.opacity(0.3))
                        .overlay(
                            IsometricRoomShape()
                                .stroke(roomColor, lineWidth: isSelected ? 3 : 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                        .fill(roomColor.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                                .strokeBorder(roomColor, lineWidth: isSelected ? 3 : 1)
                        )
                }

                // Room label
                VStack(spacing: 2) {
                    Image(systemName: room.icon)
                        .font(.title3)
                    Text(room.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? roomColor : .primary)
            }
            .frame(width: size.width, height: size.height)
        }
        .buttonStyle(.plain)
    }

    private var roomColor: Color {
        if room.damageCount > 0 {
            return .orange
        } else if room.hasScope {
            return .green
        }
        return .blue
    }
}

// MARK: - Isometric Room Shape

private struct IsometricRoomShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Create an isometric box shape
        let w = rect.width
        let h = rect.height
        let depth: CGFloat = h * 0.3

        // Top face (parallelogram)
        path.move(to: CGPoint(x: w * 0.1, y: depth))
        path.addLine(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w * 0.9, y: depth))
        path.addLine(to: CGPoint(x: w * 0.5, y: depth * 2))
        path.closeSubpath()

        // Left face
        path.move(to: CGPoint(x: w * 0.1, y: depth))
        path.addLine(to: CGPoint(x: w * 0.1, y: h - depth))
        path.addLine(to: CGPoint(x: w * 0.5, y: h))
        path.addLine(to: CGPoint(x: w * 0.5, y: depth * 2))
        path.closeSubpath()

        // Right face
        path.move(to: CGPoint(x: w * 0.5, y: depth * 2))
        path.addLine(to: CGPoint(x: w * 0.5, y: h))
        path.addLine(to: CGPoint(x: w * 0.9, y: h - depth))
        path.addLine(to: CGPoint(x: w * 0.9, y: depth))
        path.closeSubpath()

        return path
    }
}

// MARK: - View Mode Toggle

private struct ViewModeToggle: View {
    let mode: PropertyHeroView.ViewMode
    var onToggle: (() -> Void)?

    var body: some View {
        Button(action: { onToggle?() }) {
            HStack(spacing: 4) {
                Image(systemName: mode == .isometric ? "cube" : "square.split.bottomrightquarter")
                Text(mode == .isometric ? "3D" : "2D")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(.ultraThinMaterial)
            .continuousCornerRadius(AppTheme.Radius.sm)
        }
    }
}

// MARK: - Room Count Badge

private struct RoomCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: AppTheme.Icons.room)
            Text("\(count) room\(count == 1 ? "" : "s")")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(.ultraThinMaterial)
        .continuousCornerRadius(AppTheme.Radius.sm)
    }
}

// MARK: - Preview

#Preview("Property Hero - With Rooms") {
    @Previewable @State var selectedRoomId: UUID? = nil
    
    PropertyHeroView(
        rooms: [
            RoomListItem(id: UUID(), name: "Kitchen", category: "kitchen", floor: "1", hasScope: true, damageCount: 2),
            RoomListItem(id: UUID(), name: "Living Room", category: "living", floor: "1", hasScope: true, damageCount: 0),
            RoomListItem(id: UUID(), name: "Master Bed", category: "bedroom", floor: "2", hasScope: false, damageCount: 0),
            RoomListItem(id: UUID(), name: "Bathroom", category: "bathroom", floor: "2", hasScope: false, damageCount: 1)
        ],
        selectedRoomId: $selectedRoomId
    )
    .padding()
}

#Preview("Property Hero - Empty") {
    @Previewable @State var selectedRoomId: UUID? = nil
    
    PropertyHeroView(
        rooms: [],
        selectedRoomId: $selectedRoomId
    )
    .padding()
}
