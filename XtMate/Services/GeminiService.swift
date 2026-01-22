import Foundation
import UIKit
import AVFoundation
import Combine

// MARK: - Gemini Service for Isometric Rendering + Voice Processing
// Uses Gemini 2.0 Flash with native image generation (Nano Banana / Imagen 3)

@available(iOS 16.0, *)
class GeminiService: ObservableObject {
    static let shared = GeminiService()

    // Use web API proxy for Gemini calls (keeps API key secure on server)
    private var proxyBaseURL: String { APIKeys.apiBaseURL }

    // Direct Gemini API (only used if API key is available locally)
    private var apiKey: String { APIKeys.gemini }
    private let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    // Gemini 2.0 Flash with native image generation (Nano Banana)
    // This model supports responseModalities: ["IMAGE"] for image output
    private let imageGenModelId = "gemini-2.0-flash-exp"

    // Standard model for text/multimodal tasks
    private let textModelId = "gemini-2.0-flash-exp"

    // Whether to use proxy (true) or direct API (false)
    private var useProxy: Bool {
        // Always prefer proxy for security, fall back to direct only if API key is local
        return apiKey.isEmpty || !apiKey.starts(with: "AI")
    }

    @Published var isProcessing = false
    @Published var lastError: String?
    @Published var conversationHistory: [GeminiMessage] = []

    private init() {}

    // MARK: - Generate Isometric Render from Room Geometry (Nano Banana)

    /// Uses Gemini 2.0's native image generation capability (Nano Banana/Imagen 3)
    /// to create a professional isometric architectural render from room geometry.
    /// Routes through web API proxy to keep API key secure.
    func generateIsometricRender(
        roomGeometry: RoomGeometryData,
        annotations: [DamageAnnotationData] = [],
        style: IsometricStyle = .clean
    ) async throws -> UIImage {
        await MainActor.run { isProcessing = true }
        defer { Task { @MainActor in isProcessing = false } }

        // Always use proxy for security
        if useProxy {
            return try await generateIsometricRenderViaProxy(
                roomGeometry: roomGeometry,
                annotations: annotations,
                style: style
            )
        }

        // Fallback to direct API call if local API key is available
        return try await generateIsometricRenderDirect(
            roomGeometry: roomGeometry,
            annotations: annotations,
            style: style
        )
    }

    // MARK: - Proxy-based Isometric Render (Recommended)

