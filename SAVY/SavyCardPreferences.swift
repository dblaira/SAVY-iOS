import Foundation
import SwiftUI

/// Card positions sync separately from authored entries.
/// Physical-device UI checks use their own defaults domain and reset it once per launch.
@MainActor
enum SavyCardPreferences {
    /// Posted after document sync writes arrangements from another device into `defaults`.
    static let didApplySync = Notification.Name("SavyCardPreferencesDidApplySync")

    static let defaults: UserDefaults = {
        guard !SavyRuntime.isTesting else {
            let suite = "com.adamblair.savy.ui-test.card-preferences"
            let defaults = UserDefaults(suiteName: suite)!
            if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_RESET_REMINDERS") {
                defaults.removePersistentDomain(forName: suite)
            }
            return defaults
        }
        return .standard
    }()
}

/// Names a card for its custom title. Each card's prefilled title still comes from the writing.
enum SavyCardTitleKey {
    /// Reminder, Action, Event, Post and authored Connection entries, on every page they appear.
    static func entry(_ id: UUID) -> String { "entry:\(id.uuidString.lowercased())" }
    /// The older News/Advertising posts.
    static func socialPost(_ id: UUID) -> String { "social:\(id.uuidString.lowercased())" }
    /// Source Connections, Ontology, Field Essays and the seeded Social Media Posts items.
    static func item(section: String, id: String) -> String { "item:\(section):\(id)" }
    /// The lower Home destination cards.
    static func home(_ sectionID: String) -> String { "home:\(sectionID)" }
}

/// Adam, 2026-10-18: "At this time, the titles or labels on the cards are prefilled according to
/// what I've written first, and that's fine, but I also want the ability to be able to change the titles"
/// A custom title changes only the card face. The saved writing stays exactly as written, and
/// clearing the custom title brings the prefilled title back.
@MainActor
final class SavyCardTitleStore: ObservableObject {
    struct Entry: Codable, Equatable {
        var title: String
        var updatedAt: Date
    }

    static let shared: SavyCardTitleStore = {
        let file = defaultFileURL
        if SavyRuntime.isTesting, ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_RESET_REMINDERS") {
            try? FileManager.default.removeItem(at: file)
        }
        return SavyCardTitleStore(fileURL: file)
    }()

    @Published private(set) var entries: [String: Entry] = [:]
    /// An unreadable file is kept as evidence and is never replaced by an empty title list.
    private(set) var loadFailed = false
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            entries = try JSONDecoder.recall.decode([String: Entry].self, from: Data(contentsOf: fileURL))
        } catch {
            loadFailed = true
        }
    }

    static var defaultFileURL: URL {
        if SavyRuntime.isTesting {
            return FileManager.default.temporaryDirectory.appendingPathComponent("SAVYUITests/card-titles.json")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY/card-titles.json")
    }

    func title(for key: String) -> String? {
        entries[key]?.title
    }

    /// An empty title, or the prefilled title itself, removes the custom title.
    @discardableResult
    func setTitle(_ typed: String, for key: String, prefilled: String? = nil) -> Bool {
        let title = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = entries
        if title.isEmpty || title == prefilled {
            next.removeValue(forKey: key)
        } else if next[key]?.title != title {
            next[key] = Entry(title: title, updatedAt: Date())
        }
        return persist(next)
    }

    // MARK: Sync

    /// Custom titles travel inside the reminders document. Every SAVY build keeps `reminder:`
    /// entries it cannot read, so an iPhone or Mac still on an older build passes these titles
    /// through untouched. A new document would instead stop an older build's sync.
    static let syncKeyPrefix = "reminder:card-title:"

    static func isSyncKey(_ key: String) -> Bool {
        key.hasPrefix(syncKeyPrefix)
    }

    var syncValues: [String: SyncJSON] {
        entries.reduce(into: [:]) { values, pair in
            values[Self.syncKeyPrefix + pair.key] = .string(pair.value.title)
        }
    }

    func updatedAt(syncKey: String) -> Date? {
        guard Self.isSyncKey(syncKey) else { return nil }
        return entries[String(syncKey.dropFirst(Self.syncKeyPrefix.count))]?.updatedAt
    }

    /// Replaces the custom titles with the merged document's live titles.
    @discardableResult
    func applySynced(_ values: [String: SyncJSON]) -> Bool {
        var next: [String: Entry] = [:]
        for (syncKey, value) in values where Self.isSyncKey(syncKey) {
            guard case .string(let title) = value, !title.isEmpty else { continue }
            let key = String(syncKey.dropFirst(Self.syncKeyPrefix.count))
            if let current = entries[key], current.title == title {
                next[key] = current
            } else {
                next[key] = Entry(title: title, updatedAt: Date())
            }
        }
        return persist(next)
    }

    private func persist(_ next: [String: Entry]) -> Bool {
        guard !loadFailed else { return false }
        guard next != entries else { return true }
        do {
            let data = try JSONEncoder.recall.encode(next)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            entries = next
            return true
        } catch {
            return false
        }
    }
}

/// What the Rename prompt edits. `prefilled` is nil when the title is the record's own field,
/// as it is for Stories.
struct SavyCardTitleEdit: Identifiable {
    let id: String
    let current: String
    var prefilled: String? = nil
    let save: (String) -> Void

    /// A custom title over a card whose title is prefilled from the writing.
    @MainActor
    static func custom(key: String, prefilled: String) -> SavyCardTitleEdit {
        let titles = SavyCardTitleStore.shared
        return SavyCardTitleEdit(id: key, current: titles.title(for: key) ?? prefilled, prefilled: prefilled) { typed in
            _ = titles.setTitle(typed, for: key, prefilled: prefilled)
        }
    }
}

extension SavySwipeAction {
    /// Swipe right, then Rename. On the Mac, the right-click menu offers the same action.
    static func rename(_ run: @escaping () -> Void) -> SavySwipeAction {
        SavySwipeAction(title: "Rename", icon: "pencil", bg: SavyTheme.deepNavy, run: run)
    }
}

extension View {
    /// Presents the Rename prompt whenever `edit` is set.
    func savyCardTitleEditor(_ edit: Binding<SavyCardTitleEdit?>) -> some View {
        modifier(SavyCardTitleEditor(edit: edit))
    }
}

private struct SavyCardTitleEditor: ViewModifier {
    @Binding var edit: SavyCardTitleEdit?
    @State private var draft = ""
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            // The draft is filled before the prompt appears, so it opens on the current title.
            .onChange(of: edit?.id) { _, id in
                draft = edit?.current ?? ""
                isShowing = id != nil
            }
            .onChange(of: isShowing) { _, showing in
                if !showing { edit = nil }
            }
            .alert("Rename Card", isPresented: $isShowing, presenting: edit) { edit in
                TextField("Title", text: $draft)
                    .accessibilityIdentifier("cardTitleField")
                Button("Save") { edit.save(draft) }
                    .accessibilityIdentifier("cardTitleSave")
                if let prefilled = edit.prefilled, edit.current != prefilled {
                    Button("Use Original") { edit.save("") }
                        .accessibilityIdentifier("cardTitleUseOriginal")
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}
