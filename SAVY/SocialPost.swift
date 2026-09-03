import Foundation

// MARK: - Post model
//
// Adam's words, 2026-09-01: "X posts are incredibly important, and any truncated
// summarization of sources I visit is immediately discouraging. Details. Random
// connections and details between what I consume each morning ... are interesting
// when shared based on how seemingly disparate areas connect, or overlap in some way."
//
// Every field below holds one of those parts whole: the post in his words, the
// source he is reacting to, the exact line that struck him, and where it touches
// something else. Nothing posts on its own — Adam presses Post.

/// Which account the post goes out under. Adam: "using different accounts" — his name,
/// Cowboy AI, the Understood Suite, News Calm — "possible doors", opened one at a time.
enum PostDoor: String, Codable, CaseIterable, Identifiable {
    case adam, cowboyAI, understood, newsCalm
    var id: String { rawValue }
    var label: String {
        switch self {
        case .adam: return "Adam Blair"
        case .cowboyAI: return "Cowboy AI"
        case .understood: return "Understood Suite"
        case .newsCalm: return "News Calm"
        }
    }
}

/// Where it is posted. X first; YouTube and Instagram enter with the posting phase.
enum PostPlatform: String, Codable, CaseIterable, Identifiable {
    case x, youtube, instagram
    var id: String { rawValue }
    var label: String {
        switch self {
        case .x: return "X"
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        }
    }
}

/// Gary V's terms. Jab: give something useful, no ask. Hook: the ask.
/// The play keeps jabs ahead of hooks at least 3 to 1.
enum PostMove: String, Codable, CaseIterable, Identifiable {
    case jab, hook
    var id: String { rawValue }
    var label: String {
        switch self {
        case .jab: return "Jab"
        case .hook: return "Hook"
        }
    }
}

enum PostStatus: String, Codable, CaseIterable, Identifiable {
    case draft, ready, posted
    var id: String { rawValue }
    var label: String {
        switch self {
        case .draft: return "Draft"
        case .ready: return "Ready"
        case .posted: return "Posted"
        }
    }
}

/// The areas Adam watches each morning, his words: "the persistent narrative surrounding
/// peptides, a.i., entrepreneurship, and public perception in general (pace of change,
/// opportunities for new college grads, etc.)"
enum PostAreas {
    static let suggested: [String] = [
        "Peptides",
        "AI",
        "Entrepreneurship",
        "Public perception",
        "Pace of change",
        "New college grads",
    ]
}

struct SocialPost: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    // The post — his point of view, word for word.
    var text: String = ""

    // The source he is reacting to.
    var sourceLink: String = ""
    var sourceName: String = ""     // who made it
    var sourceLine: String = ""     // the specific line, the number, the name — verbatim

    // The connection.
    var connection: String = ""     // where this touches something else
    var areas: [String] = []

    // Choose.
    var door: PostDoor = .adam
    var platform: PostPlatform = .x
    var move: PostMove = .jab
    var pattern: SuccessStep = .none

    // Status.
    var status: PostStatus = .draft
    var postedAt: Date? = nil
    var postLink: String = ""       // link to the live post
    var clearSign: Bool = false     // Clear Sign: a creator he respects replied, unprompted
    var replies: Int = 0
    var likes: Int = 0
    var profileTaps: Int = 0

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    /// Every key is optional on read so the form can grow without losing saved posts.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        sourceLink = try c.decodeIfPresent(String.self, forKey: .sourceLink) ?? ""
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        sourceLine = try c.decodeIfPresent(String.self, forKey: .sourceLine) ?? ""
        connection = try c.decodeIfPresent(String.self, forKey: .connection) ?? ""
        areas = try c.decodeIfPresent([String].self, forKey: .areas) ?? []
        door = try c.decodeIfPresent(PostDoor.self, forKey: .door) ?? .adam
        platform = try c.decodeIfPresent(PostPlatform.self, forKey: .platform) ?? .x
        move = try c.decodeIfPresent(PostMove.self, forKey: .move) ?? .jab
        pattern = try c.decodeIfPresent(SuccessStep.self, forKey: .pattern) ?? .none
        status = try c.decodeIfPresent(PostStatus.self, forKey: .status) ?? .draft
        postedAt = try c.decodeIfPresent(Date.self, forKey: .postedAt)
        postLink = try c.decodeIfPresent(String.self, forKey: .postLink) ?? ""
        clearSign = try c.decodeIfPresent(Bool.self, forKey: .clearSign) ?? false
        replies = try c.decodeIfPresent(Int.self, forKey: .replies) ?? 0
        likes = try c.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        profileTaps = try c.decodeIfPresent(Int.self, forKey: .profileTaps) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

