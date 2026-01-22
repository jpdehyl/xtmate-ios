import SwiftUI
import RoomPlan

// MARK: - Damage Annotation Assistant View

@available(iOS 16.0, *)
struct DamageAnnotationAssistant: View {
    let capturedRoom: CapturedRoom
    let roomGeometry: RoomGeometryData
    @Binding var annotations: [DamageAnnotation]
    let onLineItemsGenerated: (([SuggestedXactimateLineItem]) -> Void)?

    @StateObject private var geminiService = GeminiService.shared
    @StateObject private var voiceService = VoiceRecordingService.shared

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isProcessingVoice = false
    @State private var selectedSurface: SurfaceHit?
    @State private var pendingAnnotation: PendingAnnotation?
    @State private var suggestedLineItems: [SuggestedXactimateLineItem] = []
    @State private var showingScopePreview = false
    @State private var audioData: Data?
    @State private var audioURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Isometric view at top
            IsometricRoomView(
                capturedRoom: capturedRoom,
                annotations: annotations,
                onSurfaceTapped: { hit in
                    selectedSurface = hit
                    handleSurfaceTap(hit)
                }
            )
            .frame(height: 300)

            Divider()

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Welcome message
                        if messages.isEmpty {
                            AssistantMessageBubble(
                                message: "Hi! I'm here to help you document damage in this \(roomGeometry.category). Tap on the isometric view to select a surface, or describe the damage you see.",
                                suggestions: [
                                    "Water damage on floor",
                                    "Smoke damage on walls",
                                    "Mold in corner"
                                ],
                                onSuggestionTap: { suggestion in
                                    sendMessage(suggestion)
                                }
                            )
                        }

                        ForEach(messages) { message in
                            if message.isUser {
                                UserMessageBubble(message: message.content)
                            } else {
                                AssistantMessageBubble(
                                    message: message.content,
                                    suggestions: message.suggestions,
                                    onSuggestionTap: { suggestion in
                                        sendMessage(suggestion)
                                    }
                                )
                            }
                        }

                        // Processing indicator
                        if geminiService.isProcessing || isProcessingVoice {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Analyzing...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }

            // Pending annotation preview
            if let pending = pendingAnnotation {
                PendingAnnotationCard(
                    annotation: pending,
                    onConfirm: {
                        confirmAnnotation(pending)
                    },
                    onEdit: {
                        // Could open edit sheet
                    },
                    onCancel: {
                        pendingAnnotation = nil
                    }
                )
            }

            // Generated scope preview
            if !suggestedLineItems.isEmpty {
                SuggestedScopeCard(
                    lineItems: suggestedLineItems,
                    onAccept: {
                        onLineItemsGenerated?(suggestedLineItems)
                        suggestedLineItems = []
                    },
                    onDismiss: {
                        suggestedLineItems = []
                    }
                )
            }

            Divider()

            // Input area
            HStack(spacing: 12) {
                // Voice recording button
                VoiceInputButton(
                    isRecording: voiceService.isRecording,
                    audioLevel: voiceService.audioLevel,
                    onTap: {
                        if voiceService.isRecording {
                            stopAndProcessVoice()
                        } else {
                            startVoiceRecording()
                        }
                    }
                )

                // Text input
                TextField("Describe the damage...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage(inputText)
                    }

                // Send button
                Button(action: {
                    sendMessage(inputText)
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(inputText.isEmpty ? .gray : .blue)
                }
                .disabled(inputText.isEmpty)
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Actions

    private func handleSurfaceTap(_ hit: SurfaceHit) {
        let surfaceDescription = "\(hit.surfaceType.rawValue) at position (\(String(format: "%.1f", hit.normalizedPosition.x)), \(String(format: "%.1f", hit.normalizedPosition.y)))"

        addMessage(
            "You selected: \(surfaceDescription)",
            isUser: false,
            suggestions: [
                "Mark water damage here",
                "Mark smoke damage here",
                "This area is affected"
            ]
        )
    }

    private func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }

        addMessage(text, isUser: true)
        inputText = ""

        Task {
            await processTextInput(text)
        }
    }

