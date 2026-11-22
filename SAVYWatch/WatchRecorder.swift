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
    private var startedAt: Date?
    /// Set when the recorder is found stopped before the maximum length: the system cut it short.
    private var cutShortAt: TimeInterval?

    /// Starts recording into `url`. Returns false, with `problem` set, when it cannot.
    @discardableResult
    func start(into url: URL) async -> Bool {
        guard !isRecording else { return true }
        problem = nil
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            problem = "Microphone is off for \(WatchCaptureConfig.appName). Turn it on in Settings, Privacy, Microphone."
            WatchCaptureTrail.fail("record.start", "microphone is off for this app")
            return false
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let settings: [String: Any] = [
                // Speech needs little: 16 kHz mono at 24 kbps is about 3 KB a second, so a
                // recording reaches the nearby iPhone in a few small live messages.
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 24_000,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: Self.maximumLength) else {
                problem = "The Watch could not start recording."
                WatchCaptureTrail.fail("record.start", "the recorder refused to start")
                return false
            }
            self.recorder = recorder
            fileURL = url
            startedAt = Date()
            cutShortAt = nil
            WatchCaptureTrail.note("record.start", "file=\(Self.tag(url))")
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
            WatchCaptureTrail.fail("record.start", WatchCaptureTrail.reason(error))
            return false
        }
    }

    /// The first part of a recording's file name, to follow one recording through the trail.
    nonisolated static func tag(_ url: URL) -> String {
        String(url.deletingPathExtension().lastPathComponent.prefix(8))
    }

    /// Stops and returns the recording, or nil when nothing was recorded.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording, let recorder, let fileURL else { return nil }
        let tracked = recorder.currentTime > 0 ? recorder.currentTime : elapsed
        recorder.stop()
        // The file itself says how long the recording really is, even when the system cut it short.
        let measured = (try? AVAudioPlayer(contentsOf: fileURL))?.duration ?? 0
        let duration = measured > 0 ? measured : tracked
        let wall = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        meterTask?.cancel()
        meterTask = nil
        self.recorder = nil
        self.fileURL = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        WKInterfaceDevice.current().play(.stop)
        let summary = String(format: "file=%@ recorded=%.1fs pressed=%.1fs", Self.tag(fileURL), duration, wall)
        guard duration > 0.3, FileManager.default.fileExists(atPath: fileURL.path) else {
            try? FileManager.default.removeItem(at: fileURL)
            WatchCaptureTrail.fail("record.stop", summary + " nothing kept")
            return nil
        }
        // A recording much shorter than the time between the two presses stopped on its own.
        let reachedLimit = duration >= Self.maximumLength - 1
        let stoppedEarly = !reachedLimit && (cutShortAt != nil || wall - duration > 3)
        WatchCaptureTrail.note("record.stop", ok: !stoppedEarly,
                               summary + (stoppedEarly ? " stopped before the second press" : reachedLimit ? " reached the longest length" : ""))
        cutShortAt = nil
        return (fileURL, duration)
    }

    private func tick() {
        guard let recorder else { return }
        // The recorder stops itself at the maximum length; keep what it has. If it is found
        // stopped earlier than that, the system cut it short: show the time it really reached.
        guard recorder.isRecording else {
            if elapsed >= Self.maximumLength - 1 {
                elapsed = Self.maximumLength
            } else if cutShortAt == nil {
                cutShortAt = elapsed
                WatchCaptureTrail.fail("record.cut", String(format: "file=%@ stopped by the system at %.1fs",
                                                            fileURL.map(Self.tag) ?? "-", elapsed))
            }
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
