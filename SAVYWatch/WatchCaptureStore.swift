import CloudKit
import Foundation
import WatchKit

/// Every capture is written to the Watch first, so nothing is lost on a trail with no signal.
/// Sending to iCloud follows; Watch cellular, known Wi-Fi, or the iPhone in a pocket all work.
@MainActor
final class WatchCaptureStore: ObservableObject {
    static let shared = WatchCaptureStore()

    struct Item: Codable, Equatable, Identifiable {
        var capture: WatchCapture
        /// When iCloud confirmed the latest words. Nil while waiting to send.
        var sentAt: Date?
        var id: UUID { capture.id }
    }

    enum Problem: Equatable {
        case noICloudAccount
        case couldNotSend
        case couldNotSaveOnWatch
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var problem: Problem?

    private let fileURL: URL
    private var isSending = false
    private var zoneIsReady = false
    /// Sent captures stay on the Watch this long as proof, then make room.
    private static let keepSentFor: TimeInterval = 7 * 86_400

    init(fileURL: URL? = nil) {
        let url = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVYWatch/captures.json")
        self.fileURL = url
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = (try? decoder.decode([Item].self, from: data)) ?? []
        }
    }

    var waitingCount: Int { items.filter { $0.sentAt == nil }.count }

    func item(id: UUID) -> Item? { items.first { $0.id == id } }

    /// Saves on the Watch, taps the wrist, and starts sending. Returns nil only when the Watch
    /// could not write the capture, so the screen never claims a save that did not happen.
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

    /// One tap to re-record: the new words replace the old ones on the same capture.
    @discardableResult
    func replaceWords(of id: UUID, with words: String) -> WatchCapture? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let previous = items[index]
        let updated = previous.capture.replacingWords(words)
        guard !updated.words.isEmpty else { return nil }
        items[index] = Item(capture: updated, sentAt: nil)
        guard persist() else {
            items[index] = previous
            problem = .couldNotSaveOnWatch
            WKInterfaceDevice.current().play(.failure)
            return nil
        }
        WKInterfaceDevice.current().play(.success)
        Task { await sendPending() }
        return updated
    }

    /// Sends every capture still waiting. Safe to call often; a second call while one is
    /// running returns at once.
    func sendPending() async {
        guard !isSending else { return }
        let waiting = items.filter { $0.sentAt == nil }
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
            let records = try waiting.map { try WatchCaptureInbox.record(for: $0.capture) }
            // `.allKeys` lets a re-recorded capture replace its earlier words in iCloud.
            let result = try await database.modifyRecords(
                saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
            var anyFailed = false
            for item in waiting {
                let recordID = WatchCaptureInbox.recordID(for: item.id)
                guard case .success? = result.saveResults[recordID] else {
                    anyFailed = true
                    continue
                }
                // Words re-recorded while this send was running are sent next time.
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
        if items.contains(where: { $0.sentAt == nil && !waiting.contains($0) }) {
            Task { await sendPending() }
        }
    }

    /// Asks watchOS to wake SAVY later and try again while anything is still waiting.
    func scheduleRetry() {
        guard waitingCount > 0 else { return }
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(15 * 60), userInfo: nil) { _ in }
    }

    private func pruneOldSent() {
        let cutoff = Date().addingTimeInterval(-Self.keepSentFor)
        let kept = items.filter { $0.sentAt == nil || ($0.sentAt ?? .distantPast) > cutoff }
        guard kept.count != items.count else { return }
        items = kept
        _ = persist()
    }

    private func persist() -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
