import Combine
import Foundation

/// Content adapters keep entries this build cannot decode exactly as received, so a newer copy's
/// records are never mistaken for deletions and removed everywhere.
@MainActor
private final class Passthrough {
    private(set) var values: [String: SyncJSON] = [:]

    func keep(_ decodeFailures: [String: SyncJSON]) {
        values = decodeFailures
    }

    func merged(into snapshot: [String: SyncJSON]) -> [String: SyncJSON] {
        snapshot.merging(values) { current, _ in current }
    }

    func restore(_ archived: [String: SyncJSON]) {
        values.merge(archived) { current, _ in current }
    }
}

/// Some stores retain a deleted row until transport confirms its version.
@MainActor
protocol SavyTombstoneSyncAdapter: SavySyncAdapter {
    var localTombstones: [String: Double] { get }
}

/// The durable journal restores only undecodable values, which have no editable row in this
/// build. This keeps a process restart from turning a newer app's unknown content into deletion.
@MainActor
protocol SavyPassthroughSyncAdapter: SavySyncAdapter {
    func restoreUndecodable(_ values: [String: SyncJSON])
}

private func portableReminderValue(_ value: SyncJSON) -> SyncJSON {
    guard case .object(var reminder) = value else { return value }
    reminder["needsSync"] = .bool(false)
    if case .object(var schedule) = reminder["schedule"] {
        schedule.removeValue(forKey: "calendarIdentifier")
        schedule.removeValue(forKey: "calendarEventIdentifier")
        reminder["schedule"] = .object(schedule)
        if reminder["scheduleSyncVersion"]?.numberValue == nil { reminder["scheduleSyncVersion"] = .number(1) }
    }
    return .object(reminder)
}

private func firstRunContentStamp(_ date: Date?) -> SyncStamp {
    SyncStamp(modifiedAt: date?.timeIntervalSince1970 ?? 1, uploads: true)
}

private func changeStamp(_ previous: SyncEntry?, now: Double) -> SyncStamp {
    SyncStamp(modifiedAt: SyncChangeContext.stampAfter(previous, now: now), uploads: true)
}

/// Authored Connections, source-card pins, and hidden source cards.
@MainActor
final class ConnectionsSyncAdapter: SavyPassthroughSyncAdapter {
    let documentKey = "connections"
    private let store: ConnectionStore
    private let passthrough = Passthrough()

    init(store: ConnectionStore) {
        self.store = store
    }

    var isReady: Bool { store.canSync }

    var localChanges: AnyPublisher<Void, Never> {
        store.objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    func snapshot() -> [String: SyncJSON] {
        var values: [String: SyncJSON] = [:]
        for entry in store.entries {
            if let json = try? SyncJSON.encode(entry) { values["entry:\(entry.id.uuidString.lowercased())"] = json }
        }
        for (id, pinned) in store.sourcePinOverrides { values["sourcePin:\(id)"] = .bool(pinned) }
        for id in store.hiddenSourceIDs { values["hidden:\(id)"] = .bool(true) }
        // Schedule choices travel with the entry; EventKit identifiers only name objects
        // on one device. Sanitize undecodable newer entries without discarding their data.
        return passthrough.merged(into: values).mapValues(Self.withoutNativeCalendarBindings)
    }

    private static func withoutNativeCalendarBindings(_ value: SyncJSON) -> SyncJSON {
        guard case .object(var entry) = value,
              case .object(let metadata) = entry["metadata"] else { return value }
        // Nil Schedule without a version is an older app's omission, not a deletion.
        // A versioned nil Schedule is retained so explicit removals reach other devices.
        entry["metadata"] = portableReminderValue(.object(metadata))
        return .object(entry)
    }

    func restoreUndecodable(_ values: [String: SyncJSON]) {
        passthrough.restore(values.filter { key, value in
            guard key.hasPrefix("entry:") else { return false }
            guard let entry = try? value.decode(ConnectionEntry.self) else { return true }
            return key != "entry:\(entry.id.uuidString.lowercased())"
        }
            .mapValues(Self.withoutNativeCalendarBindings))
    }

    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp {
        switch context {
        case .firstRun:
            let entry = key.hasPrefix("entry:") ? try? value.decode(ConnectionEntry.self) : nil
            let stored = store.entries.first { "entry:\($0.id.uuidString.lowercased())" == key }
            let contentDate = stored?.metadata.updatedAt ?? entry?.metadata.updatedAt
            let changed = store.syncModificationDates[key]
            return firstRunContentStamp([contentDate, changed].compactMap { $0 }.max())
        case .change(let previous, let now):
            return changeStamp(previous, now: now)
        }
    }

    func apply(_ values: [String: SyncJSON]) {
        _ = applyAndConfirm(values)
    }

    func applyAndConfirm(_ values: [String: SyncJSON]) -> Bool {
        var entries: [ConnectionEntry] = []
        var pins: [String: Bool] = [:]
        var hidden: Set<String> = []
        var undecodable: [String: SyncJSON] = [:]
        for (key, value) in values {
            if key.hasPrefix("entry:") {
                let sharedValue = Self.withoutNativeCalendarBindings(value)
                if let entry = try? sharedValue.decode(ConnectionEntry.self), key == "entry:\(entry.id.uuidString.lowercased())" {
                    entries.append(entry)
                } else { undecodable[key] = sharedValue }
            } else if key.hasPrefix("sourcePin:"), let pinned = value.boolValue {
                pins[String(key.dropFirst("sourcePin:".count))] = pinned
            } else if key.hasPrefix("hidden:"), value.boolValue == true {
                hidden.insert(String(key.dropFirst("hidden:".count)))
            }
        }
        entries.sort {
            $0.metadata.createdAt == $1.metadata.createdAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.metadata.createdAt > $1.metadata.createdAt
        }
        guard store.applySynced(entries: entries, sourcePins: pins, hiddenSourceIDs: hidden) else { return false }
        passthrough.keep(undecodable)
        return true
    }
}

/// The older News/Advertising posts.
@MainActor
final class SocialPostsSyncAdapter: SavyPassthroughSyncAdapter {
    let documentKey = "social-posts"
    private let store: SocialPostStore
    private let passthrough = Passthrough()

