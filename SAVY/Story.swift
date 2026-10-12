import Combine
import Foundation

// MARK: - Story — the long form
//
// Adam, 2026-09-03: "On X, or Youtube I will be writing long articles, or creating longer form
// videos that require more room ... The Form for Stories should have Title, Subtitle Forms and
// the ability to past formatted writing (bullet points, numbers lists, quotes, in the body
// portion of the form." Stories sit in the Stories area of the News Channel page. Local-first:
// stories.json under Application Support/SAVY. Nothing posts on its own.

struct Story: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var subtitle: String = ""
    /// Pasted as written — bullets, numbered lines, quotes, blank lines all kept.
    var body: String = ""
    var status: PostStatus = .draft
    var postedAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    /// Every key is optional on read so the form can grow without losing saved stories.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        status = try c.decodeIfPresent(PostStatus.self, forKey: .status) ?? .draft
        postedAt = try c.decodeIfPresent(Date.self, forKey: .postedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

extension Story {
    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedSubtitle: String { subtitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedBody: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }

    var headline: String {
        trimmedTitle.isEmpty ? "Story" : trimmedTitle
    }

    var hasContent: Bool {
        !trimmedTitle.isEmpty || !trimmedSubtitle.isEmpty || !trimmedBody.isEmpty
    }

    var wordCount: Int {
        trimmedBody.split { $0.isWhitespace || $0.isNewline }.count
    }

    var whenLabel: String? {
        guard let date = postedAt ?? (status == .posted ? updatedAt : nil) else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d h:mm a"
        return fmt.string(from: date)
    }
}

@MainActor
final class StoryStore: ObservableObject {
    @Published private(set) var stories: [Story]
    /// An unreadable stories.json is preserved and cannot become an empty synced collection.
    private(set) var loadFailed = false
    private(set) var lastWriteFailed = false

    private let fileURL: URL

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.stories = try Self.load(from: fileURL)
    }

    static func live() -> StoryStore {
        do {
            return try StoryStore(fileURL: defaultFileURL)
        } catch {
            let store = StoryStore(stories: [], fileURL: defaultFileURL)
            store.loadFailed = true
            return store
        }
    }

    @discardableResult
    func applySynced(_ synced: [Story]) -> Bool {
        guard !loadFailed else { return false }
        guard synced != stories else { return true }
        return persist(synced)
    }

    /// Drafts and ready first, newest first; posted after.
    var ordered: [Story] {
        let open = stories.filter { $0.status != .posted }.sorted { $0.updatedAt > $1.updatedAt }
        let posted = stories.filter { $0.status == .posted }
            .sorted { ($0.postedAt ?? $0.updatedAt) > ($1.postedAt ?? $1.updatedAt) }
        return open + posted
    }

    @discardableResult
    func save(_ story: Story) -> Bool {
        var s = story
        s.updatedAt = Date()
        if s.status == .posted, s.postedAt == nil {
            s.postedAt = s.updatedAt
        }
        var next = stories.filter { $0.id != s.id }
        next.insert(s, at: 0)
        return persist(next)
    }

    func markPosted(_ story: Story) {
        var s = story
        s.status = .posted
        if s.postedAt == nil { s.postedAt = Date() }
        save(s)
    }

    func delete(_ story: Story) {
        _ = persist(stories.filter { $0.id != story.id })
    }

    private init(stories: [Story], fileURL: URL) {
        self.stories = stories
        self.fileURL = fileURL
    }

    private static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY", isDirectory: true)
        return directory.appendingPathComponent("stories.json")
    }

    private static func load(from fileURL: URL) throws -> [Story] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let stories = try JSONDecoder.recall.decode([Story].self, from: data)
        guard Set(stories.map(\.id)).count == stories.count else { throw CocoaError(.fileReadCorruptFile) }
        return stories
    }

    private func persist(_ next: [Story]) -> Bool {
        guard !loadFailed else { return false }
        do {
            guard Set(next.map(\.id)).count == next.count else { throw CocoaError(.fileWriteUnknown) }
            let data = try JSONEncoder.recall.encode(next)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            stories = next
            lastWriteFailed = false
            return true
        } catch {
            lastWriteFailed = true
            return false
        }
    }
}
