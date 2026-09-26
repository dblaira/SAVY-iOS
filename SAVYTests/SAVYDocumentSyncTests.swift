import XCTest
@testable import SAVY

/// Mirrors the gateway: an incoming entry replaces the stored one only when it is strictly newer.
private final class InMemorySyncServer: SavyDocumentSyncClient, @unchecked Sendable {
    private let lock = NSLock()
    private var documents: [String: [String: SyncEntry]] = [:]

    func fetchDocuments() async throws -> [String: [String: SyncEntry]] {
        lock.withLock { documents }
    }

    func merge(key: String, entries: [String: SyncEntry]) async throws -> [String: SyncEntry] {
        lock.withLock {
            var stored = documents[key] ?? [:]
            for (entryKey, entry) in entries where (stored[entryKey]?.modifiedAt ?? -1) < entry.modifiedAt {
                stored[entryKey] = entry
            }
            documents[key] = stored
            return stored
        }
    }

    func entries(_ key: String) -> [String: SyncEntry] {
        lock.withLock { documents[key] ?? [:] }
    }
}

private struct UnavailableServer: SavyDocumentSyncClient {
    func fetchDocuments() async throws -> [String: [String: SyncEntry]] { throw SavyDocumentSyncError.unavailable }
    func merge(key: String, entries: [String: SyncEntry]) async throws -> [String: SyncEntry] { throw SavyDocumentSyncError.unavailable }
}

/// One simulated copy of SAVY with its own files and preferences.
@MainActor
private final class Device {
    let directory: URL
    let cardDefaults: UserDefaults
    let authorityDefaults: UserDefaults
    let connections: ConnectionStore
    let posts: SocialPostStore
    let stories: StoryStore
    let allocator: PostNumberAllocator
    private(set) var sync: SavyDocumentSync!
    private let suites: [String]

