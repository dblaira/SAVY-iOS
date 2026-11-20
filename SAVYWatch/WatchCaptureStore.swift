import CloudKit
import Foundation
import WatchKit

// Watch capture kit: the same in every app that uses it.

/// Every capture is written to the Watch first, so nothing is lost on a trail with no signal.
/// A recording is kept the moment it stops, as a draft, until Save or until the Watch leaves
/// the screen; either way it is saved. Sending to iCloud follows; Watch cellular, known Wi-Fi,
/// or the iPhone in a pocket all work.
@MainActor
final class WatchCaptureStore: ObservableObject {
    #if DEBUG
    static let shared = WatchCaptureStore(folder: WatchCaptureDemo.screen == nil ? nil : WatchCaptureDemo.folder)
    #else
    static let shared = WatchCaptureStore()
    #endif

    struct Item: Codable, Equatable, Identifiable {
        var capture: WatchCapture
        /// When iCloud confirmed the latest version. Nil while waiting to send.
        var sentAt: Date?
        /// True from the moment a recording stops until Save, or until it is saved for you.
        var isDraft: Bool = false
        var id: UUID { capture.id }
    }

    enum Problem: Equatable {
        case noICloudAccount
        case couldNotSend
        case couldNotSaveOnWatch
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var problem: Problem?

