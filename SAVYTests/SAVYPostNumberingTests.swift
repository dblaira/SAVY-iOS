import XCTest
@testable import SAVY

final class SAVYPostNumberingTests: XCTestCase {
    @MainActor
    func testBothFormatsReceiveChronologicalNumbersWithoutEditingOrCapturingContent() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var oldest = SocialPost()
        oldest.text = "My original legacy post.  "
        oldest.createdAt = Date(timeIntervalSince1970: 100)
        oldest.updatedAt = Date(timeIntervalSince1970: 500)
        let second = post(createdAt: 200)
        let third = post(createdAt: 300)
        try JSONEncoder.recall.encode([third, second]).write(to: directory.appendingPathComponent("reminders.json"))
        try JSONEncoder.recall.encode([oldest]).write(to: directory.appendingPathComponent("posts.json"))
        let reminders = try reminderStore(directory: directory)
        let posts = try SocialPostStore(fileURL: directory.appendingPathComponent("posts.json"))
        let allocator = try PostNumberAllocator(fileURL: directory.appendingPathComponent("numbers.json"))
        allocator.seed(reminders: reminders.reminders, socialPosts: posts.posts)
        reminders.configurePostNumbering(allocator)
        posts.configurePostNumbering(allocator)

        var expectedLegacy = oldest
        expectedLegacy.postNumber = 1
        XCTAssertEqual(posts.posts, [expectedLegacy])
        for (original, number) in [(second, 2), (third, 3)] {
            var expected = original
            expected.postNumber = number
            XCTAssertEqual(reminders.reminders.first { $0.id == original.id }, expected)
        }
        XCTAssertTrue(reminders.technicalCaptures.isEmpty)
        XCTAssertTrue(reminders.candidateOutboxItems.isEmpty)
        let cached = try JSONDecoder.recall.decode([Reminder].self, from: Data(contentsOf: directory.appendingPathComponent("reminders.json")))
        XCTAssertEqual(cached, reminders.reminders)
    }

    @MainActor
    func testInitialNumberingFetchesNewerRemoteContentBeforeUploadingMetadata() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = post(createdAt: 100)
        try JSONEncoder.recall.encode([local]).write(to: directory.appendingPathComponent("reminders.json"))
        var remote = local
        remote.title = "A newer title saved on another device"
        remote.notes = "Newer remote notes must survive the numbering upgrade."
        remote.postAnswers?[0] = "What happened?\n\nThe newer remote answer."
        remote.status = .completed
        remote.completedAt = Date(timeIntervalSince1970: 400)
        remote.updatedAt = Date(timeIntervalSince1970: 500)
        let repository = RecordingRepository(records: [remote])
        let store = try reminderStore(directory: directory, repository: repository)
        let allocator = try PostNumberAllocator(fileURL: directory.appendingPathComponent("numbers.json"))
        store.configurePostNumbering(allocator)
        XCTAssertEqual(store.reminders.first?.postNumber, 1)
        XCTAssertEqual(store.reminders.first?.needsSync, false)
        XCTAssertEqual(store.reminders.first?.updatedAt, local.updatedAt)

        await store.bootstrap()

        var expected = remote
        expected.postNumber = 1
        XCTAssertEqual(store.reminders, [expected])
        let events = await repository.events
        XCTAssertEqual(events, ["fetch", "upsert"], "The clean cache must not be uploaded before reading current cloud content")
        let uploads = await repository.upserts
        var expectedUpload = expected
        expectedUpload.needsSync = true
        XCTAssertEqual(uploads, [expectedUpload])
        XCTAssertTrue(store.technicalCaptures.isEmpty)
        XCTAssertTrue(store.candidateOutboxItems.isEmpty)
    }

    @MainActor
    func testNumbersSurvivePinsStaleEditorSavesDeletionAndRelaunch() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledgerURL = directory.appendingPathComponent("numbers.json")
        let postsURL = directory.appendingPathComponent("posts.json")
        let allocator = try PostNumberAllocator(fileURL: ledgerURL)
        let store = try SocialPostStore(fileURL: postsURL)
        store.configurePostNumbering(allocator)
        var first = SocialPost()
        first.text = "First synthetic post."
        var second = SocialPost()
        second.text = "Second synthetic post."
        store.save(first)
        store.save(second)
        store.togglePin(first)
        first.text = "An edit from a form opened before numbering."
        store.save(first)
        XCTAssertEqual(store.posts.first { $0.id == first.id }?.postNumber, 1)
        XCTAssertEqual(store.posts.first { $0.id == second.id }?.postNumber, 2)
        store.delete(second)

        let reopenedAllocator = try PostNumberAllocator(fileURL: ledgerURL)
        let reopenedStore = try SocialPostStore(fileURL: postsURL)
        reopenedStore.configurePostNumbering(reopenedAllocator)
        var third = SocialPost()
        third.text = "Third synthetic post."
        reopenedStore.save(third)
        XCTAssertEqual(reopenedStore.posts.first { $0.id == third.id }?.postNumber, 3)
        XCTAssertEqual(reopenedAllocator.number(for: .socialPost, id: second.id), 2, "Deleted references stay reserved")
        XCTAssertEqual(reopenedStore.posts.first { $0.id == first.id }?.postNumber, 1)
    }

    @MainActor
    func testReminderSavePreservesAssignedNumberFromBeforeAnEditorOpened() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var original = post(createdAt: 100)
        try JSONEncoder.recall.encode([original]).write(to: directory.appendingPathComponent("reminders.json"))
        let store = try reminderStore(directory: directory)
        let allocator = try PostNumberAllocator(fileURL: directory.appendingPathComponent("numbers.json"))
        store.configurePostNumbering(allocator)
        original.notes = "An authored edit from an older form copy."
        original.pinned = true
        store.save(original)
        let saved = try XCTUnwrap(store.reminders.first)
        XCTAssertEqual(saved.postNumber, 1)
        XCTAssertEqual(saved.notes, original.notes)
        XCTAssertEqual(saved.createdAt, original.createdAt)
        XCTAssertTrue(saved.pinned)
        await store.bootstrap()
    }

    @MainActor
    func testRefreshPreservesMissingNumberAndReservesRemoteNumbersBeforeNewAssignments() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var local = post(createdAt: 200)
        local.postNumber = 2
        try JSONEncoder.recall.encode([local]).write(to: directory.appendingPathComponent("reminders.json"))
        var remoteCopy = local
        remoteCopy.postNumber = nil
        var numberedRemote = post(createdAt: 400)
        numberedRemote.postNumber = 42
        let unnumberedRemote = post(createdAt: 100)
        let repository = RecordingRepository(records: [unnumberedRemote, remoteCopy, numberedRemote])
        let store = try reminderStore(directory: directory, repository: repository)
        let allocator = try PostNumberAllocator(fileURL: directory.appendingPathComponent("numbers.json"))
        store.configurePostNumbering(allocator)
        await store.refresh()

        XCTAssertEqual(store.reminders.first { $0.id == local.id }?.postNumber, 2)
        XCTAssertEqual(store.reminders.first { $0.id == numberedRemote.id }?.postNumber, 42)
        XCTAssertEqual(store.reminders.first { $0.id == unnumberedRemote.id }?.postNumber, 43)
        let uploads = await repository.upserts
        XCTAssertEqual(Set(uploads.compactMap(\.postNumber)), [2, 43])
        XCTAssertTrue(store.technicalCaptures.isEmpty)
        XCTAssertTrue(store.candidateOutboxItems.isEmpty)
        let reopened = try reminderStore(directory: directory)
        XCTAssertEqual(reopened.reminders, store.reminders)
    }

    @MainActor
    func testRecordTypesHaveSeparateIdentitiesAndExistingAssignmentsNeverChange() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let allocator = try PostNumberAllocator(fileURL: directory.appendingPathComponent("numbers.json"))
        let id = UUID()
        XCTAssertEqual(allocator.number(for: .reminder, id: id, savedNumber: 8), 8)
        XCTAssertEqual(allocator.number(for: .socialPost, id: id, savedNumber: 8), 9)
        XCTAssertEqual(allocator.number(for: .reminder, id: id, savedNumber: 15), 8)
        XCTAssertEqual(allocator.number(for: .reminder, id: UUID()), 10)
    }

    func testOlderCodecsAcceptMissingNumbersAndRoundTripAssignedNumbers() throws {
        var reminder = post(createdAt: 100)
        let oldReminderData = try JSONEncoder.recall.encode(reminder)
        XCTAssertNil(try JSONDecoder.recall.decode(Reminder.self, from: oldReminderData).postNumber)
        var legacy = try JSONDecoder.recall.decode(SocialPost.self, from: Data(#"{"text":"Preserve my words."}"#.utf8))
        XCTAssertNil(legacy.postNumber)
        reminder.postNumber = 4
        legacy.postNumber = 5
        legacy.createdAt = Date(timeIntervalSince1970: 100)
        legacy.updatedAt = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(try JSONDecoder.recall.decode(Reminder.self, from: JSONEncoder.recall.encode(reminder)), reminder)
        XCTAssertEqual(try JSONDecoder.recall.decode(SocialPost.self, from: JSONEncoder.recall.encode(legacy)), legacy)
    }

    @MainActor
    func testUIFixtureCannotWriteOutsideTheIsolatedUITestDirectory() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try reminderStore(directory: directory)
        store.seedPostsForUITesting(count: 50)
        XCTAssertTrue(store.reminders.isEmpty)
        XCTAssertTrue(store.technicalCaptures.isEmpty)
        XCTAssertTrue(store.candidateOutboxItems.isEmpty)
    }

    private func post(createdAt: TimeInterval) -> Reminder {
        var entry = Reminder()
        entry.kind = .post
        entry.title = "New Post"
        entry.postThemeID = PostThemeCatalog.defaultTheme.id
        entry.postThemeName = PostThemeCatalog.defaultTheme.name
        entry.postAnswers = PostThemeCatalog.defaultTheme.prefilledAnswers
        entry.postAnswers?[0] += "My exact original answer.  "
        entry.postAnswersContainQuestions = true
        entry.createdAt = Date(timeIntervalSince1970: createdAt)
        entry.updatedAt = Date(timeIntervalSince1970: createdAt + 5)
        return entry
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("post-number-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    private func reminderStore(directory: URL, repository: any ReminderRepository = LocalReminderRepository()) throws -> ReminderStore {
        ReminderStore(
            repo: repository,
            cacheURL: directory.appendingPathComponent("reminders.json"),
            technicalCaptureStore: try TechnicalCaptureStore(fileURL: directory.appendingPathComponent("captures.json")),
            candidateOutbox: try CowboyCandidateOutbox(fileURL: directory.appendingPathComponent("outbox.json")),
            candidateClient: OfflineCandidateClient()
        )
    }

    private actor RecordingRepository: ReminderRepository {
        let records: [Reminder]
        private(set) var upserts: [Reminder] = []
        private(set) var events: [String] = []
        init(records: [Reminder]) { self.records = records }
        func ensureReady() async -> Bool { true }
        func fetchAll() async throws -> [Reminder] {
            events.append("fetch")
            return records
        }
        func upsert(_ reminder: Reminder) async throws {
            events.append("upsert")
            upserts.append(reminder)
        }
        func delete(id: UUID) async throws {}
    }

    private struct OfflineCandidateClient: CowboyCandidateSubmitting {
        struct Offline: Error {}
        func submit(_ payload: CowboyCandidateIntakePayload) async throws -> CowboyCandidateReceipt { throw Offline() }
    }
}
