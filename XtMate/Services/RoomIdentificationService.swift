//
//  RoomIdentificationService.swift
//  XtMate
//
//  AI-powered room identification from images.
//  Uses Gemini to analyze key frames and detect room types based on visible objects.
//
//  Object → Room Mapping:
//  - Washing machine, dryer → Laundry
//  - Fridge, range, cabinets, sink (in combo) → Kitchen
//  - Dining table, chairs → Dining Room
//  - Sofa, TV, couch → Living Room
//  - Bed, dresser → Bedroom
//  - Toilet, bathtub, shower → Bathroom
//  - Garage door, car → Garage
//  - Desk, computer, bookshelf → Office
//
//  Handles ambiguous cases:
//  - Open floor plans (kitchen/dining combo)
//  - Multi-purpose rooms
//  - Unidentifiable spaces
//

import Foundation
import UIKit
import Combine

// MARK: - Room Identification Result

struct RoomIdentification: Identifiable, Codable {
    let id: UUID
    let suggestedCategory: RoomCategory
    let confidence: Float  // 0.0 to 1.0
    let detectedObjects: [DetectedObject]
    let alternativeCategories: [AlternativeCategory]
    let notes: String
    let isAmbiguous: Bool
    let combinedWith: RoomCategory?  // e.g., "Kitchen/Dining" combo

    struct DetectedObject: Codable {
        let name: String
        let confidence: Float
        let roomIndicator: RoomCategory?  // Which room type this object suggests
    }

    struct AlternativeCategory: Codable {
        let category: RoomCategory
        let confidence: Float
        let reason: String
    }

    /// User-editable version of this identification
    var editableResult: EditableRoomIdentification {
        EditableRoomIdentification(
            id: id,
            selectedCategory: suggestedCategory,
            customName: nil,
            detectedObjects: detectedObjects,
            isConfirmed: false
        )
    }
}

/// Editable room identification that the PM can modify
struct EditableRoomIdentification: Identifiable {
    let id: UUID
    var selectedCategory: RoomCategory
    var customName: String?
    let detectedObjects: [RoomIdentification.DetectedObject]
    var isConfirmed: Bool

    var displayName: String {
        customName ?? selectedCategory.rawValue
    }
}

// MARK: - Room Identification Service

@available(iOS 16.0, *)
@MainActor
class RoomIdentificationService: ObservableObject {
    static let shared = RoomIdentificationService()

    @Published var isProcessing = false
    @Published var lastError: String?

    private var proxyBaseURL: String { APIKeys.apiBaseURL }

    // Object to room mapping rules
    private let objectRoomMapping: [String: RoomCategory] = [
        // Laundry
        "washing machine": .laundry,
        "washer": .laundry,
        "dryer": .laundry,
        "laundry basket": .laundry,
        "ironing board": .laundry,

        // Kitchen
        "refrigerator": .kitchen,
        "fridge": .kitchen,
        "range": .kitchen,
        "stove": .kitchen,
        "oven": .kitchen,
        "microwave": .kitchen,
        "dishwasher": .kitchen,
        "kitchen sink": .kitchen,
        "kitchen cabinet": .kitchen,
        "kitchen island": .kitchen,

        // Dining
        "dining table": .diningRoom,
        "dining chair": .diningRoom,
        "china cabinet": .diningRoom,
        "buffet": .diningRoom,

        // Living Room
        "sofa": .livingRoom,
        "couch": .livingRoom,
        "television": .livingRoom,
        "tv": .livingRoom,
        "coffee table": .livingRoom,
        "fireplace": .livingRoom,
        "entertainment center": .livingRoom,

        // Bedroom
        "bed": .bedroom,
        "mattress": .bedroom,
        "dresser": .bedroom,
        "nightstand": .bedroom,
        "wardrobe": .bedroom,
        "closet": .bedroom,

        // Bathroom
        "toilet": .bathroom,
        "bathtub": .bathroom,
        "shower": .bathroom,
        "bathroom sink": .bathroom,
        "vanity": .bathroom,

        // Garage
        "garage door": .garage,
        "car": .garage,
        "workbench": .garage,
        "tool chest": .garage,

        // Office
        "desk": .office,
        "computer": .office,
        "office chair": .office,
        "bookshelf": .office,
        "filing cabinet": .office,

        // Utility (mapped to basement or other)
        "water heater": .basement,
        "furnace": .basement,
        "hvac": .other,
        "electrical panel": .garage
    ]

    private init() {}

