//
//  VideoWalkthroughView.swift
//  XtMate
//
//  SwiftUI view for capturing video walkthroughs to help identify room boundaries.
//  Provides a camera preview with recording controls and real-time transition detection feedback.
//
//  PRD: US-RC-006 - Video/Photo Capture for Room Boundary Hints
//

import SwiftUI
import AVFoundation

// MARK: - Video Walkthrough View

@available(iOS 16.0, *)
struct VideoWalkthroughView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var walkthroughService = VideoWalkthroughService.shared

    let onComplete: ((WalkthroughResult?) -> Void)?
    let onCancel: (() -> Void)?

    @State private var showingPermissionAlert = false
    @State private var showingLightingWarning = false
    @State private var hasStartedRecording = false
    @State private var showingInstructions = true
    @State private var showingRoomIdentification = false
    @State private var isAnalyzingRooms = false
    @State private var walkthroughResult: WalkthroughResult?
    @State private var editableRooms: [EditableRoomIdentification] = []

    @ObservedObject private var roomIdentificationService = RoomIdentificationService.shared

    init(
        onComplete: ((WalkthroughResult?) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView()
                .ignoresSafeArea()

            // Overlay UI
            VStack {
                // Top bar with status
                topBar
                    .padding(.top, 8)

                Spacer()

                // Detected transitions indicator
                if walkthroughService.isRecording && !walkthroughService.detectedTransitions.isEmpty {
                    transitionIndicator
                        .padding(.bottom, 8)
                }

                // Recording controls
                recordingControls
                    .padding(.bottom, 40)
            }

            // Instructions overlay
            if showingInstructions && !hasStartedRecording {
                instructionsOverlay
            }

            // Lighting warning overlay
            if walkthroughService.lightingCondition != .adequate && walkthroughService.isRecording {
                lightingWarningOverlay
            }
        }
        .alert("Camera Access Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                onCancel?()
                dismiss()
            }
        } message: {
            Text("XtMate needs camera access to record video walkthroughs. Please enable it in Settings.")
        }
        .alert("Poor Lighting Detected", isPresented: $showingLightingWarning) {
            Button("Continue Anyway") {
                showingLightingWarning = false
            }
            Button("Retake", role: .cancel) {
                walkthroughService.cancelRecording()
            }
        } message: {
            Text("The lighting conditions are poor, which may affect room boundary detection. Consider moving to a brighter area or turning on lights.")
        }
        .onAppear {
            Task {
                let hasPermission = await walkthroughService.requestPermissions()
                if !hasPermission {
                    showingPermissionAlert = true
                }
            }
        }
        .onDisappear {
            if walkthroughService.isRecording {
                walkthroughService.cancelRecording()
            }
        }
        .fullScreenCover(isPresented: $showingRoomIdentification) {
            RoomIdentificationEditView(
                identifications: $editableRooms,
                keyFrames: [],  // Would pass actual frames
                onConfirmAll: completeWithIdentifiedRooms,
                onCancel: {
                    showingRoomIdentification = false
                }
            )
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Close button
            Button(action: {
                if walkthroughService.isRecording {
                    walkthroughService.cancelRecording()
                }
                onCancel?()
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()

            // Recording duration
            if walkthroughService.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .fill(Color.red.opacity(0.5))
                                .frame(width: 20, height: 20)
                                .scaleEffect(walkthroughService.isRecording ? 1.5 : 1.0)
                                .opacity(walkthroughService.isRecording ? 0 : 1)
                                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: walkthroughService.isRecording)
                        )

                    Text(VideoWalkthroughService.formatDuration(walkthroughService.recordingDuration))
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(20)
            }

            Spacer()

            // Help button
            Button(action: {
                showingInstructions = true
            }) {
                Image(systemName: "questionmark.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Transition Indicator

    private var transitionIndicator: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "door.left.hand.open")
                    .foregroundColor(.green)
                Text("\(walkthroughService.detectedTransitions.count) transitions detected")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            // Mini visualization of detected transitions
            HStack(spacing: 2) {
                ForEach(walkthroughService.detectedTransitions.prefix(10)) { transition in
                    Circle()
                        .fill(colorForTransitionType(transition.transitionType))
                        .frame(width: 8, height: 8)
                }
                if walkthroughService.detectedTransitions.count > 10 {
                    Text("+\(walkthroughService.detectedTransitions.count - 10)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }

    private func colorForTransitionType(_ type: WalkthroughTransition.TransitionType) -> Color {
        switch type {
        case .doorway:
            return .green
        case .opening:
            return .blue
        case .threshold:
            return .orange
        case .turnaround:
            return .purple
        case .unknown:
            return .gray
        }
    }

    // MARK: - Recording Controls

    private var recordingControls: some View {
        VStack(spacing: 20) {
            // Main record/stop button
            Button(action: toggleRecording) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)

                    // Inner indicator
                    if walkthroughService.isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 64, height: 64)
                    }
                }
            }

            // Status text
            Text(walkthroughService.isRecording ? "Tap to stop" : "Tap to start recording")
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.5))
                .cornerRadius(20)

            // Done button (only when recording completed)
            if hasStartedRecording && !walkthroughService.isRecording {
                HStack(spacing: 16) {
                    Button(action: {
                        // Retake
                        hasStartedRecording = false
                        walkthroughService.detectedTransitions = []
                    }) {
                        Label("Retake", systemImage: "arrow.counterclockwise")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.8))
                            .cornerRadius(25)
                    }

                    Button(action: analyzeAndIdentifyRooms) {
                        if isAnalyzingRooms {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(25)
                        } else {
                            Label("Identify Rooms", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(25)
                        }
                    }
                    .disabled(isAnalyzingRooms)
                }
            }
        }
    }

    private func toggleRecording() {
        if walkthroughService.isRecording {
            let _ = walkthroughService.stopRecording()
        } else {
            do {
                let _ = try walkthroughService.startRecording()
                hasStartedRecording = true
                showingInstructions = false
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }

    // MARK: - Room Analysis

    private func analyzeAndIdentifyRooms() {
        isAnalyzingRooms = true

        // Build the result with key frames
        var result = WalkthroughResult(
            videoURL: nil,
            transitions: walkthroughService.detectedTransitions,
            duration: walkthroughService.recordingDuration,
            keyFrames: []  // Key frames are in the service
        )

        Task {
            do {
                // Get key frames from the service
                // Note: In production, you'd access the actual key frames from the service
                // For now, we'll create placeholder identifications based on transitions

                let identifications = try await roomIdentificationService.identifyRoomsFromWalkthrough(
                    transitions: walkthroughService.detectedTransitions,
                    keyFrames: []  // Would pass actual frames here
                )

                result.identifiedRooms = identifications
                editableRooms = identifications.map { $0.editableResult }

                await MainActor.run {
                    walkthroughResult = result
                    isAnalyzingRooms = false
                    showingRoomIdentification = true
                }
            } catch {
                // If analysis fails, create placeholder rooms based on transition count
                await MainActor.run {
                    let roomCount = max(1, walkthroughService.detectedTransitions.filter {
                        $0.transitionType == .doorway || $0.transitionType == .opening
                    }.count + 1)

                    editableRooms = (0..<roomCount).map { i in
                        EditableRoomIdentification(
                            id: UUID(),
                            selectedCategory: .other,
                            customName: "Room \(i + 1)",
                            detectedObjects: [],
                            isConfirmed: false
                        )
                    }

                    walkthroughResult = result
                    isAnalyzingRooms = false
                    showingRoomIdentification = true
                }
            }
        }
    }

    private func completeWithIdentifiedRooms() {
        guard var result = walkthroughResult else { return }
        result.editedRooms = editableRooms
        onComplete?(result)
        dismiss()
    }

    // MARK: - Instructions Overlay

    private var instructionsOverlay: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Video Walkthrough")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 16) {
                    InstructionRow(
                        icon: "figure.walk",
                        text: "Walk slowly through each room"
                    )
                    InstructionRow(
                        icon: "door.left.hand.open",
                        text: "Pause briefly at doorways"
                    )
                    InstructionRow(
                        icon: "arrow.turn.down.right",
                        text: "Turn to face each room as you enter"
                    )
                    InstructionRow(
                        icon: "lightbulb",
                        text: "Ensure good lighting for best results"
                    )
                }
                .padding(.horizontal, 24)

                Text("The app will automatically detect room transitions based on your movement patterns.")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: {
                    showingInstructions = false
                }) {
                    Text("Got it")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
            .padding(.vertical, 40)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: showingInstructions)
    }

    // MARK: - Lighting Warning Overlay

    private var lightingWarningOverlay: some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                Image(systemName: walkthroughService.lightingCondition == .veryPoor ? "exclamationmark.triangle.fill" : "sun.min")
                    .foregroundColor(walkthroughService.lightingCondition == .veryPoor ? .red : .yellow)

                Text(walkthroughService.lightingCondition == .veryPoor ? "Very poor lighting" : "Low lighting")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(walkthroughService.lightingCondition == .veryPoor ? Color.red.opacity(0.8) : Color.orange.opacity(0.8))
            .cornerRadius(20)
            .padding(.bottom, 160)
        }
    }
}

