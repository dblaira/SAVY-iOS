import AVFoundation
import Foundation
import WatchKit

// Watch capture kit: the same in every app that uses it.

/// One press records, one press stops, like Voice Memos. The Watch keeps the sound; the iPhone
/// or Mac writes out the words later, beside the recording. Recording must start while the app
/// is on screen; with the audio background mode it keeps going when the wrist drops.
@MainActor
final class WatchRecorder: ObservableObject {
    static let shared = WatchRecorder()

    /// Longest single recording. Long enough for a thought on a run; short enough to send.
    static let maximumLength: TimeInterval = 10 * 60
    static let levelCount = 24

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// Recent loudness, oldest first, each 0...1, for the moving bars.
    @Published private(set) var levels: [Double] = Array(repeating: 0, count: WatchRecorder.levelCount)
    @Published var problem: String?

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var meterTask: Task<Void, Never>?

    /// Starts recording into `url`. Returns false, with `problem` set, when it cannot.
    @discardableResult
    func start(into url: URL) async -> Bool {
        guard !isRecording else { return true }
        problem = nil
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else {
            problem = "Microphone is off for \(WatchCaptureConfig.appName). Turn it on in Settings, Privacy, Microphone."
            return false
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: Self.maximumLength) else {
                problem = "The Watch could not start recording."
                return false
            }
            self.recorder = recorder
            fileURL = url
            elapsed = 0
            levels = Array(repeating: 0, count: Self.levelCount)
            isRecording = true
            WKInterfaceDevice.current().play(.start)
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.tick()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            return true
        } catch {
            problem = "The Watch could not start recording."
            return false
        }
    }

    /// Stops and returns the recording, or nil when nothing was recorded.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording, let recorder, let fileURL else { return nil }
        let duration = recorder.currentTime > 0 ? recorder.currentTime : elapsed
        recorder.stop()
        meterTask?.cancel()
        meterTask = nil
        self.recorder = nil
        self.fileURL = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        WKInterfaceDevice.current().play(.stop)
        guard duration > 0.3, FileManager.default.fileExists(atPath: fileURL.path) else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return (fileURL, duration)
    }

    private func tick() {
        guard let recorder else { return }
        // The recorder stops itself at the maximum length; keep what it has.
        guard recorder.isRecording else {
            elapsed = Self.maximumLength
            return
        }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        // -50 dB and quieter reads as silence; 0 dB as full.
        let power = Double(recorder.averagePower(forChannel: 0))
        let level = max(0, min(1, (power + 50) / 50))
        levels = Array(levels.dropFirst()) + [level]
    }

    #if DEBUG
    /// Demo screens only: shows the recording screen without touching the microphone.
    func showDemoRecording() {
        isRecording = true
        elapsed = 7
        levels = (0..<Self.levelCount).map { 0.25 + 0.6 * abs(sin(Double($0) * 0.7)) }
    }
    #endif
}

/// Plays a recording back on the Watch speaker, so Adam can hear what he said before saving.
@MainActor
final class WatchRecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if isPlaying {
            player?.stop()
            isPlaying = false
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            self.player = player
            isPlaying = player.play()
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
