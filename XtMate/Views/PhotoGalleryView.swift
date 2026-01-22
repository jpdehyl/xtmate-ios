//
//  PhotoGalleryView.swift
//  XtMate
//
//  Phase 3B Enhancement: Photo gallery for viewing captured photos
//  Displays photos grouped by type with thumbnails and detail view
//

import SwiftUI

// MARK: - Photo Gallery View

/// Displays a gallery of photos for a room, estimate, or annotation
/// Supports filtering by type, viewing details, and managing photos
@available(iOS 16.0, *)
struct PhotoGalleryView: View {
    let estimateId: UUID?
    let roomId: UUID?
    let annotationId: UUID?
    let title: String

    @StateObject private var photoService = PhotoService.shared
    @State private var selectedFilter: PhotoType?
    @State private var selectedPhoto: Photo?
    @State private var showingPhotoDetail = false
    @State private var showingPhotoCapture = false
    @State private var gridColumns = 3

    init(
        estimateId: UUID? = nil,
        roomId: UUID? = nil,
        annotationId: UUID? = nil,
        title: String = "Photos"
    ) {
        self.estimateId = estimateId
        self.roomId = roomId
        self.annotationId = annotationId
        self.title = title
    }

    // Filter photos based on context
    var filteredPhotos: [Photo] {
        var photos = photoService.photos

        // Filter by context
        if let annotationId = annotationId {
            photos = photos.forAnnotation(annotationId)
        } else if let roomId = roomId {
            photos = photos.forRoom(roomId)
        } else if let estimateId = estimateId {
            photos = photos.forEstimate(estimateId)
        }

        // Filter by type if selected
        if let filter = selectedFilter {
            photos = photos.ofType(filter)
        }

        return photos.sortedByDate
    }

    // Group photos by type for section headers
    var photosByType: [(PhotoType, [Photo])] {
        let grouped = Dictionary(grouping: filteredPhotos) { $0.type }
        return PhotoType.allCases.compactMap { type in
            guard let photos = grouped[type], !photos.isEmpty else { return nil }
            return (type, photos)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter chips
                PhotoFilterBar(
                    selectedFilter: $selectedFilter,
                    photoCounts: photoCountsByType
                )
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(Color(uiColor: .secondarySystemBackground))

                // Photo grid or empty state
                if filteredPhotos.isEmpty {
                    EmptyPhotoState(onCapture: { showingPhotoCapture = true })
                } else {
                    ScrollView {
                        if selectedFilter == nil {
                            // Grouped by type
                            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                                ForEach(photosByType, id: \.0) { type, photos in
                                    PhotoTypeSection(
                                        type: type,
                                        photos: photos,
                                        columns: gridColumns,
                                        onPhotoTap: { photo in
                                            selectedPhoto = photo
                                            showingPhotoDetail = true
                                        }
                                    )
                                }
                            }
                            .padding(AppTheme.Spacing.lg)
                        } else {
                            // Flat grid when filtered
                            PhotoGrid(
                                photos: filteredPhotos,
                                columns: gridColumns,
                                onPhotoTap: { photo in
                                    selectedPhoto = photo
                                    showingPhotoDetail = true
                                }
                            )
                            .padding(AppTheme.Spacing.lg)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingPhotoCapture = true }) {
                        Image(systemName: "camera.fill")
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Picker("Grid Size", selection: $gridColumns) {
                            Label("Small", systemImage: "square.grid.3x3").tag(4)
                            Label("Medium", systemImage: "square.grid.2x2").tag(3)
                            Label("Large", systemImage: "rectangle.grid.1x2").tag(2)
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            }
            .fullScreenCover(isPresented: $showingPhotoCapture) {
                PhotoCaptureView(
                    estimateId: estimateId,
                    roomId: roomId,
                    annotationId: annotationId,
                    onPhotosCaptured: { _ in
                        showingPhotoCapture = false
                    }
                )
            }
            .sheet(isPresented: $showingPhotoDetail) {
                if let photo = selectedPhoto {
                    PhotoDetailView(
                        photo: photo,
                        allPhotos: filteredPhotos,
                        onDelete: {
                            Task {
                                try? await photoService.deletePhoto(photo)
                                showingPhotoDetail = false
                            }
                        }
                    )
                }
            }
        }
    }

    // Count photos by type for filter badges
    private var photoCountsByType: [PhotoType: Int] {
        var basephotos = photoService.photos

        if let annotationId = annotationId {
            basephotos = basephotos.forAnnotation(annotationId)
        } else if let roomId = roomId {
            basephotos = basephotos.forRoom(roomId)
        } else if let estimateId = estimateId {
            basephotos = basephotos.forEstimate(estimateId)
        }

        var counts: [PhotoType: Int] = [:]
        for type in PhotoType.allCases {
            let count = basephotos.ofType(type).count
            if count > 0 {
                counts[type] = count
            }
        }
        return counts
    }
}

// MARK: - Photo Filter Bar

@available(iOS 16.0, *)
struct PhotoFilterBar: View {
    @Binding var selectedFilter: PhotoType?
    let photoCounts: [PhotoType: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                // All photos chip
                FilterChip(
                    label: "All",
                    count: photoCounts.values.reduce(0, +),
                    isSelected: selectedFilter == nil,
                    color: .blue
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = nil
                    }
                }

