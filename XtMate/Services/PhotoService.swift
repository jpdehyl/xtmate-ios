//
//  PhotoService.swift
//  XtMate
//
//  P3B-2: Photo management service for claim documentation
//  Handles camera capture, local storage, thumbnail generation,
//  GPS extraction, and sync queue integration.
//

import SwiftUI
import UIKit
import Photos
import CoreLocation
import Combine

// MARK: - Photo Service Error

enum PhotoServiceError: Error, LocalizedError {
    case saveFailed(String)
    case loadFailed(String)
    case deleteFailed(String)
    case compressionFailed
    case thumbnailFailed
    case directoryCreationFailed
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .saveFailed(let reason): return "Failed to save photo: \(reason)"
        case .loadFailed(let reason): return "Failed to load photo: \(reason)"
        case .deleteFailed(let reason): return "Failed to delete photo: \(reason)"
        case .compressionFailed: return "Failed to compress image"
        case .thumbnailFailed: return "Failed to generate thumbnail"
        case .directoryCreationFailed: return "Failed to create storage directory"
        case .invalidImage: return "Invalid image data"
        }
    }
}

// MARK: - Photo Service

/// Manages photo capture, storage, and sync queue integration
/// Singleton pattern with @MainActor for UI binding
@MainActor
class PhotoService: ObservableObject {
    static let shared = PhotoService()

    // MARK: - Published State

    @Published var photos: [Photo] = []
    @Published var isCapturing = false
    @Published var uploadProgress: Double = 0
    @Published var lastError: String?

    // MARK: - Private Properties

    private let photosDirectory: URL
    private let thumbnailsDirectory: URL
    private let fileManager = FileManager.default

    // Configuration
    private let maxImageSizeKB = 1024
    private let thumbnailSize = CGSize(width: 300, height: 300)
    private let jpegQuality: CGFloat = 0.8

    // Persistence key
    private let photosKey = "xtmate_photos"

    // MARK: - Init

    private init() {
        // Setup directories in Documents folder
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        photosDirectory = documentsPath.appendingPathComponent("Photos", isDirectory: true)
        thumbnailsDirectory = documentsPath.appendingPathComponent("Thumbnails", isDirectory: true)

        // Create directories if needed
        createDirectoriesIfNeeded()

        // Load persisted photos
        loadPhotos()

        print("📸 PhotoService: Initialized")
        print("   Photos directory: \(photosDirectory.path)")
        print("   Thumbnails directory: \(thumbnailsDirectory.path)")
    }

    // MARK: - Directory Management

    private func createDirectoriesIfNeeded() {
        do {
            if !fileManager.fileExists(atPath: photosDirectory.path) {
                try fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
            }
            if !fileManager.fileExists(atPath: thumbnailsDirectory.path) {
                try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
            }
        } catch {
            print("📸 PhotoService: Failed to create directories: \(error)")
        }
    }

    // MARK: - Photo Operations

    /// Save a new photo from UIImage
    func savePhoto(
        _ image: UIImage,
        type: PhotoType,
        metadata: PhotoMetadata,
        estimateId: UUID?,
        roomId: UUID?,
        annotationId: UUID?
    ) async throws -> Photo {
        print("📸 PhotoService: Saving photo of type \(type.rawValue)")

        // Compress image
        guard let compressedImage = compressImage(image, maxSizeKB: maxImageSizeKB) else {
            throw PhotoServiceError.compressionFailed
        }

        guard let imageData = compressedImage.jpegData(compressionQuality: jpegQuality) else {
            throw PhotoServiceError.invalidImage
        }

        // Generate thumbnail
        guard let thumbnail = generateThumbnail(compressedImage, size: thumbnailSize) else {
            throw PhotoServiceError.thumbnailFailed
        }

        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) else {
            throw PhotoServiceError.thumbnailFailed
        }

        // Create photo ID
        let photoId = UUID()

        // Save to disk
        let photoFilename = "\(photoId.uuidString).jpg"
        let thumbnailFilename = "\(photoId.uuidString)_thumb.jpg"

        let photoPath = photosDirectory.appendingPathComponent(photoFilename)
        let thumbnailPath = thumbnailsDirectory.appendingPathComponent(thumbnailFilename)

        do {
            try imageData.write(to: photoPath)
            try thumbnailData.write(to: thumbnailPath)
        } catch {
            throw PhotoServiceError.saveFailed(error.localizedDescription)
        }

