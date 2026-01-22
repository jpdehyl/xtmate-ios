import SwiftUI

// MARK: - Room List Item Data

/// Simplified room data for display in list
struct RoomListItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let category: String?
    let floor: String?
    let hasScope: Bool
    let damageCount: Int
    let squareFeet: Double  // P3-016: Added for division eligibility check
    let isDivided: Bool     // P3-016: Track if room has been divided
    let annotations: [DamageAnnotation]  // P3-020: Full annotation data for display

    init(id: UUID, name: String, category: String?, floor: String?, hasScope: Bool, damageCount: Int, squareFeet: Double = 0, isDivided: Bool = false, annotations: [DamageAnnotation] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.floor = floor
        self.hasScope = hasScope
        self.damageCount = damageCount
        self.squareFeet = squareFeet
        self.isDivided = isDivided
        self.annotations = annotations
    }

    /// P3-016: Room can be divided if > 200 SF and not already divided
    var canBeDivided: Bool {
        squareFeet > 200 && !isDivided
    }

    var icon: String {
        switch category?.lowercased() {
        case "kitchen": return "fork.knife"
        case "bathroom": return "shower.fill"
        case "bedroom": return "bed.double.fill"
        case "living", "livingroom", "living_room": return "sofa.fill"
        case "dining", "diningroom", "dining_room": return "table.furniture.fill"
        case "garage": return "car.fill"
        case "laundry": return "washer.fill"
        case "office": return "desktopcomputer"
        case "hallway": return "arrow.left.and.right"
        case "closet": return "cabinet.fill"
        case "basement": return "arrow.down.to.line"
        case "attic": return "arrow.up.to.line"
        default: return "square.split.bottomrightquarter"
        }
    }
}

// MARK: - Rooms List Card

/// Card showing list of scanned rooms with simple info
struct RoomsListCard: View {
    let rooms: [RoomListItem]
    var selectedRoomId: UUID?
    var onSelectRoom: ((RoomListItem) -> Void)?
    var onCaptureRoom: (() -> Void)?
    var onDivideRoom: ((RoomListItem) -> Void)?  // P3-016: Callback for room division
    var onAddDamage: ((RoomListItem) -> Void)?   // P3-018: Callback for damage annotation
    var onEditAnnotation: ((RoomListItem, DamageAnnotation) -> Void)?  // P3-020: Edit annotation
    var onDeleteAnnotation: ((RoomListItem, DamageAnnotation) -> Void)?  // P3-020: Delete annotation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Rooms", systemImage: AppTheme.Icons.room)
                    .font(.headline)

                Spacer()

                Text("\(rooms.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(AppTheme.Spacing.md)

            Divider()

            // Rooms list
            if rooms.isEmpty {
                EmptyRoomsView(onCapture: onCaptureRoom)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rooms) { room in
                            RoomRow(
                                room: room,
                                isSelected: room.id == selectedRoomId,
                                onTap: { onSelectRoom?(room) },
                                onDivide: room.canBeDivided ? { onDivideRoom?(room) } : nil,
                                onAddDamage: { onAddDamage?(room) },  // P3-018
                                onEditAnnotation: { annotation in onEditAnnotation?(room, annotation) },  // P3-020
                                onDeleteAnnotation: { annotation in onDeleteAnnotation?(room, annotation) }  // P3-020
                            )

                            if room.id != rooms.last?.id {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)

                Divider()

                // Capture button
                Button(action: { onCaptureRoom?() }) {
                    Label("Capture Room", systemImage: AppTheme.Icons.scan)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(AppTheme.Spacing.md)
                }
            }
        }
        .background(AppTheme.Colors.cardBackground)
        .continuousCornerRadius(AppTheme.Radius.md)
        .appShadow(AppTheme.Shadow.sm)
    }
}

// MARK: - Room Row

private struct RoomRow: View {
    let room: RoomListItem
    let isSelected: Bool
    var onTap: (() -> Void)?
    var onDivide: (() -> Void)?  // P3-016: Callback for room division
    var onAddDamage: (() -> Void)?  // P3-018: Callback for damage annotation
    var onEditAnnotation: ((DamageAnnotation) -> Void)?  // P3-020: Edit annotation
    var onDeleteAnnotation: ((DamageAnnotation) -> Void)?  // P3-020: Delete annotation

    // P3-020: Expandable annotations section
    @State private var isAnnotationsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row content
            mainRowContent