    /// Generates isometric render via web API proxy - keeps API key secure on server
    private func generateIsometricRenderViaProxy(
        roomGeometry: RoomGeometryData,
        annotations: [DamageAnnotationData] = [],
        style: IsometricStyle = .clean
    ) async throws -> UIImage {
        print("🌐 Proxy: Requesting isometric render via web API...")

        let url = URL(string: "\(proxyBaseURL)/ai/gemini")!

        // Build room data for the proxy
        let roomData: [String: Any] = [
            "name": roomGeometry.category,
            "category": roomGeometry.category,
            "dimensions": [
                "lengthFt": roomGeometry.lengthFt,
                "widthFt": roomGeometry.widthFt,
                "heightFt": roomGeometry.heightFt,
                "squareFeet": roomGeometry.squareFeet
            ],
            "walls": roomGeometry.walls.map { wall in
                [
                    "lengthFt": wall.lengthFt,
                    "heightFt": wall.heightFt
                ]
            },
            "doors": roomGeometry.doors.map { door in
                [
                    "width": door.widthFt,
                    "height": door.heightFt
                ]
            },
            "windows": roomGeometry.windows.map { window in
                [
                    "width": window.widthFt,
                    "height": window.heightFt
                ]
            },
            "objects": roomGeometry.objects.map { obj in
                [
                    "label": obj.name,
                    "category": obj.name
                ]
            },
            "materials": [
                "floor": roomGeometry.floorMaterial ?? "",
                "wall": roomGeometry.wallMaterial ?? "",
                "ceiling": roomGeometry.ceilingMaterial ?? ""
            ]
        ]

        // Add damage info if annotations exist
        var damageInfo: [String: Any]?
        if let firstAnnotation = annotations.first {
            damageInfo = [
                "type": firstAnnotation.damageType,
                "severity": firstAnnotation.severity,
                "affectedSurfaces": firstAnnotation.affectedSurfaces
            ]
        }

        var requestBody: [String: Any] = [
            "action": "isometric-render",
            "roomData": roomData
        ]

        if let damage = damageInfo {
            var roomDataWithDamage = roomData
            roomDataWithDamage["damage"] = damage
            requestBody["roomData"] = roomDataWithDamage
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        urlRequest.timeoutInterval = 60 // Image generation can take time

        print("🌐 Proxy: Sending request to \(url)")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("🌐 Proxy Response Status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            print("🌐 Proxy Error Response: \(responseText.prefix(500))")

            // Try to extract error message
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMsg = json["error"] as? String {
                throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
            }

            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: responseText)
        }

        // Parse proxy response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool,
              success,
              let imageData64 = json["imageData"] as? String else {
            print("🌐 Proxy: Could not parse response or no image data")
            print("   Response preview: \(responseText.prefix(500))")

            // Check if we should fall back to Imagen via proxy
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["error"] != nil {
                // Try Imagen 3 as fallback
                print("🌐 Proxy: Trying Imagen 3 fallback...")
                return try await generateImageWithImagen3ViaProxy(
                    roomGeometry: roomGeometry,
                    annotations: annotations,
                    style: style
                )
            }

            throw GeminiError.noImageGenerated
        }

        guard let imageData = Data(base64Encoded: imageData64) else {
            throw GeminiError.invalidImageData
        }

        guard let image = UIImage(data: imageData) else {
            throw GeminiError.invalidImageData
        }

        print("🌐 Proxy: Image generated successfully! Size: \(image.size)")
        return image
    }

    // MARK: - Imagen 3 via Proxy (Fallback)

    /// Fallback to Imagen 3 via proxy for image generation
    private func generateImageWithImagen3ViaProxy(
        roomGeometry: RoomGeometryData,
        annotations: [DamageAnnotationData] = [],
        style: IsometricStyle = .clean
    ) async throws -> UIImage {
        print("🌐 Proxy: Requesting Imagen 3 render via web API...")

        let url = URL(string: "\(proxyBaseURL)/ai/gemini")!
        let prompt = buildIsometricPrompt(geometry: roomGeometry, annotations: annotations, style: style)

        let requestBody: [String: Any] = [
            "action": "imagen",
            "prompt": prompt
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        urlRequest.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("🌐 Proxy Imagen 3 Error: \(errorText.prefix(500))")
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: "Image generation not available. Try using the 3D Model view instead.")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool,
              success,
              let imageData64 = json["imageData"] as? String else {
            throw GeminiError.noImageGenerated
        }

        guard let imageData = Data(base64Encoded: imageData64) else {
            throw GeminiError.invalidImageData
        }

        guard let image = UIImage(data: imageData) else {
            throw GeminiError.invalidImageData
        }

        print("🌐 Proxy Imagen 3: Image generated successfully! Size: \(image.size)")
        return image
    }

    // MARK: - Direct API Isometric Render (Fallback if local key available)

