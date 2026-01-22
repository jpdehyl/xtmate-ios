//
//  DamageAnnotationView.swift
//  XtMate
//
//  P3B-5: Wrapper for damage annotation that works with or without FloorPlanData
//  Uses FloorPlanDamageAnnotationView when floor plan data is available,
//  otherwise falls back to a simplified annotation view.
//

import SwiftUI

// MARK: - Damage Annotation View (Wrapper)

/// Wrapper view for damage annotation that handles rooms with or without floor plan data
/// P3B-5: Provides a consistent interface for damage marking
@available(iOS 16.0, *)
struct DamageAnnotationView: View {
    let room: Room
    @Binding var annotations: [DamageAnnotation]

    var onAnnotationAdded: ((DamageAnnotation) -> Void)?
    var onAnnotationUpdated: ((DamageAnnotation) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                // TODO: P3B-5: Add floorPlanData property to Room struct to enable
                // FloorPlanDamageAnnotationView. For now, always use simple view.
                SimpleDamageAnnotationView(
                    room: room,
                    annotations: $annotations,
                    onAnnotationAdded: onAnnotationAdded
                )
            }
            .navigationTitle("Damage Annotation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Simple Damage Annotation View

/// Fallback annotation view for rooms without floor plan data
/// Shows a simple rectangle representing the room with tap-to-add markers
@available(iOS 16.0, *)
struct SimpleDamageAnnotationView: View {
    let room: Room
    @Binding var annotations: [DamageAnnotation]
    var onAnnotationAdded: ((DamageAnnotation) -> Void)?

    @State private var showingNewAnnotationSheet = false
    @State private var selectedPosition: CGPoint = .zero
    @State private var selectedAnnotation: DamageAnnotation?
    @State private var showingAnnotationDetail = false

    var body: some View {
        VStack(spacing: 0) {
            // Room info header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .font(.headline)
                    Text("\(Int(room.squareFeet)) SF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Annotation count badge
                if !annotations.isEmpty {
                    Label("\(annotations.count)", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))

            // Instructions
            Text("Tap on the room to mark damage locations")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

            // Simple room representation
            GeometryReader { geometry in
                let roomRect = calculateRoomRect(in: geometry.size)

                ZStack {
                    // Background
                    Color(uiColor: .systemBackground)

                    // Room rectangle
                    Rectangle()
                        .stroke(Color.primary, lineWidth: 2)
                        .background(Color.blue.opacity(0.05))
                        .frame(width: roomRect.width, height: roomRect.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    // Dimension labels
                    VStack {
                        Text("\(room.lengthFtIn)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(room.lengthFtIn)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: roomRect.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    HStack {
                        Text("\(room.widthFtIn)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(room.widthFtIn)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: roomRect.width)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    // Damage markers
                    ForEach(annotations) { annotation in
                        let markerPosition = denormalizePosition(
                            annotation.position,
                            roomRect: roomRect,
                            viewSize: geometry.size
                        )

                        DamageMarker(
                            annotation: annotation,
                            isSelected: selectedAnnotation?.id == annotation.id
                        )
                        .position(markerPosition)
                        .onTapGesture {
                            selectedAnnotation = annotation
                            showingAnnotationDetail = true
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // Normalize tap position to 0-1 range relative to room rectangle
                    let normalizedPosition = normalizePosition(
                        location,
                        roomRect: roomRect,
                        viewSize: geometry.size
                    )

                    selectedPosition = normalizedPosition
                    showingNewAnnotationSheet = true
                }
            }

            // Existing annotations list
            if !annotations.isEmpty {
                List {
                    Section("Marked Damage") {
                        ForEach(annotations) { annotation in
                            DamageAnnotationRow(annotation: annotation)
                                .onTapGesture {
                                    selectedAnnotation = annotation
                                    showingAnnotationDetail = true
                                }
                        }
                        .onDelete { indexSet in
                            annotations.remove(atOffsets: indexSet)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .frame(maxHeight: 200)
            }
        }
        .sheet(isPresented: $showingNewAnnotationSheet) {
            NewDamageAnnotationSheet(
                position: selectedPosition,
                onSave: { annotation in
                    annotations.append(annotation)
                    onAnnotationAdded?(annotation)
                    showingNewAnnotationSheet = false

                    // Haptic feedback
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)
                },
                onCancel: {
                    showingNewAnnotationSheet = false
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingAnnotationDetail) {
            if let annotation = selectedAnnotation {
                DamageAnnotationDetailSheet(
                    annotation: annotation,
                    onUpdate: { updated in
                        if let index = annotations.firstIndex(where: { $0.id == updated.id }) {
                            annotations[index] = updated
                        }
                        showingAnnotationDetail = false
                    },
                    onDelete: {
                        annotations.removeAll { $0.id == annotation.id }
                        showingAnnotationDetail = false
                    },
                    onCancel: {
                        showingAnnotationDetail = false
                    }
                )
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Position Calculations

    private func calculateRoomRect(in viewSize: CGSize) -> CGRect {
        let maxWidth = viewSize.width * 0.8
        let maxHeight = viewSize.height * 0.6

        let roomAspect = room.lengthIn / room.widthIn
        var width: CGFloat
        var height: CGFloat

        if roomAspect > maxWidth / maxHeight {
            width = maxWidth
            height = maxWidth / roomAspect
        } else {
            height = maxHeight
            width = maxHeight * roomAspect
        }

        return CGRect(
            x: (viewSize.width - width) / 2,
            y: (viewSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func normalizePosition(_ point: CGPoint, roomRect: CGRect, viewSize: CGSize) -> CGPoint {
        let x = (point.x - roomRect.minX) / roomRect.width
        let y = (point.y - roomRect.minY) / roomRect.height
        return CGPoint(x: max(0, min(1, x)), y: max(0, min(1, y)))
    }

    private func denormalizePosition(_ normalized: CGPoint, roomRect: CGRect, viewSize: CGSize) -> CGPoint {
        let x = roomRect.minX + (normalized.x * roomRect.width)
        let y = roomRect.minY + (normalized.y * roomRect.height)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Damage Marker

@available(iOS 16.0, *)
struct DamageMarker: View {
    let annotation: DamageAnnotation
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(annotation.damageType.color.opacity(0.2))
                .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)

            Circle()
                .stroke(annotation.damageType.color, lineWidth: isSelected ? 3 : 2)
                .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)

            Image(systemName: annotation.damageType.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(annotation.damageType.color)
        }
    }
}

// MARK: - Damage Annotation Row

@available(iOS 16.0, *)
struct DamageAnnotationRow: View {
    let annotation: DamageAnnotation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: annotation.damageType.icon)
                .font(.title3)
                .foregroundColor(annotation.damageType.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(annotation.damageType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(annotation.severity.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(annotation.affectedSurfaces), id: \.self) { surface in
                        Text(surface.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Damage Annotation Sheet

@available(iOS 16.0, *)
struct NewDamageAnnotationSheet: View {
    let position: CGPoint
    let onSave: (DamageAnnotation) -> Void
    let onCancel: () -> Void

    @State private var damageType: DamageType = .water
    @State private var severity: DamageSeverity = .moderate
    @State private var affectedSurfaces: Set<AffectedSurface> = [.floor]
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Damage Type") {
                    Picker("Type", selection: $damageType) {
                        ForEach(DamageType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Severity") {
                    Picker("Severity", selection: $severity) {
                        ForEach(DamageSeverity.allCases, id: \.self) { sev in
                            Text(sev.displayName).tag(sev)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Affected Surfaces") {
                    ForEach(AffectedSurface.allCases, id: \.self) { surface in
                        Toggle(surface.displayName, isOn: Binding(
                            get: { affectedSurfaces.contains(surface) },
                            set: { isOn in
                                if isOn {
                                    affectedSurfaces.insert(surface)
                                } else {
                                    affectedSurfaces.remove(surface)
                                }
                            }
                        ))
                    }
                }

                Section("Notes") {
                    TextField("Additional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Damage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let annotation = DamageAnnotation(
                            position: position,
                            damageType: damageType,
                            severity: severity,
                            affectedSurfaces: affectedSurfaces,
                            notes: notes
                        )
                        onSave(annotation)
                    }
                }
            }
        }
    }
}

// MARK: - Damage Annotation Detail Sheet

@available(iOS 16.0, *)
struct DamageAnnotationDetailSheet: View {
    let annotation: DamageAnnotation
    let onUpdate: (DamageAnnotation) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var damageType: DamageType
    @State private var severity: DamageSeverity
    @State private var affectedSurfaces: Set<AffectedSurface>
    @State private var notes: String

    init(
        annotation: DamageAnnotation,
        onUpdate: @escaping (DamageAnnotation) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.annotation = annotation
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onCancel = onCancel
        _damageType = State(initialValue: annotation.damageType)
        _severity = State(initialValue: annotation.severity)
        _affectedSurfaces = State(initialValue: annotation.affectedSurfaces)
        _notes = State(initialValue: annotation.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Damage Type") {
                    Picker("Type", selection: $damageType) {
                        ForEach(DamageType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Severity") {
                    Picker("Severity", selection: $severity) {
                        ForEach(DamageSeverity.allCases, id: \.self) { sev in
                            Text(sev.displayName).tag(sev)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Affected Surfaces") {
                    ForEach(AffectedSurface.allCases, id: \.self) { surface in
                        Toggle(surface.displayName, isOn: Binding(
                            get: { affectedSurfaces.contains(surface) },
                            set: { isOn in
                                if isOn {
                                    affectedSurfaces.insert(surface)
                                } else {
                                    affectedSurfaces.remove(surface)
                                }
                            }
                        ))
                    }
                }

                Section("Notes") {
                    TextField("Additional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Annotation", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Damage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = annotation
                        updated.damageType = damageType
                        updated.severity = severity
                        updated.affectedSurfaces = affectedSurfaces
                        updated.notes = notes
                        onUpdate(updated)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
#Preview {
    DamageAnnotationView(
        room: Room(
            id: UUID(),
            name: "Kitchen",
            category: .kitchen,
            floor: .first,
            lengthIn: 144,
            widthIn: 120,
            heightIn: 96
        ),
        annotations: .constant([])
    )
}
#endif
