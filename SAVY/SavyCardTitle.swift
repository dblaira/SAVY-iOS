import Combine
import SwiftUI

/// Display titles belong to the card's stable identity, never to its position or
/// original writing. The same entry uses the same identity on every page.
struct SavyCardTitle: Equatable {
    let id: String
    let original: String

    static func reminder(_ reminder: Reminder, title: String? = nil) -> Self {
        Self(id: "reminder:\(reminder.id.uuidString)", original: title ?? reminder.title)
    }

    static func home(_ card: HomeLeverageCard) -> Self {
        Self(id: "home:\(card.sectionID)", original: card.title)
    }

    static func source(_ item: LeverageItem, title: String? = nil) -> Self {
        Self(id: "source:\(item.id)", original: title ?? item.title)
    }

    static func connection(_ entry: ConnectionEntry) -> Self {
        Self(id: "connection:\(entry.id.uuidString)", original: entry.preview.title)
    }

    static func post(_ post: SocialPost) -> Self {
        Self(id: "post:\(post.id.uuidString)", original: SavedPost.legacy(post).preview.title)
    }

    static func story(_ story: Story) -> Self {
        Self(id: "story:\(story.id.uuidString)", original: story.trimmedTitle)
    }

    var fallback: String { original.isEmpty ? "Untitled" : original }
}

@MainActor
final class SavyCardTitleStore: ObservableObject {
    static let shared = SavyCardTitleStore()
    static let defaultsKey = "savy.cardTitles.v1"
    @Published private(set) var titles: [String: String]
    let changes = PassthroughSubject<Void, Never>()
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? SavyCardPreferences.defaults
        titles = self.defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    func title(for card: SavyCardTitle, fallback: String? = nil) -> String {
        guard let title = titles[card.id], !title.isEmpty else { return fallback ?? card.fallback }
        return title
    }

    @discardableResult
    func rename(_ card: SavyCardTitle, to title: String) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard self.title(for: card) != title else { return true }
        var updated = titles
        updated[card.id] = title
        save(updated)
        changes.send()
        return true
    }

    func restoreOriginal(_ card: SavyCardTitle) {
        // A durable empty value carries the reset across devices without losing its timestamp.
        var updated = titles
        updated[card.id] = ""
        save(updated)
        changes.send()
    }

    func applySynced(_ values: [String: String]) { save(values) }

    private func save(_ values: [String: String]) {
        guard values != titles else { return }
        defaults.set(values, forKey: Self.defaultsKey)
        titles = values
    }
}

/// A separate document keeps older apps from treating unfamiliar title keys as
/// deleted card preferences. Each title merges independently in the existing sync engine.
@MainActor
final class CardTitlesSyncAdapter: SavySyncAdapter {
    let documentKey = "card-titles"
    let isReady = true
    private let store: SavyCardTitleStore

    init(store: SavyCardTitleStore) { self.store = store }
    var localChanges: AnyPublisher<Void, Never> { store.changes.eraseToAnyPublisher() }
    func snapshot() -> [String: SyncJSON] { store.titles.mapValues(SyncJSON.string) }

    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp {
        switch context {
        case .firstRun:
            // Unlike automatic Home pins, every stored title is an explicit user edit.
            SyncStamp(modifiedAt: 1, uploads: true)
        case .change(let previous, let now):
            SyncStamp(modifiedAt: SyncChangeContext.stampAfter(previous, now: now), uploads: true)
        }
    }

    func apply(_ values: [String: SyncJSON]) {
        store.applySynced(values.compactMapValues(\.stringValue))
    }

    func applyAndConfirm(_ values: [String: SyncJSON]) -> Bool {
        guard values.values.allSatisfy({ $0.stringValue != nil }) else { return false }
        apply(values)
        return snapshot() == values
    }
}

/// Gives inline writing the space normally reserved for iPhone navigation.
@MainActor
final class SavyCardTitleEditingState: ObservableObject {
    static let shared = SavyCardTitleEditingState()
    @Published var isEditing = false
}

@MainActor
final class SavyCardTitleSession: ObservableObject {
    private static weak var active: SavyCardTitleSession?
    @Published private(set) var card: SavyCardTitle?
    @Published var draft = ""
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onDelete: (() -> Void)?
    var isEditing: Bool { card != nil }

    func begin(_ card: SavyCardTitle) {
        guard !isEditing else { return }
        if let previous = Self.active, previous !== self {
            previous.save()
            previous.cancel()
        }
        draft = SavyCardTitleStore.shared.title(for: card)
        self.card = card
        Self.active = self
        SavyCardTitleEditingState.shared.isEditing = true
    }

    func save() {
        guard let card, SavyCardTitleStore.shared.rename(card, to: draft) else { return }
        cancel()
    }

    func cancel() {
        card = nil
        if Self.active === self {
            Self.active = nil
            SavyCardTitleEditingState.shared.isEditing = false
        }
    }
    func restoreOriginal() {
        if let card { SavyCardTitleStore.shared.restoreOriginal(card) }
        cancel()
    }
}