    /// Direct Gemini API call - only used if API key is configured locally
    private func generateIsometricRenderDirect(
        roomGeometry: RoomGeometryData,
        annotations: [DamageAnnotationData] = [],
        style: IsometricStyle = .clean
    ) async throws -> UIImage {
        let prompt = buildIsometricPrompt(geometry: roomGeometry, annotations: annotations, style: style)

        print("🍌 NanoBanana Direct: Requesting image generation...")
        print("   Model: \(imageGenModelId)")
        print("   Prompt length: \(prompt.count) chars")

        // Build request with image generation config
        // Nano Banana requires responseModalities: ["IMAGE"] or ["TEXT", "IMAGE"]
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "responseModalities": ["IMAGE", "TEXT"],
                "responseMimeType": "text/plain"
            ]
        ]

        let url = URL(string: "\(geminiBaseURL)/\(imageGenModelId):generateContent?key=\(apiKey)")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        // Debug: Print response for troubleshooting
        let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("🍌 NanoBanana Response Status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            print("🍌 NanoBanana Error Response: \(responseText.prefix(500))")
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: responseText)
        }

        // Parse response - look for inline image data
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            print("🍌 NanoBanana: Could not parse response structure")
            print("   Response preview: \(responseText.prefix(500))")
            throw GeminiError.noImageGenerated
        }

        // Look for inline image data in parts
        for part in parts {
            if let inlineData = part["inlineData"] as? [String: Any],
               let mimeType = inlineData["mimeType"] as? String,
               let base64Data = inlineData["data"] as? String {

                print("🍌 NanoBanana: Found image! MIME: \(mimeType)")

                guard let imageData = Data(base64Encoded: base64Data) else {
                    throw GeminiError.invalidImageData
                }

                guard let image = UIImage(data: imageData) else {
                    throw GeminiError.invalidImageData
                }

                print("🍌 NanoBanana: Image generated successfully! Size: \(image.size)")
                return image
            }
        }

        // If no image found, check if there's text response (model might have limitations)
        var textResponse = ""
        for part in parts {
            if let text = part["text"] as? String {
                textResponse += text
            }
        }

        if !textResponse.isEmpty {
            print("🍌 NanoBanana: Got text response instead of image:")
            print("   \(textResponse.prefix(200))")
        }

        // If Gemini 2.0 native didn't return an image, try Imagen 3 endpoint
        print("🍌 NanoBanana: Gemini 2.0 didn't return image, trying Imagen 3 endpoint...")
        return try await generateImageWithImagen3Direct(prompt: prompt)
    }

    // MARK: - Imagen 3 Direct API (Fallback when local key available)

    /// Fallback to Imagen 3 API directly for image generation
    private func generateImageWithImagen3Direct(prompt: String) async throws -> UIImage {
        // Imagen 3 via generativelanguage.googleapis.com
        let imagen3ModelId = "imagen-3.0-generate-002"
        let url = URL(string: "\(geminiBaseURL)/\(imagen3ModelId):predict?key=\(apiKey)")!

        let requestBody: [String: Any] = [
            "instances": [
                ["prompt": prompt]
            ],
            "parameters": [
                "sampleCount": 1,
                "aspectRatio": "1:1",
                "safetyFilterLevel": "block_few",
                "personGeneration": "dont_allow"
            ]
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("🖼️ Imagen 3 Direct: Requesting image generation...")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("🖼️ Imagen 3 Direct Response Status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            print("🖼️ Imagen 3 Direct Error: \(responseText.prefix(500))")
            // If Imagen 3 also fails, throw the error
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: "Image generation not available. Try using the 3D Model view instead.")
        }

        // Parse Imagen 3 response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let predictions = json["predictions"] as? [[String: Any]],
              let firstPrediction = predictions.first,
              let bytesBase64 = firstPrediction["bytesBase64Encoded"] as? String else {
            print("🖼️ Imagen 3 Direct: Could not parse response")
            throw GeminiError.noImageGenerated
        }

        guard let imageData = Data(base64Encoded: bytesBase64) else {
            throw GeminiError.invalidImageData
        }

        guard let image = UIImage(data: imageData) else {
            throw GeminiError.invalidImageData
        }

        print("🖼️ Imagen 3 Direct: Image generated successfully! Size: \(image.size)")
        return image
    }

    // MARK: - Process Voice for Damage Description

    func processVoiceForDamage(
        audioData: Data,
        roomContext: RoomGeometryData,
        currentScreenshot: UIImage?
    ) async throws -> DamageInterpretation {
        isProcessing = true
        defer { isProcessing = false }

        var parts: [GeminiPart] = []

        // Add context prompt
        let contextPrompt = """
        You are a property damage assessment assistant for XtMate, helping Project Managers document restoration claims.

        Room Context:
        - Type: \(roomContext.category)
        - Dimensions: \(roomContext.lengthFt)' x \(roomContext.widthFt)' x \(roomContext.heightFt)'
        - Square Footage: \(roomContext.squareFeet) SF
        - Floor Material: \(roomContext.floorMaterial ?? "unknown")
        - Wall Material: \(roomContext.wallMaterial ?? "unknown")
        - Ceiling Material: \(roomContext.ceilingMaterial ?? "unknown")

        The PM will describe damage they see. Extract:
        1. Damage type (water, fire, smoke, mold, impact, wind)
        2. Severity (light, moderate, heavy)
        3. Affected surfaces (floor, wall, ceiling)
        4. Water line height if applicable (in inches)
        5. Specific notes about the damage
        6. Suggested Xactimate line items

        Respond in JSON format:
        {
            "damageType": "water|fire|smoke|mold|impact|wind",
            "severity": "light|moderate|heavy",
            "affectedSurfaces": ["floor", "wall", "ceiling"],
            "waterLineHeightInches": null or number,
            "notes": "description",
            "suggestedLineItems": [
                {"selector": "WTR EXTRT", "description": "Extract water", "quantity": 100, "unit": "SF"}
            ]
        }
        """
        parts.append(GeminiPart(text: contextPrompt))

        // Add screenshot if available
        if let screenshot = currentScreenshot,
           let imageData = screenshot.jpegData(compressionQuality: 0.8) {
            parts.append(GeminiPart(
                inlineData: GeminiInlineData(
                    mimeType: "image/jpeg",
                    data: imageData.base64EncodedString()
                )
            ))
        }

        // Add audio
        parts.append(GeminiPart(
            inlineData: GeminiInlineData(
                mimeType: "audio/wav",
                data: audioData.base64EncodedString()
            )
        ))

        let request = GeminiRequest(
            contents: [GeminiContent(parts: parts)],
            generationConfig: GeminiGenerationConfig(
                responseMimeType: "application/json"
            )
        )

        let response = try await sendRequest(request)

        guard let text = response.extractText() else {
            throw GeminiError.noTextResponse
        }

        // Parse JSON response
        guard let jsonData = text.data(using: .utf8),
              let interpretation = try? JSONDecoder().decode(DamageInterpretation.self, from: jsonData) else {
            throw GeminiError.invalidJsonResponse
        }

        return interpretation
    }

    // MARK: - Conversational Annotation Assistant

    func chat(
        message: String,
        roomContext: RoomGeometryData,
        screenshot: UIImage? = nil
    ) async throws -> AssistantResponse {
        isProcessing = true
        defer { isProcessing = false }

        // Add user message to history
        conversationHistory.append(GeminiMessage(role: "user", content: message))

        var parts: [GeminiPart] = []

        // System context
        let systemPrompt = """
        You are XtMate Assistant, helping Project Managers document property damage for insurance claims.

        Current Room: \(roomContext.category)
        Dimensions: \(roomContext.lengthFt)' x \(roomContext.widthFt)' (\(roomContext.squareFeet) SF)

        Help the PM:
        1. Identify and describe damage
        2. Mark affected areas on the isometric view
        3. Suggest appropriate Xactimate line items
        4. Calculate quantities based on room dimensions

        Be concise and professional. If you need clarification, ask specific questions.
        When suggesting line items, use standard Xactimate selectors.
        """
        parts.append(GeminiPart(text: systemPrompt))

        // Add conversation history
        for msg in conversationHistory.suffix(10) {
            parts.append(GeminiPart(text: "\(msg.role): \(msg.content)"))
        }

        // Add screenshot if provided
        if let screenshot = screenshot,
           let imageData = screenshot.jpegData(compressionQuality: 0.8) {
            parts.append(GeminiPart(
                inlineData: GeminiInlineData(
                    mimeType: "image/jpeg",
                    data: imageData.base64EncodedString()
                )
            ))
        }

        let request = GeminiRequest(
            contents: [GeminiContent(parts: parts)],
            generationConfig: nil
        )

        let response = try await sendRequest(request)

        guard let text = response.extractText() else {
            throw GeminiError.noTextResponse
        }

        // Add assistant response to history
        conversationHistory.append(GeminiMessage(role: "assistant", content: text))

        return AssistantResponse(
            message: text,
            suggestedAnnotations: parseAnnotationSuggestions(from: text),
            suggestedLineItems: parseLineItemSuggestions(from: text)
        )
    }

    // MARK: - Analyze Image with Custom Prompt

    /// Analyzes an image using a custom text prompt and returns the text response
    /// Used by PreliminaryReportService to identify room types and damage
    func analyzeImageWithPrompt(_ image: UIImage, prompt: String) async throws -> String {
        await MainActor.run { isProcessing = true }
        defer { Task { @MainActor in isProcessing = false } }

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw GeminiError.invalidImageData
        }

        let parts: [GeminiPart] = [
            GeminiPart(text: prompt),
            GeminiPart(
                inlineData: GeminiInlineData(
                    mimeType: "image/jpeg",
                    data: imageData.base64EncodedString()
                )
            )
        ]

        let request = GeminiRequest(
            contents: [GeminiContent(parts: parts)],
            generationConfig: nil
        )

        let response = try await sendRequest(request)

        guard let text = response.extractText() else {
            throw GeminiError.noTextResponse
        }

        return text
    }

    // MARK: - Update Render with Annotations

    func updateRenderWithHighlights(
        baseImage: UIImage,
        highlights: [DamageHighlight]
    ) async throws -> UIImage {
        isProcessing = true
        defer { isProcessing = false }

        guard let imageData = baseImage.jpegData(compressionQuality: 0.9) else {
            throw GeminiError.invalidImageData
        }

        let highlightDescriptions = highlights.map { highlight in
            "- \(highlight.surfaceType) at position (\(highlight.normalizedX), \(highlight.normalizedY)): \(highlight.damageType) damage, \(highlight.severity) severity"
        }.joined(separator: "\n")

        let prompt = """
        Update this isometric room render to show damage highlights:

        \(highlightDescriptions)

        Visual requirements:
        - Use red/orange overlay for damaged areas
        - Show water line if applicable (blue dashed line at specified height)
        - Add damage type icons at annotation points
        - Maintain the clean architectural style
        - Keep walls, windows, doors visible

        Generate the updated image.
        """

        let request = GeminiRequest(
            contents: [
                GeminiContent(parts: [
                    GeminiPart(
                        inlineData: GeminiInlineData(
                            mimeType: "image/jpeg",
                            data: imageData.base64EncodedString()
                        )
                    ),
                    GeminiPart(text: prompt)
                ])
            ],
            generationConfig: GeminiGenerationConfig(
                responseModalities: ["IMAGE", "TEXT"],
                responseMimeType: "image/png"
            )
        )

        let response = try await sendRequest(request)

        guard let newImageData = response.extractImageData(),
              let newImage = UIImage(data: newImageData) else {
            throw GeminiError.noImageGenerated
        }

        return newImage
    }

    // MARK: - Private Helpers

    private func buildIsometricPrompt(
        geometry: RoomGeometryData,
        annotations: [DamageAnnotationData],
        style: IsometricStyle
    ) -> String {
        // Nano Banana works best with clear, visual descriptions
        // Focus on what the image should LOOK LIKE rather than technical specs

        let lengthDisplay = String(format: "%.0f", geometry.lengthFt)
        let widthDisplay = String(format: "%.0f", geometry.widthFt)
        let heightDisplay = String(format: "%.0f", geometry.heightFt)

        var prompt = """
        Create a professional isometric 3D architectural illustration of a \(geometry.category.lowercased()) room.

        The image should show:
        - A clean, modern isometric view (30° angle) looking at the corner of the room
        - The room is \(lengthDisplay) feet long by \(widthDisplay) feet wide by \(heightDisplay) feet high
        - White/off-white walls with subtle shadows
        - Light gray or beige floor
        - The view shows two walls and the floor clearly visible
        """

        // Add doors
        if !geometry.doors.isEmpty {
            prompt += "\n- Include \(geometry.doors.count) door(s) - show as brown wooden door panels with frames"
        }

        // Add windows
        if !geometry.windows.isEmpty {
            prompt += "\n- Include \(geometry.windows.count) window(s) - show as light blue glass with white frames"
        }

        // Add objects (simplified)
        if !geometry.objects.isEmpty {
            let objectNames = geometry.objects.map { $0.name }.joined(separator: ", ")
            prompt += "\n- Include these items in the room: \(objectNames)"
        }

        // Add materials if known
        if let floorMat = geometry.floorMaterial {
            prompt += "\n- Floor material: \(floorMat)"
        }

        // Style guidance
        switch style {
        case .clean:
            prompt += """

            Style: Clean, minimalist architectural render. White background. Professional quality like an architectural visualization. No textures, simple shading.
            """
        case .detailed:
            prompt += """

            Style: Detailed architectural visualization with realistic materials and lighting. Show wood grain on doors, glass reflections on windows.
            """
        case .schematic:
            prompt += """

            Style: Blueprint/technical drawing style with light blue lines on white background. Show dimension lines and measurements.
            """
        }

        // Add damage annotations if present
        if !annotations.isEmpty {
            prompt += "\n\nDAMAGE TO VISUALIZE:"
            for annotation in annotations {
                let surfaces = annotation.affectedSurfaces.joined(separator: " and ")
                prompt += "\n- Show \(annotation.severity.lowercased()) \(annotation.damageType.lowercased()) damage on the \(surfaces)"

                if let waterLine = annotation.waterLineHeight {
                    let inches = Int(waterLine)
                    let feet = inches / 12
                    let remainingInches = inches % 12
                    prompt += " with a visible water line at \(feet)'\(remainingInches)\" height"
                }

                // Visual guidance for damage types
                switch annotation.damageType.lowercased() {
                case "water":
                    prompt += " - show as darkened/wet-looking areas with subtle blue tint"
                case "fire":
                    prompt += " - show as blackened/charred areas"
                case "smoke":
                    prompt += " - show as gray/sooty discoloration"
                case "mold":
                    prompt += " - show as dark green/black spotty patches"
                default:
                    prompt += " - highlight with \(annotation.highlightColor) overlay"
                }
            }
        }

        prompt += "\n\nGenerate a single, high-quality isometric room image."

        return prompt
    }

    private func sendRequest(_ request: GeminiRequest) async throws -> GeminiResponse {
        // For text-based requests, we still use direct Gemini API if key is available
        // since these don't require image generation
        let url = URL(string: "\(geminiBaseURL)/\(textModelId):generateContent?key=\(apiKey)")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        return try JSONDecoder().decode(GeminiResponse.self, from: data)
    }

    private func parseAnnotationSuggestions(from text: String) -> [SuggestedAnnotation] {
        // Simple parsing - look for damage mentions
        var suggestions: [SuggestedAnnotation] = []

        let damageTypes = ["water", "fire", "smoke", "mold", "impact", "wind"]
        let surfaces = ["floor", "wall", "ceiling"]

        let lowercased = text.lowercased()

        for damageType in damageTypes {
            if lowercased.contains(damageType) {
                for surface in surfaces {
                    if lowercased.contains(surface) {
                        suggestions.append(SuggestedAnnotation(
                            damageType: damageType,
                            surface: surface,
                            confidence: 0.8
                        ))
                    }
                }
            }
        }

        return suggestions
    }

    private func parseLineItemSuggestions(from text: String) -> [SuggestedLineItem] {
        // Look for Xactimate selectors in the response
        var suggestions: [SuggestedLineItem] = []

        // Common selectors to look for
        let selectorPatterns = [
            ("WTR", "Water extraction"),
            ("DRY", "Drying equipment"),
            ("DEM", "Demolition"),
            ("FLR", "Flooring"),
            ("DRW", "Drywall"),
            ("PNT", "Paint"),
            ("CLN", "Cleaning"),
            ("BSBD", "Baseboard")
        ]

        let uppercased = text.uppercased()

        for (prefix, category) in selectorPatterns {
            if uppercased.contains(prefix) {
                suggestions.append(SuggestedLineItem(
                    selector: prefix,
                    category: category,
                    confidence: 0.7
                ))
            }
        }

        return suggestions
    }

    func clearConversation() {
        conversationHistory.removeAll()
    }
}

