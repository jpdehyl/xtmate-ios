//
//  PhotoCaptureView.swift
//  XtMate
//
//  P3B-3: Full-screen camera capture with photo type selection
//  Features: PhotoType chips, 80pt capture button, flash toggle, camera switch
//  56pt touch targets for field staff use
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Photo Capture View

/// Full-screen camera capture view for claim documentation
/// Supports type selection, multi-photo capture, and metadata tagging
@available(iOS 16.0, *)
struct PhotoCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    // Configuration
    let estimateId: UUID?
    let roomId: UUID?
    let annotationId: UUID?
    let onPhotosCaptured: (([Photo]) -> Void)?

    // State
    @State private var selectedType: PhotoType = .damage
    @State private var capturedPhotos: [Photo] = []
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var flashEnabled = false
    @State private var isFrontCamera = false
    @State private var showingPhotoReview = false

    // Services
    @StateObject private var photoService = PhotoService.shared

    init(
        estimateId: UUID? = nil,
        roomId: UUID? = nil,
        annotationId: UUID? = nil,
        onPhotosCaptured: (([Photo]) -> Void)? = nil
    ) {
        self.estimateId = estimateId
        self.roomId = roomId
        self.annotationId = annotationId
        self.onPhotosCaptured = onPhotosCaptured
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar with photo type chips
                    PhotoTypeChipBar(selectedType: $selectedType)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.top, AppTheme.Spacing.md)

                    // Camera preview area (placeholder - actual camera in sheet)
                    ZStack {
                        Color(.systemGray6)

                        VStack(spacing: AppTheme.Spacing.xl) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.gray)

                            Text("Tap the capture button to take a photo")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            // Show captured count
                            if !capturedPhotos.isEmpty {
                                HStack {
                                    ForEach(capturedPhotos.prefix(5)) { photo in
                                        if let thumbnail = photoService.loadThumbnail(photo) {
                                            Image(uiImage: thumbnail)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 50, height: 50)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                    if capturedPhotos.count > 5 {
                                        Text("+\(capturedPhotos.count - 5)")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(8)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)

                    // Bottom control bar
                    CaptureControlBar(
                        capturedCount: capturedPhotos.count,
                        flashEnabled: $flashEnabled,
                        onCameraCapture: { showingCamera = true },
                        onLibrarySelect: { showingLibrary = true },
                        onDone: finishCapture
                    )
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.xl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .principal) {
                    Text("Capture Photos")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingCamera) {
                PhotoCameraView(
                    flashEnabled: flashEnabled,
                    onImageCaptured: handleCapturedImage
                )
            }
            .sheet(isPresented: $showingLibrary) {
                CapturePhotoLibraryPicker(onImageSelected: handleCapturedImage)
            }
        }
    }

    // MARK: - Actions

    private func handleCapturedImage(_ image: UIImage) {
        Task {
            let metadata = PhotoMetadata(
                latitude: nil, // GPS extraction could be added here
                longitude: nil,
                takenAt: Date(),
                caption: ""
            )

            do {
                let photo = try await photoService.savePhoto(
                    image,
                    type: selectedType,
                    metadata: metadata,
                    estimateId: estimateId,
                    roomId: roomId,
                    annotationId: annotationId
                )

                await MainActor.run {
                    capturedPhotos.append(photo)

                    // Haptic feedback
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)
                }
            } catch {
                print("📸 PhotoCaptureView: Failed to save photo: \(error)")

                await MainActor.run {
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.error)
                }
            }
        }
    }

    private func finishCapture() {
        onPhotosCaptured?(capturedPhotos)
        dismiss()
    }
}

// MARK: - Photo Type Chip Bar

@available(iOS 16.0, *)
struct PhotoTypeChipBar: View {
    @Binding var selectedType: PhotoType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(PhotoType.allCases) { type in
                    PhotoTypeChip(
                        type: type,
                        isSelected: selectedType == type,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedType = type
                            }
                            let feedback = UIImpactFeedbackGenerator(style: .light)
                            feedback.impactOccurred()
                        }
                    )
                }
            }
            .padding(.vertical, AppTheme.Spacing.sm)
        }
    }
}

@available(iOS 16.0, *)
struct PhotoTypeChip: View {
    let type: PhotoType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 14, weight: .medium))
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : type.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 56) // 56pt touch target
            .background(isSelected ? type.color : type.color.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Capture Control Bar

@available(iOS 16.0, *)
struct CaptureControlBar: View {
    let capturedCount: Int
    @Binding var flashEnabled: Bool
    let onCameraCapture: () -> Void
    let onLibrarySelect: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xl) {
            // Left: Flash toggle + Library
            HStack(spacing: AppTheme.Spacing.md) {
                // Flash toggle
                Button(action: {
                    flashEnabled.toggle()
                    let feedback = UIImpactFeedbackGenerator(style: .light)
                    feedback.impactOccurred()
                }) {
                    Image(systemName: flashEnabled ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 24))
                        .foregroundColor(flashEnabled ? .yellow : .white)
                        .frame(width: 56, height: 56) // 56pt touch target
                }

                // Library picker
                Button(action: onLibrarySelect) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56) // 56pt touch target
                }
            }

            Spacer()

            // Center: 80pt capture button
            Button(action: onCameraCapture) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 68, height: 68)
                }
            }

            Spacer()

            // Right: Done button with count
            Button(action: onDone) {
                HStack(spacing: 6) {
                    Text("Done")
                        .font(.body)
                        .fontWeight(.semibold)
                    if capturedCount > 0 {
                        Text("\(capturedCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                }
                .foregroundColor(.white)
                .frame(minWidth: 80, minHeight: 56) // 56pt touch target
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }
}

// MARK: - Camera View (UIImagePickerController wrapper)

@available(iOS 16.0, *)
struct PhotoCameraView: UIViewControllerRepresentable {
    let flashEnabled: Bool
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.cameraFlashMode = flashEnabled ? .on : .off
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        uiViewController.cameraFlashMode = flashEnabled ? .on : .off
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoCameraView

        init(_ parent: PhotoCameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                // Compress image
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

// MARK: - Photo Library Picker

@available(iOS 16.0, *)
struct CapturePhotoLibraryPicker: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CapturePhotoLibraryPicker

        init(_ parent: CapturePhotoLibraryPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                // Compress image
                let compressed = compressImage(image, maxSizeKB: 1024)
                parent.onImageSelected(compressed)
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

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
#Preview {
    PhotoCaptureView(
        estimateId: UUID(),
        roomId: nil,
        annotationId: nil,
        onPhotosCaptured: { photos in
            print("Captured \(photos.count) photos")
        }
    )
}
#endif
