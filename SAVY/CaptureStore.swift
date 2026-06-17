import Foundation

@MainActor
final class CaptureStore: ObservableObject {
    @Published private(set) var entries: [CaptureEntry]

    init(entries: [CaptureEntry] = CaptureStore.seedEntries) {
        self.entries = entries
    }

    func save(title: String, meaning: String) {
        let entry = CaptureEntry(title: title, meaning: meaning)
        guard !entry.title.isEmpty || !entry.meaning.isEmpty else { return }
        entries.insert(entry, at: 0)
    }

    private static let seedEntries: [CaptureEntry] = [
        CaptureEntry(
            title: "Momentum is information",
            meaning: "Anything that creates forward motion deserves a native surface."
        )
    ]
}
