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
}

private func firstRunContentStamp(_ date: Date?) -> SyncStamp {
    SyncStamp(modifiedAt: date?.timeIntervalSince1970 ?? 1, uploads: true)
}

private func changeStamp(_ previous: SyncEntry?, now: Double) -> SyncStamp {
    SyncStamp(modifiedAt: SyncChangeContext.stampAfter(previous, now: now), uploads: true)
}

/// Authored Connections, source-card pins, and hidden source cards.
@MainActor
final class ConnectionsSyncAdapter: SavySyncAdapter {
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
        // Schedule delivery and Calendar bindings belong to the device that created them.
        // Sanitize passthrough entries too, including records from a newer app version.
        return passthrough.merged(into: values).mapValues(Self.withoutLocalSchedule)
    }

    private static func withoutLocalSchedule(_ value: SyncJSON) -> SyncJSON {
        guard case .object(var entry) = value,
              case .object(var metadata) = entry["metadata"] else { return value }
        if let schedule = metadata.removeValue(forKey: "schedule"), schedule != .null {
            metadata.removeValue(forKey: "dueDate")
            metadata.removeValue(forKey: "dueTime")
            metadata.removeValue(forKey: "endTime")
        }
        entry["metadata"] = .object(metadata)
        return .object(entry)
    }

    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp {
        switch context {
        case .firstRun:
            let entry = key.hasPrefix("entry:") ? try? value.decode(ConnectionEntry.self) : nil
            return firstRunContentStamp(entry?.metadata.updatedAt)
        case .change(let previous, let now):
            return changeStamp(previous, now: now)
        }
    }

    func apply(_ values: [String: SyncJSON]) {
        var entries: [ConnectionEntry] = []
        var pins: [String: Bool] = [:]
        var hidden: Set<String> = []
        var undecodable: [String: SyncJSON] = [:]
        for (key, value) in values {
            if key.hasPrefix("entry:") {
                let sharedValue = Self.withoutLocalSchedule(value)
                if let entry = try? sharedValue.decode(ConnectionEntry.self) { entries.append(entry) } else { undecodable[key] = sharedValue }
            } else if key.hasPrefix("sourcePin:"), let pinned = value.boolValue {
                pins[String(key.dropFirst("sourcePin:".count))] = pinned
            } else if key.hasPrefix("hidden:"), value.boolValue == true {
                hidden.insert(String(key.dropFirst("hidden:".count)))
            }
        }
        passthrough.keep(undecodable)
        entries.sort {
            $0.metadata.createdAt == $1.metadata.createdAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.metadata.createdAt > $1.metadata.createdAt
        }
        store.applySynced(entries: entries, sourcePins: pins, hiddenSourceIDs: hidden)
    }
}

/// The older News/Advertising posts.
@MainActor
final class SocialPostsSyncAdapter: SavySyncAdapter {
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
            return firstRunContentStamp((try? value.decode(SocialPost.self))?.updatedAt)
        case .change(let previous, let now):
            return changeStamp(previous, now: now)
        }
    }

    func apply(_ values: [String: SyncJSON]) {
        var posts: [SocialPost] = []
        var undecodable: [String: SyncJSON] = [:]
        for (key, value) in values where key.hasPrefix("post:") {
            if let post = try? value.decode(SocialPost.self) { posts.append(post) } else { undecodable[key] = value }
        }
        passthrough.keep(undecodable)
        posts.sort { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
        store.applySynced(posts)
    }
}

/// Long-form Stories.
@MainActor
final class StoriesSyncAdapter: SavySyncAdapter {
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
            return firstRunContentStamp((try? value.decode(Story.self))?.updatedAt)
        case .change(let previous, let now):
            return changeStamp(previous, now: now)
        }
    }

    func apply(_ values: [String: SyncJSON]) {
        var stories: [Story] = []
        var undecodable: [String: SyncJSON] = [:]
        for (key, value) in values where key.hasPrefix("story:") {
            if let story = try? value.decode(Story.self) { stories.append(story) } else { undecodable[key] = value }
        }
        passthrough.keep(undecodable)
        stories.sort { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
        store.applySynced(stories)
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
            return SyncStamp(modifiedAt: legacyDevice ? 1 : 0, uploads: legacyDevice)
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
/// never handed out again on another. The number doubles as the entry's time so the larger wins.
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
        if let number = values["lastIssued"]?.numberValue { allocator.raiseLastIssued(to: Int(number)) }
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
        cardDefaults: UserDefaults
    ) -> Bool {
        if !connectionStore.entries.isEmpty || !connectionStore.sourcePinOverrides.isEmpty || !connectionStore.hiddenSourceIDs.isEmpty {
            return true
        }
        if !postStore.posts.isEmpty || !storyStore.stories.isEmpty { return true }
        let arrangementKeys = [PostCardOrderStore.defaultsKey, PostCardOrderStore.connectionsDefaultsKey, HomeSectionPinStore.orderDefaultsKey]
        return arrangementKeys.contains { cardDefaults.object(forKey: $0) != nil }
            || UserDefaults.standard.object(forKey: PersonalAuthorityReviewStore.reviewDefaultsKey) != nil
    }
}
