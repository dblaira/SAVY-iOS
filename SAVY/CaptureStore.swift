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