    init(name: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("savy-sync-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cardSuite = "savy-sync-cards-\(UUID().uuidString)"
        let authoritySuite = "savy-sync-authority-\(UUID().uuidString)"
        suites = [cardSuite, authoritySuite]
        cardDefaults = try XCTUnwrap(UserDefaults(suiteName: cardSuite))
        authorityDefaults = try XCTUnwrap(UserDefaults(suiteName: authoritySuite))
        connections = ConnectionStore(fileURL: directory.appendingPathComponent("connections.json"), launchArguments: [])
        posts = try SocialPostStore(fileURL: directory.appendingPathComponent("posts.json"))
        stories = try StoryStore(fileURL: directory.appendingPathComponent("stories.json"))
        allocator = try PostNumberAllocator(fileURL: directory.appendingPathComponent("post-numbers.json"))
        posts.configurePostNumbering(allocator)
    }

    func connect(to client: any SavyDocumentSyncClient) {
        let legacy = SavyDocumentSync.holdsLocalRecords(
            connectionStore: connections, postStore: posts, storyStore: stories, cardDefaults: cardDefaults
        ) || authorityDefaults.object(forKey: PersonalAuthorityReviewStore.reviewDefaultsKey) != nil
        sync = SavyDocumentSync(
            adapters: [
                ConnectionsSyncAdapter(store: connections),
                SocialPostsSyncAdapter(store: posts),
                StoriesSyncAdapter(store: stories),
                CardPreferencesSyncAdapter(defaults: cardDefaults),
                PersonalAuthoritySyncAdapter(defaults: authorityDefaults),
                PostNumbersSyncAdapter(allocator: allocator),
            ],
            client: client,
            directory: directory.appendingPathComponent("Sync", isDirectory: true),
            legacyDevice: legacy
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
    }
}

final class SAVYDocumentSyncTests: XCTestCase {
    @MainActor
    func testRecordsSurviveTheJSONRoundTripUnchanged() throws {
        var post = SocialPost()
        post.text = "Volume is where patterns can be seen."
        post.postNumber = 7
        post.pinned = true
        post.likes = 3
        let json = try SyncJSON.encode(post)
        let reloaded = try json.decode(SocialPost.self)
        XCTAssertEqual(try SyncJSON.encode(reloaded), json)
        XCTAssertEqual(reloaded.postNumber, 7)
        XCTAssertEqual(reloaded.pinned, true)

        let wire = try JSONSerialization.data(withJSONObject: ["n": json.anyValue])
        let back = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        XCTAssertEqual(try SyncJSON(any: try XCTUnwrap(back["n"])), json)
        XCTAssertEqual(try SyncJSON(any: NSNumber(value: true)), .bool(true))
        XCTAssertEqual(try SyncJSON(any: NSNumber(value: 1)), .number(1))
    }

    @MainActor
    func testPhoneRecordsReachAFreshMacWithoutTheMacDefaultsReplacingThem() async throws {
        let server = InMemorySyncServer()
        let phone = try Device(name: "phone")
        let mac = try Device(name: "mac")
        defer { phone.tearDown(); mac.tearDown() }

        var connection = Reminder()
        connection.postAnswers = ["", "", "Specialization is a kill switch.", ""]
        XCTAssertTrue(phone.connections.save(connection))
        XCTAssertTrue(phone.connections.setSourcePinned(id: "polymath-specialization-kill-switch", isPinned: true))
        var post = SocialPost()
        post.text = "Taste is not the new moat."
        phone.posts.save(post)
        var story = Story()
        story.title = "Volume"
        phone.stories.save(story)
        phone.cardDefaults.set(["beliefs", "news-channel"], forKey: HomeSectionPinStore.pinnedIDsDefaultsKey)
        phone.cardDefaults.set(["beliefs", "news-channel", "ontology", "field-essays"], forKey: HomeSectionPinStore.orderDefaultsKey)
        let phonePostNumber = try XCTUnwrap(phone.posts.posts.first?.postNumber)

        // A fresh Mac writes its default Home pin before it has ever synced.
        _ = HomeSectionPinStore(defaults: mac.cardDefaults)
        XCTAssertEqual(mac.cardDefaults.stringArray(forKey: HomeSectionPinStore.pinnedIDsDefaultsKey), ["news-channel"])

        mac.connect(to: server)
        await mac.sync.start()
        XCTAssertNil(server.entries("card-preferences")["home.pinned"], "A fresh install must not upload its defaults")

        phone.connect(to: server)
        await phone.sync.start()
        await mac.sync.syncNow()

        XCTAssertEqual(mac.connections.entries.map(\.id), [connection.id])
        XCTAssertEqual(mac.connections.entries.first?.answers[2], "Specialization is a kill switch.")
        XCTAssertEqual(mac.connections.sourcePinOverrides["polymath-specialization-kill-switch"], true)
        XCTAssertEqual(mac.posts.posts.map(\.text), ["Taste is not the new moat."])
        XCTAssertEqual(mac.posts.posts.first?.postNumber, phonePostNumber)
        XCTAssertEqual(mac.stories.stories.map(\.title), ["Volume"])
        XCTAssertEqual(mac.cardDefaults.stringArray(forKey: HomeSectionPinStore.pinnedIDsDefaultsKey), ["beliefs", "news-channel"])
        XCTAssertEqual(mac.cardDefaults.stringArray(forKey: HomeSectionPinStore.orderDefaultsKey),
                       ["beliefs", "news-channel", "ontology", "field-essays"])
        XCTAssertGreaterThanOrEqual(mac.allocator.lastIssuedNumber, phonePostNumber)
        XCTAssertEqual(try mac.posts.posts.map(SyncJSON.encode), try phone.posts.posts.map(SyncJSON.encode))
    }

    @MainActor
    func testEditsAndDeletionsOnTheMacReachThePhone() async throws {
        let server = InMemorySyncServer()
        let phone = try Device(name: "phone")
        let mac = try Device(name: "mac")
        defer { phone.tearDown(); mac.tearDown() }

        var first = SocialPost()
        first.text = "First"
        phone.posts.save(first)
        var second = SocialPost()
        second.text = "Second"
        phone.posts.save(second)
        phone.cardDefaults.set(["legacy-a"], forKey: PostCardOrderStore.defaultsKey)
        phone.connect(to: server)
        await phone.sync.start()
        mac.connect(to: server)
        await mac.sync.start()
        XCTAssertEqual(Set(mac.posts.posts.map(\.text)), ["First", "Second"])

        let macFirst = try XCTUnwrap(mac.posts.posts.first { $0.id == first.id })
        mac.posts.delete(macFirst)
        let macSecond = try XCTUnwrap(mac.posts.posts.first { $0.id == second.id })
        mac.posts.togglePin(macSecond)
        let pins = HomeSectionPinStore(defaults: mac.cardDefaults)
        pins.toggle("ontology")
        var connection = Reminder()
        connection.postAnswers = ["", "", "Written on the Mac.", ""]
        XCTAssertTrue(mac.connections.save(connection))
        await mac.sync.syncNow()
        await phone.sync.syncNow()

        XCTAssertEqual(phone.posts.posts.map(\.id), [second.id])
        XCTAssertEqual(phone.posts.posts.first?.pinned, true)
        XCTAssertEqual(phone.connections.entries.first?.answers[2], "Written on the Mac.")
        XCTAssertTrue(phone.cardDefaults.stringArray(forKey: HomeSectionPinStore.pinnedIDsDefaultsKey)?.contains("ontology") == true)
        XCTAssertEqual(phone.cardDefaults.stringArray(forKey: PostCardOrderStore.defaultsKey)?.first, "legacy-a")
        XCTAssertEqual(server.entries("social-posts")["post:\(first.id.uuidString.lowercased())"]?.deleted, true)
    }

    @MainActor
    func testADeliberateDecisionOutranksAnAutomaticApproval() async throws {
        let server = InMemorySyncServer()
        let phone = try Device(name: "phone")
        let mac = try Device(name: "mac")
        defer { phone.tearDown(); mac.tearDown() }

        let encoder = JSONEncoder()
        let phoneDecisions: [String: PersonalAuthorityDecision] = ["a": .evidenceOnly, "b": .mine]
        phone.authorityDefaults.set(try encoder.encode(phoneDecisions), forKey: PersonalAuthorityReviewStore.reviewDefaultsKey)
        let macAutomatic: [String: PersonalAuthorityDecision] = ["a": .mine, "c": .mine]
        mac.authorityDefaults.set(try encoder.encode(macAutomatic), forKey: PersonalAuthorityReviewStore.reviewDefaultsKey)

        phone.connect(to: server)
        await phone.sync.start()
        mac.connect(to: server)
        await mac.sync.start()
        await phone.sync.syncNow()

        let expected: [String: PersonalAuthorityDecision] = ["a": .evidenceOnly, "b": .mine, "c": .mine]
        XCTAssertEqual(PersonalAuthorityReviewStore.savedDecisions(defaults: mac.authorityDefaults), expected)
        XCTAssertEqual(PersonalAuthorityReviewStore.savedDecisions(defaults: phone.authorityDefaults), expected)
    }

    @MainActor
    func testUnavailableGatewayKeepsChangesPendingAndLocalRecordsIntact() async throws {
        let phone = try Device(name: "phone")
        defer { phone.tearDown() }
        var post = SocialPost()
        post.text = "Kept"
        phone.posts.save(post)
        phone.connect(to: UnavailableServer())
        await phone.sync.start()
        XCTAssertEqual(phone.sync.status, .unavailable)
        XCTAssertEqual(phone.posts.posts.map(\.text), ["Kept"])

        let server = InMemorySyncServer()
        phone.connect(to: server)
        await phone.sync.start()
        XCTAssertEqual(server.entries("social-posts").count, 1)
    }

    @MainActor
    func testASourceThatSuddenlyReadsEmptyIsNotSyncedAsDeletions() throws {
        let phone = try Device(name: "phone")
        defer { phone.tearDown() }
        for index in 0..<SavySyncDocument.emptySnapshotGuard {
            var post = SocialPost()
            post.text = "Post \(index)"
            phone.posts.save(post)
        }
        let document = SavySyncDocument(adapter: SocialPostsSyncAdapter(store: phone.posts), directory: phone.directory)
        document.recordLocalChanges(now: Date().timeIntervalSince1970, legacyDevice: true)
        phone.posts.applySynced([])
        XCTAssertFalse(document.recordLocalChanges(now: Date().timeIntervalSince1970, legacyDevice: true))
        XCTAssertTrue(document.shadow.entries.values.allSatisfy { !$0.deleted })
    }

    @MainActor
    func testTheHighestPostNumberOnlyRises() async throws {
        let server = InMemorySyncServer()
        let phone = try Device(name: "phone")
        let mac = try Device(name: "mac")
        defer { phone.tearDown(); mac.tearDown() }
        _ = phone.allocator.number(for: .socialPost, id: UUID())
        _ = phone.allocator.number(for: .socialPost, id: UUID())
        _ = phone.allocator.number(for: .socialPost, id: UUID())
        phone.connect(to: server)
        await phone.sync.start()
        mac.connect(to: server)
        await mac.sync.start()
        XCTAssertEqual(mac.allocator.lastIssuedNumber, 3)
        XCTAssertEqual(mac.allocator.number(for: .socialPost, id: UUID()), 4)
        mac.allocator.raiseLastIssued(to: 2)
        XCTAssertEqual(mac.allocator.lastIssuedNumber, 4)
    }
}