        // Create photo model
        let photo = Photo(
            id: photoId,
            type: type,
            localPath: photoFilename,
            thumbnailPath: thumbnailFilename,
            caption: metadata.caption,
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            takenAt: metadata.takenAt,
            estimateId: estimateId,
            roomId: roomId,
            annotationId: annotationId,
            syncStatus: .pending
        )

        // Add to array and persist
        photos.append(photo)
        savePhotos()

        // Queue for sync
        await queueForSync(photo)

        print("📸 PhotoService: Photo saved successfully: \(photoId)")
        return photo
    }

    /// Load a photo's UIImage from local storage
    func loadPhoto(_ photo: Photo) -> UIImage? {
        guard let localPath = photo.localPath else { return nil }
        let fullPath = photosDirectory.appendingPathComponent(localPath)

        guard let data = try? Data(contentsOf: fullPath) else {
            print("📸 PhotoService: Failed to load photo data: \(localPath)")
            return nil
        }

        return UIImage(data: data)
    }

    /// Load a photo's thumbnail from local storage
    func loadThumbnail(_ photo: Photo) -> UIImage? {
        guard let thumbnailPath = photo.thumbnailPath else { return nil }
        let fullPath = thumbnailsDirectory.appendingPathComponent(thumbnailPath)

        guard let data = try? Data(contentsOf: fullPath) else {
            print("📸 PhotoService: Failed to load thumbnail: \(thumbnailPath)")
            return nil
        }

        return UIImage(data: data)
    }

    /// Delete a photo and its files
    func deletePhoto(_ photo: Photo) async throws {
        print("📸 PhotoService: Deleting photo: \(photo.id)")

        // Delete photo file
        if let localPath = photo.localPath {
            let fullPath = photosDirectory.appendingPathComponent(localPath)
            try? fileManager.removeItem(at: fullPath)
        }

        // Delete thumbnail file
        if let thumbnailPath = photo.thumbnailPath {
            let fullPath = thumbnailsDirectory.appendingPathComponent(thumbnailPath)
            try? fileManager.removeItem(at: fullPath)
        }

        // Remove from array
        photos.removeAll { $0.id == photo.id }
        savePhotos()

        print("📸 PhotoService: Photo deleted successfully")
    }

    /// Update photo properties
    func updatePhoto(_ photo: Photo) {
        if let index = photos.firstIndex(where: { $0.id == photo.id }) {
            var updatedPhoto = photo
            updatedPhoto.updatedAt = Date()
            photos[index] = updatedPhoto
            savePhotos()
        }
    }

    // MARK: - Image Processing

    /// Compress image to target size
    func compressImage(_ image: UIImage, maxSizeKB: Int) -> UIImage? {
        var compression: CGFloat = 1.0
        let maxBytes = maxSizeKB * 1024

        guard var imageData = image.jpegData(compressionQuality: compression) else {
            return nil
        }

        // Progressively reduce quality until under target size
        while imageData.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            if let newData = image.jpegData(compressionQuality: compression) {
                imageData = newData
            }
        }

        // If still too large, resize the image
        if imageData.count > maxBytes {
            let scale = sqrt(Double(maxBytes) / Double(imageData.count))
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            if let resized = resizeImage(image, to: newSize) {
                return resized
            }
        }

        return UIImage(data: imageData) ?? image
    }

    /// Generate thumbnail at specified size
    func generateThumbnail(_ image: UIImage, size: CGSize) -> UIImage? {
        let aspectWidth = size.width / image.size.width
        let aspectHeight = size.height / image.size.height
        let aspectRatio = min(aspectWidth, aspectHeight)

        let scaledSize = CGSize(
            width: image.size.width * aspectRatio,
            height: image.size.height * aspectRatio
        )

        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: scaledSize))
        }
    }

    /// Resize image to specified size
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - GPS Extraction

    /// Extract GPS coordinates from image metadata
    func extractGPS(from metadata: [String: Any]?) -> (lat: Double?, lon: Double?) {
        guard let meta = metadata,
              let gps = meta["{GPS}"] as? [String: Any] else {
            return (nil, nil)
        }

        let latitude = gps["Latitude"] as? Double
        let longitude = gps["Longitude"] as? Double

        // Handle latitude/longitude references (N/S, E/W)
        var lat = latitude
        var lon = longitude

        if let latRef = gps["LatitudeRef"] as? String, latRef == "S" {
            lat = lat.map { -$0 }
        }
        if let lonRef = gps["LongitudeRef"] as? String, lonRef == "W" {
            lon = lon.map { -$0 }
        }

        return (lat, lon)
    }

    /// Get current location for photo metadata
    func getCurrentLocation() async -> (lat: Double?, lon: Double?) {
        // This would integrate with CLLocationManager
        // For now, return nil - location will be extracted from image metadata if available
        return (nil, nil)
    }

    // MARK: - Sync Integration

    /// Queue photo for upload via OfflineQueueManager
    func queueForSync(_ photo: Photo) async {
        guard let estimateId = photo.estimateId else {
            print("📸 PhotoService: Photo has no estimateId, skipping sync queue")
            return
        }

        guard let localPath = photo.localPath else {
            print("📸 PhotoService: Photo has no local path, skipping sync queue")
            return
        }

        let fullPath = photosDirectory.appendingPathComponent(localPath)

        await OfflineQueueManager.shared.queueEstimatePhoto(
            estimateId: estimateId,
            roomId: photo.roomId,
            annotationId: photo.annotationId,
            photo: photo,
            localPhotoPath: fullPath.path
        )
    }

    /// Mark photo as uploaded
    func markAsUploaded(_ photoId: UUID, remoteUrl: String) {
        if let index = photos.firstIndex(where: { $0.id == photoId }) {
            photos[index].syncStatus = .uploaded
            photos[index].remoteUrl = remoteUrl
            photos[index].uploadedAt = Date()
            photos[index].updatedAt = Date()
            savePhotos()
            print("📸 PhotoService: Photo marked as uploaded: \(photoId)")
        }
    }

    /// Mark photo upload as failed
    func markAsFailed(_ photoId: UUID) {
        if let index = photos.firstIndex(where: { $0.id == photoId }) {
            photos[index].syncStatus = .failed
            photos[index].retryCount += 1
            photos[index].updatedAt = Date()
            savePhotos()
            print("📸 PhotoService: Photo marked as failed: \(photoId)")
        }
    }

    // MARK: - Query Methods

    /// Get photos for an estimate
    func photosForEstimate(_ estimateId: UUID) -> [Photo] {
        photos.filter { $0.estimateId == estimateId }
    }

    /// Get photos for a room
    func photosForRoom(_ roomId: UUID) -> [Photo] {
        photos.filter { $0.roomId == roomId }
    }

    /// Get photos for an annotation
    func photosForAnnotation(_ annotationId: UUID) -> [Photo] {
        photos.filter { $0.annotationId == annotationId }
    }

    /// Get pending photos for sync
    func pendingPhotos() -> [Photo] {
        photos.filter { $0.syncStatus == .pending || ($0.syncStatus == .failed && $0.retryCount < 5) }
    }

    // MARK: - Persistence

    private func loadPhotos() {
        guard let data = UserDefaults.standard.data(forKey: photosKey) else {
            print("📸 PhotoService: No persisted photos found")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            photos = try decoder.decode([Photo].self, from: data)
            print("📸 PhotoService: Loaded \(photos.count) photos from storage")
        } catch {
            print("📸 PhotoService: Failed to decode photos: \(error)")
        }
    }

    private func savePhotos() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(photos)
            UserDefaults.standard.set(data, forKey: photosKey)
        } catch {
            print("📸 PhotoService: Failed to encode photos: \(error)")
        }
    }

    // MARK: - Cleanup

    /// Remove orphaned files not referenced by any photo
    func cleanupOrphanedFiles() async {
        print("📸 PhotoService: Starting orphaned file cleanup")

        let photoFilenames = Set(photos.compactMap { $0.localPath })
        let thumbnailFilenames = Set(photos.compactMap { $0.thumbnailPath })

        // Clean photo directory
        if let photoFiles = try? fileManager.contentsOfDirectory(atPath: photosDirectory.path) {
            for file in photoFiles where !photoFilenames.contains(file) {
                let filePath = photosDirectory.appendingPathComponent(file)
                try? fileManager.removeItem(at: filePath)
                print("📸 PhotoService: Removed orphaned photo: \(file)")
            }
        }

        // Clean thumbnail directory
        if let thumbFiles = try? fileManager.contentsOfDirectory(atPath: thumbnailsDirectory.path) {
            for file in thumbFiles where !thumbnailFilenames.contains(file) {
                let filePath = thumbnailsDirectory.appendingPathComponent(file)
                try? fileManager.removeItem(at: filePath)
                print("📸 PhotoService: Removed orphaned thumbnail: \(file)")
            }
        }

        print("📸 PhotoService: Cleanup complete")
    }
}
