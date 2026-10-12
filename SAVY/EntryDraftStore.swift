import Foundation

/// Private, device-local working copies. These never invoke Save, Calendar, or cloud capture.
struct EntryRecoveryDraft: Codable, Equatable, Identifiable {
    struct ReminderWriting: Codable, Equatable {
        var original: Reminder?
        var entry: Reminder
        var questions: PostEntryDraft
        var subtasks: [Subtask]
        var tagDraft: String
        var imageData: Data?
        var connectionMode: Bool
    }
    struct PostWriting: Codable, Equatable {
        var original: SocialPost?
        var post: SocialPost
        var postedDate: Date
        var areaDraft: String
    }
    struct StoryWriting: Codable, Equatable {
        var original: Story?
        var story: Story
        var postedDate: Date
    }
    enum Contents: Codable, Equatable {
        case reminder(ReminderWriting)
        case post(PostWriting)
        case story(StoryWriting)
    }

    var id: String
    var editedAt: Date
    var contents: Contents

    static func reminderKey(existing: Reminder?, kind: ReminderKind, connectionMode: Bool) -> String {
        let destination = connectionMode ? "connection" : "reminder"
        return destination + ":" + (existing?.id.uuidString ?? "new-\(kind.rawValue)")
    }
    static func postKey(_ existing: SocialPost?) -> String { "post:" + (existing?.id.uuidString ?? "new") }
    static func storyKey(_ existing: Story?) -> String { "story:" + (existing?.id.uuidString ?? "new") }
}

@MainActor
final class EntryDraftStore {
    static let shared: EntryDraftStore = {
        let file = defaultFileURL
        let arguments = ProcessInfo.processInfo.arguments
        if SavyRuntime.isTesting, arguments.contains("SAVY_UI_TEST_RESET_REMINDERS"),
           !arguments.contains("SAVY_UI_TEST_KEEP_DRAFTS") {
            try? FileManager.default.removeItem(at: file)
        }
        return EntryDraftStore(fileURL: file)
    }()

    private let fileURL: URL
    private var drafts: [String: EntryRecoveryDraft] = [:]
    private(set) var loadFailed = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            drafts = try JSONDecoder().decode([String: EntryRecoveryDraft].self, from: Data(contentsOf: fileURL))
        } catch {
            // An unreadable recovery file is evidence, never an empty replacement.
            loadFailed = true
        }
    }

    static var defaultFileURL: URL {
        if SavyRuntime.isTesting {
            return FileManager.default.temporaryDirectory.appendingPathComponent("SAVYUITests/entry-drafts.json")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY/entry-drafts.json")
    }

    var latest: EntryRecoveryDraft? { drafts.values.max { $0.editedAt < $1.editedAt } }
    func draft(for key: String) -> EntryRecoveryDraft? { drafts[key] }

    /// Synchronous atomic writes: no debounce or queued task can die with the process.
    @discardableResult
    func save(id: String, contents: EntryRecoveryDraft.Contents) -> Bool {
        if drafts[id]?.contents == contents { return true }
        var next = drafts
        next[id] = EntryRecoveryDraft(id: id, editedAt: Date(), contents: contents)
        return persist(next)
    }

    @discardableResult
    func remove(_ id: String) -> Bool {
        guard drafts[id] != nil else { return !loadFailed }
        var next = drafts
        next.removeValue(forKey: id)
        return persist(next)
    }

    private func persist(_ next: [String: EntryRecoveryDraft]) -> Bool {
        guard !loadFailed else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            drafts = next
            return true
        } catch {
            return false
        }
    }
}
