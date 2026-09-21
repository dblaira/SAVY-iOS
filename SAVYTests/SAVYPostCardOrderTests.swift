import XCTest
@testable import SAVY

final class SAVYPostCardOrderTests: XCTestCase {
    @MainActor
    func testDefaultOrderContinuesFollowingStatusAndDateUntilAValidMove() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PostCardOrderStore(defaults: defaults)
        let original = ["entry-pinned", "legacy-pinned", "entry-active", "legacy-ready", "legacy-draft", "entry-completed", "legacy-posted"]
        let pinned: Set<String> = ["entry-pinned", "legacy-pinned"]
        XCTAssertEqual(store.orderedIDs(defaultOrder: original, pinnedIDs: pinned), original)
        store.reconcile(defaultOrder: original)

        let refreshed = ["legacy-pinned", "entry-pinned", "entry-new", "entry-active", "legacy-draft", "legacy-ready", "entry-completed", "legacy-posted"]
        XCTAssertEqual(store.orderedIDs(defaultOrder: refreshed, pinnedIDs: pinned), refreshed)
        XCTAssertNil(store.manualOrder)
        XCTAssertNil(defaults.object(forKey: PostCardOrderStore.defaultsKey))
    }

    @MainActor
    func testMovesCrossFormatsAndStatusesButStayInsideTheirPinGroup() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PostCardOrderStore(defaults: defaults)
        let original = ["entry-pinned", "legacy-pinned", "entry-active", "legacy-ready", "legacy-draft", "entry-completed", "legacy-posted"]
        let pinned: Set<String> = ["entry-pinned", "legacy-pinned"]

        XCTAssertTrue(store.move("legacy-pinned", direction: -1, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertTrue(store.move("legacy-ready", direction: -1, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertTrue(store.move("entry-completed", direction: -1, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertEqual(store.orderedIDs(defaultOrder: original, pinnedIDs: pinned), [
            "legacy-pinned", "entry-pinned", "legacy-ready", "entry-active", "entry-completed", "legacy-draft", "legacy-posted",
        ])
        XCTAssertFalse(store.move("entry-pinned", direction: 1, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertFalse(store.move("legacy-ready", direction: -1, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertFalse(store.move("legacy-pinned", direction: -1, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertFalse(store.move("legacy-posted", direction: 1, defaultOrder: original, pinnedIDs: pinned))
    }

    @MainActor
    func testInvalidMovesDoNotCreateManualOrderAndDuplicateIDsAreIgnored() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PostCardOrderStore(defaults: defaults)
        let original = ["entry-pinned", "legacy-draft", "entry-pinned", "legacy-draft"]
        let pinned: Set<String> = ["entry-pinned"]
        XCTAssertEqual(store.orderedIDs(defaultOrder: original, pinnedIDs: pinned), ["entry-pinned", "legacy-draft"])
        XCTAssertFalse(store.move("entry-pinned", direction: 1, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertFalse(store.move("legacy-draft", direction: 2, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertFalse(store.move("missing", direction: -1, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertNil(store.manualOrder)
        XCTAssertNil(defaults.object(forKey: PostCardOrderStore.defaultsKey))
    }

    @MainActor
    func testRestoredOrderRetainsNewCardsAndPositionsOfTemporarilyAbsentCards() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = ["entry-a", "legacy-b", "entry-c"]
        let store = PostCardOrderStore(defaults: defaults)
        XCTAssertTrue(store.move("legacy-b", direction: -1, defaultOrder: original, pinnedIDs: []))

        let reopened = PostCardOrderStore(defaults: defaults)
        let refreshed = ["entry-new", "entry-c", "entry-a", "legacy-b", "legacy-new"]
        XCTAssertEqual(reopened.orderedIDs(defaultOrder: refreshed, pinnedIDs: []), ["legacy-b", "entry-a", "entry-c", "entry-new", "legacy-new"])
        reopened.reconcile(defaultOrder: refreshed)
        let afterDeletionAndEdit = ["legacy-new", "entry-new", "legacy-b", "entry-c"]
        reopened.reconcile(defaultOrder: afterDeletionAndEdit)
        let restoredAgain = PostCardOrderStore(defaults: defaults)
        XCTAssertEqual(restoredAgain.orderedIDs(defaultOrder: afterDeletionAndEdit, pinnedIDs: []), ["legacy-b", "entry-c", "entry-new", "legacy-new"])
        XCTAssertEqual(defaults.stringArray(forKey: PostCardOrderStore.defaultsKey), ["legacy-b", "entry-a", "entry-c", "entry-new", "legacy-new"])
        XCTAssertEqual(restoredAgain.orderedIDs(defaultOrder: refreshed, pinnedIDs: []), ["legacy-b", "entry-a", "entry-c", "entry-new", "legacy-new"])

        // Even a move while one source is missing must retain its reserved positions.
        XCTAssertTrue(restoredAgain.move("entry-c", direction: -1, defaultOrder: afterDeletionAndEdit, pinnedIDs: []))
        XCTAssertEqual(restoredAgain.orderedIDs(defaultOrder: afterDeletionAndEdit, pinnedIDs: []), ["entry-c", "legacy-b", "entry-new", "legacy-new"])
        XCTAssertEqual(restoredAgain.orderedIDs(defaultOrder: refreshed, pinnedIDs: []), ["entry-c", "entry-a", "legacy-b", "entry-new", "legacy-new"])
    }

    @MainActor
    func testPinChangesPartitionTheSavedOrderWithoutMovingAcrossGroups() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PostCardOrderStore(defaults: defaults)
        let original = ["entry-a", "legacy-b", "entry-c", "legacy-d"]
        XCTAssertTrue(store.move("legacy-b", direction: -1, defaultOrder: original, pinnedIDs: []))
        let pinned: Set<String> = ["entry-a", "legacy-d"]
        XCTAssertEqual(store.orderedIDs(defaultOrder: original, pinnedIDs: pinned), ["entry-a", "legacy-d", "legacy-b", "entry-c"])
        XCTAssertFalse(store.move("legacy-b", direction: -1, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertTrue(store.move("legacy-d", direction: -1, defaultOrder: original, pinnedIDs: pinned))
        XCTAssertEqual(store.orderedIDs(defaultOrder: original, pinnedIDs: pinned), ["legacy-d", "entry-a", "legacy-b", "entry-c"])
        XCTAssertEqual(store.orderedIDs(defaultOrder: original, pinnedIDs: ["entry-a"]), ["entry-a", "legacy-d", "legacy-b", "entry-c"])
    }

    @MainActor
    func testSourceQualifiedIDsKeepIdenticalUUIDsDistinct() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PostCardOrderStore(defaults: defaults)
        let id = UUID().uuidString
        let original = ["entry-\(id)", "legacy-\(id)"]
        XCTAssertTrue(store.move(original[1], direction: -1, defaultOrder: original, pinnedIDs: []))
        XCTAssertEqual(store.orderedIDs(defaultOrder: original, pinnedIDs: []), Array(original.reversed()))
    }

    @MainActor
    func testRearrangementOnlyWritesDisplayIDsAndLeavesSavedContentNumbersAndCaptureUntouched() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("post-card-order-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var entry = Reminder()
        entry.kind = .post
        entry.postNumber = 17
        entry.postAnswers = ["What happened?\n\nMy full answer.  "]
        entry.postAnswersContainQuestions = true
        entry.needsSync = false
        var legacy = SocialPost()
        legacy.text = "My original legacy post.  "
        legacy.postNumber = 42
        legacy.status = .posted
        let remindersURL = directory.appendingPathComponent("reminders.json")
        let postsURL = directory.appendingPathComponent("posts.json")
        try JSONEncoder.recall.encode([entry]).write(to: remindersURL)
        try JSONEncoder.recall.encode([legacy]).write(to: postsURL)
        let remindersBefore = try Data(contentsOf: remindersURL)
        let postsBefore = try Data(contentsOf: postsURL)
        let repository = RecordingRepository()
        let reminders = ReminderStore(
            repo: repository,
            cacheURL: remindersURL,
            technicalCaptureStore: try TechnicalCaptureStore(fileURL: directory.appendingPathComponent("captures.json")),
            candidateOutbox: try CowboyCandidateOutbox(fileURL: directory.appendingPathComponent("outbox.json")),
            candidateClient: OfflineCandidateClient()
        )
        let posts = try SocialPostStore(fileURL: postsURL)
        let loadedReminders = reminders.reminders
        let loadedPosts = posts.posts
        let order = PostCardOrderStore(defaults: defaults)
        let ids = ["entry-\(entry.id.uuidString)", "legacy-\(legacy.id.uuidString)"]

        XCTAssertTrue(order.move(ids[1], direction: -1, defaultOrder: ids, pinnedIDs: []))
        XCTAssertEqual(order.orderedIDs(defaultOrder: ids, pinnedIDs: []), Array(ids.reversed()))
        XCTAssertEqual(reminders.reminders, loadedReminders)
        XCTAssertEqual(posts.posts, loadedPosts)
        XCTAssertEqual(try Data(contentsOf: remindersURL), remindersBefore)
        XCTAssertEqual(try Data(contentsOf: postsURL), postsBefore)
        XCTAssertTrue(reminders.technicalCaptures.isEmpty)
        XCTAssertTrue(reminders.candidateOutboxItems.isEmpty)
        XCTAssertEqual(reminders.pendingSyncCount, 0)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?.keys.sorted(), [PostCardOrderStore.defaultsKey])
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "SAVYPostCardOrderTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    private actor RecordingRepository: ReminderRepository {
        func ensureReady() async -> Bool { true }
        func fetchAll() async throws -> [Reminder] { [] }
        func upsert(_ reminder: Reminder) async throws { XCTFail("Reordering must not sync content") }
        func delete(id: UUID) async throws { XCTFail("Reordering must not delete content") }
    }

    private struct OfflineCandidateClient: CowboyCandidateSubmitting {
        struct Offline: Error {}
        func submit(_ payload: CowboyCandidateIntakePayload) async throws -> CowboyCandidateReceipt {
            XCTFail("Reordering must not capture a candidate")
            throw Offline()
        }
    }
}