// MARK: - Data Models

struct RoomGeometryData: Codable {
    let category: String
    let lengthFt: Double
    let widthFt: Double
    let heightFt: Double
    let squareFeet: Double
    let isRectangular: Bool

    let walls: [WallData]
    let doors: [DoorData]
    let windows: [WindowData]
    let objects: [ObjectData]

    let floorMaterial: String?
    let wallMaterial: String?
    let ceilingMaterial: String?

    struct WallData: Codable {
        let lengthFt: Double
        let heightFt: Double
        let positionDescription: String
    }

    struct DoorData: Codable {
        let widthFt: Double
        let heightFt: Double
        let wallPosition: String
    }

    struct WindowData: Codable {
        let widthFt: Double
        let heightFt: Double
        let wallPosition: String
    }

    struct ObjectData: Codable {
        let name: String
        let positionDescription: String
    }
}

struct DamageAnnotationData: Codable {
    let damageType: String
    let severity: String
    let affectedSurfaces: [String]
    let waterLineHeight: Double?
    let highlightColor: String
}

struct DamageInterpretation: Codable {
    let damageType: String
    let severity: String
    let affectedSurfaces: [String]
    let waterLineHeightInches: Double?
    let notes: String
    let suggestedLineItems: [SuggestedXactimateItem]

