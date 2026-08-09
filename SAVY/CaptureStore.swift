import Foundation

@MainActor
final class CaptureStore: ObservableObject {
    @Published private(set) var entries: [CaptureEntry]

    init(entries: [CaptureEntry] = CaptureSeed.entries) {
        self.entries = entries
    }

    func save(title: String, meaning: String) {
        let entry = CaptureEntry(title: title, meaning: meaning)
        guard !entry.title.isEmpty || !entry.meaning.isEmpty else { return }
        entries.insert(entry, at: 0)
    }

}

struct TechnicalCaptureExactWords: Codable, Equatable, Sendable {
    var want: String
    var whenIAm: String
    var doneLooksLike: String
}

struct TechnicalCaptureFlags: Codable, Equatable, Sendable {
    var isClearSignOfSuccess: Bool
    var isCompound: Bool

    init(
        isClearSignOfSuccess: Bool = false,
        isCompound: Bool = false
    ) {
        self.isClearSignOfSuccess = isClearSignOfSuccess
        self.isCompound = isCompound
    }

    init(successStep: SuccessStep) {
        self.init(
            isClearSignOfSuccess: successStep == .clearSign,
            isCompound: successStep == .compound
        )
    }
}

struct TechnicalCaptureMetadata: Codable, Equatable, Sendable {
    var kind: ReminderKind
    var priority: Priority
    var energy: Energy
    var flags: TechnicalCaptureFlags
    var listName: String
    var pinned: Bool
    var urgent: Bool
    var tags: [String]
    var dueAt: Date?
    var deferUntil: Date?
    var waitingOn: String
    var location: String
    var url: String
    var notes: String
    var steps: [String]

    init(reminder: Reminder) {
        self.kind = reminder.kind
        self.priority = reminder.priority
        self.energy = reminder.energy
        self.flags = TechnicalCaptureFlags(successStep: reminder.context)
        self.listName = reminder.listName
        self.pinned = reminder.pinned
        self.urgent = reminder.urgent
        self.tags = reminder.tags
        if reminder.dueTime == nil {
            self.dueAt = reminder.dueDate
        } else {
            self.dueAt = reminder.fireDate
        }
        self.deferUntil = reminder.deferDate
        self.waitingOn = reminder.waitingOn.trimmingCharacters(in: .whitespacesAndNewlines)
        self.location = reminder.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = reminder.url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = reminder.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.steps = reminder.subtasks.map(\.title)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum TechnicalCapturePromptBuilder {
    static func build(
        exactWords: TechnicalCaptureExactWords,
        metadata: TechnicalCaptureMetadata
    ) -> String {
        let dueAt = metadata.dueAt.map(isoString(from:)) ?? "none"
        let deferUntil = metadata.deferUntil.map(isoString(from:)) ?? "none"
        let tags = metadata.tags.isEmpty ? "none" : metadata.tags.joined(separator: ", ")
        let waitingOn = metadata.waitingOn.isEmpty ? "none" : metadata.waitingOn
        let location = metadata.location.isEmpty ? "none" : metadata.location
        let url = metadata.url.isEmpty ? "none" : metadata.url
        let notes = metadata.notes.isEmpty ? "none" : metadata.notes
        let steps = metadata.steps.isEmpty ? "none" : metadata.steps.joined(separator: " | ")

        return """
        What do I want?
        \(exactWords.want)

        When I am...I like to
        \(exactWords.whenIAm)

        Done looks like...
        \(exactWords.doneLooksLike)

        Metadata
        Kind: \(metadata.kind.rawValue)
        Priority: \(metadata.priority.rawValue)
        Energy: \(metadata.energy.rawValue)
        Success Flags: clear_sign=\(metadata.flags.isClearSignOfSuccess) compound=\(metadata.flags.isCompound)
        Lift: \(metadata.listName.isEmpty ? "none" : metadata.listName)
        Pinned: \(metadata.pinned)
        Urgent: \(metadata.urgent)
        Tags: \(tags)
        Due At: \(dueAt)
        Defer Until: \(deferUntil)
        Waiting On: \(waitingOn)
        Location: \(location)
        URL: \(url)
        Notes: \(notes)
        Steps: \(steps)
        """
    }

    private static func isoString(from date: Date) -> String {
        return ISO8601DateFormatter().string(from: date)
    }
}

struct TechnicalCapture: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var reminderID: UUID
    var exactWords: TechnicalCaptureExactWords
    var metadata: TechnicalCaptureMetadata
    var promptText: String
    var createdAt: Date
    var updatedAt: Date

    var flags: TechnicalCaptureFlags { metadata.flags }

    init(
        id: UUID = UUID(),
        reminderID: UUID,
        exactWords: TechnicalCaptureExactWords,
        metadata: TechnicalCaptureMetadata,
        promptText: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.reminderID = reminderID
        self.exactWords = exactWords
        self.metadata = metadata
        self.promptText = promptText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func from(
        reminder: Reminder,
        existing: TechnicalCapture? = nil
    ) -> TechnicalCapture {
        let exactWords = TechnicalCaptureExactWords(
            want: reminder.title.trimmingCharacters(in: .whitespacesAndNewlines),
            whenIAm: (reminder.whenIAm ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            doneLooksLike: reminder.outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let metadata = TechnicalCaptureMetadata(reminder: reminder)
        return TechnicalCapture(
            id: existing?.id ?? UUID(),
            reminderID: reminder.id,
            exactWords: exactWords,
            metadata: metadata,
            promptText: TechnicalCapturePromptBuilder.build(exactWords: exactWords, metadata: metadata),
            createdAt: existing?.createdAt ?? reminder.createdAt,
            updatedAt: reminder.updatedAt
        )
    }
}

@MainActor
final class TechnicalCaptureStore: ObservableObject {
    @Published private(set) var captures: [TechnicalCapture]

    private let fileURL: URL

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.captures = try Self.load(from: fileURL)
    }

    static func live() -> TechnicalCaptureStore {
        do {
            return try TechnicalCaptureStore(fileURL: defaultFileURL)
        } catch {
            return TechnicalCaptureStore(captures: [], fileURL: defaultFileURL)
        }
    }

    func capture(forReminderID reminderID: UUID) -> TechnicalCapture? {
        captures.first { $0.reminderID == reminderID }
    }

    @discardableResult
    func save(_ capture: TechnicalCapture) -> TechnicalCapture {
        captures.removeAll { $0.id == capture.id || $0.reminderID == capture.reminderID }
        captures.insert(capture, at: 0)
        persist()
        return capture
    }

    func recentClearSignEntries(limit: Int) -> [TechnicalCapture] {
        recentEntries(limit: limit) { $0.flags.isClearSignOfSuccess }
    }

    func recentCompoundEntries(limit: Int) -> [TechnicalCapture] {
        recentEntries(limit: limit) { $0.flags.isCompound }
    }

    func recentClearSignOrCompoundEntries(limit: Int) -> [TechnicalCapture] {
        recentEntries(limit: limit) { $0.flags.isClearSignOfSuccess || $0.flags.isCompound }
    }

    private init(captures: [TechnicalCapture], fileURL: URL) {
        self.captures = captures
        self.fileURL = fileURL
    }

    private func recentEntries(
        limit: Int,
        where predicate: (TechnicalCapture) -> Bool
    ) -> [TechnicalCapture] {
        captures
            .filter(predicate)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    private static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY", isDirectory: true)
        return directory.appendingPathComponent("technical-captures.json")
    }

    private static func load(from fileURL: URL) throws -> [TechnicalCapture] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder.recall.decode([TechnicalCapture].self, from: data)
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.recall.encode(captures) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
