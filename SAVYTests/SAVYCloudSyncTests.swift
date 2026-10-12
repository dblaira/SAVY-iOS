import Combine
import XCTest
@testable import SAVY

final class SAVYCloudSyncTests: XCTestCase {
    @MainActor
    func testCanonicalTieAndDeletionAreIndependentOfReceiveOrder() throws {
        let a = SyncEntry(value: .object(["writing": .string("a exact original")]), modifiedAt: 100, deleted: false)
        let z = SyncEntry(value: .object(["writing": .string("z exact original")]), modifiedAt: 100, deleted: false)
        let deleted = SyncEntry(value: nil, modifiedAt: 100, deleted: true)
        XCTAssertEqual(try SavyCloudSyncState.winner(a, z), z)
        XCTAssertEqual(try SavyCloudSyncState.winner(z, a), z)
        XCTAssertEqual(try SavyCloudSyncState.winner(z, deleted), deleted)
        XCTAssertEqual(try SavyCloudSyncState.winner(deleted, z), deleted)
        var newer = a
        newer.modifiedAt = 101
        XCTAssertEqual(try SavyCloudSyncState.winner(deleted, newer), newer)
    }

    @MainActor
    func testPendingExactVersionAndSystemFieldsSurviveRestart() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("stories.json")
        var original = story(body: "Original", updatedAt: 100)
        try JSONEncoder.recall.encode([original]).write(to: fileURL)
        let store = try StoryStore(fileURL: fileURL)
        let adapter = StoriesSyncAdapter(store: store)
        let state = try SavyCloudSyncState(fileURL: directory.appendingPathComponent("state.json"))
        try state.accountChanged(to: "owner")
        let first = try XCTUnwrap(state.observeLocal(adapter: adapter, legacyDevice: true, now: 999).first)
        XCTAssertEqual(first.entry.modifiedAt, 100)
        original.body = "New local writing"
        store.save(original)
        let newer = try XCTUnwrap(state.observeLocal(adapter: adapter, legacyDevice: true, now: 50).first)
        XCTAssertGreaterThan(newer.entry.modifiedAt, first.entry.modifiedAt)
        try state.acknowledgeSaved([first], generation: state.generation)
        XCTAssertEqual(state.pendingRecords.map(\.entry), [newer.entry])
        let restarted = try SavyCloudSyncState(fileURL: state.fileURL)
        XCTAssertEqual(restarted.pendingRecords.map(\.entry), [newer.entry])
        XCTAssertFalse(restarted.canTransport(generation: restarted.generation))
        try restarted.accountChanged(to: "owner")
        var receipt = newer
        receipt.systemFields = Data("saved-change-tag".utf8)
        try restarted.acknowledgeSaved([receipt], generation: restarted.generation)
        XCTAssertTrue(restarted.pendingRecords.isEmpty)
        XCTAssertEqual(restarted.systemFields(for: receipt.id), receipt.systemFields)
    }

    @MainActor
    func testIncomingReplaySurvivesCheckpointAfterFailedActualStoreWrite() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("stories.json")
        let original = story(body: "Exact original.  \n", updatedAt: 100)
        let originalBytes = try JSONEncoder.recall.encode([original])
        try originalBytes.write(to: fileURL)
        let store = try StoryStore(fileURL: fileURL)
        let adapter = StoriesSyncAdapter(store: store)
        let state = try SavyCloudSyncState(fileURL: directory.appendingPathComponent("state.json"))
        try state.accountChanged(to: "owner")
        let first = try XCTUnwrap(state.observeLocal(adapter: adapter, legacyDevice: true, now: 500).first)
        var edited = original
        edited.body = "Exact incoming writing.  \n"
        edited.updatedAt = Date(timeIntervalSince1970: 200)
        let incoming = SavyCloudRecord(id: first.id, entry: SyncEntry(value: try SyncJSON.encode(edited), modifiedAt: 200, deleted: false),
                                       systemFields: Data("fetched-system-fields".utf8))
        try state.retainIncoming([incoming], generation: state.generation)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
        XCTAssertTrue(try state.replayIncoming(using: ["stories": adapter], generation: state.generation).isEmpty)
        XCTAssertEqual(store.stories, [original])
        XCTAssertEqual(state.entry(for: first.id), first.entry)
        XCTAssertEqual(state.pendingRecords.map(\.entry), [first.entry])
        let checkpoint = Data("advanced-fetch-checkpoint".utf8)
        try state.persistEngineState(checkpoint, generation: state.generation)
        let restarted = try SavyCloudSyncState(fileURL: state.fileURL)
        XCTAssertEqual(restarted.engineState, checkpoint)
        XCTAssertEqual(restarted.incomingRecords.map(\.entry), [incoming.entry])
        XCTAssertEqual(restarted.systemFields(for: first.id), incoming.systemFields)
        XCTAssertEqual(restarted.conflicts.first?.displaced, first.entry)
        XCTAssertEqual(restarted.conflicts.first?.retained, incoming.entry)
        try FileManager.default.removeItem(at: fileURL)
        try originalBytes.write(to: fileURL)
        let reopenedStore = try StoryStore(fileURL: fileURL)
        XCTAssertThrowsError(try restarted.replayIncoming(using: ["stories": StoriesSyncAdapter(store: reopenedStore)], generation: restarted.generation))
        XCTAssertEqual(reopenedStore.stories, [original])
        XCTAssertEqual(restarted.incomingRecords.map(\.entry), [incoming.entry])
        try restarted.accountChanged(to: "owner")
        XCTAssertEqual(try restarted.replayIncoming(using: ["stories": StoriesSyncAdapter(store: reopenedStore)], generation: restarted.generation), ["stories"])
        XCTAssertTrue(restarted.incomingRecords.isEmpty)
        XCTAssertEqual(reopenedStore.stories.first?.body, edited.body)
        XCTAssertEqual(try JSONDecoder.recall.decode([Story].self, from: Data(contentsOf: fileURL)), reopenedStore.stories)
    }

    @MainActor
    func testPostAndStoryDoNotPublishFailedApply() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let postFile = directory.appendingPathComponent("posts.json")
        let storyFile = directory.appendingPathComponent("stories.json")
        var post = SocialPost(); post.text = "Exact saved Post"
        let originalStory = story(body: "Exact saved Story", updatedAt: 100)
        try JSONEncoder.recall.encode([post]).write(to: postFile)
        try JSONEncoder.recall.encode([originalStory]).write(to: storyFile)
        let posts = try SocialPostStore(fileURL: postFile), stories = try StoryStore(fileURL: storyFile)
        let confirmedPosts = posts.posts, confirmedStories = stories.stories
        for file in [postFile, storyFile] {
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        }
        post.text = "Unwriteable replacement"
        var incomingStory = originalStory; incomingStory.body = "Unwriteable replacement"
        XCTAssertFalse(posts.applySynced([post]))
        XCTAssertFalse(stories.applySynced([incomingStory]))
        XCTAssertEqual(posts.posts, confirmedPosts)
        XCTAssertEqual(stories.stories, confirmedStories)
        XCTAssertTrue(posts.lastWriteFailed)
        XCTAssertTrue(stories.lastWriteFailed)
    }

    @MainActor
    func testFailedOwnerBindRetriesSameIdentityAndOtherAccountCannotTransport() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("parent")
        try Data("blocking directory creation".utf8).write(to: blocked)
        let state = try SavyCloudSyncState(fileURL: blocked.appendingPathComponent("state.json"))
        XCTAssertThrowsError(try state.accountChanged(to: "original"))
        XCTAssertNil(state.originalOwner)
        XCTAssertFalse(state.canTransport(generation: state.generation))
        try FileManager.default.removeItem(at: blocked)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
        XCTAssertEqual(try state.accountChanged(to: "original"), .authorized)
        let originalGeneration = state.generation
        try state.persistEngineState(Data("original-checkpoint".utf8), generation: originalGeneration)
        XCTAssertEqual(try state.accountChanged(to: nil), .unavailable)
        XCTAssertFalse(state.canTransport(generation: originalGeneration))
        XCTAssertEqual(try state.accountChanged(to: "other"), .differentAccount)
        XCTAssertEqual(state.originalOwner, "original")
        XCTAssertThrowsError(try state.retainIncoming([], generation: state.generation))
        XCTAssertThrowsError(try state.acknowledgeSaved([], generation: originalGeneration))
        XCTAssertEqual(state.engineState, Data("original-checkpoint".utf8))
        XCTAssertEqual(try state.accountChanged(to: "original"), .authorized)
        XCTAssertTrue(state.canTransport(generation: state.generation))
        XCTAssertFalse(state.canTransport(generation: originalGeneration))
    }

    @MainActor
    func testMaterializedTargetSurvivesLaterFailedReplacementAndRestart() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("stories.json")
        let a = story(body: "A confirmed original", updatedAt: 100)
        var b = a; b.body = "B materialized version"; b.updatedAt = Date(timeIntervalSince1970: 200)
        var c = a; c.body = "C received replacement"; c.updatedAt = Date(timeIntervalSince1970: 300)
        try JSONEncoder.recall.encode([a]).write(to: fileURL)
        let store = try StoryStore(fileURL: fileURL)
        let adapter = StoriesSyncAdapter(store: store)
        let state = try SavyCloudSyncState(fileURL: directory.appendingPathComponent("state.json"))
        try state.accountChanged(to: "owner")
        let first = try XCTUnwrap(state.observeLocal(adapter: adapter, legacyDevice: true, now: 100).first)
        try state.acknowledgeSaved([first], generation: state.generation)
        let recordB = SavyCloudRecord(id: first.id, entry: .init(value: try SyncJSON.encode(b), modifiedAt: 200, deleted: false))
        let recordC = SavyCloudRecord(id: first.id, entry: .init(value: try SyncJSON.encode(c), modifiedAt: 300, deleted: false))
        try state.retainIncoming([recordB], generation: state.generation)
        var preparedBytes = Data()
        let publication = store.objectWillChange.sink {
            preparedBytes = (try? Data(contentsOf: state.fileURL)) ?? Data()
            try? FileManager.default.removeItem(at: state.fileURL)
            try? FileManager.default.createDirectory(at: state.fileURL, withIntermediateDirectories: false)
        }
        XCTAssertThrowsError(try state.replayIncoming(using: ["stories": adapter], generation: state.generation))
        publication.cancel()
        XCTAssertEqual(store.stories.first?.body, b.body)
        XCTAssertEqual(state.entry(for: first.id), first.entry)
        XCTAssertFalse(preparedBytes.isEmpty)
        try FileManager.default.removeItem(at: state.fileURL)
        try preparedBytes.write(to: state.fileURL)
        try state.retainIncoming([recordC], generation: state.generation)
        let savedB = try Data(contentsOf: fileURL)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
        XCTAssertTrue(try state.replayIncoming(using: ["stories": adapter], generation: state.generation).isEmpty)
        XCTAssertEqual(store.stories.first?.body, b.body)
        _ = try state.observeLocal(adapter: adapter, legacyDevice: true, now: 9_000_000_000)
        XCTAssertTrue(state.pendingRecords.isEmpty)
        XCTAssertEqual(state.incomingRecords.map(\.entry), [recordC.entry])
        try FileManager.default.removeItem(at: fileURL)
        try savedB.write(to: fileURL)
        let reopenedStore = try StoryStore(fileURL: fileURL)
        let reopenedAdapter = StoriesSyncAdapter(store: reopenedStore)
        let restarted = try SavyCloudSyncState(fileURL: state.fileURL)
        try restarted.accountChanged(to: "owner")
        _ = try restarted.observeLocal(adapter: reopenedAdapter, legacyDevice: true, now: 10_000_000_000)
        XCTAssertTrue(restarted.pendingRecords.isEmpty)
        XCTAssertEqual(restarted.incomingRecords.map(\.entry), [recordC.entry])
        XCTAssertEqual(reopenedStore.stories.first?.body, b.body)
        _ = try restarted.replayIncoming(using: ["stories": reopenedAdapter], generation: restarted.generation)
        XCTAssertTrue(restarted.incomingRecords.isEmpty)
        XCTAssertEqual(restarted.entry(for: first.id), recordC.entry)
        XCTAssertEqual(reopenedStore.stories.first?.body, c.body)
    }

    @MainActor
    func testNewerInboxWinnerStaysPendingWhenLatestFetchedReceiptIsOlder() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("stories.json")
        let a = story(body: "A original writing.  \n", updatedAt: 100)
        var b = a; b.body = "B newer writing.  \n"; b.updatedAt = Date(timeIntervalSince1970: 200)
        let originalBytes = try JSONEncoder.recall.encode([a])
        try originalBytes.write(to: fileURL)
        let store = try StoryStore(fileURL: fileURL)
        let adapter = StoriesSyncAdapter(store: store)
        let state = try SavyCloudSyncState(fileURL: directory.appendingPathComponent("state.json"))
        try state.accountChanged(to: "owner")
        let recordA = try XCTUnwrap(state.observeLocal(adapter: adapter, legacyDevice: true, now: 100).first)
        let recordB = SavyCloudRecord(id: recordA.id,
            entry: .init(value: try SyncJSON.encode(b), modifiedAt: 200, deleted: false),
            systemFields: Data("B-fetched-fields".utf8))
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
        try state.retainIncoming([recordB], generation: state.generation)
        XCTAssertTrue(try state.replayIncoming(using: ["stories": adapter], generation: state.generation).isEmpty)
        XCTAssertEqual(store.stories, [a])
        XCTAssertEqual(state.pendingRecords.map(\.entry), [recordA.entry])
        var fetchedA = recordA
        fetchedA.systemFields = Data("A-latest-fetched-fields".utf8)
        try state.retainIncoming([fetchedA], generation: state.generation)
        XCTAssertEqual(state.incomingRecords.map(\.entry), [recordB.entry])
        XCTAssertEqual(state.systemFields(for: recordA.id), fetchedA.systemFields)
        let retainedArchive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: state.fileURL)) as? [String: Any])
        let retainedDocuments = try XCTUnwrap(retainedArchive["documents"] as? [String: [String: Any]])
        let receipts = try XCTUnwrap(retainedDocuments["stories"]?["incomingReceipts"] as? [String: Any])
        XCTAssertEqual(receipts.count, 1)
        XCTAssertNotNil(receipts[recordA.id.key])
        try FileManager.default.removeItem(at: fileURL)
        try originalBytes.write(to: fileURL)
        let reopenedStore = try StoryStore(fileURL: fileURL)
        let restarted = try SavyCloudSyncState(fileURL: state.fileURL)
        try restarted.accountChanged(to: "owner")
        XCTAssertEqual(try restarted.replayIncoming(using: ["stories": StoriesSyncAdapter(store: reopenedStore)], generation: restarted.generation), ["stories"])
        XCTAssertEqual(reopenedStore.stories, [b])
        XCTAssertEqual(restarted.entry(for: recordB.id), recordB.entry)
        XCTAssertTrue(restarted.incomingRecords.isEmpty)
        XCTAssertEqual(restarted.pendingRecords.map(\.entry), [recordB.entry])
        XCTAssertEqual(restarted.pendingRecords.first?.systemFields, fetchedA.systemFields)
        let confirmedArchive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: restarted.fileURL)) as? [String: Any])
        let confirmedDocuments = try XCTUnwrap(confirmedArchive["documents"] as? [String: [String: Any]])
        XCTAssertNil(confirmedDocuments["stories"]?["incomingReceipts"])
        XCTAssertTrue(restarted.conflicts.contains { $0.id == recordA.id && $0.displaced == recordA.entry && $0.retained == recordB.entry })
        let restartedAgain = try SavyCloudSyncState(fileURL: state.fileURL)
        try restartedAgain.accountChanged(to: "owner")
        XCTAssertEqual(restartedAgain.pendingRecords.map(\.entry), [recordB.entry])
        try restartedAgain.acknowledgeSaved([fetchedA], generation: restartedAgain.generation)
        XCTAssertEqual(restartedAgain.pendingRecords.map(\.entry), [recordB.entry])
        var savedB = recordB
        savedB.systemFields = Data("B-actual-save-fields".utf8)
        try restartedAgain.acknowledgeSaved([savedB], generation: restartedAgain.generation)
        XCTAssertTrue(restartedAgain.pendingRecords.isEmpty)
        XCTAssertEqual(restartedAgain.systemFields(for: savedB.id), savedB.systemFields)
    }

    @MainActor
    func testLegacyInboxWithoutFetchedReceiptRequeuesItsAppliedWinner() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("stories.json")
        let a = story(body: "Legacy original A", updatedAt: 100)
        var b = a; b.body = "Legacy incoming B"; b.updatedAt = Date(timeIntervalSince1970: 200)
        try JSONEncoder.recall.encode([a]).write(to: fileURL)
        let store = try StoryStore(fileURL: fileURL)
        let adapter = StoriesSyncAdapter(store: store)
        let state = try SavyCloudSyncState(fileURL: directory.appendingPathComponent("state.json"))
        try state.accountChanged(to: "owner")
        let recordA = try XCTUnwrap(state.observeLocal(adapter: adapter, legacyDevice: true, now: 100).first)
        let recordB = SavyCloudRecord(id: recordA.id, entry: .init(value: try SyncJSON.encode(b), modifiedAt: 200, deleted: false))
        try state.retainIncoming([recordB], generation: state.generation)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: state.fileURL)) as? [String: Any])
        var documents = try XCTUnwrap(legacy["documents"] as? [String: [String: Any]])
        documents["stories"]?.removeValue(forKey: "incomingReceipts")
        legacy["documents"] = documents
        legacy.removeValue(forKey: "foregroundChangeToken")
        try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys]).write(to: state.fileURL, options: .atomic)
        let restarted = try SavyCloudSyncState(fileURL: state.fileURL)
        XCTAssertNil(restarted.foregroundChangeToken)
        XCTAssertEqual(restarted.incomingRecords.map(\.entry), [recordB.entry])
        try restarted.accountChanged(to: "owner")
        _ = try restarted.replayIncoming(using: ["stories": adapter], generation: restarted.generation)
        XCTAssertEqual(store.stories, [b])
        XCTAssertTrue(restarted.incomingRecords.isEmpty)
        XCTAssertEqual(restarted.pendingRecords.map(\.entry), [recordB.entry])
        let afterApply = try SavyCloudSyncState(fileURL: state.fileURL)
        try afterApply.accountChanged(to: "owner")
        XCTAssertEqual(afterApply.pendingRecords.map(\.entry), [recordB.entry])
        try afterApply.acknowledgeSaved([recordB], generation: afterApply.generation)
        XCTAssertTrue(afterApply.pendingRecords.isEmpty)
    }

    @MainActor
    func testForegroundCursorPersistsWithRetainedIncomingAndRejectsInvalidCallbacks() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("stories.json")
        let a = story(body: "Foreground original A", updatedAt: 100)
        var b = a; b.body = "Foreground retained B"; b.updatedAt = Date(timeIntervalSince1970: 200)
        let originalBytes = try JSONEncoder.recall.encode([a])
        try originalBytes.write(to: fileURL)
        let store = try StoryStore(fileURL: fileURL)
        let adapter = StoriesSyncAdapter(store: store)
        let state = try SavyCloudSyncState(fileURL: directory.appendingPathComponent("state.json"))
        try state.accountChanged(to: "owner")
        let recordA = try XCTUnwrap(state.observeLocal(adapter: adapter, legacyDevice: true, now: 100).first)
        let recordB = SavyCloudRecord(id: recordA.id, entry: .init(value: try SyncJSON.encode(b), modifiedAt: 200, deleted: false))
        let engineCheckpoint = Data("independent-engine-checkpoint".utf8)
        let cursor = Data("opaque-foreground-cursor".utf8)
        let advancedCursor = Data("next-opaque-foreground-cursor".utf8)
        try state.persistEngineState(engineCheckpoint, generation: state.generation)
        try state.retainIncoming([recordB], generation: state.generation)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
        XCTAssertTrue(try state.replayIncoming(using: ["stories": adapter], generation: state.generation).isEmpty)
        try state.persistForegroundChangeToken(cursor, generation: state.generation)
        let durableBytes = try Data(contentsOf: state.fileURL)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: durableBytes) as? [String: Any])
        XCTAssertEqual(encoded["formatVersion"] as? Int, 1)
        let restarted = try SavyCloudSyncState(fileURL: state.fileURL)
        XCTAssertEqual(restarted.foregroundChangeToken, cursor)
        XCTAssertEqual(restarted.engineState, engineCheckpoint)
        XCTAssertEqual(restarted.incomingRecords.map(\.entry), [recordB.entry])
        XCTAssertThrowsError(try restarted.persistForegroundChangeToken(advancedCursor, generation: restarted.generation)) {
            XCTAssertEqual($0 as? SavyCloudSyncStateError, .staleGeneration)
        }
        XCTAssertEqual(try Data(contentsOf: restarted.fileURL), durableBytes)
        try restarted.accountChanged(to: "owner")
        let authorizedGeneration = restarted.generation
        let savedJournal = try Data(contentsOf: restarted.fileURL)
        try FileManager.default.removeItem(at: restarted.fileURL)
        try FileManager.default.createDirectory(at: restarted.fileURL, withIntermediateDirectories: false)
        XCTAssertThrowsError(try restarted.persistForegroundChangeToken(advancedCursor, generation: authorizedGeneration))
        XCTAssertEqual(restarted.foregroundChangeToken, cursor)
        XCTAssertEqual(restarted.engineState, engineCheckpoint)
        XCTAssertEqual(restarted.incomingRecords.map(\.entry), [recordB.entry])
        try FileManager.default.removeItem(at: restarted.fileURL)
        try savedJournal.write(to: restarted.fileURL)
        let afterFailure = try SavyCloudSyncState(fileURL: restarted.fileURL)
        XCTAssertEqual(afterFailure.foregroundChangeToken, cursor)
        XCTAssertEqual(afterFailure.incomingRecords.map(\.entry), [recordB.entry])
        try restarted.accountChanged(to: nil)
        XCTAssertThrowsError(try restarted.persistForegroundChangeToken(advancedCursor, generation: restarted.generation)) {
            XCTAssertEqual($0 as? SavyCloudSyncStateError, .staleGeneration)
        }
        try restarted.accountChanged(to: "other")
        XCTAssertThrowsError(try restarted.persistForegroundChangeToken(advancedCursor, generation: restarted.generation)) {
            XCTAssertEqual($0 as? SavyCloudSyncStateError, .staleGeneration)
        }
        try restarted.accountChanged(to: "owner")
        XCTAssertThrowsError(try restarted.persistForegroundChangeToken(advancedCursor, generation: authorizedGeneration)) {
            XCTAssertEqual($0 as? SavyCloudSyncStateError, .staleGeneration)
        }
        XCTAssertEqual(restarted.foregroundChangeToken, cursor)
        try restarted.persistForegroundChangeToken(advancedCursor, generation: restarted.generation)
        XCTAssertEqual(restarted.engineState, engineCheckpoint)
        XCTAssertEqual(restarted.incomingRecords.map(\.entry), [recordB.entry])
        try FileManager.default.removeItem(at: fileURL)
        try originalBytes.write(to: fileURL)
        let reopenedStore = try StoryStore(fileURL: fileURL)
        _ = try restarted.replayIncoming(using: ["stories": StoriesSyncAdapter(store: reopenedStore)], generation: restarted.generation)
        XCTAssertEqual(reopenedStore.stories, [b])
        XCTAssertTrue(restarted.incomingRecords.isEmpty)
        XCTAssertEqual(restarted.foregroundChangeToken, advancedCursor)
        try restarted.persistForegroundChangeToken(nil, generation: restarted.generation)
        let afterReset = try SavyCloudSyncState(fileURL: restarted.fileURL)
        XCTAssertNil(afterReset.foregroundChangeToken)
        XCTAssertEqual(afterReset.engineState, engineCheckpoint)
    }

    @MainActor
    func testUnreadableJournalKeepsOriginalBytes() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("state.json")
        let bytes = Data("Keep the original unreadable state".utf8)
        try bytes.write(to: fileURL)
        XCTAssertThrowsError(try SavyCloudSyncState(fileURL: fileURL))
        XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
    }

    private func story(body: String, updatedAt: Double) -> Story {
        var story = Story()
        story.body = body
        story.createdAt = Date(timeIntervalSince1970: 10)
        story.updatedAt = Date(timeIntervalSince1970: updatedAt)
        return story
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("savy-cloud-xctests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
