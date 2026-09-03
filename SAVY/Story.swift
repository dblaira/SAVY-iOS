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

    private let fileURL: URL

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.stories = try Self.load(from: fileURL)
    }

    static func live() -> StoryStore {
        do {
            return try StoryStore(fileURL: defaultFileURL)
        } catch {
            return StoryStore(stories: [], fileURL: defaultFileURL)
        }
    }

    /// Drafts and ready first, newest first; posted after.
    var ordered: [Story] {
        let open = stories.filter { $0.status != .posted }.sorted { $0.updatedAt > $1.updatedAt }
        let posted = stories.filter { $0.status == .posted }
            .sorted { ($0.postedAt ?? $0.updatedAt) > ($1.postedAt ?? $1.updatedAt) }
        return open + posted
    }

    func save(_ story: Story) {
        var s = story
        s.updatedAt = Date()
        if s.status == .posted, s.postedAt == nil {
            s.postedAt = s.updatedAt
        }
        stories.removeAll { $0.id == s.id }
        stories.insert(s, at: 0)
        persist()
    }

    func markPosted(_ story: Story) {
        var s = story
        s.status = .posted
        if s.postedAt == nil { s.postedAt = Date() }
        save(s)
    }

    func delete(_ story: Story) {
        stories.removeAll { $0.id == story.id }
        persist()
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
        guard !data.isEmpty else { return [] }
        return try JSONDecoder.recall.decode([Story].self, from: data)
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.recall.encode(stories) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