    private let folder: URL
    private var fileURL: URL { folder.appendingPathComponent("captures.json") }
    private var audioFolder: URL { folder.appendingPathComponent("Audio", isDirectory: true) }
    private var isSending = false
    private var zoneIsReady = false
    /// Sent captures stay on the Watch this long as proof, then make room.
    private static let keepSentFor: TimeInterval = 7 * 86_400

    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(WatchCaptureConfig.storageFolder, isDirectory: true)
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = (try? decoder.decode([Item].self, from: data)) ?? []
        }
        // A draft left by an app that was closed mid-review is saved with the type it had.
        if items.contains(where: \.isDraft) {
            for index in items.indices { items[index].isDraft = false }
            _ = persist()
        }
    }

    var waitingCount: Int { items.filter { $0.sentAt == nil && !$0.isDraft }.count }

    func item(id: UUID) -> Item? { items.first { $0.id == id } }

    // MARK: Recordings

    /// Where a new recording is written before it becomes a draft.
    func newRecordingURL() -> URL {
        try? FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        return audioFolder.appendingPathComponent("\(UUID().uuidString.lowercased()).m4a")
    }

    func audioURL(for capture: WatchCapture) -> URL? {
        guard let name = capture.audioFileName else { return nil }
        let url = audioFolder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A finished recording is kept at once, as a draft of the default type.
    @discardableResult
    func keepRecording(at url: URL, duration: TimeInterval) -> WatchCapture? {
        let capture = WatchCapture(kind: WatchCaptureKind.saveDefault, words: "", source: .wrist,
                                   audioFileName: url.lastPathComponent, audioDuration: duration)
        items.insert(Item(capture: capture, sentAt: nil, isDraft: true), at: 0)
        guard persist() else {
            items.removeAll { $0.id == capture.id }
            problem = .couldNotSaveOnWatch
            WKInterfaceDevice.current().play(.failure)
            return nil
        }
        return capture
    }

    /// Save: the chosen type, a tap on the wrist, and the send begins.
    @discardableResult
    func save(_ id: UUID, as kind: WatchCaptureKind) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let previous = items[index]
        items[index].capture = previous.capture.withKind(kind)
        items[index].isDraft = false
        items[index].sentAt = nil
        guard persist() else {
            items[index] = previous
            problem = .couldNotSaveOnWatch
            WKInterfaceDevice.current().play(.failure)
            return false
        }
        WKInterfaceDevice.current().play(.success)
        Task { await sendPending() }
        return true
    }

    /// Only a draft can be thrown away; a saved capture may already be on its way.
    func discardDraft(_ id: UUID) {
        guard let item = item(id: id), item.isDraft else { return }
        if let url = audioURL(for: item.capture) { try? FileManager.default.removeItem(at: url) }
        items.removeAll { $0.id == id }
        _ = persist()
    }

    // MARK: Words (Siri and the Action Button phrases)

    /// Saves Siri's words on the Watch, taps the wrist, and starts sending. Returns nil only when
    /// the Watch could not write the capture, so nothing claims a save that did not happen.
    @discardableResult
    func capture(_ kind: WatchCaptureKind, words: String, source: WatchCapture.Source) -> WatchCapture? {
        let capture = WatchCapture(kind: kind, words: words, source: source)
        guard !capture.words.isEmpty else { return nil }
        items.insert(Item(capture: capture, sentAt: nil), at: 0)
        guard persist() else {
            items.removeAll { $0.id == capture.id }
            problem = .couldNotSaveOnWatch
            WKInterfaceDevice.current().play(.failure)
            return nil
        }
        WKInterfaceDevice.current().play(.success)
        Task { await sendPending() }
        return capture
    }

    // MARK: Sending

    /// Sends every saved capture still waiting. Safe to call often; a second call while one is
    /// running returns at once.
    func sendPending() async {
        #if DEBUG
        // Demo captures never leave the device: no iCloud, so they can never become entries.
        if WatchCaptureDemo.screen != nil { return }
        #endif
        guard !isSending else { return }
        let waiting = items.filter { $0.sentAt == nil && !$0.isDraft }
        guard !waiting.isEmpty else {
            pruneOldSent()
            return
        }
        isSending = true
        defer { isSending = false }

        let container = CKContainer(identifier: WatchCaptureInbox.containerIdentifier)
        let database = container.privateCloudDatabase
        do {
            guard try await container.accountStatus() == .available else {
                problem = .noICloudAccount
                scheduleRetry()
                return
            }
            if !zoneIsReady {
                _ = try await database.modifyRecordZones(
                    saving: [CKRecordZone(zoneID: WatchCaptureInbox.zoneID)], deleting: [])
                zoneIsReady = true
            }
            let records = try waiting.map {
                try WatchCaptureInbox.record(for: $0.capture, audioURL: audioURL(for: $0.capture))
            }
            // `.allKeys` lets a re-sent capture replace its earlier version in iCloud.
            let result = try await database.modifyRecords(
                saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
            var anyFailed = false
            for item in waiting {
                let recordID = WatchCaptureInbox.recordID(for: item.id)
                guard case .success? = result.saveResults[recordID] else {
                    anyFailed = true
                    continue
                }
                // A type changed while this send was running is sent next time.
                if let index = items.firstIndex(where: { $0.id == item.id }), items[index].capture == item.capture {
                    items[index].sentAt = Date()
                }
            }
            _ = persist()
            problem = anyFailed ? .couldNotSend : nil
            if anyFailed { scheduleRetry() }
        } catch {
            if let ckError = error as? CKError, ckError.code == .zoneNotFound || ckError.code == .userDeletedZone {
                zoneIsReady = false
            }
            problem = .couldNotSend
            scheduleRetry()
        }
        if items.contains(where: { $0.sentAt == nil && !$0.isDraft && !waiting.contains($0) }) {
            Task { await sendPending() }
        }
    }

    /// Asks watchOS to wake the app later and try again while anything is still waiting.
    func scheduleRetry() {
        guard waitingCount > 0 else { return }
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(15 * 60), userInfo: nil) { _ in }
    }

    #if DEBUG
    /// Demo screens only: one capture per kind with that kind's demo words, plus one silent
    /// recording, newest first. Writes only to the temporary demo folder.
    func seedDemo() -> WatchCapture? {
        guard WatchCaptureDemo.screen != nil else { return nil }
        let start = Date().addingTimeInterval(-600)
        items = WatchCaptureKind.allCases.enumerated().reversed().map { offset, kind in
            Item(capture: WatchCapture(kind: kind, words: kind.demoWords, source: .shortcut,
                                       capturedAt: start.addingTimeInterval(Double(offset) * 60)),
                 sentAt: nil)
        }
        let url = newRecordingURL().deletingPathExtension().appendingPathExtension("wav")
        if (try? WatchCaptureDemo.silentWAV(seconds: 7).write(to: url)) != nil,
           let recording = keepRecording(at: url, duration: 7) {
            return recording
        }
        _ = persist()
        return items.first?.capture
    }
    #endif

    private func pruneOldSent() {
        let cutoff = Date().addingTimeInterval(-Self.keepSentFor)
        let old = items.filter { !$0.isDraft && ($0.sentAt ?? .distantFuture) < cutoff }
        guard !old.isEmpty else { return }
        for item in old {
            if let url = audioURL(for: item.capture) { try? FileManager.default.removeItem(at: url) }
        }
        let oldIDs = Set(old.map(\.id))
        items.removeAll { oldIDs.contains($0.id) }
        _ = persist()
    }

    private func persist() -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
