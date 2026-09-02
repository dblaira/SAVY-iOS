import Foundation

// MARK: - Posts store
//
// A post is an entry on Adam's entry form with the destination set to Post. Adam,
// 2026-09-02: "I have an entry form. That's good ... Everything on this page matters."
// So a post carries every field that form carries — the three sentences, Steps, Pattern,
// Clear Signs of Success, Compounding, Lift, Tags, Priority, Energy, Schedule, Details,
// Place / People. Posted = his Done. Nothing posts on its own; Adam presses Post in X.
//
// Local-first, on this phone: posts.json under Application Support/SAVY. No gateway, no
// sync — "Manual at First".

@MainActor
final class SocialPostStore: ObservableObject {
    @Published private(set) var posts: [Reminder]

    private let fileURL: URL

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.posts = try Self.load(from: fileURL)
    }

    static func live() -> SocialPostStore {
        do {
            return try SocialPostStore(fileURL: defaultFileURL)
        } catch {
            return SocialPostStore(posts: [], fileURL: defaultFileURL)
        }
    }

    // MARK: Reading

    /// Not posted yet. Pinned first, then newest.
    var drafts: [Reminder] {
        posts.filter { $0.status == .active }
            .sorted {
                if $0.pinned != $1.pinned { return $0.pinned }
                return $0.updatedAt > $1.updatedAt
            }
    }

    /// Posted = Done on his form. Newest first.
    var posted: [Reminder] {
        posts.filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    /// Kill switch input. Adam: "If I don't use something for two days, then it's not working."
    var lastPostedAt: Date? {
        posted.first.map { $0.completedAt ?? $0.updatedAt }
    }

    /// His toggle on the form: Clear Signs of Success.
    var clearSignCount: Int {
        posted.filter(\.isClearSignOfSuccess).count
    }

    /// Tags used on posts, most-used first — fed to the form's recent-tag menu.
    var recentTags: [String] {
        let counts = Dictionary(grouping: posts.flatMap(\.tags), by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    // MARK: Writing

    func save(_ post: Reminder) {
        var p = post
        p.kind = .post
        p.updatedAt = Date()
        p.needsSync = false
        posts.removeAll { $0.id == p.id }
        posts.insert(p, at: 0)
        persist()
    }

    func markPosted(_ post: Reminder) {
        var p = post
        p.status = .completed
        p.completedAt = Date()
        save(p)
    }

    func unpost(_ post: Reminder) {
        var p = post
        p.status = .active
        p.completedAt = nil
        save(p)
    }

    func togglePin(_ post: Reminder) {
        var p = post
        p.pinned.toggle()
        save(p)
    }

    func delete(_ post: Reminder) {
        posts.removeAll { $0.id == post.id }
        persist()
    }

    // MARK: X

    /// The X compose page with the post already in the box. Adam presses Post.
    static func xComposeURL(for text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://x.com/intent/post?text=\(encoded)")
    }

    // MARK: Disk

    private init(posts: [Reminder], fileURL: URL) {
        self.posts = posts
        self.fileURL = fileURL
    }

    private static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY", isDirectory: true)
        return directory.appendingPathComponent("posts.json")
    }

    private static func load(from fileURL: URL) throws -> [Reminder] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        if let entries = try? JSONDecoder.recall.decode([Reminder].self, from: data) {
            return entries
        }
        // Posts saved by the first form, 2026-09-02, before Post became an entry destination.
        // His words are kept: the post text becomes the title, the rest lands in his fields.
        let legacy = try JSONDecoder.recall.decode([LegacySocialPost].self, from: data)
        return legacy.map { $0.asEntry }
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.recall.encode(posts) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// Shape of posts.json from the first Post form. Read only, never written.
private struct LegacySocialPost: Decodable {
    var id: UUID?
    var text: String?
    var sourceLink: String?
    var sourceName: String?
    var sourceLine: String?
    var connection: String?
    var areas: [String]?
    var pattern: SuccessStep?
    var status: String?
    var postedAt: Date?
    var clearSign: Bool?
    var createdAt: Date?
    var updatedAt: Date?

    var asEntry: Reminder {
        var r = Reminder()
        r.id = id ?? UUID()
        r.kind = .post
        r.title = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        r.url = sourceLink ?? ""
        r.notes = [sourceName, sourceLine, connection]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        r.tags = areas ?? []
        r.context = pattern ?? .none
        r.marksClearSignOfSuccess = clearSign
        if status == "posted" {
            r.status = .completed
            r.completedAt = postedAt ?? updatedAt ?? Date()
        }
        r.createdAt = createdAt ?? Date()
        r.updatedAt = updatedAt ?? r.createdAt
        return r
    }
}