    struct SuggestedXactimateItem: Codable {
        let selector: String
        let description: String
        let quantity: Double
        let unit: String
    }
}

struct DamageHighlight {
    let surfaceType: String
    let normalizedX: Double
    let normalizedY: Double
    let damageType: String
    let severity: String
    let waterLineHeight: Double?
}

struct AssistantResponse {
    let message: String
    let suggestedAnnotations: [SuggestedAnnotation]
    let suggestedLineItems: [SuggestedLineItem]
}

struct SuggestedAnnotation {
    let damageType: String
    let surface: String
    let confidence: Double
}

struct SuggestedLineItem {
    let selector: String
    let category: String
    let confidence: Double
}

struct GeminiMessage {
    let role: String
    let content: String
}

enum IsometricStyle {
    case clean
    case detailed
    case schematic

    var description: String {
        switch self {
        case .clean: return "Clean architectural render with minimal detail, white walls, professional look"
        case .detailed: return "Detailed render showing textures, materials, realistic lighting"
        case .schematic: return "Blueprint style with dimension lines and technical annotations"
        }
    }
}

// MARK: - API Models

struct GeminiRequest: Codable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig?
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    var text: String?
    var inlineData: GeminiInlineData?

    init(text: String) {
        self.text = text
    }

    init(inlineData: GeminiInlineData) {
        self.inlineData = inlineData
    }
}