private struct SavyCardTitleSessionKey: EnvironmentKey {
    static let defaultValue: SavyCardTitleSession? = nil
}
private struct SavyCardTitleEditingKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var savyCardTitleSession: SavyCardTitleSession? {
        get { self[SavyCardTitleSessionKey.self] }
        set { self[SavyCardTitleSessionKey.self] = newValue }
    }
    var isEditingSavyCardTitle: Bool {
        get { self[SavyCardTitleEditingKey.self] }
        set { self[SavyCardTitleEditingKey.self] = newValue }
    }
}

/// Replaces only the title, inside its existing card. The surrounding font,
/// foreground, background and underline remain the card's own presentation.
struct SavyCardTitleText: View {
    let card: SavyCardTitle
    var fallback: String? = nil
    var accessibilityIdentifier: String? = nil
    @ObservedObject private var titles = SavyCardTitleStore.shared
    @Environment(\.savyCardTitleSession) private var session
    @Environment(\.isEditingSavyCardTitle) private var isEditing

    var body: some View {
        if isEditing, let session {
            SavyInlineCardTitle(session: session)
        } else {
            Text(titles.title(for: card, fallback: fallback))
                .accessibilityIdentifier(accessibilityIdentifier ?? "cardTitleText")
        }
    }
}

private struct SavyInlineCardTitle: View {
    @ObservedObject var session: SavyCardTitleSession
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $session.draft, selection: $selection, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { session.save() }
                .accessibilityLabel("Card title")
                .accessibilityIdentifier("cardTitleField")
            HStack(spacing: 16) {
                if let remove = session.onDelete {
                    control("Delete", icon: "trash", id: "deleteCard", action: {
                        session.cancel()
                        remove()
                    })
                }
                if let move = session.onMoveUp {
                    control("Move up", icon: "chevron.up", id: "reorderUp", action: move)
                }
                if let move = session.onMoveDown {
                    control("Move down", icon: "chevron.down", id: "reorderDown", action: move)
                }
                Spacer(minLength: 0)
                control("Cancel", icon: "xmark", id: "cancelCardTitle", action: session.cancel)
                if let card = session.card, let title = SavyCardTitleStore.shared.titles[card.id], !title.isEmpty {
                    control("Use Original Title", icon: "arrow.uturn.backward", id: "restoreCardTitle", action: session.restoreOriginal)
                }
                control("Save", icon: "checkmark", id: "saveCardTitle", action: session.save)
                    .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.system(size: 14, weight: .semibold))
        }
        .onAppear {
            selection = TextSelection(insertionPoint: session.draft.endIndex)
            focused = true
        }
    }

    private func control(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}

private struct SavyCardTitleContext: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var session: SavyCardTitleSession
    func body(content: Content) -> some View {
        content
            .environment(\.savyCardTitleSession, session)
            .environment(\.isEditingSavyCardTitle, session.isEditing)
            .onDisappear {
                session.save()
                // An empty draft keeps its saved title and must not leave the
                // iPhone navigation hidden after this card leaves the screen.
                session.cancel()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { session.save() }
            }
    }
}

private struct SavyCardTitleHold: ViewModifier {
    let card: SavyCardTitle
    @ObservedObject var session: SavyCardTitleSession
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in session.begin(card) })
            .contextMenu { Button("Change Title", systemImage: "pencil") { session.begin(card) } }
            .accessibilityAction(named: "Change Title") { session.begin(card) }
    }
}

/// While editing, the label is a plain card instead of a navigation control.
/// Tapping its text or editing controls can never open the entry underneath it.
struct SavyEditableCardLink<Destination: View, Label: View>: View {
    let cardTitle: SavyCardTitle
    @ViewBuilder var destination: Destination
    @ViewBuilder var label: Label
    @StateObject private var session = SavyCardTitleSession()

    var body: some View {
        Group {
            if session.isEditing { label }
            else {
                NavigationLink { destination } label: { label }
                    .buttonStyle(.plain)
                    .modifier(SavyCardTitleHold(card: cardTitle, session: session))
            }
        }
        .savyCardTitleContext(session)
    }
}

struct SavyEditableCardButton<Label: View>: View {
    let cardTitle: SavyCardTitle
    var action: () -> Void
    @ViewBuilder var label: Label
    @StateObject private var session: SavyCardTitleSession

    init(cardTitle: SavyCardTitle, session: SavyCardTitleSession? = nil,
         action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.cardTitle = cardTitle
        self.action = action
        self.label = label()
        _session = StateObject(wrappedValue: session ?? SavyCardTitleSession())
    }

    var body: some View {
        Group {
            if session.isEditing { label }
            else {
                Button(action: action) { label }
                    .buttonStyle(.plain)
                    .modifier(SavyCardTitleHold(card: cardTitle, session: session))
            }
        }
        .savyCardTitleContext(session)
    }
}

extension View {
    func savyCardTitleContext(_ session: SavyCardTitleSession) -> some View {
        modifier(SavyCardTitleContext(session: session))
    }
    func savyCardTitleHold(_ card: SavyCardTitle, session: SavyCardTitleSession) -> some View {
        modifier(SavyCardTitleHold(card: card, session: session))
    }
}