                // Type-specific chips
                ForEach(PhotoType.allCases) { type in
                    if let count = photoCounts[type] {
                        FilterChip(
                            label: type.displayName,
                            count: count,
                            isSelected: selectedFilter == type,
                            color: type.color
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedFilter = selectedFilter == type ? nil : type
                            }
                        }
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }
    }
}

@available(iOS 16.0, *)
struct FilterChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: {
            action()
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.impactOccurred()
        }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : color.opacity(0.2))
                    .clipShape(Capsule())
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : color.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Photo Type Section

@available(iOS 16.0, *)
struct PhotoTypeSection: View {
    let type: PhotoType
    let photos: [Photo]
    let columns: Int
    let onPhotoTap: (Photo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .foregroundColor(type.color)

                Text(type.displayName)
                    .font(.headline)

                Text("\(photos.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }

            // Photo grid
            PhotoGrid(
                photos: photos,
                columns: columns,
                onPhotoTap: onPhotoTap
            )
        }
    }
}

// MARK: - Photo Grid

@available(iOS 16.0, *)
struct PhotoGrid: View {
    let photos: [Photo]
    let columns: Int
    let onPhotoTap: (Photo) -> Void

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: AppTheme.Spacing.sm) {
            ForEach(photos) { photo in
                PhotoThumbnail(photo: photo)
                    .onTapGesture {
                        onPhotoTap(photo)
                    }
            }
        }
    }
}

// MARK: - Photo Thumbnail

@available(iOS 16.0, *)
struct PhotoThumbnail: View {
    let photo: Photo
    @StateObject private var photoService = PhotoService.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Thumbnail image
            if let thumbnail = photoService.loadThumbnail(photo) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(uiColor: .systemGray5))
                    .aspectRatio(1, contentMode: .fill)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
            }

            // Sync status indicator
            HStack(spacing: 4) {
                // Type badge
                Image(systemName: photo.type.icon)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(photo.type.color)
                    .clipShape(Circle())

                // Sync status
                if photo.syncStatus != .uploaded {
                    Image(systemName: photo.syncStatus.icon)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(photo.syncStatus.color)
                        .clipShape(Circle())
                }
            }
            .padding(4)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
        )
    }
}

// MARK: - Empty Photo State