    private func processTextInput(_ text: String) async {
        do {
            // Take screenshot of current view for context
            // In real implementation, capture the SceneKit view
            let response = try await geminiService.chat(
                message: text,
                roomContext: roomGeometry,
                screenshot: nil
            )

            await MainActor.run {
                // Add assistant response
                addMessage(
                    response.message,
                    isUser: false,
                    suggestions: generateFollowUpSuggestions(from: response)
                )

                // If annotations were suggested, create pending annotation
                if let firstAnnotation = response.suggestedAnnotations.first {
                    createPendingAnnotation(from: firstAnnotation)
                }

                // If line items were suggested, show them
                if !response.suggestedLineItems.isEmpty {
                    suggestedLineItems = response.suggestedLineItems.map { item in
                        SuggestedXactimateLineItem(
                            selector: item.selector,
                            description: item.category,
                            quantity: 0, // Would be calculated
                            unit: "SF",
                            confidence: item.confidence
                        )
                    }
                }
            }
        } catch {
            await MainActor.run {
                addMessage(
                    "Sorry, I had trouble understanding that. Could you describe the damage in more detail?",
                    isUser: false,
                    suggestions: ["Water damage", "Fire damage", "Smoke damage", "Mold"]
                )
            }
        }
    }

    private func startVoiceRecording() {
        Task {
            let hasPermission = await voiceService.requestPermissions()
            if hasPermission {
                do {
                    _ = try voiceService.startRecording()
                } catch {
                    print("Failed to start recording: \(error)")
                }
            }
        }
    }

    private func stopAndProcessVoice() {
        guard let audioData = voiceService.stopRecording() else { return }

        isProcessingVoice = true
        addMessage("[Voice message]", isUser: true)

        Task {
            do {
                let interpretation = try await geminiService.processVoiceForDamage(
                    audioData: audioData,
                    roomContext: roomGeometry,
                    currentScreenshot: nil
                )

                await MainActor.run {
                    isProcessingVoice = false

                    // Create pending annotation from voice interpretation
                    let pending = PendingAnnotation(
                        damageType: DamageType(rawValue: interpretation.damageType) ?? .water,
                        severity: DamageSeverity(rawValue: interpretation.severity) ?? .moderate,
                        affectedSurfaces: Set(interpretation.affectedSurfaces.compactMap { AffectedSurface(rawValue: $0) }),
                        waterLineHeight: interpretation.waterLineHeightInches,
                        notes: interpretation.notes,
                        position: selectedSurface?.normalizedPosition ?? CGPoint(x: 0.5, y: 0.5)
                    )
                    pendingAnnotation = pending

                    // Show suggested line items
                    suggestedLineItems = interpretation.suggestedLineItems.map { item in
                        SuggestedXactimateLineItem(
                            selector: item.selector,
                            description: item.description,
                            quantity: item.quantity,
                            unit: item.unit,
                            confidence: 0.8
                        )
                    }

                    addMessage(
                        "I understood: \(interpretation.damageType) damage (\(interpretation.severity)) affecting \(interpretation.affectedSurfaces.joined(separator: ", ")). \(interpretation.notes)",
                        isUser: false,
                        suggestions: ["Confirm annotation", "Add more damage", "Generate scope"]
                    )
                }
            } catch {
                await MainActor.run {
                    isProcessingVoice = false
                    addMessage(
                        "Sorry, I couldn't process that recording. Could you try again or type your description?",
                        isUser: false
                    )
                }
            }
        }
    }

    private func addMessage(_ content: String, isUser: Bool, suggestions: [String] = []) {
        messages.append(ChatMessage(
            content: content,
            isUser: isUser,
            suggestions: suggestions
        ))
    }

    private func generateFollowUpSuggestions(from response: AssistantResponse) -> [String] {
        var suggestions: [String] = []

        if !response.suggestedAnnotations.isEmpty {
            suggestions.append("Confirm annotation")
        }

        if !response.suggestedLineItems.isEmpty {
            suggestions.append("View suggested scope")
        }

        suggestions.append("Add more damage")
        suggestions.append("Generate full scope")

        return suggestions
    }

