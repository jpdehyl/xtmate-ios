//
//  PreliminaryReportService.swift
//  XtMate
//
//  Created by XtMate on 2026-01-17.
//

import Foundation
import UIKit
import AVFoundation
import Combine

/// Service for generating and managing Preliminary Reports
/// Uses AI to analyze photos/video frames and auto-generate damage descriptions
@available(iOS 16.0, *)
@MainActor
class PreliminaryReportService: ObservableObject {
    static let shared = PreliminaryReportService()

    // MARK: - Published State
    @Published var isGenerating = false
    @Published var generationProgress: Double = 0.0
    @Published var generationStatus: String = ""
    @Published var currentReport: PreliminaryReport?
    @Published var error: String?

    // MARK: - Dependencies
    private let geminiService = GeminiService.shared
    private let roomIdentificationService = RoomIdentificationService.shared

    // MARK: - Configuration
    private let maxPhotosPerRoom = 5
    private let frameExtractionInterval: TimeInterval = 3.0  // Extract every 3 seconds
    private let minPhotoQualityScore: Double = 0.6

    private init() {}

    // MARK: - Report Generation from Video Walkthrough

    /// Generates a preliminary report from video walkthrough data
    /// - Parameters:
    ///   - walkthroughResult: The result from VideoWalkthroughService
    ///   - estimateId: The associated estimate ID
    ///   - existingReport: Optional existing report to update
    /// - Returns: A populated PreliminaryReport
    func generateFromWalkthrough(
        _ walkthroughResult: WalkthroughResult,
        estimateId: UUID,
        existingReport: PreliminaryReport? = nil
    ) async throws -> PreliminaryReport {
        isGenerating = true
        generationProgress = 0.0
        generationStatus = "Preparing report..."
        error = nil

        defer {
            isGenerating = false
        }

        var report = existingReport ?? PreliminaryReport(estimateId: estimateId)
        report.updatedAt = Date()

        // Step 1: Extract and analyze key frames (40% of progress)
        generationStatus = "Analyzing video frames..."
        let analyzedPhotos = try await analyzeKeyFrames(walkthroughResult.keyFrames)
        generationProgress = 0.4

        // Step 2: Group photos by room (10% of progress)
        generationStatus = "Grouping photos by room..."
        let groupedPhotos = groupPhotosByRoom(analyzedPhotos)
        generationProgress = 0.5

        // Step 3: Detect damage in each room (30% of progress)
        generationStatus = "Detecting damage..."
        let roomDamage = try await detectRoomDamage(from: groupedPhotos)
        generationProgress = 0.8

        // Step 4: Generate cause of loss description (10% of progress)
        generationStatus = "Generating report text..."
        let causeOfLoss = try await generateCauseOfLossDescription(from: roomDamage)
        generationProgress = 0.9

        // Step 5: Assemble final report
        generationStatus = "Finalizing report..."
        report.photos = selectBestPhotos(from: analyzedPhotos)
        report.roomDamage = roomDamage
        report.causeOfLoss = causeOfLoss
        report.siteInspectedDate = walkthroughResult.recordedAt

        // Use room identifications if available
        if let identifiedRooms = walkthroughResult.identifiedRooms {
            report = mergeRoomIdentifications(report, identifiedRooms: identifiedRooms)
        }

        generationProgress = 1.0
        generationStatus = "Report generated!"
        currentReport = report

        return report
    }

    // MARK: - Key Frame Analysis