// MARK: - Instruction Row

private struct InstructionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)

            Text(text)
                .font(.body)
                .foregroundColor(.white)

            Spacer()
        }
    }
}

// MARK: - Camera Preview View

@available(iOS 16.0, *)
struct CameraPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewUIView()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

@available(iOS 16.0, *)
class CameraPreviewUIView: UIView {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isSessionRunning = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        guard let session = captureSession else { return }

        session.sessionPreset = .hd1280x720

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            return
        }

        session.addInput(videoInput)

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = bounds

        if let previewLayer = previewLayer {
            layer.addSublayer(previewLayer)
        }

        startSession()
    }

    func startSession() {
        guard let session = captureSession, !isSessionRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = true
            }
        }
    }

    func stopSession() {
        guard let session = captureSession, isSessionRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.stopRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = false
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    override func removeFromSuperview() {
        stopSession()
        super.removeFromSuperview()
    }

    deinit {
        captureSession?.stopRunning()
    }
}

// MARK: - Walkthrough Summary View

@available(iOS 16.0, *)
struct WalkthroughSummaryView: View {
    let result: WalkthroughResult
    let onUse: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Summary header
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Walkthrough Complete")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(VideoWalkthroughService.formatDuration(result.duration))
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // Stats
                    HStack(spacing: 32) {
                        StatBox(
                            icon: "door.left.hand.open",
                            value: "\(result.transitions.count)",
                            label: "Transitions"
                        )

                        StatBox(
                            icon: "square.split.2x2",
                            value: "\(result.potentialRoomCount)",
                            label: "Est. Rooms"
                        )

                        StatBox(
                            icon: "photo.stack",
                            value: "\(result.keyFrames.count)",
                            label: "Key Frames"
                        )
                    }
                    .padding(.horizontal)