@available(iOS 16.0, *)
struct EmptyPhotoState: View {
    let onCapture: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Photos Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Capture photos to document the claim")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onCapture) {
                Label("Take Photos", systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            .padding(.top, AppTheme.Spacing.md)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Photo Detail View

@available(iOS 16.0, *)
struct PhotoDetailView: View {
    let photo: Photo
    let allPhotos: [Photo]
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var photoService = PhotoService.shared
    @State private var currentIndex: Int = 0
    @State private var caption: String = ""
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var scale: CGFloat = 1.0

    init(photo: Photo, allPhotos: [Photo], onDelete: @escaping () -> Void) {
        self.photo = photo
        self.allPhotos = allPhotos
        self.onDelete = onDelete
        _currentIndex = State(initialValue: allPhotos.firstIndex(where: { $0.id == photo.id }) ?? 0)
        _caption = State(initialValue: photo.caption)
    }

    var currentPhoto: Photo {
        allPhotos.indices.contains(currentIndex) ? allPhotos[currentIndex] : photo
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Photo viewer with swipe
                    TabView(selection: $currentIndex) {
                        ForEach(Array(allPhotos.enumerated()), id: \.element.id) { index, photo in
                            ZStack {
                                Color.black

                                if let image = photoService.loadPhoto(photo) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .scaleEffect(scale)
                                        .gesture(
                                            MagnificationGesture()
                                                .onChanged { value in
                                                    scale = value
                                                }
                                                .onEnded { _ in
                                                    withAnimation {
                                                        scale = max(1.0, min(scale, 3.0))
                                                    }
                                                }
                                        )
                                        .onTapGesture(count: 2) {
                                            withAnimation {
                                                scale = scale > 1.0 ? 1.0 : 2.0
                                            }
                                        }
                                } else {
                                    ProgressView()
                                        .tint(.white)
                                }
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .frame(height: geometry.size.height * 0.65)
                    .background(Color.black)

                    // Photo info panel
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            // Type and date
                            HStack {
                                Label(currentPhoto.type.displayName, systemImage: currentPhoto.type.icon)
                                    .font(.subheadline)
                                    .foregroundColor(currentPhoto.type.color)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(currentPhoto.type.color.opacity(0.15))
                                    .clipShape(Capsule())

                                Spacer()

                                Text(currentPhoto.formattedDate)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            // Caption
                            if isEditing {
                                TextField("Add a caption...", text: $caption, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(3...6)
                            } else if !currentPhoto.caption.isEmpty {
                                Text(currentPhoto.caption)
                                    .font(.body)
                            } else {
                                Text("No caption")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }

                            // Location if available
                            if currentPhoto.hasLocation {
                                Label(
                                    String(format: "%.4f, %.4f", currentPhoto.latitude ?? 0, currentPhoto.longitude ?? 0),
                                    systemImage: "location.fill"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            // Sync status
                            HStack {
                                Image(systemName: currentPhoto.syncStatus.icon)
                                    .foregroundColor(currentPhoto.syncStatus.color)
                                Text(currentPhoto.syncStatus.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            // Counter
                            if allPhotos.count > 1 {
                                Text("\(currentIndex + 1) of \(allPhotos.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding(AppTheme.Spacing.lg)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        if isEditing {
                            saveCaption()
                        }
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            isEditing.toggle()
                            if !isEditing {
                                saveCaption()
                            }
                        }) {
                            Label(isEditing ? "Save Caption" : "Edit Caption", systemImage: "pencil")
                        }

                        Button(action: sharePhoto) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Divider()

                        Button(role: .destructive, action: {
                            showingDeleteConfirmation = true
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Delete Photo?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This photo will be permanently deleted.")
            }
        }
    }

    private func saveCaption() {
        var updatedPhoto = currentPhoto
        updatedPhoto.caption = caption
        photoService.updatePhoto(updatedPhoto)

        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
    }

    private func sharePhoto() {
        guard let image = photoService.loadPhoto(currentPhoto) else { return }

        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
#Preview {
    PhotoGalleryView(
        estimateId: UUID(),
        roomId: nil,
        title: "Kitchen Photos"
    )
}
#endif
