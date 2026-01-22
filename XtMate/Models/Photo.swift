//
//  Photo.swift
//  XtMate
//
//  P3B-1: Photo model for claim documentation
//  Supports camera capture with type classification, GPS extraction,
//  and sync queue integration for offline-first workflow.
//

import SwiftUI

// MARK: - Photo Type

/// Classification for claim photos following insurance documentation standards
enum PhotoType: String, Codable, CaseIterable, Identifiable {
    case before = "BEFORE"
    case during = "DURING"
    case after = "AFTER"
    case damage = "DAMAGE"
    case equipment = "EQUIPMENT"
    case overview = "OVERVIEW"

    var id: String { rawValue }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .before: return "Before"
        case .during: return "During"
        case .after: return "After"
        case .damage: return "Damage"
        case .equipment: return "Equipment"
        case .overview: return "Overview"
        }
    }

    /// SF Symbol icon for UI display
    var icon: String {
        switch self {
        case .before: return "clock.arrow.circlepath"
        case .during: return "wrench.and.screwdriver"
        case .after: return "checkmark.circle"
        case .damage: return "exclamationmark.triangle"
        case .equipment: return "fan"
        case .overview: return "photo.on.rectangle"
        }
    }

    /// Theme color for visual distinction
    var color: Color {
        switch self {
        case .before: return .blue
        case .during: return .orange
        case .after: return .green
        case .damage: return .red
        case .equipment: return .purple
        case .overview: return .teal
        }
    }

    /// Short label for compact display
    var shortLabel: String {
        switch self {
        case .before: return "BEF"
        case .during: return "DUR"
        case .after: return "AFT"
        case .damage: return "DMG"
        case .equipment: return "EQP"
        case .overview: return "OVW"
        }
    }
}

// MARK: - Photo Sync Status

/// Sync status for offline-first photo management
enum PhotoSyncStatus: String, Codable {
    case pending
    case uploading
    case uploaded
    case failed

    /// Human-readable description
    var displayName: String {
        switch self {
        case .pending: return "Pending Upload"
        case .uploading: return "Uploading..."
        case .uploaded: return "Uploaded"
        case .failed: return "Upload Failed"
        }
    }

    /// SF Symbol icon
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .uploading: return "arrow.up.circle"
        case .uploaded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        }
    }

    /// Status color
    var color: Color {
        switch self {
        case .pending: return .gray
        case .uploading: return .blue
        case .uploaded: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Photo Model

/// Represents a photo captured for claim documentation
/// Supports local storage, thumbnail generation, and server sync
struct Photo: Identifiable, Codable, Hashable {
    let id: UUID

    // Classification
    var type: PhotoType

    // Local storage paths (relative to Documents directory)
    var localPath: String?
    var thumbnailPath: String?

    // Remote URL after successful upload
    var remoteUrl: String?

    // Metadata
    var caption: String
    var latitude: Double?
    var longitude: Double?
    var takenAt: Date

    // Relationships (optional foreign keys)
    var estimateId: UUID?
    var roomId: UUID?
    var annotationId: UUID?

    // Sync tracking
    var syncStatus: PhotoSyncStatus
    var retryCount: Int
    var uploadedAt: Date?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Initializers

    /// Create a new photo with default values
    init(
        id: UUID = UUID(),
        type: PhotoType,
        localPath: String? = nil,
        thumbnailPath: String? = nil,
        remoteUrl: String? = nil,
        caption: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        takenAt: Date = Date(),
        estimateId: UUID? = nil,
        roomId: UUID? = nil,
        annotationId: UUID? = nil,
        syncStatus: PhotoSyncStatus = .pending,
        retryCount: Int = 0,
        uploadedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.localPath = localPath
        self.thumbnailPath = thumbnailPath
        self.remoteUrl = remoteUrl
        self.caption = caption
        self.latitude = latitude
        self.longitude = longitude
        self.takenAt = takenAt
        self.estimateId = estimateId
        self.roomId = roomId
        self.annotationId = annotationId
        self.syncStatus = syncStatus
        self.retryCount = retryCount
        self.uploadedAt = uploadedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    /// Check if photo has location data
    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }

    /// Check if photo is synced to server
    var isSynced: Bool {
        syncStatus == .uploaded && remoteUrl != nil
    }

    /// Check if photo needs retry
    var needsRetry: Bool {
        syncStatus == .failed && retryCount < 5
    }

    /// Display-friendly taken date
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: takenAt)
    }

    /// Short date for compact display
    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: takenAt)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Photo, rhs: Photo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Photo Metadata Helper

/// Helper struct for photo metadata extraction
struct PhotoMetadata {
    var latitude: Double?
    var longitude: Double?
    var takenAt: Date
    var caption: String

    init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        takenAt: Date = Date(),
        caption: String = ""
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.takenAt = takenAt
        self.caption = caption
    }
}

// MARK: - Photo Collection Extension

extension Array where Element == Photo {
    /// Filter photos by type
    func ofType(_ type: PhotoType) -> [Photo] {
        filter { $0.type == type }
    }

    /// Filter photos for a specific estimate
    func forEstimate(_ estimateId: UUID) -> [Photo] {
        filter { $0.estimateId == estimateId }
    }

    /// Filter photos for a specific room
    func forRoom(_ roomId: UUID) -> [Photo] {
        filter { $0.roomId == roomId }
    }

    /// Filter photos for a specific annotation
    func forAnnotation(_ annotationId: UUID) -> [Photo] {
        filter { $0.annotationId == annotationId }
    }

    /// Get photos pending sync
    var pendingSync: [Photo] {
        filter { $0.syncStatus == .pending || $0.syncStatus == .failed }
    }

    /// Get synced photos
    var synced: [Photo] {
        filter { $0.syncStatus == .uploaded }
    }

    /// Sort by taken date (newest first)
    var sortedByDate: [Photo] {
        sorted { $0.takenAt > $1.takenAt }
    }
}
