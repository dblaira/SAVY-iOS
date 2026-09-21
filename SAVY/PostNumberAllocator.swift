import Foundation

/// One sequence shared by both saved Post formats. Deleted assignments stay in this ledger
/// so a later post never takes a number Adam has already used as a reference.
@MainActor
final class PostNumberAllocator {
    enum Source: String { case reminder, socialPost }

    private struct Ledger: Codable {
        var assignments: [String: Int] = [:]
        var lastIssued: Int = 0
    }

    private struct Record {
        let source: Source
        let id: UUID
        let createdAt: Date
        let number: Int?

        var key: String { PostNumberAllocator.key(source: source, id: id) }
    }

    private let fileURL: URL
    private var ledger: Ledger

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: fileURL))
        } else {
            ledger = Ledger()
        }
        ledger.lastIssued = max(ledger.lastIssued, ledger.assignments.values.max() ?? 0)
    }

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY/post-numbers.json")
    }

    /// Call with both loaded caches before attaching either store. On subsequent loads the
    /// retained assignments win; already numbered remote records reserve their numbers first.
    func seed(reminders: [Reminder], socialPosts: [SocialPost]) {
        let records = reminders.filter { $0.kind == .post && ($0.status != .deleted || $0.postNumber != nil) }
            .map { Record(source: .reminder, id: $0.id, createdAt: $0.createdAt, number: $0.postNumber) }
            + socialPosts.map { Record(source: .socialPost, id: $0.id, createdAt: $0.createdAt, number: $0.postNumber) }
        let chronological = records.sorted {
            $0.createdAt == $1.createdAt ? $0.key < $1.key : $0.createdAt < $1.createdAt
        }
        // Reserve every existing number before filling gaps, even when a numbered record
        // is newer than an unnumbered record in the same fetched batch.
        for record in chronological where (record.number ?? 0) > 0 {
            _ = number(for: record.source, id: record.id, savedNumber: record.number)
        }
        for record in chronological {
            _ = number(for: record.source, id: record.id, savedNumber: record.number)
        }
    }

    func number(for source: Source, id: UUID, savedNumber: Int? = nil) -> Int {
        let recordKey = Self.key(source: source, id: id)
        if let assigned = ledger.assignments[recordKey] { return assigned }
        let assigned: Int
        if let savedNumber, savedNumber > 0, !ledger.assignments.values.contains(savedNumber) {
            assigned = savedNumber
        } else {
            assigned = ledger.lastIssued + 1
        }
        ledger.assignments[recordKey] = assigned
        ledger.lastIssued = max(ledger.lastIssued, assigned)
        persist()
        return assigned
    }

    private nonisolated static func key(source: Source, id: UUID) -> String {
        "\(source.rawValue):\(id.uuidString.lowercased())"
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(ledger) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
