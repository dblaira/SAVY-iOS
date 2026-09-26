import Combine
import Foundation

/// An authored Connection owns the complete shared form metadata, but never enters the
/// Reminder, Post, Harness, candidate, or validated RDF stores. Explicit Schedule alerts
/// use local notifications without changing where the authored Connection is stored.
struct ConnectionEntry: Identifiable, Codable, Equatable {
    var metadata: Reminder
    var id: UUID { metadata.id }

    static let theme = PostTheme(
        id: "connection-personal-take-lessons-learned",
        name: "Your Personal Take & Lessons Learned",
        questions: [
            PostThemeQuestion(prompt: "What did you believe before?", symbol: "clock.arrow.circlepath"),
            PostThemeQuestion(prompt: "What experience changed or confirmed your connection?", symbol: "figure.walk"),
            PostThemeQuestion(prompt: "What do you believe now? What is the new connection?", symbol: "lightbulb"),
            PostThemeQuestion(prompt: "What do you do differently because of it?", symbol: "arrow.uturn.forward"),
        ]
    )

    var questionAndAnswers: [String] {
        Self.theme.questionAndAnswers(
            from: metadata.postAnswers,
            containQuestions: metadata.postAnswersContainQuestions == true
        )
    }

    /// Display-only answer portions. The complete editable fields stay in metadata.
    var answers: [String] {
        questionAndAnswers.enumerated().map { index, field in
            let prompt = Self.theme.questions.indices.contains(index) ? Self.theme.questions[index].prompt : nil
            return PostTheme.answerText(in: field, originalPrompt: prompt)
        }
    }

    var preview: NewsChannelPostPreview {
        let values = answers
        let current = values.indices.contains(2) ? values[2] : ""
        let title = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let authoredTitle = ["New Connection", "New Reminder"].contains(title) ? "" : title
        let text = [current, authoredTitle] + values + [metadata.notes, "Connection"]
        let headline = text.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "Connection"
        return NewsChannelPostPreview(
            text: headline,
            additionalDetails: values.filter { !$0.isEmpty && $0 != headline } + [metadata.notes, metadata.outcome]
        )
    }

    var metadataSummary: String {
        var parts: [String] = []
        if metadata.priority != .none { parts.append(metadata.priority.marks) }
        if metadata.context != .none { parts.append(metadata.context.label) }
        if metadata.energy != .none { parts.append("Energy: \(metadata.energy.label)") }
        if !metadata.listName.isEmpty { parts.append(metadata.listName) }
        parts.append(contentsOf: metadata.tags.map { "#\($0)" })
        return parts.joined(separator: "   ·   ")
    }
}

/// Local authoring storage. Source pin preferences affect presentation only; existing
/// gateway/static Connection records are never copied into this archive or rewritten.
@MainActor
final class ConnectionStore: ObservableObject {
    @Published private(set) var entries: [ConnectionEntry] = []
    @Published private(set) var sourcePinOverrides: [String: Bool] = [:]
    @Published private(set) var hiddenSourceIDs: Set<String> = []
    @Published private(set) var errorMessage: String?

    let fileURL: URL
    private var loadFailed = false

    private struct Archive: Codable {
        var entries: [ConnectionEntry]
        var sourcePins: [String: Bool]
        var hiddenSourceIDs: Set<String>

        enum CodingKeys: String, CodingKey {
            case entries, sourcePins, hiddenSourceIDs
        }