extension SocialPost {
    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First line of the post — the row title and the form header.
    var headline: String {
        let first = trimmedText
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "Post" : first
    }

    var hasContent: Bool {
        if !trimmedText.isEmpty { return true }
        if !sourceLink.isEmpty || !sourceName.isEmpty || !sourceLine.isEmpty { return true }
        if !connection.isEmpty || !areas.isEmpty { return true }
        return false
    }

    /// X's line for a post without Premium.
    static let xCharacterLine = 280

    var characterCount: Int {
        trimmedText.count
    }

    /// Compact "Sep 2" / "Sep 2 1:14 PM" label for rows.
    var whenLabel: String? {
        guard let date = postedAt ?? (status == .posted ? updatedAt : nil) else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d h:mm a"
        return fmt.string(from: date)
    }

    /// The X compose page with this post already in the box. Adam presses Post.
    var xComposeURL: URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = trimmedText.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "https://x.com/intent/post?text=\(encoded)")
    }
}

// MARK: - Store
//
// Local-first, on this phone: posts.json under Application Support/SAVY, the same
// pocket the technical captures use. No gateway, no sync — "Manual at First".

@MainActor
final class SocialPostStore: ObservableObject {
    @Published private(set) var posts: [SocialPost]

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

    var drafts: [SocialPost] {
        posts.filter { $0.status == .draft }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var ready: [SocialPost] {
        posts.filter { $0.status == .ready }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var posted: [SocialPost] {
        posts.filter { $0.status == .posted }
            .sorted { ($0.postedAt ?? $0.updatedAt) > ($1.postedAt ?? $1.updatedAt) }
    }

    /// Jabs and hooks among posted items — the 3 to 1 rule, visible.
    var postedJabCount: Int {
        posted.filter { $0.move == .jab }.count
    }

    var postedHookCount: Int {
        posted.filter { $0.move == .hook }.count
    }

    /// Kill switch input. Adam: "If I don't use something for two days, then it's not working."
    var lastPostedAt: Date? {
        posted.first.map { $0.postedAt ?? $0.updatedAt }
    }

    var clearSignCount: Int {
        posted.filter(\.clearSign).count
    }

    /// Areas used before, most-used first, ahead of the standing suggestions.
    var recentAreas: [String] {
        let counts = Dictionary(grouping: posts.flatMap(\.areas), by: { $0 }).mapValues(\.count)
        let used = counts.sorted { $0.value > $1.value }.map(\.key)
        return used + PostAreas.suggested.filter { !used.contains($0) }
    }

    // MARK: Writing

    func save(_ post: SocialPost) {
        var p = post
        p.updatedAt = Date()
        if p.status == .posted, p.postedAt == nil {
            p.postedAt = p.updatedAt
        }
        posts.removeAll { $0.id == p.id }
        posts.insert(p, at: 0)
        persist()
    }

    func markPosted(_ post: SocialPost) {
        var p = post
        p.status = .posted
        if p.postedAt == nil { p.postedAt = Date() }
        save(p)
    }

    func delete(_ post: SocialPost) {
        posts.removeAll { $0.id == post.id }
        persist()
    }

    // MARK: Disk

    private init(posts: [SocialPost], fileURL: URL) {
        self.posts = posts
        self.fileURL = fileURL
    }

    private static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY", isDirectory: true)
        return directory.appendingPathComponent("posts.json")
    }

    private static func load(from fileURL: URL) throws -> [SocialPost] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder.recall.decode([SocialPost].self, from: data)
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.recall.encode(posts) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
