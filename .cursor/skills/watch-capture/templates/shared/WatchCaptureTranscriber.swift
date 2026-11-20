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

/// Writes out the words of a Watch recording, on this device when it can. Adam's own words
/// (WatchCaptureConfig.vocabulary) are given to the recognizer as hints, so “Codex” is less
/// likely to come back as “Kodak”. The recording is kept either way, so any word can be checked.
enum WatchCaptureTranscriber {
    static func words(fromRecordingAt url: URL) async -> String? {
        guard await isAuthorized(), let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.contextualStrings = WatchCaptureConfig.vocabulary
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let once = ResumeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            once.set(continuation)
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    once.resume(text.isEmpty ? nil : text)
                } else if error != nil {
                    once.resume(nil)
                }
            }
            // A recognizer that never answers must not hold up the import.
            Task {
                try? await Task.sleep(for: .seconds(120))
                once.resume(nil)
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
}

/// Resumes a continuation exactly once, from whichever callback arrives first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    func set(_ continuation: CheckedContinuation<String?, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func resume(_ value: String?) {
        let pending: CheckedContinuation<String?, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
