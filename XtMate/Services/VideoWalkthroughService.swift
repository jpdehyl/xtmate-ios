//
//  VideoWalkthroughService.swift
//  XtMate
//
//  Service for capturing video walkthroughs to help identify room boundaries.
//  Uses AVFoundation for video capture and CoreMotion for device motion tracking.
//  Extracts key frames at motion transitions (potential doorways/room boundaries).
//
//  PRD: US-RC-006 - Video/Photo Capture for Room Boundary Hints
//

import Foundation
@preconcurrency import AVFoundation
import CoreMotion
import UIKit
import Combine

// MARK: - Walkthrough Transition Model

/// Represents a detected transition point during a walkthrough (potential room boundary)
struct WalkthroughTransition: Identifiable, Codable {
    let id: UUID
    let timestamp: TimeInterval
    let frameImage: Data?  // JPEG data of the key frame
    let motionData: MotionSnapshot
    let transitionType: TransitionType
    let confidence: Float

    enum TransitionType: String, Codable {
        case doorway       // Significant direction change + motion pause
        case opening       // Direction change without full stop
        case threshold     // Height change detected (step up/down)
        case turnaround    // 180-degree turn
        case unknown
    }

    struct MotionSnapshot: Codable {
        let rotationX: Double  // Roll
        let rotationY: Double  // Pitch
        let rotationZ: Double  // Yaw
        let accelerationX: Double
        let accelerationY: Double
        let accelerationZ: Double
        let magneticHeading: Double?
    }
}

// MARK: - Video Walkthrough Service

@available(iOS 16.0, *)
@MainActor
class VideoWalkthroughService: NSObject, ObservableObject {
    static let shared = VideoWalkthroughService()

    // MARK: - Published Properties

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var detectedTransitions: [WalkthroughTransition] = []
    @Published var permissionStatus: PermissionStatus = .unknown
    @Published var recordingError: String?
    @Published var lightingCondition: LightingCondition = .adequate

    enum PermissionStatus {
        case unknown
        case authorized
        case cameraOnlyAuthorized
        case denied
        case restricted
    }

    enum LightingCondition {
        case adequate
        case poor
        case veryPoor
    }

    // MARK: - Private Properties

    // AVFoundation (nonisolated(unsafe) for non-Sendable AV types)
    private nonisolated(unsafe) var captureSession: AVCaptureSession?
    private nonisolated(unsafe) var videoOutput: AVCaptureVideoDataOutput?
    private nonisolated(unsafe) var movieOutput: AVCaptureMovieFileOutput?
    private nonisolated(unsafe) var videoDeviceInput: AVCaptureDeviceInput?
    private var currentVideoURL: URL?

    // CoreMotion (nonisolated(unsafe) for non-Sendable CMMotionManager)
    private nonisolated(unsafe) var motionManager: CMMotionManager?
    private nonisolated(unsafe) var motionData: [(timestamp: TimeInterval, motion: CMDeviceMotion)] = []
    private let motionQueue = OperationQueue()

    // Frame processing
    private let minKeyFrameInterval: TimeInterval = 0.5  // Minimum 0.5s between key frames
    private nonisolated(unsafe) var keyFrames: [(timestamp: TimeInterval, image: UIImage)] = []
    private let ciContext = CIContext()  // Reuse for performance

    // Motion analysis (nonisolated(unsafe) because accessed from motionQueue)
    private nonisolated(unsafe) var lastYaw: Double = 0
    private nonisolated(unsafe) var lastPitch: Double = 0
    private nonisolated(unsafe) var accumulatedRotation: Double = 0
    private let rotationThreshold: Double = 0.3  // radians (~17 degrees) for significant turn
    private let pauseThreshold: Double = 0.1     // acceleration magnitude for "stopped"
    private nonisolated(unsafe) var motionHistory: [CMDeviceMotion] = []
    private let motionHistorySize = 20  // Keep last 20 samples for analysis
    private nonisolated(unsafe) var lastKeyFrameTime: TimeInterval = 0

    // Timers
    private var durationTimer: Timer?
    private var lightingTimer: Timer?
    private var startTime: Date?

    // Queues
    private let sessionQueue = DispatchQueue(label: "com.xtmate.walkthrough.session")
    private let processingQueue = DispatchQueue(label: "com.xtmate.walkthrough.processing", qos: .userInitiated)

    // MARK: - Initialization