    init(store: SocialPostStore) {
        self.store = store
    }

    var isReady: Bool { !store.loadFailed }

    var localChanges: AnyPublisher<Void, Never> {
        store.objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    func snapshot() -> [String: SyncJSON] {
        var values: [String: SyncJSON] = [:]
        for post in store.posts {
            if let json = try? SyncJSON.encode(post) { values["post:\(post.id.uuidString.lowercased())"] = json }
        }
        return passthrough.merged(into: values)
    }

    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp {
        switch context {
        case .firstRun:
            let stored = store.posts.first { "post:\($0.id.uuidString.lowercased())" == key }
            return firstRunContentStamp(stored?.updatedAt ?? (try? value.decode(SocialPost.self))?.updatedAt)
        case .change(let previous, let now):
            return changeStamp(previous, now: now)
        }
    }

    func apply(_ values: [String: SyncJSON]) {
        _ = applyAndConfirm(values)
    }

    func restoreUndecodable(_ values: [String: SyncJSON]) {
        passthrough.restore(values.filter { key, value in
            guard key.hasPrefix("post:") else { return false }
            guard let post = try? value.decode(SocialPost.self) else { return true }
            return key != "post:\(post.id.uuidString.lowercased())"
        })
    }

    func applyAndConfirm(_ values: [String: SyncJSON]) -> Bool {
        var posts: [SocialPost] = []
        var undecodable: [String: SyncJSON] = [:]
        for (key, value) in values where key.hasPrefix("post:") {
            if let post = try? value.decode(SocialPost.self), key == "post:\(post.id.uuidString.lowercased())" {
                posts.append(post)
            } else { undecodable[key] = value }
        }
        posts.sort { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
        guard store.applySynced(posts) else { return false }
        passthrough.keep(undecodable)
        return true
    }
}

/// Long-form Stories.
@MainActor
final class StoriesSyncAdapter: SavyPassthroughSyncAdapter {
    let documentKey = "stories"
    private let store: StoryStore
    private let passthrough = Passthrough()

    init(store: StoryStore) {
        self.store = store
    }

    var isReady: Bool { !store.loadFailed }

    var localChanges: AnyPublisher<Void, Never> {
        store.objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    func snapshot() -> [String: SyncJSON] {
        var values: [String: SyncJSON] = [:]
        for story in store.stories {
            if let json = try? SyncJSON.encode(story) { values["story:\(story.id.uuidString.lowercased())"] = json }
        }
        return passthrough.merged(into: values)
    }

    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp {
        switch context {
        case .firstRun:
            let stored = store.stories.first { "story:\($0.id.uuidString.lowercased())" == key }
            return firstRunContentStamp(stored?.updatedAt ?? (try? value.decode(Story.self))?.updatedAt)
        case .change(let previous, let now):
            return changeStamp(previous, now: now)
        }
    }

    func apply(_ values: [String: SyncJSON]) {
        _ = applyAndConfirm(values)
    }

    func restoreUndecodable(_ values: [String: SyncJSON]) {
        passthrough.restore(values.filter { key, value in
            guard key.hasPrefix("story:") else { return false }
            guard let story = try? value.decode(Story.self) else { return true }
            return key != "story:\(story.id.uuidString.lowercased())"
        })
    }

    func applyAndConfirm(_ values: [String: SyncJSON]) -> Bool {
        var stories: [Story] = []
        var undecodable: [String: SyncJSON] = [:]
        for (key, value) in values where key.hasPrefix("story:") {
            if let story = try? value.decode(Story.self), key == "story:\(story.id.uuidString.lowercased())" {
                stories.append(story)
            } else { undecodable[key] = value }
        }
        stories.sort { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
        guard store.applySynced(stories) else { return false }
        passthrough.keep(undecodable)
        return true
    }
}

/// Reminder-based Reminders, Actions, Calendar entries, and Posts share one portable store.
@MainActor
final class RemindersSyncAdapter: SavyTombstoneSyncAdapter, SavyPassthroughSyncAdapter {
    let documentKey = "reminders"
    private let store: ReminderStore
    private let passthrough = Passthrough()

    init(store: ReminderStore) { self.store = store }
    var isReady: Bool { store.canSync }
    var localChanges: AnyPublisher<Void, Never> {
        store.objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    var localTombstones: [String: Double] {
        store.reminders.filter { $0.status == .deleted }.reduce(into: [:]) { result, reminder in
            result["reminder:\(reminder.id.uuidString.lowercased())"] = reminder.updatedAt.timeIntervalSince1970
        }
    }

    func snapshot() -> [String: SyncJSON] {
        var values: [String: SyncJSON] = [:]
        for reminder in store.reminders where reminder.status != .deleted {
            if let value = try? SyncJSON.encode(reminder) {
                values["reminder:\(reminder.id.uuidString.lowercased())"] = portableReminderValue(value)
            }
        }
        return passthrough.merged(into: values).mapValues(portableReminderValue)
    }

    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp {
        switch context {
        case .firstRun:
            let stored = store.reminders.first { "reminder:\($0.id.uuidString.lowercased())" == key }
            return firstRunContentStamp(stored?.updatedAt ?? (try? value.decode(Reminder.self))?.updatedAt)
        case .change(let previous, let now):
            return changeStamp(previous, now: now)
        }
    }

    func restoreUndecodable(_ values: [String: SyncJSON]) {
        passthrough.restore(values.filter { key, value in
            guard key.hasPrefix("reminder:") else { return false }
            guard let reminder = try? value.decode(Reminder.self) else { return true }
            return reminder.status == .deleted || key != "reminder:\(reminder.id.uuidString.lowercased())"
        }
            .mapValues(portableReminderValue))
    }

    func apply(_ values: [String: SyncJSON]) { _ = applyAndConfirm(values) }

    func applyAndConfirm(_ values: [String: SyncJSON]) -> Bool {
        var reminders: [Reminder] = []
        var undecodable: [String: SyncJSON] = [:]
        for (key, value) in values where key.hasPrefix("reminder:") {
            let portable = portableReminderValue(value)
            if let reminder = try? portable.decode(Reminder.self), reminder.status != .deleted,
               key == "reminder:\(reminder.id.uuidString.lowercased())" { reminders.append(reminder) }
            else { undecodable[key] = portable }
        }
        reminders.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        guard store.applySynced(reminders) else { return false }
        passthrough.keep(undecodable)
        return true
    }
}

/// Card order and pins for Home, Social Media Posts, and Connection.
@MainActor
final class CardPreferencesSyncAdapter: SavySyncAdapter {
    let documentKey = "card-preferences"
    private let defaults: UserDefaults

    static let defaultsKeys: [String: String] = [
        "posts.order": PostCardOrderStore.defaultsKey,
        "connections.order": PostCardOrderStore.connectionsDefaultsKey,
        "home.pinned": HomeSectionPinStore.pinnedIDsDefaultsKey,
        "home.order": HomeSectionPinStore.orderDefaultsKey,
    ]

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    let isReady = true

    var localChanges: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func snapshot() -> [String: SyncJSON] {
        Self.defaultsKeys.reduce(into: [:]) { values, pair in
            if let ids = defaults.stringArray(forKey: pair.value) { values[pair.key] = .array(ids.map(SyncJSON.string)) }
        }
    }

    /// A new install writes default pins before it has synced. Those defaults are never uploaded,
    /// so they cannot replace the arrangement from a device that already had one.
    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp {
        switch context {
        case .firstRun(let legacyDevice):
            let automaticPin = key == "home.pinned"
                && value.stringArray == [HomeSectionPinStore.defaultPinnedSectionID]
                && defaults.object(forKey: HomeSectionPinStore.orderDefaultsKey) == nil
            return SyncStamp(modifiedAt: legacyDevice && !automaticPin ? 1 : 0,
                             uploads: legacyDevice && !automaticPin)
        case .change(let previous, let now):
            return changeStamp(previous, now: now)
        }
    }

    func apply(_ values: [String: SyncJSON]) {
        for (entryKey, defaultsKey) in Self.defaultsKeys {
            guard let ids = values[entryKey]?.stringArray, defaults.stringArray(forKey: defaultsKey) != ids else { continue }
            defaults.set(ids, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: SavyCardPreferences.didApplySync, object: nil)
    }
}

/// The highest post number issued anywhere. It only rises, so a number used on one device is
/// reserved before that device creates another Post. Simultaneous offline references stay intact.
/// The number doubles as the entry's time so the larger wins.
@MainActor
final class PostNumbersSyncAdapter: SavySyncAdapter {
    let documentKey = "post-numbers"
    private let allocator: PostNumberAllocator

    init(allocator: PostNumberAllocator) {
        self.allocator = allocator
    }

    let isReady = true

    var localChanges: AnyPublisher<Void, Never> {
        allocator.changes.eraseToAnyPublisher()
    }

    func snapshot() -> [String: SyncJSON] {
        ["lastIssued": .number(Double(allocator.lastIssuedNumber))]
    }

    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp {
        SyncStamp(modifiedAt: value.numberValue ?? 0, uploads: true)
    }

    func apply(_ values: [String: SyncJSON]) {
        _ = applyAndConfirm(values)
    }

    func applyAndConfirm(_ values: [String: SyncJSON]) -> Bool {
        guard let number = values["lastIssued"]?.numberValue else { return true }
        guard number.isFinite, number >= 0, number < Double(Int.max), number.rounded() == number else { return false }
        return allocator.raiseLastIssued(to: Int(number))
    }
}

/// Teach Cowboy AI decisions. Automatic approvals and decisions made before this build carry no
/// time, so a deliberate "context" or "evidence only" choice outranks an automatic approval.
@MainActor
final class PersonalAuthoritySyncAdapter: SavySyncAdapter {
    let documentKey = "personal-authority"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    let isReady = true

    var localChanges: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func snapshot() -> [String: SyncJSON] {
        PersonalAuthorityReviewStore.savedDecisions(defaults: defaults).reduce(into: [:]) { values, pair in
            values["decision:\(pair.key)"] = .string(pair.value.rawValue)
        }
    }

    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp {
        let id = String(key.dropFirst("decision:".count))
        if let decided = PersonalAuthorityReviewStore.savedDecisionDates(defaults: defaults)[id] {
            return SyncStamp(modifiedAt: decided.timeIntervalSince1970, uploads: true)
        }
        return SyncStamp(modifiedAt: value.stringValue == PersonalAuthorityDecision.mine.rawValue ? 0 : 1, uploads: true)
    }

    func apply(_ values: [String: SyncJSON]) {
        var decisions: [String: PersonalAuthorityDecision] = [:]
        for (key, value) in values where key.hasPrefix("decision:") {
            if let raw = value.stringValue, let decision = PersonalAuthorityDecision(rawValue: raw) {
                decisions[String(key.dropFirst("decision:".count))] = decision
            }
        }
        PersonalAuthorityReviewStore.saveSyncedDecisions(decisions, defaults: defaults)
    }
}

extension SavyDocumentSync {
    /// A device that already holds records of its own seeds the shared copy with them. A fresh
    /// install (the first Mac launch) only receives.
    static func holdsLocalRecords(
        connectionStore: ConnectionStore,
        postStore: SocialPostStore,
        storyStore: StoryStore,
        cardDefaults: UserDefaults,
        authorityDefaults: UserDefaults = .standard
    ) -> Bool {
        if !connectionStore.entries.isEmpty || !connectionStore.sourcePinOverrides.isEmpty || !connectionStore.hiddenSourceIDs.isEmpty {
            return true
        }
        if !postStore.posts.isEmpty || !storyStore.stories.isEmpty { return true }
        let arrangementKeys = [PostCardOrderStore.defaultsKey, PostCardOrderStore.connectionsDefaultsKey, HomeSectionPinStore.orderDefaultsKey]
        return arrangementKeys.contains { cardDefaults.object(forKey: $0) != nil }
            || authorityDefaults.object(forKey: PersonalAuthorityReviewStore.reviewDefaultsKey) != nil
    }
}