    private func analyzeKeyFrames(_ keyFrames: [(timestamp: TimeInterval, image: UIImage)]) async throws -> [PreliminaryReportPhoto] {
        var photos: [PreliminaryReportPhoto] = []
        let totalFrames = keyFrames.count

        for (index, keyFrame) in keyFrames.enumerated() {
            // Update progress within the 0-40% range
            let frameProgress = Double(index) / Double(totalFrames) * 0.4
            generationProgress = frameProgress
            generationStatus = "Analyzing frame \(index + 1) of \(totalFrames)..."

            let frame = keyFrame.image
            var photo = PreliminaryReportPhoto()
            photo.imageData = frame.jpegData(compressionQuality: 0.8)
            photo.thumbnailData = frame.jpegData(compressionQuality: 0.3)
            photo.source = .videoExtraction
            photo.extractedFromVideoAt = keyFrame.timestamp
            photo.order = index

            // Analyze frame with AI
            if let analysis = try? await analyzePhoto(frame) {
                photo.aiAnalysis = analysis
                photo.roomName = analysis.identifiedRoom ?? "Unknown"
                photo.roomCategory = analysis.identifiedRoomCategory ?? .other
                photo.showsDamage = !analysis.detectedDamage.isEmpty

                if let suggestedCaption = analysis.suggestedCaption {
                    photo.caption = suggestedCaption
                }

                // Set damage type from detected damage
                if let primaryDamage = analysis.detectedDamage.first {
                    photo.damageType = primaryDamage.damageType
                }
            }

            photos.append(photo)
        }

        return photos
    }

    /// Analyzes a single photo using Gemini AI
    private func analyzePhoto(_ image: UIImage) async throws -> PhotoAIAnalysis {
        let prompt = """
        Analyze this photo from a property damage inspection. Provide a JSON response with:

        1. "identifiedRoom": The room type (kitchen, bathroom, bedroom, living room, etc.)
        2. "confidence": Your confidence in the room identification (0.0 to 1.0)
        3. "detectedDamage": Array of damage areas found, each with:
           - "damageType": water, fire, smoke, mold, wind, impact, freezing, or other
           - "severity": light, moderate, heavy, or destroyed
           - "affectedMaterial": carpet, carpet_pad, drywall, baseboards, hardwood, tile, etc.
           - "description": Brief description of the damage
           - "confidence": Confidence in this detection (0.0 to 1.0)
        4. "detectedMaterials": Array of materials visible (carpet, hardwood, drywall, tile, etc.)
        5. "detectedObjects": Array of objects that help identify the room (bed, toilet, refrigerator, etc.)
        6. "suggestedCaption": A brief caption for this photo suitable for an insurance report

        Focus on identifying:
        - Water damage: staining, warping, swelling, discoloration
        - Fire/smoke damage: charring, soot, discoloration
        - Structural damage: cracks, holes, separation
        - Mold: visible growth, discoloration patterns

        Return ONLY valid JSON, no markdown or explanation.
        """

        let response = try await geminiService.analyzeImageWithPrompt(image, prompt: prompt)

        // Parse JSON response
        guard let jsonData = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            // Return basic analysis if parsing fails
            return PhotoAIAnalysis()
        }

        var analysis = PhotoAIAnalysis()

        analysis.identifiedRoom = json["identifiedRoom"] as? String
        analysis.confidence = json["confidence"] as? Double ?? 0.5

        // Map room string to category
        if let roomStr = analysis.identifiedRoom?.lowercased() {
            analysis.identifiedRoomCategory = mapStringToRoomCategory(roomStr)
        }

        // Parse detected damage
        if let damageArray = json["detectedDamage"] as? [[String: Any]] {
            analysis.detectedDamage = damageArray.compactMap { parseDamageEntry($0) }
        }

        analysis.detectedMaterials = json["detectedMaterials"] as? [String] ?? []
        analysis.detectedObjects = json["detectedObjects"] as? [String] ?? []
        analysis.suggestedCaption = json["suggestedCaption"] as? String