    private override init() {
        super.init()
        motionManager = CMMotionManager()
        motionQueue.name = "com.xtmate.walkthrough.motion"
        motionQueue.maxConcurrentOperationCount = 1
    }

    deinit {
        // Clean up resources
        durationTimer?.invalidate()
        lightingTimer?.invalidate()
        motionManager?.stopDeviceMotionUpdates()
        captureSession?.stopRunning()
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        // Request camera permission
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

        let cameraGranted: Bool
        switch cameraStatus {
        case .authorized:
            cameraGranted = true
        case .notDetermined:
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraGranted = false
        }

        // Request microphone permission (optional for video)
        var micGranted = false
        if cameraGranted {
            if #available(iOS 17.0, *) {
                micGranted = await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            } else {
                micGranted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        }

        await MainActor.run {
            if cameraGranted && micGranted {
                permissionStatus = .authorized
            } else if cameraGranted {
                permissionStatus = .cameraOnlyAuthorized
            } else {
                permissionStatus = .denied
            }
        }

        return cameraGranted
    }

    // MARK: - Recording Control

    func startRecording() throws -> URL {
        guard !isRecording else {
            throw WalkthroughError.alreadyRecording
        }

        // Reset state
        detectedTransitions = []
        motionData = []
        keyFrames = []
        motionHistory = []
        accumulatedRotation = 0
        recordingError = nil

        // Create video URL
        let filename = "walkthrough_\(UUID().uuidString).mov"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoURL = documentsPath.appendingPathComponent(filename)
        currentVideoURL = videoURL

        // Setup capture session
        try setupCaptureSession()

        // Start motion tracking
        startMotionTracking()

        // Start video recording
        guard let movieOutput = movieOutput else {
            throw WalkthroughError.captureSessionNotConfigured
        }

        // Capture nonisolated(unsafe) value before entering async context
        let output = movieOutput
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            output.startRecording(to: videoURL, recordingDelegate: self)
        }

