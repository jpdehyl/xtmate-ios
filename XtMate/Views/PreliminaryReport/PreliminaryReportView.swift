//
//  PreliminaryReportView.swift
//  XtMate
//
//  Created by XtMate on 2026-01-17.
//
//  Main view for editing and reviewing a Preliminary Report.
//  Allows PM to review AI-generated content and make edits before submission.
//

import SwiftUI

@available(iOS 16.0, *)
struct PreliminaryReportView: View {
    @Binding var report: PreliminaryReport
    @ObservedObject private var reportService = PreliminaryReportService.shared

    @State private var selectedSection: ReportSection = .claimLog
    @State private var showingPhotoDetail: PreliminaryReportPhoto?
    @State private var showingAddPhoto = false
    @State private var showingPreview = false
    @State private var showingMaterialPicker = false
    @State private var selectedRoomDamageIndex: Int?

    @Environment(\.dismiss) private var dismiss

    enum ReportSection: String, CaseIterable {
        case claimLog = "Claim Log"
        case emergencyServices = "Emergency Services"
        case causeOfLoss = "Cause of Loss"
        case structuralDamage = "Structural Damage"
        case photos = "Photos"
        case costs = "Repair Costs"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section tabs
                sectionTabs

                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        switch selectedSection {
                        case .claimLog:
                            claimLogSection
                        case .emergencyServices:
                            emergencyServicesSection
                        case .causeOfLoss:
                            causeOfLossSection
                        case .structuralDamage:
                            structuralDamageSection
                        case .photos:
                            photosSection
                        case .costs:
                            costsSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Preliminary Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Preview") {
                        showingPreview = true
                    }
                }
            }
            .sheet(item: $showingPhotoDetail) { photo in
                PrelimReportPhotoDetailView(photo: photo, onUpdate: { updated in
                    if let index = report.photos.firstIndex(where: { $0.id == updated.id }) {
                        report.photos[index] = updated
                    }
                })
            }
            .sheet(isPresented: $showingAddPhoto) {
                AddPhotoSheet(onAdd: { image, roomName, caption in
                    Task {
                        try? await reportService.addManualPhoto(image, roomName: roomName, caption: caption)
                        if let updated = reportService.currentReport {
                            report = updated
                        }
                    }
                })
            }
            .sheet(isPresented: $showingPreview) {
                PreliminaryReportPreviewView(report: report)
            }
            .sheet(isPresented: $showingMaterialPicker) {
                if let index = selectedRoomDamageIndex {
                    PrelimReportMaterialPickerSheet(
                        roomCategory: report.roomDamage[index].roomCategory,
                        selectedMaterials: report.roomDamage[index].affectedMaterials.map { $0.material },
                        onSave: { materials in
                            report.roomDamage[index].affectedMaterials = materials.map {
                                AffectedMaterial(material: $0, severity: .moderate)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Section Tabs

    private var sectionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ReportSection.allCases, id: \.self) { section in
                    Button {
                        withAnimation {
                            selectedSection = section
                        }
                    } label: {
                        Text(section.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedSection == section ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedSection == section ?
                                Color.accentColor : Color.gray.opacity(0.15)
                            )
                            .foregroundColor(
                                selectedSection == section ?
                                .white : .primary
                            )
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Claim Log Section

    private var claimLogSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Claim Log", icon: "calendar")

            FormCard {
                DatePickerRow(
                    label: "Claim Received",
                    date: Binding(
                        get: { report.claimReceivedDate ?? Date() },
                        set: { report.claimReceivedDate = $0 }
                    )
                )

                Divider()

                DatePickerRow(
                    label: "Insured Contacted",
                    date: Binding(
                        get: { report.insuredContactedDate ?? Date() },
                        set: { report.insuredContactedDate = $0 }
                    )
                )

                Divider()

                DatePickerRow(
                    label: "Site Inspected",
                    date: Binding(
                        get: { report.siteInspectedDate ?? Date() },
                        set: { report.siteInspectedDate = $0 }
                    )
                )
            }
        }
    }

    // MARK: - Emergency Services Section

    private var emergencyServicesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Emergency Services", icon: "bolt.fill")

            FormCard {
                Toggle("Emergency Work Completed", isOn: $report.emergencyServicesCompleted)

                if report.emergencyServicesCompleted {
                    Divider()

                    Toggle("By Another Contractor", isOn: $report.emergencyServicesByOther)

                    if !report.emergencyServicesByOther {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextEditor(text: $report.emergencyServicesDescription)
                                .frame(minHeight: 100)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cause of Loss Section

    private var causeOfLossSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Cause of Loss", icon: "exclamationmark.triangle.fill")

            FormCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Loss Type")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(CauseOfLossType.allCases, id: \.self) { type in
                            LossTypeButton(
                                type: type,
                                isSelected: report.causeOfLossType == type,
                                action: { report.causeOfLossType = type }
                            )
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $report.causeOfLoss)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Structural Damage Section

    private var structuralDamageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Resulting Structural Damage", icon: "building.2.fill")

            ForEach(Array(report.roomDamage.enumerated()), id: \.element.id) { index, damage in
                RoomDamageCard(
                    damage: damage,
                    onEdit: {
                        selectedRoomDamageIndex = index
                        showingMaterialPicker = true
                    },
                    onDelete: {
                        report.roomDamage.remove(at: index)
                    }
                )
            }

            Button {
                let newRoom = RoomDamageEntry(
                    roomName: "New Room",
                    roomCategory: .other
                )
                report.roomDamage.append(newRoom)
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Room")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Photos Section

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader(title: "Photos", icon: "photo.fill")
                Spacer()
                Button {
                    showingAddPhoto = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }

            // Group photos by room
            let groupedPhotos = Dictionary(grouping: report.photos) { $0.roomName }

            ForEach(groupedPhotos.keys.sorted(), id: \.self) { roomName in
                VStack(alignment: .leading, spacing: 12) {
                    Text(roomName.isEmpty ? "Unassigned" : roomName)
                        .font(.headline)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(groupedPhotos[roomName] ?? []) { photo in
                            PrelimReportPhotoThumbnail(photo: photo) {
                                showingPhotoDetail = photo
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

            if report.photos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No photos yet")
                        .foregroundColor(.secondary)
                    Text("Photos from video walkthrough will appear here, or add photos manually.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Costs Section

    private var costsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Repair Costs", icon: "dollarsign.circle.fill")

            // Auto-calculate costs
            let costs = reportService.estimateCosts(for: report)

            FormCard {
                VStack(spacing: 16) {
                    CostRangeRow(
                        label: "Repairs",
                        minValue: Binding(
                            get: { report.repairCostMin ?? costs.repairMin },
                            set: { report.repairCostMin = $0 }
                        ),
                        maxValue: Binding(
                            get: { report.repairCostMax ?? costs.repairMax },
                            set: { report.repairCostMax = $0 }
                        )
                    )

                    Divider()

                    CostRangeRow(
                        label: "Contents",
                        minValue: Binding(
                            get: { report.contentsCostMin ?? costs.contentsMin },
                            set: { report.contentsCostMin = $0 }
                        ),
                        maxValue: Binding(
                            get: { report.contentsCostMax ?? costs.contentsMax },
                            set: { report.contentsCostMax = $0 }
                        )
                    )

                    if report.emergencyServicesCompleted && !report.emergencyServicesByOther {
                        Divider()

                        HStack {
                            Text("Emergency")
                                .foregroundColor(.secondary)
                            Spacer()
                            TextField("$0", value: $report.emergencyCost, format: .currency(code: "USD"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }
                    }
                }
            }

            // Total summary
            let totalMin = (report.repairCostMin ?? costs.repairMin) + (report.contentsCostMin ?? costs.contentsMin) + (report.emergencyCost ?? 0)
            let totalMax = (report.repairCostMax ?? costs.repairMax) + (report.contentsCostMax ?? costs.contentsMax) + (report.emergencyCost ?? 0)

            HStack {
                Text("Estimated Total")
                    .font(.headline)
                Spacer()
                Text("\(totalMin, format: .currency(code: "USD")) - \(totalMax, format: .currency(code: "USD"))")
                    .font(.headline)
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Supporting Views

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
        }
    }
}

private struct FormCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

private struct DatePickerRow: View {
    let label: String
    @Binding var date: Date

    var body: some View {
        DatePicker(label, selection: $date, displayedComponents: [.date, .hourAndMinute])
    }
}

private struct LossTypeButton: View {
    let type: CauseOfLossType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.title2)
                Text(type.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(8)
        }
    }
}

private struct RoomDamageCard: View {
    let damage: RoomDamageEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: damage.roomCategory.icon)
                    .foregroundColor(.accentColor)
                Text(damage.roomName)
                    .font(.headline)
                Spacer()

                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash.circle")
                        .font(.title3)
                        .foregroundColor(.red)
                }
            }

            if damage.affectedMaterials.isEmpty {
                Text("No damage recorded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                Text(damage.fullDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Material chips
            FlowLayout(spacing: 8) {
                ForEach(damage.affectedMaterials) { material in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(severityColor(material.severity))
                            .frame(width: 8, height: 8)
                        Text(material.material.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .cornerRadius(16)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func severityColor(_ severity: DamageSeverity) -> Color {
        severity.color
    }
}

private struct PrelimReportPhotoThumbnail: View {
    let photo: PreliminaryReportPhoto
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let data = photo.thumbnailData ?? photo.imageData,
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                }

                if photo.showsDamage {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .cornerRadius(4)
                            Spacer()
                        }
                    }
                    .padding(4)
                }
            }
            .cornerRadius(8)
        }
    }
}

private struct CostRangeRow: View {
    let label: String
    @Binding var minValue: Double
    @Binding var maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)

            HStack {
                TextField("Min", value: $minValue, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                Text("-")
                    .foregroundColor(.secondary)

                TextField("Max", value: $maxValue, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

// MARK: - Flow Layout for Material Chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, containerWidth: bounds.width).offsets

        for (subview, offset) in zip(subviews, offsets) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX - spacing)
        }

        return (offsets, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}

// MARK: - Prelim Report Photo Detail View

@available(iOS 16.0, *)
struct PrelimReportPhotoDetailView: View {
    let photo: PreliminaryReportPhoto
    let onUpdate: (PreliminaryReportPhoto) -> Void

    @State private var editedPhoto: PreliminaryReportPhoto
    @Environment(\.dismiss) private var dismiss

    init(photo: PreliminaryReportPhoto, onUpdate: @escaping (PreliminaryReportPhoto) -> Void) {
        self.photo = photo
        self.onUpdate = onUpdate
        _editedPhoto = State(initialValue: photo)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Photo
                    if let data = photo.imageData,
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                    }

                    // Room assignment
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Room")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Room name", text: $editedPhoto.roomName)
                            .textFieldStyle(.roundedBorder)

                        Picker("Category", selection: $editedPhoto.roomCategory) {
                            ForEach(RoomCategory.allCases, id: \.self) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Caption
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Caption")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Describe this photo...", text: $editedPhoto.caption, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Damage toggle
                    Toggle("Shows Damage", isOn: $editedPhoto.showsDamage)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                    // AI Analysis (if available)
                    if let analysis = photo.aiAnalysis {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AI Analysis")
                                .font(.headline)

                            if !analysis.detectedDamage.isEmpty {
                                ForEach(analysis.detectedDamage.indices, id: \.self) { index in
                                    let damage = analysis.detectedDamage[index]
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        VStack(alignment: .leading) {
                                            Text("\(damage.damageType.rawValue) - \(damage.severity.rawValue)")
                                                .font(.subheadline)
                                            Text(damage.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("\(Int(damage.confidence * 100))%")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            if !analysis.detectedMaterials.isEmpty {
                                Text("Materials: \(analysis.detectedMaterials.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Photo Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        onUpdate(editedPhoto)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Add Photo Sheet

@available(iOS 16.0, *)
struct AddPhotoSheet: View {
    let onAdd: (UIImage, String, String) -> Void

    @State private var selectedImage: UIImage?
    @State private var roomName = ""
    @State private var caption = ""
    @State private var showingImagePicker = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .onTapGesture {
                                showingImagePicker = true
                            }
                    } else {
                        Button {
                            showingImagePicker = true
                        } label: {
                            HStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.largeTitle)
                                    Text("Tap to add photo")
                                }
                                .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(40)
                        }
                    }
                }

                Section("Details") {
                    TextField("Room name", text: $roomName)
                    TextField("Caption (optional)", text: $caption)
                }
            }
            .navigationTitle("Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        if let image = selectedImage {
                            onAdd(image, roomName, caption)
                            dismiss()
                        }
                    }
                    .disabled(selectedImage == nil || roomName.isEmpty)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage)
            }
        }
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Prelim Report Material Picker Sheet

@available(iOS 16.0, *)
struct PrelimReportMaterialPickerSheet: View {
    let roomCategory: RoomCategory
    let selectedMaterials: [MaterialType]
    let onSave: ([MaterialType]) -> Void

    @State private var selected: Set<MaterialType>
    @Environment(\.dismiss) private var dismiss

    init(roomCategory: RoomCategory, selectedMaterials: [MaterialType], onSave: @escaping ([MaterialType]) -> Void) {
        self.roomCategory = roomCategory
        self.selectedMaterials = selectedMaterials
        self.onSave = onSave
        _selected = State(initialValue: Set(selectedMaterials))
    }

    var body: some View {
        NavigationStack {
            List {
                // Suggested materials for this room type
                Section("Common for \(roomCategory.rawValue)") {
                    ForEach(roomCategory.typicalMaterials, id: \.self) { material in
                        materialRow(material)
                    }
                }

                // All other materials
                Section("Other Materials") {
                    ForEach(MaterialType.allCases.filter { !roomCategory.typicalMaterials.contains($0) }, id: \.self) { material in
                        materialRow(material)
                    }
                }
            }
            .navigationTitle("Affected Materials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        onSave(Array(selected))
                        dismiss()
                    }
                }
            }
        }
    }

    private func materialRow(_ material: MaterialType) -> some View {
        Button {
            if selected.contains(material) {
                selected.remove(material)
            } else {
                selected.insert(material)
            }
        } label: {
            HStack {
                Text(material.displayName.capitalized)
                    .foregroundColor(.primary)
                Spacer()
                if selected.contains(material) {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

// Note: RoomCategory.icon is defined in ContentView.swift
