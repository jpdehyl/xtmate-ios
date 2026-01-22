//
//  FloorPlanDamageAnnotationView.swift
//  XtMate
//
//  P3-018: Interactive 2D floor plan view for marking damage annotations.
//  Supports tap-to-place markers with damage type icons.
//

import SwiftUI

/// Main view for annotating damage on a 2D floor plan
/// P3-018: Shows floor plan with tap-to-place damage markers
struct FloorPlanDamageAnnotationView: View {
    @Environment(\.dismiss) private var dismiss

    let room: Room
    let floorPlanData: FloorPlanData
    @Binding var annotations: [DamageAnnotation]
    var onAnnotationAdded: ((DamageAnnotation) -> Void)?
    var onAnnotationUpdated: ((DamageAnnotation) -> Void)?

    // View state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showDimensions = true
    @State private var isAnnotationMode = true

    // Annotation state
    @State private var selectedAnnotation: DamageAnnotation?
    @State private var showingAnnotationDetail = false
    @State private var pendingTapPosition: CGPoint?
    @State private var showingNewAnnotationSheet = false

    // Colors
    private let wallColor = Color.primary
    private let gridColor = Color.gray.opacity(0.2)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Toolbar info bar
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

                    // Toggle annotation mode
                    Toggle(isOn: $isAnnotationMode) {
                        Label("Add Mode", systemImage: "plus.circle")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(isAnnotationMode ? .blue : .gray)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground))

                // Instructions
                if isAnnotationMode {
                    Text("Tap on the floor plan to add a damage marker")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                // Floor plan canvas with annotations
                GeometryReader { geometry in
                    let viewSize = geometry.size
                    let floorPlanSize = floorPlanData.boundingBox.size
                    let baseScale = calculateBaseScale(viewSize: viewSize, floorPlanSize: floorPlanSize)

                    ZStack {
                        // Background
                        Color(uiColor: .systemBackground)

                        // Floor plan canvas
                        Canvas { context, size in
                            let centerOffset = CGSize(
                                width: size.width / 2,
                                height: size.height / 2
                            )

                            context.translateBy(x: centerOffset.width + offset.width, y: centerOffset.height + offset.height)
                            context.scaleBy(x: scale * baseScale, y: scale * baseScale)

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

                            // Draw objects (furniture)
                            for object in floorPlanData.objects {
                                drawObject(context: context, object: object)
                            }

                            // Draw dimensions
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
                                        if !isAnnotationMode {
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                        .onTapGesture(count: 1) { location in
                            if isAnnotationMode {
                                // Convert tap to normalized position
                                pendingTapPosition = convertToNormalizedPosition(
                                    tapPoint: location,
                                    viewSize: viewSize,
                                    baseScale: baseScale
                                )
                                showingNewAnnotationSheet = true
                            }
                        }

                        // Annotation markers overlay
                        ForEach(annotations) { annotation in
                            DamageMarkerView(
                                annotation: annotation,
                                position: convertToViewPosition(
                                    normalizedPosition: annotation.position,
                                    viewSize: viewSize,
                                    baseScale: baseScale
                                ),
                                isSelected: selectedAnnotation?.id == annotation.id,
                                onTap: {
                                    selectedAnnotation = annotation
                                    showingAnnotationDetail = true
                                }
                            )
                        }
                    }
                }

                // Annotation list summary
                if !annotations.isEmpty {
                    Divider()
                    DamageAnnotationSummaryBar(
                        annotations: annotations,
                        onAnnotationTapped: { annotation in
                            selectedAnnotation = annotation
                            showingAnnotationDetail = true
                        }
                    )
                }
            }
            .navigationTitle("Mark Damage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle("Show Dimensions", isOn: $showDimensions)
                        Button(action: {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }) {
                            Label("Reset View", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingNewAnnotationSheet) {
                if let position = pendingTapPosition {
                    QuickDamageAnnotationSheet(
                        position: position,
                        roomId: room.id,
                        onSave: { annotation in
                            annotations.append(annotation)
                            onAnnotationAdded?(annotation)
                            showingNewAnnotationSheet = false
                            pendingTapPosition = nil
                        },
                        onCancel: {
                            showingNewAnnotationSheet = false
                            pendingTapPosition = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showingAnnotationDetail) {
                if let annotation = selectedAnnotation {
                    FloorPlanDamageDetailSheet(
                        annotation: Binding(
                            get: { annotation },
                            set: { updatedAnnotation in
                                if let index = annotations.firstIndex(where: { $0.id == updatedAnnotation.id }) {
                                    annotations[index] = updatedAnnotation
                                    onAnnotationUpdated?(updatedAnnotation)
                                }
                            }
                        ),
                        onDelete: {
                            annotations.removeAll { $0.id == annotation.id }
                            selectedAnnotation = nil
                            showingAnnotationDetail = false
                        },
                        onDismiss: {
                            selectedAnnotation = nil
                            showingAnnotationDetail = false
                        }
                    )
                }
            }
        }
    }

    // MARK: - Coordinate Conversion

    private func calculateBaseScale(viewSize: CGSize, floorPlanSize: CGSize) -> CGFloat {
        let padding: CGFloat = 40
        let availableWidth = viewSize.width - padding * 2
        let availableHeight = viewSize.height - padding * 2

        let scaleX = availableWidth / max(floorPlanSize.width, 1)
        let scaleY = availableHeight / max(floorPlanSize.height, 1)

        return min(scaleX, scaleY) * 0.9
    }

    private func convertToNormalizedPosition(tapPoint: CGPoint, viewSize: CGSize, baseScale: CGFloat) -> CGPoint {
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2

        // Reverse the transformations
        let adjustedX = (tapPoint.x - centerX - offset.width) / (scale * baseScale)
        let adjustedY = (tapPoint.y - centerY - offset.height) / (scale * baseScale)

        // Add back the floor plan center offset
        let floorPlanX = adjustedX + floorPlanData.boundingBox.midX
        let floorPlanY = adjustedY + floorPlanData.boundingBox.midY

        // Normalize to 0-1 range based on bounding box
        let normalizedX = (floorPlanX - floorPlanData.boundingBox.minX) / floorPlanData.boundingBox.width
        let normalizedY = (floorPlanY - floorPlanData.boundingBox.minY) / floorPlanData.boundingBox.height

        return CGPoint(x: max(0, min(1, normalizedX)), y: max(0, min(1, normalizedY)))
    }

    private func convertToViewPosition(normalizedPosition: CGPoint, viewSize: CGSize, baseScale: CGFloat) -> CGPoint {
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2

        // Convert from normalized to floor plan coordinates
        let floorPlanX = floorPlanData.boundingBox.minX + normalizedPosition.x * floorPlanData.boundingBox.width
        let floorPlanY = floorPlanData.boundingBox.minY + normalizedPosition.y * floorPlanData.boundingBox.height

        // Apply transformations
        let adjustedX = (floorPlanX - floorPlanData.boundingBox.midX) * scale * baseScale
        let adjustedY = (floorPlanY - floorPlanData.boundingBox.midY) * scale * baseScale

        return CGPoint(
            x: centerX + adjustedX + offset.width,
            y: centerY + adjustedY + offset.height
        )
    }

    // MARK: - Drawing Methods

    private func drawGrid(context: GraphicsContext, boundingBox: CGRect) {
        let gridSpacing: CGFloat = 1.0 // 1 foot grid
        let minX = floor(boundingBox.minX)
        let maxX = ceil(boundingBox.maxX)
        let minY = floor(boundingBox.minY)
        let maxY = ceil(boundingBox.maxY)

        var gridPath = Path()

        // Vertical lines
        var x = minX
        while x <= maxX {
            gridPath.move(to: CGPoint(x: x, y: minY))
            gridPath.addLine(to: CGPoint(x: x, y: maxY))
            x += gridSpacing
        }

        // Horizontal lines
        var y = minY
        while y <= maxY {
            gridPath.move(to: CGPoint(x: minX, y: y))
            gridPath.addLine(to: CGPoint(x: maxX, y: y))
            y += gridSpacing
        }

        context.stroke(gridPath, with: .color(gridColor), lineWidth: 0.02)
    }

    private func drawWall(context: GraphicsContext, wall: FloorPlanWall) {
        var path = Path()
        path.move(to: wall.startPoint)
        path.addLine(to: wall.endPoint)
        context.stroke(path, with: .color(wallColor), lineWidth: 0.15)
    }

    private func drawDoor(context: GraphicsContext, door: FloorPlanDoor) {
        // Calculate door line based on position, width, and rotation
        let halfWidth = door.width / 2
        let dx = cos(door.rotation) * halfWidth
        let dy = sin(door.rotation) * halfWidth

        var path = Path()
        path.move(to: CGPoint(x: door.position.x - dx, y: door.position.y - dy))
        path.addLine(to: CGPoint(x: door.position.x + dx, y: door.position.y + dy))
        context.stroke(path, with: .color(Color.brown), style: StrokeStyle(lineWidth: 0.1, dash: [0.2, 0.1]))
    }

    private func drawWindow(context: GraphicsContext, window: FloorPlanWindow) {
        // Calculate window line based on position, width, and rotation
        let halfWidth = window.width / 2
        let dx = cos(window.rotation) * halfWidth
        let dy = sin(window.rotation) * halfWidth

        var path = Path()
        path.move(to: CGPoint(x: window.position.x - dx, y: window.position.y - dy))
        path.addLine(to: CGPoint(x: window.position.x + dx, y: window.position.y + dy))
        context.stroke(path, with: .color(Color.blue), lineWidth: 0.12)
    }

    private func drawObject(context: GraphicsContext, object: FloorPlanObject) {
        let rect = CGRect(
            x: object.position.x - object.width / 2,
            y: object.position.y - object.depth / 2,
            width: object.width,
            height: object.depth
        )
        context.fill(Path(rect), with: .color(Color.gray.opacity(0.3)))
        context.stroke(Path(rect), with: .color(Color.gray.opacity(0.6)), lineWidth: 0.03)
    }

    private func drawDimensions(context: GraphicsContext) {
        // Draw room dimensions on the edges
        let bbox = floorPlanData.boundingBox
        let widthFt = String(format: "%.1f'", bbox.width)
        let heightFt = String(format: "%.1f'", bbox.height)

        // Width dimension (bottom)
        let widthPoint = CGPoint(x: bbox.midX, y: bbox.maxY + 0.5)
        let widthText = Text(widthFt).font(.system(size: 0.4)).foregroundColor(.secondary)
        context.draw(context.resolve(widthText), at: widthPoint, anchor: .center)

        // Height dimension (right)
        let heightPoint = CGPoint(x: bbox.maxX + 0.5, y: bbox.midY)
        let heightText = Text(heightFt).font(.system(size: 0.4)).foregroundColor(.secondary)
        context.draw(context.resolve(heightText), at: heightPoint, anchor: .center)
    }
}

// MARK: - Damage Marker View

/// Visual marker for a damage annotation on the floor plan
struct DamageMarkerView: View {
    let annotation: DamageAnnotation
    let position: CGPoint
    let isSelected: Bool
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack {
                // Background circle
                Circle()
                    .fill(annotation.damageType.color.opacity(0.2))
                    .frame(width: 36, height: 36)

                // Border
                Circle()
                    .stroke(isSelected ? Color.blue : annotation.damageType.color, lineWidth: isSelected ? 3 : 2)
                    .frame(width: 36, height: 36)

                // Icon
                Image(systemName: annotation.damageType.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(annotation.damageType.color)
            }
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .position(position)
    }
}

// MARK: - Damage Annotation Summary Bar

/// Horizontal scrolling bar showing all damage annotations
struct DamageAnnotationSummaryBar: View {
    let annotations: [DamageAnnotation]
    var onAnnotationTapped: ((DamageAnnotation) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(annotations) { annotation in
                    Button(action: { onAnnotationTapped?(annotation) }) {
                        HStack(spacing: 4) {
                            Image(systemName: annotation.damageType.icon)
                                .foregroundStyle(annotation.damageType.color)

                            Text(annotation.damageType.rawValue)
                                .font(.caption)

                            // Severity indicator
                            Circle()
                                .fill(annotation.severity.color)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemBackground))
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

// MARK: - Quick Damage Annotation Sheet

/// Sheet for quickly adding a new damage annotation at a tapped position
/// P3-019: Enhanced with notes, water height, photos, and voice memo
struct QuickDamageAnnotationSheet: View {
    let position: CGPoint
    let roomId: UUID
    var onSave: ((DamageAnnotation) -> Void)?
    var onCancel: (() -> Void)?

    @State private var damageType: DamageType = .water
    @State private var severity: DamageSeverity = .moderate
    @State private var affectedSurfaces: Set<AffectedSurface> = [.floor]
    @State private var affectedHeightIn: Double?
    @State private var notes: String = ""

    // P3-019: Photo and voice memo state
    @State private var showingPhotoOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var capturedPhotos: [String] = []
    @State private var isRecordingVoice = false
    @State private var voiceMemoPath: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Damage Type") {
                    Picker("Type", selection: $damageType) {
                        ForEach(DamageType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Severity") {
                    Picker("Severity", selection: $severity) {
                        ForEach(DamageSeverity.allCases, id: \.self) { sev in
                            HStack {
                                Circle()
                                    .fill(sev.color)
                                    .frame(width: 12, height: 12)
                                Text(sev.rawValue)
                            }
                            .tag(sev)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Affected Surfaces") {
                    ForEach(AffectedSurface.allCases, id: \.self) { surface in
                        Toggle(isOn: Binding(
                            get: { affectedSurfaces.contains(surface) },
                            set: { isOn in
                                if isOn {
                                    affectedSurfaces.insert(surface)
                                } else {
                                    affectedSurfaces.remove(surface)
                                }
                            }
                        )) {
                            Label(surface.rawValue, systemImage: surface.icon)
                        }
                    }
                }

                // P3-019: Water line height (shows for water damage on walls)
                if damageType == .water && affectedSurfaces.contains(.wall) {
                    Section("Water Line Height") {
                        HStack {
                            Text("Height")
                            Spacer()
                            TextField("inches", value: $affectedHeightIn, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("in")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // P3-019: Notes field
                Section("Notes") {
                    TextField("Describe the damage...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                // P3-019: Media attachments
                Section("Attachments") {
                    // Photo button
                    Button(action: { showingPhotoOptions = true }) {
                        HStack {
                            Label("Add Photo", systemImage: "camera.fill")
                            Spacer()
                            if !capturedPhotos.isEmpty {
                                Text("\(capturedPhotos.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Voice memo button
                    Button(action: toggleVoiceRecording) {
                        HStack {
                            if isRecordingVoice {
                                Label("Stop Recording", systemImage: "stop.circle.fill")
                                    .foregroundStyle(.red)
                            } else {
                                Label("Record Voice Memo", systemImage: "mic.fill")
                            }
                            Spacer()
                            if voiceMemoPath != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Damage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { onCancel?() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let annotation = DamageAnnotation(
                            roomId: roomId,
                            position: position,
                            damageType: damageType,
                            severity: severity,
                            affectedSurfaces: affectedSurfaces,
                            affectedHeightIn: affectedHeightIn,
                            notes: notes,
                            photos: capturedPhotos,
                            audioPath: voiceMemoPath
                        )
                        onSave?(annotation)
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Add Photo", isPresented: $showingPhotoOptions) {
                Button("Take Photo") { showingCamera = true }
                Button("Choose from Library") { showingPhotoLibrary = true }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPickerView { imagePath in
                    if let path = imagePath {
                        capturedPhotos.append(path)
                    }
                    showingCamera = false
                }
            }
            .sheet(isPresented: $showingPhotoLibrary) {
                FloorPlanPhotoLibraryPicker { imagePath in
                    if let path = imagePath {
                        capturedPhotos.append(path)
                    }
                    showingPhotoLibrary = false
                }
            }
        }
        .presentationDetents([.large])
    }

    private func toggleVoiceRecording() {
        if isRecordingVoice {
            // Stop recording and save
            _ = VoiceRecordingService.shared.stopRecording()
            voiceMemoPath = VoiceRecordingService.shared.getRecordingURL()?.path
            isRecordingVoice = false
        } else {
            // Start recording
            do {
                _ = try VoiceRecordingService.shared.startRecording()
                isRecordingVoice = true
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }
}

// MARK: - Floor Plan Damage Annotation Detail Sheet

/// Sheet for viewing and editing an existing damage annotation on a floor plan
/// P3-019: Enhanced with photo and voice memo management
struct FloorPlanDamageDetailSheet: View {
    @Binding var annotation: DamageAnnotation
    var onDelete: (() -> Void)?
    var onDismiss: (() -> Void)?

    @State private var showingDeleteConfirmation = false

    // P3-019: Photo and voice memo state
    @State private var showingPhotoOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var isRecordingVoice = false
    @State private var showingPhotoViewer = false
    @State private var selectedPhotoIndex: Int = 0

    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle("Damage Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .confirmationDialog("Add Photo", isPresented: $showingPhotoOptions) {
                    Button("Take Photo") { showingCamera = true }
                    Button("Choose from Library") { showingPhotoLibrary = true }
                    Button("Cancel", role: .cancel) { }
                }
                .sheet(isPresented: $showingCamera) { cameraSheet }
                .sheet(isPresented: $showingPhotoLibrary) { photoLibrarySheet }
                .fullScreenCover(isPresented: $showingPhotoViewer) { photoViewerCover }
                .alert("Delete Annotation?", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) { onDelete?() }
                } message: {
                    Text("This will permanently remove this damage annotation.")
                }
        }
    }

    // MARK: - Form Content

    private var formContent: some View {
        Form {
            damageTypeSection
            severitySection
            surfacesSection
            waterHeightSection
            notesSection
            photosSection
            voiceMemoSection
            infoSection
            deleteSection
        }
    }

    private var damageTypeSection: some View {
        Section("Damage Type") {
            Picker("Type", selection: $annotation.damageType) {
                ForEach(DamageType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    private var severitySection: some View {
        Section("Severity") {
            Picker("Severity", selection: $annotation.severity) {
                ForEach(DamageSeverity.allCases, id: \.self) { sev in
                    HStack {
                        Circle()
                            .fill(sev.color)
                            .frame(width: 12, height: 12)
                        Text(sev.rawValue)
                    }
                    .tag(sev)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var surfacesSection: some View {
        Section("Affected Surfaces") {
            ForEach(AffectedSurface.allCases, id: \.self) { surface in
                Toggle(isOn: surfaceBinding(for: surface)) {
                    Label(surface.rawValue, systemImage: surface.icon)
                }
            }
        }
    }

    private func surfaceBinding(for surface: AffectedSurface) -> Binding<Bool> {
        Binding(
            get: { annotation.affectedSurfaces.contains(surface) },
            set: { isOn in
                if isOn {
                    annotation.affectedSurfaces.insert(surface)
                } else {
                    annotation.affectedSurfaces.remove(surface)
                }
            }
        )
    }

    @ViewBuilder
    private var waterHeightSection: some View {
        if annotation.damageType == .water && annotation.affectedSurfaces.contains(.wall) {
            Section("Water Line Height") {
                HStack {
                    Text("Height")
                    Spacer()
                    TextField("inches", value: $annotation.affectedHeightIn, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("in")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Add notes...", text: $annotation.notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var photosSection: some View {
        Section("Photos") {
            if !annotation.photos.isEmpty {
                photoThumbnailsRow
            }
            Button(action: { showingPhotoOptions = true }) {
                Label("Add Photo", systemImage: "camera.fill")
            }
        }
    }

    private var photoThumbnailsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(annotation.photos.enumerated()), id: \.offset) { index, photoPath in
                    PhotoThumbnailView(
                        photoPath: photoPath,
                        onTap: {
                            selectedPhotoIndex = index
                            showingPhotoViewer = true
                        },
                        onDelete: {
                            annotation.photos.remove(at: index)
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var voiceMemoSection: some View {
        Section("Voice Memo") {
            if let audioPath = annotation.audioPath {
                voiceMemoRow(audioPath: audioPath)
            }
            Button(action: toggleVoiceRecording) {
                if isRecordingVoice {
                    Label("Stop Recording", systemImage: "stop.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    Label("Record Voice Memo", systemImage: "mic.fill")
                }
            }
        }
    }

    private func voiceMemoRow(audioPath: String) -> some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(.blue)
            Text("Voice memo attached")
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: {
                if let url = URL(fileURLWithPath: audioPath) as URL? {
                    try? VoiceRecordingService.shared.playRecording(url: url)
                }
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            Button(action: { annotation.audioPath = nil }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
    }

    private var infoSection: some View {
        Section("Info") {
            LabeledContent("Created") {
                Text(annotation.createdAt, style: .date)
            }
            LabeledContent("Last Updated") {
                Text(annotation.updatedAt, style: .relative)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                Label("Delete Annotation", systemImage: "trash")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                annotation.updatedAt = Date()
                onDismiss?()
            }
        }
    }

    // MARK: - Sheets

    private var cameraSheet: some View {
        CameraPickerView { imagePath in
            if let path = imagePath {
                annotation.photos.append(path)
            }
            showingCamera = false
        }
    }

    private var photoLibrarySheet: some View {
        FloorPlanPhotoLibraryPicker { imagePath in
            if let path = imagePath {
                annotation.photos.append(path)
            }
            showingPhotoLibrary = false
        }
    }

    @ViewBuilder
    private var photoViewerCover: some View {
        if !annotation.photos.isEmpty {
            PhotoViewerSheet(
                photos: annotation.photos,
                initialIndex: selectedPhotoIndex,
                onDismiss: { showingPhotoViewer = false }
            )
        }
    }

    private func toggleVoiceRecording() {
        if isRecordingVoice {
            _ = VoiceRecordingService.shared.stopRecording()
            annotation.audioPath = VoiceRecordingService.shared.getRecordingURL()?.path
            isRecordingVoice = false
        } else {
            do {
                _ = try VoiceRecordingService.shared.startRecording()
                isRecordingVoice = true
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }
}

// MARK: - Photo Thumbnail View

/// Thumbnail view for a photo with delete option
struct PhotoThumbnailView: View {
    let photoPath: String
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: { onTap?() }) {
                if let image = loadImage(from: photoPath) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                        .cornerRadius(8)
                }
            }
            .buttonStyle(.plain)

            Button(action: { onDelete?() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white, .red)
            }
            .offset(x: 4, y: -4)
        }
    }

    private func loadImage(from path: String) -> UIImage? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fullPath = documentsPath.appendingPathComponent(path)
        return UIImage(contentsOfFile: fullPath.path)
    }
}

// MARK: - Photo Viewer Sheet

/// Full-screen photo viewer with swipe navigation
struct PhotoViewerSheet: View {
    let photos: [String]
    let initialIndex: Int
    var onDismiss: (() -> Void)?

    @State private var currentIndex: Int

    init(photos: [String], initialIndex: Int, onDismiss: (() -> Void)?) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photoPath in
                    if let image = loadImage(from: photoPath) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .tag(index)
                    } else {
                        Color.gray
                            .overlay {
                                Text("Unable to load image")
                                    .foregroundStyle(.secondary)
                            }
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .navigationTitle("\(currentIndex + 1) of \(photos.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss?()
                    }
                }
            }
        }
    }

    private func loadImage(from path: String) -> UIImage? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fullPath = documentsPath.appendingPathComponent(path)
        return UIImage(contentsOfFile: fullPath.path)
    }
}

// MARK: - Camera Picker View

/// UIImagePickerController wrapper for taking photos with camera
/// P3-019: Camera capture for damage documentation
struct CameraPickerView: UIViewControllerRepresentable {
    var onImageCaptured: ((String?) -> Void)?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                let savedPath = saveImageToDocuments(image)
                parent.onImageCaptured?(savedPath)
            } else {
                parent.onImageCaptured?(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onImageCaptured?(nil)
        }

        private func saveImageToDocuments(_ image: UIImage) -> String? {
            guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }

            let filename = "damage_photo_\(UUID().uuidString).jpg"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filePath = documentsPath.appendingPathComponent(filename)

            do {
                try data.write(to: filePath)
                return filename
            } catch {
                print("Error saving image: \(error)")
                return nil
            }
        }
    }
}

// MARK: - Floor Plan Photo Library Picker View

/// PHPickerViewController wrapper for selecting photos from library
/// P3-019: Photo library access for damage documentation
import PhotosUI

struct FloorPlanPhotoLibraryPicker: UIViewControllerRepresentable {
    var onImageSelected: ((String?) -> Void)?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: FloorPlanPhotoLibraryPicker

        init(_ parent: FloorPlanPhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.onImageSelected?(nil)
                return
            }

            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        let savedPath = self?.saveImageToDocuments(image)
                        self?.parent.onImageSelected?(savedPath)
                    } else {
                        self?.parent.onImageSelected?(nil)
                    }
                }
            }
        }

        private func saveImageToDocuments(_ image: UIImage) -> String? {
            guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }

            let filename = "damage_photo_\(UUID().uuidString).jpg"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filePath = documentsPath.appendingPathComponent(filename)

            do {
                try data.write(to: filePath)
                return filename
            } catch {
                print("Error saving image: \(error)")
                return nil
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var annotations: [DamageAnnotation] = [
        DamageAnnotation(
            position: CGPoint(x: 0.3, y: 0.4),
            damageType: .water,
            severity: .moderate,
            affectedSurfaces: [.floor, .wall]
        ),
        DamageAnnotation(
            position: CGPoint(x: 0.7, y: 0.6),
            damageType: .mold,
            severity: .light,
            affectedSurfaces: [.wall]
        )
    ]

    // Sample room
    let sampleRoom = Room(
        name: "Kitchen",
        category: .kitchen,
        floor: .first,
        lengthIn: 144,
        widthIn: 120,
        heightIn: 96
    )

    // Sample floor plan
    let sampleWalls = [
        FloorPlanWall(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 12, y: 0), length: 12, height: 8),
        FloorPlanWall(startPoint: CGPoint(x: 12, y: 0), endPoint: CGPoint(x: 12, y: 10), length: 10, height: 8),
        FloorPlanWall(startPoint: CGPoint(x: 12, y: 10), endPoint: CGPoint(x: 0, y: 10), length: 12, height: 8),
        FloorPlanWall(startPoint: CGPoint(x: 0, y: 10), endPoint: CGPoint(x: 0, y: 0), length: 10, height: 8)
    ]

    let sampleData = FloorPlanData(
        walls: sampleWalls,
        doors: [],
        windows: [],
        objects: [],
        boundingBox: CGRect(x: -1, y: -1, width: 14, height: 12),
        squareFootage: 120,
        linearFeet: 44
    )

    FloorPlanDamageAnnotationView(
        room: sampleRoom,
        floorPlanData: sampleData,
        annotations: $annotations
    )
}