    // MARK: - Analyze Single Image

    /// Analyze a single image to identify room type
    func identifyRoom(from image: UIImage) async throws -> RoomIdentification {
        isProcessing = true
        defer { isProcessing = false }

        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw RoomIdentificationError.invalidImage
        }

        let base64Image = imageData.base64EncodedString()

        // Build the request to Gemini via proxy
        let requestBody: [String: Any] = [
            "action": "identify-room",
            "imageData": base64Image,
            "prompt": buildIdentificationPrompt()
        ]

        let url = URL(string: "\(proxyBaseURL)/ai/gemini")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        urlRequest.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RoomIdentificationError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RoomIdentificationError.apiError(message: errorText)
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool,
              success,
              let resultJson = json["result"] as? String else {
            // Fallback to local heuristics if API fails
            return try await identifyRoomLocally(from: image)
        }

        return try parseIdentificationResult(resultJson)
    }

    // MARK: - Analyze Multiple Frames (Walkthrough)

    /// Analyze multiple frames from a walkthrough to identify room transitions
    func identifyRoomsFromWalkthrough(
        transitions: [WalkthroughTransition],
        keyFrames: [(timestamp: TimeInterval, image: UIImage)]
    ) async throws -> [RoomIdentification] {
        isProcessing = true
        defer { isProcessing = false }

        var identifications: [RoomIdentification] = []

        // Analyze frames at transition points first (these are likely room boundaries)
        for transition in transitions {
            // Find the closest key frame
            if let closestFrame = keyFrames.min(by: { abs($0.timestamp - transition.timestamp) < abs($1.timestamp - transition.timestamp) }) {
                if abs(closestFrame.timestamp - transition.timestamp) < 3.0 {
                    do {
                        let identification = try await identifyRoom(from: closestFrame.image)
                        identifications.append(identification)
                    } catch {
                        // Continue with other frames
                        print("Failed to identify room at \(transition.timestamp): \(error)")
                    }
                }
            }
        }

        // If no transition frames, sample from key frames
        if identifications.isEmpty && !keyFrames.isEmpty {
            // Sample up to 5 evenly spaced frames
            let step = max(1, keyFrames.count / 5)
            for i in stride(from: 0, to: keyFrames.count, by: step) {
                do {
                    let identification = try await identifyRoom(from: keyFrames[i].image)
                    identifications.append(identification)
                } catch {
                    print("Failed to identify room from frame \(i): \(error)")
                }
            }
        }

        // Deduplicate consecutive same room types
        return deduplicateIdentifications(identifications)
    }

    // MARK: - Local Fallback (No Network)

    /// Fallback identification using Core ML Vision (works offline)
    private func identifyRoomLocally(from image: UIImage) async throws -> RoomIdentification {
        // Use basic image analysis to detect common objects
        // This is a simplified version - in production, you'd use a Core ML model

        // For now, return an "Unknown" room with low confidence
        // The PM can manually select the correct category
        return RoomIdentification(
            id: UUID(),
            suggestedCategory: .other,
            confidence: 0.3,
            detectedObjects: [],
            alternativeCategories: RoomCategory.allCases.map { category in
                RoomIdentification.AlternativeCategory(
                    category: category,
                    confidence: 0.1,
                    reason: "Select if this matches the room"
                )
            },
            notes: "Unable to automatically identify room. Please select the room type.",
            isAmbiguous: true,
            combinedWith: nil
        )
    }

    // MARK: - Private Helpers

    private func buildIdentificationPrompt() -> String {
        return """
        Analyze this image of a room interior and identify:

        1. What type of room is this? Options:
           - Kitchen
           - Bathroom
           - Bedroom
           - Living Room
           - Dining Room
           - Laundry
           - Garage
           - Office
           - Utility Room
           - Hallway
           - Entryway/Foyer
           - Closet
           - Other

        2. List all visible objects that indicate the room type (e.g., "refrigerator", "toilet", "bed")

        3. Confidence level (0.0 to 1.0)

        4. Is this room ambiguous or a combination? (e.g., open kitchen/dining)

        5. Any alternative room type this could be

        Respond in JSON format:
        {
            "roomType": "Kitchen",
            "confidence": 0.95,
            "detectedObjects": [
                {"name": "refrigerator", "confidence": 0.98, "roomIndicator": "Kitchen"},
                {"name": "stove", "confidence": 0.95, "roomIndicator": "Kitchen"}
            ],
            "isAmbiguous": false,
            "combinedWith": null,
            "alternatives": [
                {"category": "Dining Room", "confidence": 0.2, "reason": "Has eating area"}
            ],
            "notes": "Standard residential kitchen with modern appliances"
        }
        """
    }

    private func parseIdentificationResult(_ jsonString: String) throws -> RoomIdentification {
        guard let data = jsonString.data(using: .utf8) else {
            throw RoomIdentificationError.parseError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RoomIdentificationError.parseError
        }

        let roomTypeString = json["roomType"] as? String ?? "Other"
        let confidence = Float(json["confidence"] as? Double ?? 0.5)
        let isAmbiguous = json["isAmbiguous"] as? Bool ?? false
        let combinedWithString = json["combinedWith"] as? String
        let notes = json["notes"] as? String ?? ""

        // Parse detected objects
        var detectedObjects: [RoomIdentification.DetectedObject] = []
        if let objectsArray = json["detectedObjects"] as? [[String: Any]] {
            for obj in objectsArray {
                let name = obj["name"] as? String ?? "Unknown"
                let objConfidence = Float(obj["confidence"] as? Double ?? 0.5)
                let indicatorString = obj["roomIndicator"] as? String
                let indicator = indicatorString.flatMap { RoomCategory(rawValue: $0) }

                detectedObjects.append(RoomIdentification.DetectedObject(
                    name: name,
                    confidence: objConfidence,
                    roomIndicator: indicator
                ))
            }
        }

        // Parse alternatives
        var alternatives: [RoomIdentification.AlternativeCategory] = []
        if let altsArray = json["alternatives"] as? [[String: Any]] {
            for alt in altsArray {
                let catString = alt["category"] as? String ?? "Other"
                let altConfidence = Float(alt["confidence"] as? Double ?? 0.1)
                let reason = alt["reason"] as? String ?? ""

                if let category = RoomCategory(rawValue: catString) {
                    alternatives.append(RoomIdentification.AlternativeCategory(
                        category: category,
                        confidence: altConfidence,
                        reason: reason
                    ))
                }
            }
        }

        return RoomIdentification(
            id: UUID(),
            suggestedCategory: RoomCategory(rawValue: roomTypeString) ?? .other,
            confidence: confidence,
            detectedObjects: detectedObjects,
            alternativeCategories: alternatives,
            notes: notes,
            isAmbiguous: isAmbiguous,
            combinedWith: combinedWithString.flatMap { RoomCategory(rawValue: $0) }
        )
    }

    private func deduplicateIdentifications(_ identifications: [RoomIdentification]) -> [RoomIdentification] {
        var result: [RoomIdentification] = []
        var lastCategory: RoomCategory?

        for identification in identifications {
            // Skip if same as previous room type (likely same room)
            if identification.suggestedCategory != lastCategory {
                result.append(identification)
                lastCategory = identification.suggestedCategory
            }
        }

        return result
    }

    // MARK: - Apply Heuristics

    /// Apply object-based heuristics to improve room detection
    func applyHeuristics(to identification: RoomIdentification) -> RoomIdentification {
        var objectVotes: [RoomCategory: Float] = [:]

        // Count votes from detected objects
        for obj in identification.detectedObjects {
            let objNameLower = obj.name.lowercased()

            // Check our mapping
            if let mappedRoom = objectRoomMapping[objNameLower] {
                objectVotes[mappedRoom, default: 0] += obj.confidence
            }

            // Also use the AI-suggested indicator
            if let indicator = obj.roomIndicator {
                objectVotes[indicator, default: 0] += obj.confidence * 0.5
            }
        }

        // Find the room type with most votes
        if let (bestCategory, bestScore) = objectVotes.max(by: { $0.value < $1.value }) {
            if bestScore > identification.confidence {
                // Object evidence is stronger than AI suggestion
                return RoomIdentification(
                    id: identification.id,
                    suggestedCategory: bestCategory,
                    confidence: min(bestScore, 1.0),
                    detectedObjects: identification.detectedObjects,
                    alternativeCategories: identification.alternativeCategories,
                    notes: identification.notes + " (Adjusted based on object detection)",
                    isAmbiguous: identification.isAmbiguous,
                    combinedWith: identification.combinedWith
                )
            }
        }

        return identification
    }
}

// MARK: - Errors

enum RoomIdentificationError: LocalizedError {
    case invalidImage
    case invalidResponse
    case apiError(message: String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process the image"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let message):
            return "API error: \(message)"
        case .parseError:
            return "Could not parse room identification result"
        }
    }
}