                    // Transition list
                    if !result.transitions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Detected Transitions")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(result.transitions) { transition in
                                TransitionRow(transition: transition)
                            }
                        }
                    }

                    // Key frames preview
                    if !result.keyFrames.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Key Frames")
                                .font(.headline)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(result.keyFrames.enumerated()), id: \.offset) { index, frame in
                                        KeyFramePreview(image: frame.image, timestamp: frame.timestamp)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Walkthrough Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        onDiscard()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onUse()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct StatBox: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

private struct TransitionRow: View {
    let transition: WalkthroughTransition

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(colorForType)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(transition.transitionType.rawValue.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(String(format: "%.1fs", transition.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(Int(transition.confidence * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var colorForType: Color {
        switch transition.transitionType {
        case .doorway: return .green
        case .opening: return .blue
        case .threshold: return .orange
        case .turnaround: return .purple
        case .unknown: return .gray
        }
    }
}

private struct KeyFramePreview: View {
    let image: UIImage
    let timestamp: TimeInterval

    var body: some View {
        VStack(spacing: 4) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 80)
                .clipped()
                .cornerRadius(8)

            Text(String(format: "%.1fs", timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    if #available(iOS 16.0, *) {
        VideoWalkthroughView(
            onComplete: { result in
                print("Walkthrough complete: \(result?.transitions.count ?? 0) transitions")
            },
            onCancel: {
                print("Cancelled")
            }
        )
    }
}
