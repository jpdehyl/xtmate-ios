import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - Voice Recording Service

@available(iOS 16.0, *)
class VoiceRecordingService: NSObject, ObservableObject {
    static let shared = VoiceRecordingService()

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var transcription: String = ""
    @Published var permissionStatus: PermissionStatus = .unknown

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    private var timer: Timer?
    private var levelTimer: Timer?

    enum PermissionStatus {
        case unknown
        case authorized
        case denied
        case restricted
    }

    private override init() {
        super.init()
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        // Request microphone permission
        let microphoneGranted = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard microphoneGranted else {
            await MainActor.run {
                permissionStatus = .denied
            }
            return false
        }

        await MainActor.run {
            permissionStatus = .authorized
        }
        return true
    }

    // MARK: - Recording

    func startRecording() throws -> URL {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try audioSession.setActive(true)

        // Create unique filename
        let filename = "voice_memo_\(UUID().uuidString).wav"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsPath.appendingPathComponent(filename)
        recordingURL = audioURL

        // Recording settings for best Gemini compatibility
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
        audioRecorder?.record()

        isRecording = true
        recordingDuration = 0

        // Start duration timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 0.1
        }

        // Start level monitoring
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.audioRecorder?.updateMeters()
            let level = self?.audioRecorder?.averagePower(forChannel: 0) ?? -160
            // Convert dB to 0-1 range
            let normalizedLevel = max(0, (level + 50) / 50)
            self?.audioLevel = normalizedLevel
        }

        return audioURL
    }

    func stopRecording() -> Data? {
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0

        guard let url = recordingURL else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return data
        } catch {
            print("Error reading audio file: \(error)")
            return nil
        }
    }

    func cancelRecording() {
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0
        recordingDuration = 0

        // Delete the partial recording
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    // MARK: - Playback

    func playRecording(url: URL) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default)
        try audioSession.setActive(true)

        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: - File Management

    func getRecordingURL() -> URL? {
        return recordingURL
    }

    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Duration Formatting

    static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration - Double(Int(duration))) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Voice Recording View

import SwiftUI

@available(iOS 16.0, *)
struct VoiceRecordingButton: View {
    @StateObject private var voiceService = VoiceRecordingService.shared
    @Binding var audioData: Data?
    @Binding var audioURL: URL?

    @State private var showingPermissionAlert = false

    var body: some View {
        VStack(spacing: 12) {
            // Recording button
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(voiceService.isRecording ? Color.red : Color.blue)
                        .frame(width: 70, height: 70)

                    if voiceService.isRecording {
                        // Animated recording indicator
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 3)
                            .frame(width: 70 + CGFloat(voiceService.audioLevel) * 20, height: 70 + CGFloat(voiceService.audioLevel) * 20)
                            .animation(.easeOut(duration: 0.1), value: voiceService.audioLevel)

                        // Stop icon
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    } else {
                        // Microphone icon
                        Image(systemName: "mic.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
            }

            // Duration display
            if voiceService.isRecording {
                Text(VoiceRecordingService.formatDuration(voiceService.recordingDuration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)
            } else if audioData != nil {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Recording saved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Tap to record")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Cancel button while recording
            if voiceService.isRecording {
                Button("Cancel") {
                    voiceService.cancelRecording()
                    audioData = nil
                    audioURL = nil
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .alert("Microphone Access Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("XtMate needs microphone access to record voice notes. Please enable it in Settings.")
        }
    }

    private func toggleRecording() {
        if voiceService.isRecording {
            audioData = voiceService.stopRecording()
            audioURL = voiceService.getRecordingURL()
        } else {
            Task {
                let hasPermission = await voiceService.requestPermissions()
                if hasPermission {
                    do {
                        audioURL = try voiceService.startRecording()
                    } catch {
                        print("Failed to start recording: \(error)")
                    }
                } else {
                    showingPermissionAlert = true
                }
            }
        }
    }
}

// MARK: - Audio Playback View

@available(iOS 16.0, *)
struct AudioPlaybackView: View {
    let audioURL: URL
    let onDelete: (() -> Void)?

    @StateObject private var voiceService = VoiceRecordingService.shared
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            // Play/Stop button
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.blue)
            }

            // Waveform placeholder
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue.opacity(0.5))
                        .frame(width: 3, height: CGFloat.random(in: 8...24))
                }
            }
            .frame(height: 30)

            Spacer()

            // Delete button
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func togglePlayback() {
        if isPlaying {
            voiceService.stopPlayback()
            isPlaying = false
        } else {
            do {
                try voiceService.playRecording(url: audioURL)
                isPlaying = true
            } catch {
                print("Failed to play audio: \(error)")
            }
        }
    }
}