        return analysis
    }

    private func parseDamageEntry(_ dict: [String: Any]) -> DetectedDamageArea? {
        guard let typeStr = dict["damageType"] as? String,
              let description = dict["description"] as? String else {
            return nil
        }

        let damageType = CauseOfLossType(rawValue: typeStr.capitalized) ?? .other
        let severityStr = dict["severity"] as? String ?? "moderate"
        let severity = DamageSeverity(rawValue: severityStr.capitalized) ?? .moderate
        let confidence = dict["confidence"] as? Double ?? 0.5

        var affectedMaterial: MaterialType?
        if let materialStr = dict["affectedMaterial"] as? String {
            affectedMaterial = MaterialType(rawValue: materialStr)
        }

        return DetectedDamageArea(
            damageType: damageType,
            severity: severity,
            affectedMaterial: affectedMaterial,
            description: description,
            confidence: confidence
        )
    }

    private func mapStringToRoomCategory(_ str: String) -> RoomCategory {
        let lowercased = str.lowercased()

        if lowercased.contains("kitchen") { return .kitchen }
        if lowercased.contains("bath") { return .bathroom }
        if lowercased.contains("bed") { return .bedroom }
        if lowercased.contains("living") { return .livingRoom }
        if lowercased.contains("dining") { return .diningRoom }
        if lowercased.contains("laundry") { return .laundry }
        if lowercased.contains("garage") { return .garage }
        if lowercased.contains("basement") { return .basement }
        if lowercased.contains("hall") { return .hallway }
        if lowercased.contains("closet") { return .closet }
        if lowercased.contains("office") { return .office }

        return .other
    }

    // MARK: - Photo Grouping

    private func groupPhotosByRoom(_ photos: [PreliminaryReportPhoto]) -> [String: [PreliminaryReportPhoto]] {
        var grouped: [String: [PreliminaryReportPhoto]] = [:]

        for photo in photos {
            let roomKey = photo.roomName.isEmpty ? "Unknown" : photo.roomName
            if grouped[roomKey] == nil {
                grouped[roomKey] = []
            }
            grouped[roomKey]?.append(photo)
        }

        return grouped
    }

    // MARK: - Damage Detection

    private func detectRoomDamage(from groupedPhotos: [String: [PreliminaryReportPhoto]]) async throws -> [RoomDamageEntry] {
        var entries: [RoomDamageEntry] = []
        var order = 0

        for (roomName, photos) in groupedPhotos.sorted(by: { $0.key < $1.key }) {
            // Determine room category from photos
            let roomCategory = photos.first?.roomCategory ?? .other

            var entry = RoomDamageEntry(roomName: roomName, roomCategory: roomCategory)
            entry.order = order
            order += 1

            // Aggregate all detected damage from photos
            var materialSet = Set<MaterialType>()

            for photo in photos {
                if let analysis = photo.aiAnalysis {
                    for damage in analysis.detectedDamage {
                        if let material = damage.affectedMaterial {
                            materialSet.insert(material)
                        }
                    }

                    // Also check detected materials that might be damaged
                    for materialStr in analysis.detectedMaterials {
                        if let material = MaterialType(rawValue: materialStr) {
                            // Only include if damage was detected
                            if !analysis.detectedDamage.isEmpty {
                                materialSet.insert(material)
                            }
                        }
                    }
                }
            }

            // If no specific materials detected but damage shown, use room's typical materials
            if materialSet.isEmpty && photos.contains(where: { $0.showsDamage }) {
                // Add common damaged materials based on room type
                let typicalMaterials = roomCategory.typicalMaterials
                // Just add carpet and carpet pad for most rooms as a default
                if typicalMaterials.contains(.carpet) {
                    materialSet.insert(.carpet)
                    materialSet.insert(.carpetPad)
                }
            }

            // Convert to AffectedMaterial entries
            entry.affectedMaterials = materialSet.map { material in
                // Determine severity from damage analysis
                let severity = determineSeverity(for: material, from: photos)
                return AffectedMaterial(material: material, severity: severity)
            }.sorted { $0.material.displayName < $1.material.displayName }

            entries.append(entry)
        }

        return entries
    }

    private func determineSeverity(for material: MaterialType, from photos: [PreliminaryReportPhoto]) -> DamageSeverity {
        var maxSeverity: DamageSeverity = .light

        for photo in photos {
            if let analysis = photo.aiAnalysis {
                for damage in analysis.detectedDamage {
                    if damage.affectedMaterial == material || damage.affectedMaterial == nil {
                        if damage.severity.rawValue > maxSeverity.rawValue {
                            maxSeverity = damage.severity
                        }
                    }
                }
            }
        }

        return maxSeverity
    }

    // MARK: - Cause of Loss Generation

    private func generateCauseOfLossDescription(from roomDamage: [RoomDamageEntry]) async throws -> String {
        // Build a summary of affected rooms and materials
        let affectedRooms = roomDamage
            .filter { !$0.affectedMaterials.isEmpty }
            .map { $0.roomName.lowercased() }

        guard !affectedRooms.isEmpty else {
            return "Damage assessment pending detailed inspection."
        }

        // Determine primary damage type from the photos
        var damageTypes = Set<CauseOfLossType>()
        if let report = currentReport {
            for photo in report.photos {
                if let damageType = photo.damageType {
                    damageTypes.insert(damageType)
                }
            }
        }

        let primaryDamageType = damageTypes.first ?? .water

        // Generate description based on damage type and affected rooms
        let roomList: String
        if affectedRooms.count == 1 {
            roomList = affectedRooms[0]
        } else if affectedRooms.count == 2 {
            roomList = "\(affectedRooms[0]) and \(affectedRooms[1])"
        } else {
            let allButLast = affectedRooms.dropLast().joined(separator: ", ")
            roomList = "\(allButLast) and \(affectedRooms.last!)"
        }

        switch primaryDamageType {
        case .water:
            return "Water damage affecting the \(roomList)."
        case .fire:
            return "Fire damage affecting the \(roomList)."
        case .smoke:
            return "Smoke damage affecting the \(roomList)."
        case .mold:
            return "Mold damage discovered in the \(roomList)."
        case .wind:
            return "Wind damage affecting the \(roomList)."
        case .impact:
            return "Impact damage affecting the \(roomList)."
        case .freezing:
            return "Freeze damage affecting the \(roomList)."
        case .other:
            return "Damage affecting the \(roomList)."
        }
    }

    // MARK: - Photo Selection

    private func selectBestPhotos(from photos: [PreliminaryReportPhoto]) -> [PreliminaryReportPhoto] {
        // Group by room and select best photos from each
        let grouped = groupPhotosByRoom(photos)
        var selected: [PreliminaryReportPhoto] = []

        for (_, roomPhotos) in grouped {
            // Sort by:
            // 1. Photos showing damage first
            // 2. Higher AI confidence
            // 3. Original order
            let sorted = roomPhotos.sorted { p1, p2 in
                if p1.showsDamage != p2.showsDamage {
                    return p1.showsDamage
                }
                let conf1 = p1.aiAnalysis?.confidence ?? 0
                let conf2 = p2.aiAnalysis?.confidence ?? 0
                if conf1 != conf2 {
                    return conf1 > conf2
                }
                return p1.order < p2.order
            }

            // Take up to maxPhotosPerRoom
            selected.append(contentsOf: sorted.prefix(maxPhotosPerRoom))
        }

        // Re-order selected photos
        return selected.enumerated().map { index, photo in
            var p = photo
            p.order = index
            return p
        }
    }

    // MARK: - Room Identification Merge

    private func mergeRoomIdentifications(_ report: PreliminaryReport, identifiedRooms: [RoomIdentification]) -> PreliminaryReport {
        var updatedReport = report

        // Update photo room names based on identifications
        updatedReport.photos = report.photos.map { photo in
            var p = photo
            // Find matching room identification
            for room in identifiedRooms {
                if photo.roomCategory == room.suggestedCategory {
                    p.roomName = room.suggestedCategory.rawValue
                    p.roomCategory = room.suggestedCategory
                    break
                }
            }
            return p
        }

        // Update room damage entries
        for room in identifiedRooms {
            if let index = updatedReport.roomDamage.firstIndex(where: { $0.roomCategory == room.suggestedCategory }) {
                updatedReport.roomDamage[index].roomName = room.suggestedCategory.rawValue
            }
        }

        return updatedReport
    }

    // MARK: - Manual Photo Addition

    /// Adds a manually captured photo to the current report
    func addManualPhoto(_ image: UIImage, roomName: String, caption: String = "") async throws {
        guard var report = currentReport else {
            throw PreliminaryReportError.noActiveReport
        }

        var photo = PreliminaryReportPhoto()
        photo.imageData = image.jpegData(compressionQuality: 0.8)
        photo.thumbnailData = image.jpegData(compressionQuality: 0.3)
        photo.source = .manual
        photo.roomName = roomName
        photo.caption = caption
        photo.order = report.photos.count

        // Optionally analyze the photo
        if let analysis = try? await analyzePhoto(image) {
            photo.aiAnalysis = analysis
            photo.showsDamage = !analysis.detectedDamage.isEmpty
            if photo.caption.isEmpty, let suggested = analysis.suggestedCaption {
                photo.caption = suggested
            }
        }

        report.photos.append(photo)
        report.updatedAt = Date()
        currentReport = report
    }

    // MARK: - Cost Estimation

    /// Generates preliminary cost estimates based on room damage
    func estimateCosts(for report: PreliminaryReport) -> (repairMin: Double, repairMax: Double, contentsMin: Double, contentsMax: Double) {
        var totalRepairMin: Double = 0
        var totalRepairMax: Double = 0

        for damage in report.roomDamage {
            let (min, max) = estimateRoomRepairCost(damage)
            totalRepairMin += min
            totalRepairMax += max
        }

        // Contents typically 25-40% of structural for water damage
        let contentsMin = totalRepairMin * 0.25
        let contentsMax = totalRepairMax * 0.40

        return (totalRepairMin, totalRepairMax, contentsMin, contentsMax)
    }

    private func estimateRoomRepairCost(_ damage: RoomDamageEntry) -> (min: Double, max: Double) {
        var min: Double = 0
        var max: Double = 0

        for material in damage.affectedMaterials {
            let (matMin, matMax) = getMaterialCostRange(material.material, severity: material.severity)
            min += matMin
            max += matMax
        }

        // Apply room size multiplier (rough estimate)
        let sizeMultiplier: Double
        switch damage.roomCategory {
        case .livingRoom, .basement:
            sizeMultiplier = 1.5
        case .bedroom, .kitchen:
            sizeMultiplier = 1.2
        case .bathroom, .laundry, .closet:
            sizeMultiplier = 0.8
        default:
            sizeMultiplier = 1.0
        }

        return (min * sizeMultiplier, max * sizeMultiplier)
    }

    private func getMaterialCostRange(_ material: MaterialType, severity: DamageSeverity) -> (min: Double, max: Double) {
        // Base costs per material (rough estimates)
        let baseCost: (min: Double, max: Double)
        switch material {
        case .carpet:
            baseCost = (300, 800)
        case .carpetPad:
            baseCost = (100, 300)
        case .hardwood:
            baseCost = (800, 2000)
        case .laminate, .lvp, .vinyl:
            baseCost = (400, 1000)
        case .tile:
            baseCost = (500, 1500)
        case .drywall:
            baseCost = (200, 600)
        case .baseboards:
            baseCost = (150, 400)
        case .ceilingDrywall:
            baseCost = (300, 800)
        case .insulation:
            baseCost = (200, 500)
        case .cabinets:
            baseCost = (1000, 5000)
        case .countertops:
            baseCost = (500, 2000)
        default:
            baseCost = (200, 500)
        }

        // Apply severity multiplier
        let severityMultiplier: Double
        switch severity {
        case .light:
            severityMultiplier = 0.5
        case .moderate:
            severityMultiplier = 1.0
        case .heavy:
            severityMultiplier = 1.5
        case .destroyed:
            severityMultiplier = 2.0
        }

        return (baseCost.min * severityMultiplier, baseCost.max * severityMultiplier)
    }

    // MARK: - Report Persistence

    func saveReport(_ report: PreliminaryReport) async throws {
        // TODO: Implement saving to local storage and syncing to server
        currentReport = report
    }

    func loadReport(for estimateId: UUID) async throws -> PreliminaryReport? {
        // TODO: Implement loading from local storage or server
        return nil
    }
}

// MARK: - Errors

enum PreliminaryReportError: LocalizedError {
    case noActiveReport
    case analysisFailure(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .noActiveReport:
            return "No active report. Please generate a report first."
        case .analysisFailure(let message):
            return "Failed to analyze photos: \(message)"
        case .saveFailed(let message):
            return "Failed to save report: \(message)"
        }
    }
}
