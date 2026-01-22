import SwiftUI
import PhotosUI
import UIKit

// MARK: - Task Photo Capture View

/// Photo capture component for work order task completion
/// Supports camera capture and photo library selection
/// Per UX requirements: 56pt touch targets for field staff use
@available(iOS 16.0, *)
struct TaskPhotoCapture: View {
    @Binding var selectedPhotos: [UIImage]
    let maxPhotos: Int
    let onPhotoAdded: ((UIImage) -> Void)?

    @State private var showingActionSheet = false
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var showingPhotoViewer = false
    @State private var selectedPhotoIndex = 0

    init(
        selectedPhotos: Binding<[UIImage]>,
        maxPhotos: Int = 5,
        onPhotoAdded: ((UIImage) -> Void)? = nil
    ) {
        self._selectedPhotos = selectedPhotos
        self.maxPhotos = maxPhotos
        self.onPhotoAdded = onPhotoAdded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Header
            HStack {
                Image(systemName: "camera.fill")
                    .font(.body)
                    .foregroundColor(.blue)
                Text("Completion Photos")
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                if !selectedPhotos.isEmpty {
                    Text("\(selectedPhotos.count)/\(maxPhotos)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Photo grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: AppTheme.Spacing.sm) {
                // Add photo button (if under max)
                if selectedPhotos.count < maxPhotos {
                    AddPhotoButton(action: { showingActionSheet = true })
                }

                // Existing photos
                ForEach(Array(selectedPhotos.enumerated()), id: \.offset) { index, image in
                    TaskPhotoThumbnail(
                        image: image,
                        onTap: {
                            selectedPhotoIndex = index
                            showingPhotoViewer = true
                        },
                        onDelete: {
                            _ = withAnimation {
                                selectedPhotos.remove(at: index)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    )
                }
            }
        }
        .confirmationDialog("Add Photo", isPresented: $showingActionSheet, titleVisibility: .visible) {
            Button("Take Photo") {
                showingCamera = true
            }
            Button("Choose from Library") {
                showingLibrary = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(onImageCaptured: handleNewPhoto)
        }
        .sheet(isPresented: $showingLibrary) {
            PhotoLibraryPicker(onImageSelected: handleNewPhoto)
        }
        .sheet(isPresented: $showingPhotoViewer) {
            TaskPhotoViewerSheet(
                photos: selectedPhotos,
                initialIndex: selectedPhotoIndex,
                onDelete: { index in
                    _ = withAnimation {
                        selectedPhotos.remove(at: index)
                    }
                }
            )
        }
    }

    private func handleNewPhoto(_ image: UIImage) {
        withAnimation {
            selectedPhotos.append(image)
        }
        onPhotoAdded?(image)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Add Photo Button

@available(iOS 16.0, *)
private struct AddPhotoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
                Text("Add")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Task Photo Thumbnail

@available(iOS 16.0, *)
private struct TaskPhotoThumbnail: View {
    let image: UIImage
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
            }
            .buttonStyle(PlainButtonStyle())

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 24, height: 24)
                    )
            }
            .offset(x: 6, y: -6)
        }
    }
}

// MARK: - Camera View (UIImagePickerController wrapper)

@available(iOS 16.0, *)
struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                // Compress image for upload
                let compressed = compressImage(image, maxSizeKB: 1024)
                parent.onImageCaptured(compressed)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        private func compressImage(_ image: UIImage, maxSizeKB: Int) -> UIImage {
            var compression: CGFloat = 1.0
            let maxBytes = maxSizeKB * 1024

            guard var imageData = image.jpegData(compressionQuality: compression) else {
                return image
            }

            while imageData.count > maxBytes && compression > 0.1 {
                compression -= 0.1
                if let newData = image.jpegData(compressionQuality: compression) {
                    imageData = newData
                }
            }

            return UIImage(data: imageData) ?? image
        }
    }
}

// MARK: - Photo Library Picker (PHPicker wrapper)

@available(iOS 16.0, *)
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard let result = results.first else { return }

            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        // Compress image for upload
                        let compressed = self?.compressImage(image, maxSizeKB: 1024) ?? image
                        self?.parent.onImageSelected(compressed)
                    }
                }
            }
        }

        private func compressImage(_ image: UIImage, maxSizeKB: Int) -> UIImage {
            var compression: CGFloat = 1.0
            let maxBytes = maxSizeKB * 1024

            guard var imageData = image.jpegData(compressionQuality: compression) else {
                return image
            }

            while imageData.count > maxBytes && compression > 0.1 {
                compression -= 0.1
                if let newData = image.jpegData(compressionQuality: compression) {
                    imageData = newData
                }
            }

            return UIImage(data: imageData) ?? image
        }
    }
}

// MARK: - Task Photo Viewer Sheet

@available(iOS 16.0, *)
struct TaskPhotoViewerSheet: View {
    let photos: [UIImage]
    let initialIndex: Int
    let onDelete: ((Int) -> Void)?

    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(photos: [UIImage], initialIndex: Int = 0, onDelete: ((Int) -> Void)? = nil) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onDelete = onDelete
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if !photos.isEmpty && currentIndex < photos.count {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .principal) {
                    Text("\(currentIndex + 1) of \(photos.count)")
                        .font(.body)
                        .foregroundColor(.white)
                }

                if let onDelete = onDelete {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            let indexToDelete = currentIndex
                            if currentIndex > 0 {
                                currentIndex -= 1
                            }
                            onDelete(indexToDelete)
                            if photos.count <= 1 {
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Compact Photo Button (for inline use in task rows)

@available(iOS 16.0, *)
struct CompactPhotoButton: View {
    let photoCount: Int
    let hasPhoto: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: hasPhoto ? "photo.fill" : "camera")
                    .font(.system(size: 14))
                if photoCount > 0 {
                    Text("\(photoCount)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(hasPhoto ? .green : .blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(hasPhoto ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
#Preview {
    struct PreviewWrapper: View {
        @State private var photos: [UIImage] = []

        var body: some View {
            VStack {
                TaskPhotoCapture(selectedPhotos: $photos)
                    .padding()

                Spacer()

                CompactPhotoButton(
                    photoCount: photos.count,
                    hasPhoto: !photos.isEmpty,
                    action: {}
                )
            }
        }
    }

    return PreviewWrapper()
}
#endif