        init(entries: [ConnectionEntry], sourcePins: [String: Bool], hiddenSourceIDs: Set<String>) {
            self.entries = entries
            self.sourcePins = sourcePins
            self.hiddenSourceIDs = hiddenSourceIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entries = try container.decode([ConnectionEntry].self, forKey: .entries)
            sourcePins = try container.decode([String: Bool].self, forKey: .sourcePins)
            hiddenSourceIDs = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenSourceIDs) ?? []
        }
    }

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY", isDirectory: true)
            .appendingPathComponent("connections.json")
    }

    static var isolatedFileURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SAVYUITests", isDirectory: true)
            .appendingPathComponent("connections.json")
    }

    init(fileURL: URL? = nil, launchArguments: [String] = ProcessInfo.processInfo.arguments) {
        let isUITest = launchArguments.contains("SAVY_UI_TEST_UNLOCKED")
        self.fileURL = fileURL ?? (isUITest ? Self.isolatedFileURL : Self.defaultFileURL)
        do {
            // RESET must never delete live or caller-supplied non-isolated storage.
            if isUITest,
               launchArguments.contains("SAVY_UI_TEST_RESET_REMINDERS"),
               self.fileURL.resolvingSymlinksInPath().standardizedFileURL == Self.isolatedFileURL.resolvingSymlinksInPath().standardizedFileURL,
               FileManager.default.fileExists(atPath: self.fileURL.path) {
                try FileManager.default.removeItem(at: self.fileURL)
            }
            guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
            let data = try Data(contentsOf: self.fileURL)
            let archive = try JSONDecoder.recall.decode(Archive.self, from: data)
            guard Set(archive.entries.map(\.id)).count == archive.entries.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            entries = archive.entries
            if !isUITest {
                entries.filter { $0.metadata.schedule != nil }
                    .forEach { NotificationScheduler.schedule($0.metadata) }
            }
            sourcePinOverrides = archive.sourcePins
            hiddenSourceIDs = archive.hiddenSourceIDs
        } catch {
            loadFailed = true
            errorMessage = "Your saved connections could not be opened. The original file has been kept."
        }
    }

    var recentTags: [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for tag in entry.metadata.tags { counts[tag, default: 0] += 1 }
        }
        return counts.keys.sorted {
            let left = counts[$0, default: 0]
            let right = counts[$1, default: 0]
            return left == right ? $0.localizedStandardCompare($1) == .orderedAscending : left > right
        }
    }

    @discardableResult
    func save(_ reminder: Reminder) -> Bool {
        var metadata = reminder
        let previous = entries.first { $0.id == reminder.id }
        metadata.kind = .reminder
        metadata.postNumber = nil
        metadata.needsSync = false
        metadata.postThemeID = ConnectionEntry.theme.id
        metadata.postThemeName = ConnectionEntry.theme.name
        metadata.postAnswers = ConnectionEntry(metadata: metadata).questionAndAnswers
        metadata.postAnswersContainQuestions = true
        metadata.createdAt = previous?.metadata.createdAt ?? metadata.createdAt
        metadata.updatedAt = Date()
        var next = entries
        let entry = ConnectionEntry(metadata: metadata)
        if let index = next.firstIndex(where: { $0.id == entry.id }) {
            next[index] = entry
        } else {
            next.insert(entry, at: 0)
        }
        let saved = persist(entries: next, sourcePins: sourcePinOverrides)
        if saved {
            if metadata.schedule != nil { NotificationScheduler.schedule(metadata) }
            else if previous?.metadata.schedule != nil { NotificationScheduler.cancel(metadata) }
        }
        return saved
    }

    @discardableResult
    func delete(_ entry: ConnectionEntry) -> Bool {
        let deleted = persist(entries: entries.filter { $0.id != entry.id }, sourcePins: sourcePinOverrides)
        if deleted, entry.metadata.schedule != nil { NotificationScheduler.cancel(entry.metadata) }
        return deleted
    }

    /// Remove an existing source card from this page without modifying its source text or RDF.
    @discardableResult
    func deleteSource(id: String) -> Bool {
        var hidden = hiddenSourceIDs
        hidden.insert(id)
        return persist(entries: entries, sourcePins: sourcePinOverrides, hiddenSourceIDs: hidden)
    }

    @discardableResult
    func togglePin(_ entry: ConnectionEntry) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return false }
        var next = entries
        next[index].metadata.pinned.toggle()
        return persist(entries: next, sourcePins: sourcePinOverrides)
    }

    func sourcePinned(id: String, defaultValue: Bool) -> Bool {
        sourcePinOverrides[id] ?? defaultValue
    }

    @discardableResult
    func setSourcePinned(id: String, isPinned: Bool) -> Bool {
        var pins = sourcePinOverrides
        pins[id] = isPinned
        return persist(entries: entries, sourcePins: pins)
    }

    func clearError() {
        errorMessage = nil
    }

    private func persist(
        entries nextEntries: [ConnectionEntry],
        sourcePins: [String: Bool],
        hiddenSourceIDs nextHiddenSourceIDs: Set<String>? = nil
    ) -> Bool {
        guard !loadFailed else {
            errorMessage = "Your original connections file needs to be recovered before new changes can be saved."
            return false
        }
        do {
            let hidden = nextHiddenSourceIDs ?? hiddenSourceIDs
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.recall.encode(Archive(entries: nextEntries, sourcePins: sourcePins, hiddenSourceIDs: hidden))
            try data.write(to: fileURL, options: [.atomic])
            entries = nextEntries
            sourcePinOverrides = sourcePins
            hiddenSourceIDs = hidden
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Your connection changes could not be saved. Your previous connections are unchanged."
            return false
        }
    }
}