    private func createPendingAnnotation(from suggested: SuggestedAnnotation) {
        let damageType = DamageType(rawValue: suggested.damageType.capitalized) ?? .water
        let surface = AffectedSurface(rawValue: suggested.surface.capitalized) ?? .floor

        pendingAnnotation = PendingAnnotation(
            damageType: damageType,
            severity: .moderate,
            affectedSurfaces: [surface],
            waterLineHeight: nil,
            notes: "",
            position: selectedSurface?.normalizedPosition ?? CGPoint(x: 0.5, y: 0.5)
        )
    }

    private func confirmAnnotation(_ pending: PendingAnnotation) {
        let annotation = DamageAnnotation(
            position: pending.position,
            damageType: pending.damageType,
            severity: pending.severity,
            affectedSurfaces: pending.affectedSurfaces,
            affectedHeightIn: pending.waterLineHeight,
            notes: pending.notes
        )

        annotations.append(annotation)
        pendingAnnotation = nil

        addMessage(
            "Annotation added! \(pending.damageType.rawValue) damage on \(pending.affectedSurfaces.map { $0.rawValue }.joined(separator: ", ")).",
            isUser: false,
            suggestions: ["Add more damage", "Generate scope", "Done"]
        )
    }
}

// MARK: - Supporting Views

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    var suggestions: [String] = []
}

struct UserMessageBubble: View {
    let message: String

    var body: some View {
        HStack {
            Spacer()
            Text(message)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(18)
                .cornerRadius(18, corners: [.topLeft, .topRight, .bottomLeft])
        }
    }
}

struct AssistantMessageBubble: View {
    let message: String
    var suggestions: [String] = []
    var onSuggestionTap: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text(message)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(18)
                    .cornerRadius(18, corners: [.topLeft, .topRight, .bottomRight])
                Spacer()
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(action: {
                                onSuggestionTap?(suggestion)
                            }) {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.leading, 32)
                }
            }
        }
    }
}

struct VoiceInputButton: View {
    let isRecording: Bool
    let audioLevel: Float
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)

                if isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 2)
                        .frame(width: 44 + CGFloat(audioLevel) * 15, height: 44 + CGFloat(audioLevel) * 15)
                        .animation(.easeOut(duration: 0.1), value: audioLevel)
                }

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .foregroundColor(isRecording ? .white : .blue)
            }
        }
    }
}

struct PendingAnnotation {
    var damageType: DamageType
    var severity: DamageSeverity
    var affectedSurfaces: Set<AffectedSurface>
    var waterLineHeight: Double?
    var notes: String
    var position: CGPoint
}

struct PendingAnnotationCard: View {
    let annotation: PendingAnnotation
    let onConfirm: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: annotation.damageType.icon)
                    .foregroundColor(annotation.damageType.color)
                Text("Pending Annotation")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(annotation.damageType.rawValue)
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading) {
                    Text("Severity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(annotation.severity.rawValue)
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading) {
                    Text("Surfaces")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(annotation.affectedSurfaces.map { $0.rawValue }.joined(separator: ", "))
                        .fontWeight(.medium)
                }
            }

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Text("Edit")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }

                Button(action: onConfirm) {
                    Text("Confirm")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
        .padding()
    }
}

struct SuggestedXactimateLineItem: Identifiable {
    let id = UUID()
    let selector: String
    let description: String
    let quantity: Double
    let unit: String
    let confidence: Double
}

struct SuggestedScopeCard: View {
    let lineItems: [SuggestedXactimateLineItem]
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.blue)
                Text("Suggested Scope Items")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            ForEach(lineItems.prefix(5)) { item in
                HStack {
                    Text(item.selector)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)

                    Text(item.description)
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer()

                    if item.quantity > 0 {
                        Text("\(Int(item.quantity)) \(item.unit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if lineItems.count > 5 {
                Text("+ \(lineItems.count - 5) more items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onAccept) {
                Text("Add to Scope")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
        .padding()
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