struct GeminiInlineData: Codable {
    let mimeType: String
    let data: String
}

struct GeminiGenerationConfig: Codable {
    var responseModalities: [String]?
    var responseMimeType: String?
}

struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]?
    let error: GeminiErrorResponse?

    func extractText() -> String? {
        candidates?.first?.content?.parts?.compactMap { $0.text }.joined()
    }

    func extractImageData() -> Data? {
        guard let part = candidates?.first?.content?.parts?.first(where: { $0.inlineData != nil }),
              let base64 = part.inlineData?.data else {
            return nil
        }
        return Data(base64Encoded: base64)
    }
}

struct GeminiCandidate: Codable {
    let content: GeminiResponseContent?
}

struct GeminiResponseContent: Codable {
    let parts: [GeminiResponsePart]?
}

struct GeminiResponsePart: Codable {
    let text: String?
    let inlineData: GeminiInlineData?
}

struct GeminiErrorResponse: Codable {
    let message: String
    let status: String?
}

enum GeminiError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case noImageGenerated
    case invalidImageData
    case noTextResponse
    case invalidJsonResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Gemini API"
        case .apiError(let code, let msg): return "API Error (\(code)): \(msg)"
        case .noImageGenerated: return "No image was generated"
        case .invalidImageData: return "Invalid image data received"
        case .noTextResponse: return "No text response received"
        case .invalidJsonResponse: return "Could not parse JSON response"
        }
    }
}
