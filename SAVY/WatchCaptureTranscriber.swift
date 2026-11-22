import AVFoundation
import Foundation
import Speech

// Watch capture kit: the same in every app that uses it. iPhone and Mac only.

/// Watch recordings kept on this iPhone or Mac, one file per entry, named by the entry's id.
/// They stay beside the written words so Adam can hear what he actually said.
enum WatchRecordingFiles {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(WatchCaptureConfig.appName, isDirectory: true)
            .appendingPathComponent("WatchRecordings", isDirectory: true)
    }

    /// The recording for an entry, if this device has it.
    static func url(for entryID: UUID) -> URL? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let prefix = entryID.uuidString.lowercased() + "."
        return names.first { $0.hasPrefix(prefix) }.map { folder.appendingPathComponent($0) }
    }

    /// Copies a downloaded recording into place. Returns the kept file, or nil on failure.
    @discardableResult
    static func keep(_ source: URL, for capture: WatchCapture) -> URL? {
        if let existing = url(for: capture.id) { return existing }
        let ext = capture.audioFileName.map { ($0 as NSString).pathExtension } ?? ""
        let destination = folder.appendingPathComponent(capture.id.uuidString.lowercased() + "." + (ext.isEmpty ? "m4a" : ext))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

/// Writes out the words of a Watch recording, on this device. On iOS 26 and later it uses the
/// on-device SpeechAnalyzer first, which can work while the app is in the background; the older
/// recognizer is the fallback. Adam's own words (WatchCaptureConfig.vocabulary) are given as hints,
/// and his fix list (WatchCaptureConfig.corrections, such as “Kodak” → “Codex”) is applied last.
/// The recording is kept either way, so any word can be checked.
enum WatchCaptureTranscriber {
    static func words(fromRecordingAt url: URL, capture: UUID? = nil) async -> String? {
        let started = Date()
        var text: String? = nil
        var engine = ""
        var tried: [String] = []
        if #available(iOS 26.0, *) {
            let attempt = await analyzerWords(fromRecordingAt: url)
            text = attempt.text
            engine = "analyzer"
            if attempt.text == nil { tried.append("analyzer: " + attempt.why) }
        } else {
            tried.append("analyzer: needs iOS 26")
        }
        if text == nil {
            let attempt = await recognizerWords(fromRecordingAt: url)
            text = attempt.text
            engine = "recognizer"
            if attempt.text == nil { tried.append("recognizer: " + attempt.why) }
        }
        let took = String(format: "in %.1fs", Date().timeIntervalSince(started))
        if let text {
            WatchCaptureTrail.note("words", capture: capture,
                                   (["engine=\(engine) chars=\(text.count) \(took)"] + tried).joined(separator: "; "))
        } else {
            WatchCaptureTrail.fail("words", capture: capture, (tried + [took]).joined(separator: "; "))
        }
        return text.map(corrected)
    }

    /// The words, or why there are none.
    private struct Attempt: Sendable {
        var text: String?
        var why: String = ""
    }

    private static func authorizationName(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "allowed"
        case .denied: return "turned off in Settings"
        case .restricted: return "restricted on this device"
        case .notDetermined: return "never asked"
        @unknown default: return "unknown"
        }
    }

    /// Speech Recognition permission as it stands, for the trail.
    static var authorizationSummary: String {
        "speechRecognition=" + authorizationName(SFSpeechRecognizer.authorizationStatus())
    }

    /// Whole words from the fix list, matched without regard to case.
    static func corrected(_ text: String) -> String {
        var result = text
        for (heard, meant) in WatchCaptureConfig.corrections {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: heard) + "\\b"
            result = result.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: meant),
                                                 options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    @available(iOS 26.0, *)
    private static func analyzerWords(fromRecordingAt url: URL) async -> Attempt {
        guard SpeechTranscriber.isAvailable else { return Attempt(why: "not available on this device") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            return Attempt(why: "no speech model for \(Locale.current.identifier)")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installation.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber], options: nil)
            let context = AnalysisContext()
            context.contextualStrings[.general] = WatchCaptureConfig.vocabulary
            try await analyzer.setContext(context)
            async let collected = transcriber.results.reduce(into: AttributedString()) { whole, result in
                whole += result.text
            }
            let file = try AVAudioFile(forReading: url)
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let text = String(try await collected.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? Attempt(why: "heard no words") : Attempt(text: text)
        } catch {
            return Attempt(why: WatchCaptureTrail.reason(error))
        }
    }

    private static func recognizerWords(fromRecordingAt url: URL) async -> Attempt {
        guard await isAuthorized() else {
            return Attempt(why: "Speech Recognition is " + authorizationName(SFSpeechRecognizer.authorizationStatus()))
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            return Attempt(why: "not available right now")
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.contextualStrings = WatchCaptureConfig.vocabulary
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let once = ResumeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Attempt, Never>) in
            once.set(continuation)
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    once.resume(text.isEmpty ? Attempt(why: "heard no words") : Attempt(text: text))
                } else if let error {
                    once.resume(Attempt(why: WatchCaptureTrail.reason(error)))
                }
            }
            // A recognizer that never answers must not hold up the import.
            Task {
                try? await Task.sleep(for: .seconds(120))
                once.resume(Attempt(why: "no answer in 120s"))
            }
        }
    }

    static func isAuthorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default:
            return false
        }
    }

    /// Resumes a continuation exactly once, from whichever callback arrives first.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Attempt, Never>?

        func set(_ continuation: CheckedContinuation<Attempt, Never>) {
            lock.withLock { self.continuation = continuation }
        }

        func resume(_ value: Attempt) {
            let pending: CheckedContinuation<Attempt, Never>? = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            pending?.resume(returning: value)
        }
    }
}