            // P3-020: Expandable annotations list
            if isAnnotationsExpanded && !room.annotations.isEmpty {
                annotationsExpandedSection
            }
        }
        // P3-016 & P3-018: Context menu for room actions
        .contextMenu {
            // P3-018: Mark Damage option (always available)
            if let onAddDamage = onAddDamage {
                Button(action: onAddDamage) {
                    Label("Mark Damage", systemImage: "exclamationmark.triangle")
                }
            }

            // Divide Room option - only shown if room can be divided
            if let onDivide = onDivide {
                Button(action: onDivide) {
                    Label("Divide Room", systemImage: "square.split.2x1")
                }
            }

            Divider()

            // View details (always available)
            Button(action: { onTap?() }) {
                Label("View Details", systemImage: "info.circle")
            }
        }
    }

    // MARK: - Main Row Content

    private var mainRowContent: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Room icon
                Image(systemName: room.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.Colors.primary : .secondary)
                    .frame(width: 32)

                // Room info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(room.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        // P3-016: Show divided badge if room has been divided
                        if room.isDivided {
                            Text("Divided")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 4) {
                        if let floor = room.floor {
                            Text("Floor \(floor)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // P3-016: Show square footage
                        if room.squareFeet > 0 {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("\(Int(room.squareFeet)) SF")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Status indicators
                HStack(spacing: AppTheme.Spacing.sm) {
                    // P3-020: Tappable damage count badge
                    if room.damageCount > 0 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isAnnotationsExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                Text("\(room.damageCount)")
                                    .font(.caption)
                                Image(systemName: isAnnotationsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    // Has scope checkmark
                    if room.hasScope {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.md)
            .background(isSelected ? AppTheme.Colors.primary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Annotations Expanded Section

    private var annotationsExpandedSection: some View {
        VStack(spacing: 0) {
            ForEach(room.annotations) { annotation in
                AnnotationRowView(
                    annotation: annotation,
                    onTap: { onEditAnnotation?(annotation) },
                    onDelete: { onDeleteAnnotation?(annotation) }
                )

                if annotation.id != room.annotations.last?.id {
                    Divider()
                        .padding(.leading, 60)
                }
            }
        }
        .padding(.leading, 32)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

// MARK: - Annotation Row View

/// P3-020: Row view for displaying a single damage annotation
private struct AnnotationRowView: View {
    let annotation: DamageAnnotation
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Damage type icon with severity color
                ZStack {
                    Circle()
                        .fill(annotation.severity.color.opacity(0.2))
                        .frame(width: 28, height: 28)
                    Image(systemName: annotation.damageType.icon)
                        .font(.caption)
                        .foregroundStyle(annotation.severity.color)
                }

                // Annotation info
                VStack(alignment: .leading, spacing: 2) {
                    Text(annotation.damageType.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text(annotation.severity.rawValue)
                            .font(.caption2)
                            .foregroundStyle(annotation.severity.color)

                        if !annotation.affectedSurfaces.isEmpty {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(annotation.affectedSurfaces.map(\.rawValue).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // P3-020: Photo preview if present
                if let firstPhoto = annotation.photos.first {
                    AnnotationPhotoThumbnail(photoPath: firstPhoto)
                }

                // More indicator
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: { onDelete?() }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Annotation Photo Thumbnail

/// P3-020: Small photo thumbnail for annotation preview
private struct AnnotationPhotoThumbnail: View {
    let photoPath: String

    var body: some View {
        if let image = loadImage(from: photoPath) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipped()
                .cornerRadius(4)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "photo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func loadImage(from path: String) -> UIImage? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fullPath = documentsPath.appendingPathComponent(path)
        return UIImage(contentsOfFile: fullPath.path)
    }
}

// MARK: - Empty Rooms View

private struct EmptyRoomsView: View {
    var onCapture: (() -> Void)?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: AppTheme.Spacing.xs) {
                Text("No rooms captured")
                    .font(.headline)

                Text("Use LiDAR to scan rooms")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: { onCapture?() }) {
                Label("Capture First Room", systemImage: AppTheme.Icons.scan)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(AppTheme.Colors.primary)
                    .continuousCornerRadius(AppTheme.Radius.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.xxl)
    }
}

// MARK: - Compact Rooms Summary

/// Ultra-compact rooms summary for tight spaces
struct CompactRoomsSummary: View {
    let roomCount: Int
    let scopedCount: Int
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack {
                Image(systemName: AppTheme.Icons.room)
                    .foregroundStyle(.secondary)

                Text("\(roomCount) room\(roomCount == 1 ? "" : "s")")
                    .font(.subheadline)

                if scopedCount > 0 {
                    Text("\(scopedCount) scoped")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.cardBackground)
            .continuousCornerRadius(AppTheme.Radius.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Rooms List Card") {
    // P3-020: Sample annotations for preview
    let kitchenAnnotations = [
        DamageAnnotation(
            position: CGPoint(x: 0.3, y: 0.4),
            damageType: .water,
            severity: .moderate,
            affectedSurfaces: [.floor, .wall]
        ),
        DamageAnnotation(
            position: CGPoint(x: 0.6, y: 0.7),
            damageType: .mold,
            severity: .light,
            affectedSurfaces: [.wall]
        )
    ]

    let livingRoomAnnotations = [
        DamageAnnotation(
            position: CGPoint(x: 0.5, y: 0.5),
            damageType: .water,
            severity: .heavy,
            affectedSurfaces: [.floor, .wall, .ceiling]
        )
    ]

    RoomsListCard(
        rooms: [
            RoomListItem(id: UUID(), name: "Kitchen", category: "kitchen", floor: "1", hasScope: true, damageCount: 2, squareFeet: 150, annotations: kitchenAnnotations),
            RoomListItem(id: UUID(), name: "Living Room", category: "living", floor: "1", hasScope: true, damageCount: 1, squareFeet: 320, annotations: livingRoomAnnotations),  // Can be divided
            RoomListItem(id: UUID(), name: "Master Bedroom", category: "bedroom", floor: "2", hasScope: false, damageCount: 0, squareFeet: 180),
            RoomListItem(id: UUID(), name: "Open Space", category: "other", floor: "1", hasScope: false, damageCount: 0, squareFeet: 450, isDivided: true)  // Already divided
        ],
        selectedRoomId: nil as UUID?,
        onDivideRoom: { room in
            print("Divide room: \(room.name)")
        },
        onAddDamage: { room in
            print("Add damage to room: \(room.name)")
        },
        onEditAnnotation: { room, annotation in
            print("Edit annotation \(annotation.damageType.rawValue) in \(room.name)")
        },
        onDeleteAnnotation: { room, annotation in
            print("Delete annotation \(annotation.damageType.rawValue) in \(room.name)")
        }
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Empty Rooms") {
    RoomsListCard(rooms: [])
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}