        // Start timers
        startTime = Date()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                guard let self, let startTime = self.startTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }

        // Monitor lighting conditions
        lightingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                self?.checkLightingConditions()
            }
        }

        isRecording = true
        return videoURL
    }

    func stopRecording() -> WalkthroughResult? {
        guard isRecording else { return nil }

        // Stop timers
        durationTimer?.invalidate()
        durationTimer = nil
        lightingTimer?.invalidate()
        lightingTimer = nil

        // Stop motion tracking
        stopMotionTracking()

        // Stop video recording - capture values before async context
        let output = movieOutput
        let session = captureSession
        sessionQueue.async {
            output?.stopRecording()
            session?.stopRunning()
        }

        isRecording = false

        // Analyze motion data for transitions
        analyzeMotionForTransitions()

        // Return results
        return WalkthroughResult(
            videoURL: currentVideoURL,
            transitions: detectedTransitions,
            duration: recordingDuration,
            keyFrames: keyFrames.map { ($0.timestamp, $0.image) }
        )
    }

    func cancelRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        lightingTimer?.invalidate()
        lightingTimer = nil

        stopMotionTracking()

        // Capture values before async context
        let output = movieOutput
        let session = captureSession
        sessionQueue.async {
            output?.stopRecording()
            session?.stopRunning()
        }

        // Delete partial recording
        if let url = currentVideoURL {
            try? FileManager.default.removeItem(at: url)
        }

        isRecording = false
        detectedTransitions = []
        motionData = []
        keyFrames = []
        recordingDuration = 0
    }

    // MARK: - Capture Session Setup

    private func setupCaptureSession() throws {
        captureSession = AVCaptureSession()
        guard let session = captureSession else {
            throw WalkthroughError.captureSessionNotConfigured
        }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720  // Balance quality vs file size

        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw WalkthroughError.cameraUnavailable
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
            videoDeviceInput = videoInput
        } else {
            throw WalkthroughError.cannotAddInput
        }

        // Add audio input (optional)
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        // Add video data output for frame analysis
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: processingQueue)
        dataOutput.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
            videoOutput = dataOutput
        }

        // Add movie file output for saving video
        let movieOutput = AVCaptureMovieFileOutput()
        movieOutput.maxRecordedDuration = CMTime(seconds: 300, preferredTimescale: 1)  // 5 minute max

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            self.movieOutput = movieOutput
        } else {
            throw WalkthroughError.cannotAddOutput
        }

        session.commitConfiguration()

        // Capture session before async context
        let capturedSession = session
        sessionQueue.async {
            capturedSession.startRunning()
        }
    }

    // MARK: - Motion Tracking

    private func startMotionTracking() {
        guard let motionManager = motionManager, motionManager.isDeviceMotionAvailable else {
            print("Device motion not available")
            return
        }

        // Capture start time before entering closure (MainActor-isolated property)
        let capturedStartTime = startTime

        motionManager.deviceMotionUpdateInterval = 0.05  // 20Hz
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: motionQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }

            let timestamp = capturedStartTime.map { Date().timeIntervalSince($0) } ?? 0

            // Store motion data (nonisolated(unsafe) properties)
            self.motionData.append((timestamp: timestamp, motion: motion))

            // Update motion history for real-time analysis
            self.motionHistory.append(motion)
            if self.motionHistory.count > self.motionHistorySize {
                self.motionHistory.removeFirst()
            }

            // Check for significant motion changes
            self.checkForTransition(motion: motion, timestamp: timestamp)
        }
    }

    private func stopMotionTracking() {
        motionManager?.stopDeviceMotionUpdates()
    }

    // MARK: - Transition Detection

    private nonisolated func checkForTransition(motion: CMDeviceMotion, timestamp: TimeInterval) {
        let currentYaw = motion.attitude.yaw
        let currentPitch = motion.attitude.pitch

        // Calculate rotation change
        let yawDelta = abs(currentYaw - lastYaw)
        let pitchDelta = abs(currentPitch - lastPitch)

        // Accumulate rotation (handling wrap-around at +/- pi)
        var normalizedYawDelta = yawDelta
        if normalizedYawDelta > .pi {
            normalizedYawDelta = 2 * .pi - normalizedYawDelta
        }
        accumulatedRotation += normalizedYawDelta

        // Check if user has paused (low acceleration)
        let acceleration = sqrt(
            pow(motion.userAcceleration.x, 2) +
            pow(motion.userAcceleration.y, 2) +
            pow(motion.userAcceleration.z, 2)
        )
        let isPaused = acceleration < pauseThreshold

        // Detect transition conditions
        var transitionType: WalkthroughTransition.TransitionType?
        var confidence: Float = 0.0

        // Doorway detection: significant turn + pause
        if normalizedYawDelta > rotationThreshold && isPaused {
            transitionType = .doorway
            confidence = min(1.0, Float(normalizedYawDelta / .pi) * 2)
        }
        // Opening detection: significant turn without pause
        else if normalizedYawDelta > rotationThreshold * 1.5 {
            transitionType = .opening
            confidence = min(1.0, Float(normalizedYawDelta / .pi))
        }
        // Turnaround detection: very large rotation
        else if accumulatedRotation > .pi * 0.75 {
            transitionType = .turnaround
            confidence = min(1.0, Float(accumulatedRotation / .pi))
            accumulatedRotation = 0  // Reset after detecting turnaround
        }
        // Threshold detection: pitch change (going up/down stairs)
        else if pitchDelta > 0.2 && motionHistory.count >= 10 {
            // Verify it's a sustained pitch change
            let avgPitch = motionHistory.suffix(10).map { $0.attitude.pitch }.reduce(0, +) / 10
            if abs(avgPitch - currentPitch) < 0.1 && pitchDelta > 0.3 {
                transitionType = .threshold
                confidence = min(1.0, Float(pitchDelta / 0.5))
            }
        }

        // Record transition if detected and enough time has passed
        if let type = transitionType,
           timestamp - lastKeyFrameTime >= minKeyFrameInterval {

            let snapshot = WalkthroughTransition.MotionSnapshot(
                rotationX: motion.attitude.roll,
                rotationY: motion.attitude.pitch,
                rotationZ: motion.attitude.yaw,
                accelerationX: motion.userAcceleration.x,
                accelerationY: motion.userAcceleration.y,
                accelerationZ: motion.userAcceleration.z,
                magneticHeading: motion.heading > 0 ? motion.heading : nil
            )

            let transition = WalkthroughTransition(
                id: UUID(),
                timestamp: timestamp,
                frameImage: nil,  // Will be populated from key frame
                motionData: snapshot,
                transitionType: type,
                confidence: confidence
            )

            Task { @MainActor [weak self] in
                self?.detectedTransitions.append(transition)
            }

            lastKeyFrameTime = timestamp

            // Reset rotation accumulator after doorway/opening
            if type == .doorway || type == .opening {
                accumulatedRotation = 0
            }
        }

        lastYaw = currentYaw
        lastPitch = currentPitch
    }

    // MARK: - Post-Recording Analysis

    private func analyzeMotionForTransitions() {
        // Additional analysis on full motion data to find missed transitions
        guard motionData.count > 10 else { return }

        // Look for patterns in the motion data that indicate room changes
        var additionalTransitions: [WalkthroughTransition] = []

        // Sliding window analysis for pause detection
        let windowSize = 10
        for i in stride(from: windowSize, to: motionData.count - windowSize, by: windowSize) {
            let windowBefore = motionData[(i - windowSize)..<i]
            let windowAfter = motionData[i..<min(i + windowSize, motionData.count)]

            // Calculate average heading before and after
            let headingBefore = windowBefore.map { $0.motion.attitude.yaw }.reduce(0, +) / Double(windowSize)
            let headingAfter = windowAfter.map { $0.motion.attitude.yaw }.reduce(0, +) / Double(windowSize)

            var headingChange = abs(headingAfter - headingBefore)
            if headingChange > .pi {
                headingChange = 2 * .pi - headingChange
            }

            // Check if this is a significant heading change not already detected
            if headingChange > rotationThreshold * 1.2 {
                let timestamp = motionData[i].timestamp
                let existingTransition = detectedTransitions.contains { abs($0.timestamp - timestamp) < 1.0 }

                if !existingTransition {
                    let motion = motionData[i].motion
                    let snapshot = WalkthroughTransition.MotionSnapshot(
                        rotationX: motion.attitude.roll,
                        rotationY: motion.attitude.pitch,
                        rotationZ: motion.attitude.yaw,
                        accelerationX: motion.userAcceleration.x,
                        accelerationY: motion.userAcceleration.y,
                        accelerationZ: motion.userAcceleration.z,
                        magneticHeading: motion.heading > 0 ? motion.heading : nil
                    )

                    let transition = WalkthroughTransition(
                        id: UUID(),
                        timestamp: timestamp,
                        frameImage: nil,
                        motionData: snapshot,
                        transitionType: .opening,
                        confidence: Float(headingChange / .pi) * 0.7  // Lower confidence for post-analysis
                    )

                    additionalTransitions.append(transition)
                }
            }
        }

        // Merge and sort all transitions
        detectedTransitions.append(contentsOf: additionalTransitions)
        detectedTransitions.sort { $0.timestamp < $1.timestamp }
    }

    // MARK: - Lighting Check

    private func checkLightingConditions() {
        guard let videoDevice = videoDeviceInput?.device else { return }

        // Check ISO and exposure duration as indicators of lighting
        let iso = videoDevice.iso
        let exposureDuration = CMTimeGetSeconds(videoDevice.exposureDuration)

        // Already on MainActor, update directly
        if iso > 1600 || exposureDuration > 1.0/15.0 {
            lightingCondition = .veryPoor
        } else if iso > 800 || exposureDuration > 1.0/30.0 {
            lightingCondition = .poor
        } else {
            lightingCondition = .adequate
        }
    }

    // MARK: - Cleanup

    func cleanupWalkthroughFiles(olderThan date: Date = Date().addingTimeInterval(-86400)) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: [.creationDateKey])

            for file in files {
                if file.lastPathComponent.hasPrefix("walkthrough_") {
                    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                    if let creationDate = attributes[.creationDate] as? Date,
                       creationDate < date {
                        try FileManager.default.removeItem(at: file)
                    }
                }
            }
        } catch {
            print("Error cleaning up walkthrough files: \(error)")
        }
    }

    // MARK: - Duration Formatting

    static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

