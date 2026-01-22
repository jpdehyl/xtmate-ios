//
//  RoomIdentificationEditView.swift
//  XtMate
//
//  View for reviewing and editing AI-detected room identifications from walkthrough.
//  PMs can confirm, change room type, or add custom names.
//
//  Features:
//  - Shows AI confidence and detected objects
//  - Allows changing room category
//  - Supports custom room names
//  - Shows key frame preview for context
//  - Handles ambiguous/combo rooms
//

import SwiftUI

// MARK: - Room Identification Edit View

@available(iOS 16.0, *)
struct RoomIdentificationEditView: View {
    @Binding var identifications: [EditableRoomIdentification]
    let keyFrames: [(timestamp: TimeInterval, image: UIImage)]
    let onConfirmAll: () -> Void
    let onCancel: () -> Void

    @State private var sheetItem: IdentifiableValue<Int>? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with summary
                summaryHeader
                    .padding()
                    .background(Color(.secondarySystemBackground))

                // Room list
                if identifications.isEmpty {
                    emptyState
                } else {
                    roomList
                }

                // Bottom action bar
                actionBar
            }
            .navigationTitle("Identified Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            .sheet(item: $sheetItem) { index in
                RoomIdentificationEditSheet(
                    room: $identifications[index.value],
                    keyFrames: keyFrames,
                    onDone: { sheetItem = nil }
                )
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(identifications.count) Rooms Detected")
                    .font(.headline)

                let confirmed = identifications.filter { $0.isConfirmed }.count
                Text("\(confirmed) confirmed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: confirmAllRooms) {
                Label("Confirm All", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .disabled(identifications.allSatisfy { $0.isConfirmed })
        }
    }

    // MARK: - Room List

    private var roomList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(identifications.enumerated()), id: \.element.id) { index, room in
                    RoomIdentificationCard(
                        room: room,
                        index: index + 1,
                        onEdit: { sheetItem = IdentifiableValue(value: index) },
                        onToggleConfirm: { toggleConfirm(at: index) },
                        onDelete: { deleteRoom(at: index) }
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Rooms Detected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("The walkthrough didn't capture enough detail to identify rooms. You can add rooms manually after the scan.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 16) {
                // Add manual room button
                Button(action: addManualRoom) {
                    Label("Add Room", systemImage: "plus.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
                .foregroundColor(.primary)

                // Use these rooms button
                Button(action: onConfirmAll) {
                    Text("Use \(identifications.filter { $0.isConfirmed }.count > 0 ? "\(identifications.filter { $0.isConfirmed }.count) " : "")Rooms")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(identifications.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(identifications.isEmpty)
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func confirmAllRooms() {
        for i in 0..<identifications.count {
            identifications[i].isConfirmed = true
        }
    }

    private func toggleConfirm(at index: Int) {
        identifications[index].isConfirmed.toggle()
    }

    private func deleteRoom(at index: Int) {
        identifications.remove(at: index)
    }

    private func addManualRoom() {
        let newRoom = EditableRoomIdentification(
            id: UUID(),
            selectedCategory: .other,
            customName: nil,
            detectedObjects: [],
            isConfirmed: false
        )
        identifications.append(newRoom)
        sheetItem = IdentifiableValue(value: identifications.count - 1)
    }
}

// MARK: - Room Identification Card

@available(iOS 16.0, *)
private struct RoomIdentificationCard: View {
    let room: EditableRoomIdentification
    let index: Int
    let onEdit: () -> Void
    let onToggleConfirm: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Room icon and name
                HStack(spacing: 10) {
                    Image(systemName: room.selectedCategory.icon)
                        .font(.title2)
                        .foregroundColor(room.isConfirmed ? .green : .blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.displayName)
                            .font(.headline)

                        Text("Room \(index)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Confirm toggle
                Button(action: onToggleConfirm) {
                    Image(systemName: room.isConfirmed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(room.isConfirmed ? .green : .gray)
                }
            }

            // Detected objects (if any)
            if !room.detectedObjects.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(room.detectedObjects.prefix(5), id: \.name) { obj in
                            Text(obj.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                        if room.detectedObjects.count > 5 {
                            Text("+\(room.detectedObjects.count - 5)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: { showingDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(room.isConfirmed ? Color.green : Color.clear, lineWidth: 2)
        )
        .confirmationDialog("Delete Room?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Room Identification Edit Sheet

@available(iOS 16.0, *)
private struct RoomIdentificationEditSheet: View {
    @Binding var room: EditableRoomIdentification
    let keyFrames: [(timestamp: TimeInterval, image: UIImage)]
    let onDone: () -> Void

    @State private var customNameText: String = ""
    @State private var useCustomName: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // Room type selection
                Section("Room Type") {
                    Picker("Category", selection: $room.selectedCategory) {
                        ForEach(RoomCategory.allCases, id: \.self) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                // Custom name
                Section("Custom Name (Optional)") {
                    Toggle("Use custom name", isOn: $useCustomName)

                    if useCustomName {
                        TextField("Room name", text: $customNameText)
                            .textInputAutocapitalization(.words)
                    }
                }

                // Detected objects (read-only)
                if !room.detectedObjects.isEmpty {
                    Section("Detected Objects") {
                        ForEach(room.detectedObjects, id: \.name) { obj in
                            HStack {
                                Text(obj.name.capitalized)
                                Spacer()
                                if let indicator = obj.roomIndicator {
                                    Text(indicator.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text("\(Int(obj.confidence * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Key frame preview
                if !keyFrames.isEmpty {
                    Section("Reference Images") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(keyFrames.prefix(5).enumerated()), id: \.offset) { _, frame in
                                    Image(uiImage: frame.image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 70)
                                        .clipped()
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if useCustomName && !customNameText.isEmpty {
                            room.customName = customNameText
                        } else {
                            room.customName = nil
                        }
                        room.isConfirmed = true
                        onDone()
                    }
                }
            }
            .onAppear {
                if let customName = room.customName {
                    customNameText = customName
                    useCustomName = true
                }
            }
        }
    }
}

// MARK: - Helpers

struct IdentifiableValue<T>: Swift.Identifiable {
    let id = UUID()
    let value: T
}

// MARK: - Preview

#Preview {
    if #available(iOS 16.0, *) {
        RoomIdentificationEditView(
            identifications: .constant([
                EditableRoomIdentification(
                    id: UUID(),
                    selectedCategory: .kitchen,
                    customName: nil,
                    detectedObjects: [
                        RoomIdentification.DetectedObject(name: "refrigerator", confidence: 0.95, roomIndicator: .kitchen),
                        RoomIdentification.DetectedObject(name: "stove", confidence: 0.92, roomIndicator: .kitchen)
                    ],
                    isConfirmed: true
                ),
                EditableRoomIdentification(
                    id: UUID(),
                    selectedCategory: .livingRoom,
                    customName: nil,
                    detectedObjects: [
                        RoomIdentification.DetectedObject(name: "sofa", confidence: 0.88, roomIndicator: .livingRoom),
                        RoomIdentification.DetectedObject(name: "television", confidence: 0.85, roomIndicator: .livingRoom)
                    ],
                    isConfirmed: false
                )
            ]),
            keyFrames: [],
            onConfirmAll: {},
            onCancel: {}
        )
    }
}
