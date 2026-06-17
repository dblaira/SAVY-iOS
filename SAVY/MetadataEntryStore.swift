import Foundation

final class MetadataEntryStore: ObservableObject {
    @Published private(set) var entries: [MetadataEntry]

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.entries = try Self.loadEntries(from: fileURL, decoder: decoder)
    }

    static func live() -> MetadataEntryStore {
        do {
            return try MetadataEntryStore(fileURL: defaultFileURL)
        } catch {
            return MetadataEntryStore(entries: [], fileURL: defaultFileURL)
        }
    }

    func save(_ entry: MetadataEntry) throws {
        guard !entry.title.isEmpty else { return }
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        try persist()
    }

    private init(entries: [MetadataEntry], fileURL: URL) {
        self.entries = entries
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    private static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY", isDirectory: true)
        return directory.appendingPathComponent("metadata-entries.json")
    }

    private static func loadEntries(from fileURL: URL, decoder: JSONDecoder) throws -> [MetadataEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([MetadataEntry].self, from: data)
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: [.atomic])
    }
}