@available(iOS 16.0, *)
extension VideoWalkthroughService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process frame in background - delegate is called on processingQueue
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)

        // Dispatch to main actor for state updates
        Task { @MainActor [weak self] in
            guard let self = self, let startTime = self.startTime else { return }

            let timestamp = Date().timeIntervalSince(startTime)

            // Extract key frame every 2 seconds
            if timestamp - (self.keyFrames.last?.timestamp ?? -2.0) >= 2.0 {
                self.keyFrames.append((timestamp: timestamp, image: image))
                self.updateTransitionsWithFrameImages()
            }
        }
    }

    private func updateTransitionsWithFrameImages() {
        // Match transitions with nearest key frames
        for i in 0..<detectedTransitions.count {
            if detectedTransitions[i].frameImage == nil {
                // Find closest key frame
                let transitionTime = detectedTransitions[i].timestamp
                if let closestFrame = keyFrames.min(by: { abs($0.timestamp - transitionTime) < abs($1.timestamp - transitionTime) }) {
                    if abs(closestFrame.timestamp - transitionTime) < 2.0 {
                        // Update transition with frame image
                        var transition = detectedTransitions[i]
                        if let jpegData = closestFrame.image.jpegData(compressionQuality: 0.7) {
                            transition = WalkthroughTransition(
                                id: transition.id,
                                timestamp: transition.timestamp,
                                frameImage: jpegData,
                                motionData: transition.motionData,
                                transitionType: transition.transitionType,
                                confidence: transition.confidence
                            )
                            detectedTransitions[i] = transition
                        }
                    }
                }
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

@available(iOS 16.0, *)
extension VideoWalkthroughService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error)")
            Task { @MainActor [weak self] in
                self?.recordingError = error.localizedDescription
            }
        }
    }
}

