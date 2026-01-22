//
//  FloorPlanAnnotationModels.swift
//  XtMate
//
//  Data models for damage annotations on 2D floor plans.
//  Supports tap-to-annotate workflow for property damage documentation.
//

import Foundation
import SwiftUI

// MARK: - Annotation Position

/// Represents a normalized position on the floor plan (0-1 range)
struct AnnotationPosition: Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Convert from view coordinates to normalized position
    static func fromViewCoordinates(
        point: CGPoint,
        viewSize: CGSize,
        scale: CGFloat,
        offset: CGSize
    ) -> AnnotationPosition {
        // Reverse the transformations applied in FloorPlanView
        let adjustedX = (point.x - viewSize.width / 2 - offset.width) / scale
        let adjustedY = (point.y - viewSize.height / 2 - offset.height) / scale

        // Normalize to 0-1 range (assuming floor plan is centered)
        let normalizedX = (adjustedX / viewSize.width) + 0.5
        let normalizedY = (adjustedY / viewSize.height) + 0.5

        return AnnotationPosition(
            x: max(0, min(1, normalizedX)),
            y: max(0, min(1, normalizedY))
        )
    }

    /// Convert to view coordinates for rendering
    func toViewCoordinates(
        viewSize: CGSize,
        scale: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2

        // Convert from normalized to actual coordinates
        let actualX = (x - 0.5) * viewSize.width
        let actualY = (y - 0.5) * viewSize.height

        // Apply scale and offset
        let viewX = centerX + actualX * scale + offset.width
        let viewY = centerY + actualY * scale + offset.height

        return CGPoint(x: viewX, y: viewY)
    }
}

// MARK: - Floor Plan Annotation DTO

/// A lightweight representation of an annotation for 2D floor plan UI
struct FloorPlanAnnotationDTO: Identifiable {
    let id: UUID
    var damageType: DamageType
    var affectedSurface: AffectedSurface
    var position: AnnotationPosition
    var heightMarker: Double?
    var severity: DamageSeverity
    var notes: String
    var photoPaths: [String]
    var audioPath: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        damageType: DamageType,
        affectedSurface: AffectedSurface,
        position: AnnotationPosition,
        heightMarker: Double? = nil,
        severity: DamageSeverity = .moderate,
        notes: String = "",
        photoPaths: [String] = [],
        audioPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.damageType = damageType
        self.affectedSurface = affectedSurface
        self.position = position
        self.heightMarker = heightMarker
        self.severity = severity
        self.notes = notes
        self.photoPaths = photoPaths
        self.audioPath = audioPath
        self.createdAt = createdAt
    }
}

// MARK: - Note on Types
// DamageType, AffectedSurface, and DamageSeverity are defined in ContentView.swift
// This file uses those types via FloorPlanAnnotationDTO