// MARK: - Walkthrough Result

struct WalkthroughResult {
    let videoURL: URL?
    let transitions: [WalkthroughTransition]
    let duration: TimeInterval
    let keyFrames: [(timestamp: TimeInterval, image: UIImage)]

    /// Timestamp when the walkthrough was recorded
    var recordedAt: Date = Date()

    /// AI-identified rooms from the walkthrough (populated after analysis)
    var identifiedRooms: [RoomIdentification]?

    /// User-edited room identifications
    var editedRooms: [EditableRoomIdentification] = []

    /// Get frame images as JPEG data for storage/transmission
    func getKeyFrameData() -> [(timestamp: TimeInterval, data: Data)] {
        return keyFrames.compactMap { frame in
            if let data = frame.image.jpegData(compressionQuality: 0.7) {
                return (timestamp: frame.timestamp, data: data)
            }
            return nil
        }
    }

    /// Get key frame UIImages for report generation
    var keyFrameImages: [UIImage] {
        return keyFrames.map { $0.image }
    }

    /// Returns the number of detected room boundaries
    var potentialRoomCount: Int {
        // Each doorway/opening transition suggests a room boundary
        return transitions.filter { $0.transitionType == .doorway || $0.transitionType == .opening }.count + 1
    }

    /// Returns the number of identified rooms (either AI-detected or user-confirmed)
    var confirmedRoomCount: Int {
        if !editedRooms.isEmpty {
            return editedRooms.filter { $0.isConfirmed }.count
        }
        return identifiedRooms?.count ?? 0
    }

    /// Extract high-quality frames at regular intervals for preliminary report
    /// - Parameter interval: Seconds between frame extractions
    /// - Parameter maxFrames: Maximum number of frames to return
    /// - Returns: Array of high-quality UIImages
    func extractReportFrames(interval: TimeInterval = 3.0, maxFrames: Int = 50) -> [UIImage] {
        guard !keyFrames.isEmpty else { return [] }

        var selectedFrames: [UIImage] = []
        var lastSelectedTime: TimeInterval = -interval

        for frame in keyFrames {
            if frame.timestamp - lastSelectedTime >= interval {
                selectedFrames.append(frame.image)
                lastSelectedTime = frame.timestamp

                if selectedFrames.count >= maxFrames {
                    break
                }
            }
        }

        return selectedFrames
    }

    /// Get frames at transition points (doorways, openings)
    var transitionFrames: [UIImage] {
        var frames: [UIImage] = []

        for transition in transitions {
            // Find closest key frame to transition
            if let closest = keyFrames.min(by: { abs($0.timestamp - transition.timestamp) < abs($1.timestamp - transition.timestamp) }) {
                if abs(closest.timestamp - transition.timestamp) < 2.0 {
                    frames.append(closest.image)
                }
            }
        }

        return frames
    }
}

// MARK: - Walkthrough Error

enum WalkthroughError: LocalizedError {
    case alreadyRecording
    case captureSessionNotConfigured
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already in progress"
        case .captureSessionNotConfigured:
            return "Camera session could not be configured"
        case .cameraUnavailable:
            return "Camera is not available"
        case .cannotAddInput:
            return "Could not add camera input"
        case .cannotAddOutput:
            return "Could not add video output"
        case .permissionDenied:
            return "Camera permission denied"
        }
    }
}
