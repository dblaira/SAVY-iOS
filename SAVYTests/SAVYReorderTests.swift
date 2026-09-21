import XCTest
@testable import SAVY

final class SAVYReorderTests: XCTestCase {
    @MainActor
    func testActionsMovePastHiddenKindsWithoutEditingTheirRanksOrContent() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = item("First action", kind: .action, pinned: true, rank: 10, createdAt: 100)
        let hidden = item("Hidden reminder", kind: .reminder, pinned: true, rank: 20, createdAt: 200)
        let second = item("Second action", kind: .action, pinned: true, rank: 30, createdAt: 300)
        let unpinned = item("Unpinned action", kind: .action, pinned: false, rank: 0, createdAt: 400)
        let store = try makeStore(directory, records: [first, hidden, second, unpinned])

        store.moveUpNext(second, direction: .up)

        XCTAssertEqual(store.active.map(\.id), [second.id, hidden.id, first.id, unpinned.id])
        XCTAssertEqual(store.reminders.first { $0.id == hidden.id }, hidden)
        XCTAssertEqual(store.reminders.first { $0.id == unpinned.id }, unpinned)
        try assertContentPreserved(second, saved: store.reminders.first { $0.id == second.id }, rank: 10)
        try assertContentPreserved(first, saved: store.reminders.first { $0.id == first.id }, rank: 30)
        assertNoCaptures(store)

        let reopened = try makeStore(directory)
        XCTAssertEqual(reopened.active.map(\.id), [second.id, hidden.id, first.id, unpinned.id])
        XCTAssertEqual(reopened.reminders.first { $0.id == hidden.id }, hidden)
        reopened.moveUpNext(second, direction: .down)
        XCTAssertEqual(reopened.active.map(\.id), [first.id, hidden.id, second.id, unpinned.id])
        XCTAssertEqual(reopened.reminders.first { $0.id == hidden.id }, hidden)
        assertNoCaptures(reopened)
    }

    @MainActor
    func testOlderUnrankedCardsKeepHiddenSlotsAndSaveTheNewVisibleOrder() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = item("First reminder", kind: .reminder, createdAt: 100)
        let hidden = item("Hidden event", kind: .event, createdAt: 200)
        let second = item("Second reminder", kind: .reminder, createdAt: 300)
        let store = try makeStore(directory, records: [first, hidden, second])

        store.moveUpNext(second, direction: .up)

        XCTAssertEqual(store.active.map(\.id), [second.id, hidden.id, first.id])
        XCTAssertEqual(store.active.compactMap(\.upNextOrder), [0, 1, 2])
        try assertContentPreserved(hidden, saved: store.reminders.first { $0.id == hidden.id }, rank: 1)
        let reopened = try makeStore(directory)
        XCTAssertEqual(reopened.active.map(\.id), [second.id, hidden.id, first.id])
        XCTAssertEqual(reopened.active.compactMap(\.upNextOrder), [0, 1, 2])
        assertNoCaptures(store)
    }

    @MainActor
    func testMovementStopsAtTheVisiblePinGroupBoundaries() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pinned = item("Only pinned action", kind: .action, pinned: true, rank: 0, createdAt: 100)
        let hiddenPinned = item("Hidden pinned event", kind: .event, pinned: true, rank: 1, createdAt: 200)
        let hiddenUnpinned = item("Hidden unpinned reminder", kind: .reminder, rank: 0, createdAt: 300)
        let unpinned = item("Only unpinned action", kind: .action, rank: 1, createdAt: 400)
        let original = [pinned, hiddenPinned, hiddenUnpinned, unpinned]
        let store = try makeStore(directory, records: original)

        for direction in [ReminderStore.UpNextMoveDirection.up, .down] {
            store.moveUpNext(pinned, direction: direction)
            store.moveUpNext(unpinned, direction: direction)
        }

        XCTAssertEqual(store.reminders, original)
        XCTAssertEqual(try makeStore(directory).reminders, original)
        assertNoCaptures(store)
    }

    @MainActor
    func testMovementUsesTheCurrentPinStateInsteadOfAnOlderCardCopy() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let existingPinned = item("Existing pinned action", kind: .action, pinned: true, rank: 0, createdAt: 100)
        let staleCard = item("Newly pinned action", kind: .action, rank: 0, createdAt: 200)
        let unpinned = item("Remaining unpinned action", kind: .action, rank: 1, createdAt: 300)
        let store = try makeStore(directory, records: [existingPinned, staleCard, unpinned])

        store.togglePin(staleCard)
        XCTAssertEqual(store.active.filter(\.pinned).map(\.id), [staleCard.id, existingPinned.id])
        store.moveUpNext(staleCard, direction: .down)

        XCTAssertEqual(store.active.map(\.id), [existingPinned.id, staleCard.id, unpinned.id])
        XCTAssertTrue(try XCTUnwrap(store.reminders.first { $0.id == staleCard.id }).pinned)
        assertNoCaptures(store)
    }

    @MainActor
    func testPinAndUnpinPersistWhenTheOnlyCardAlreadyHasRankZero() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = item("Saved post", kind: .post, rank: 0, createdAt: 100)
        let store = try makeStore(directory, records: [original])

        store.togglePin(original)

        let pinned = try XCTUnwrap(store.reminders.first)
        XCTAssertTrue(pinned.pinned)
        XCTAssertTrue(pinned.needsSync)
        XCTAssertGreaterThan(pinned.updatedAt, original.updatedAt)
        XCTAssertEqual(pinned.upNextOrder, 0)
        XCTAssertEqual(pinned.notes, original.notes)
        XCTAssertEqual(pinned.postAnswers, original.postAnswers)
        let reopened = try makeStore(directory)
        XCTAssertTrue(try XCTUnwrap(reopened.reminders.first).pinned)

        reopened.togglePin(pinned)

        let reopenedAgain = try makeStore(directory)
        let unpinned = try XCTUnwrap(reopenedAgain.reminders.first)
        XCTAssertFalse(unpinned.pinned)
        XCTAssertTrue(unpinned.needsSync)
        XCTAssertEqual(unpinned.upNextOrder, 0)
        XCTAssertEqual(unpinned.postAnswers, original.postAnswers)
        XCTAssertEqual(unpinned.postNumber, original.postNumber)
        assertNoCaptures(store)
        assertNoCaptures(reopened)
    }

    @MainActor
    func testCompletedAndDeletedItemsCannotBeReordered() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let active = item("Active action", kind: .action, rank: 0, createdAt: 100)
        var completed = item("Completed action", kind: .action, rank: 1, createdAt: 200)
        completed.status = .completed
        var deleted = item("Deleted action", kind: .action, rank: 2, createdAt: 300)
        deleted.status = .deleted
        let original = [active, completed, deleted]
        let store = try makeStore(directory, records: original)

        store.moveUpNext(completed, direction: .up)
        store.moveUpNext(deleted, direction: .up)
        store.moveUpNext(active, direction: .down)

        XCTAssertEqual(store.reminders, original)
        assertNoCaptures(store)
    }

    @MainActor
    func testReorderFixtureCannotWriteToARegularStore() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = item("Existing action", kind: .action, createdAt: 100)
        let store = try makeStore(directory, records: [original])
        store.seedActionsForReorderUITesting()
        XCTAssertEqual(store.reminders, [original])
        assertNoCaptures(store)
    }

    private func item(
        _ title: String,
        kind: ReminderKind,
        pinned: Bool = false,
        rank: Int? = nil,
        createdAt: TimeInterval
    ) -> Reminder {
        var value = Reminder()
        value.title = title
        value.kind = kind
        value.pinned = pinned
        value.upNextOrder = rank
        value.notes = "Exact saved notes.  \nSecond line."
        value.tags = ["Original", "Retained"]
        value.createdAt = Date(timeIntervalSince1970: createdAt)
        value.updatedAt = Date(timeIntervalSince1970: createdAt + 5)
        if kind == .post {
            value.postAnswers = ["What happened?\n\nMy exact answer.  "]
            value.postAnswersContainQuestions = true
            value.postNumber = 42
        }
        return value
    }

    private func assertContentPreserved(_ original: Reminder, saved: Reminder?, rank: Int) throws {
        let saved = try XCTUnwrap(saved)
        var expected = original
        expected.upNextOrder = rank
        expected.updatedAt = saved.updatedAt
        expected.needsSync = true
        XCTAssertEqual(saved, expected)
        XCTAssertGreaterThan(saved.updatedAt, original.updatedAt)
    }

    @MainActor
    private func assertNoCaptures(_ store: ReminderStore) {
        XCTAssertTrue(store.technicalCaptures.isEmpty)
        XCTAssertTrue(store.candidateOutboxItems.isEmpty)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("savy-reorder-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    private func makeStore(_ directory: URL, records: [Reminder]? = nil) throws -> ReminderStore {
        let cacheURL = directory.appendingPathComponent("reminders.json")
        if let records { try JSONEncoder.recall.encode(records).write(to: cacheURL) }
        return ReminderStore(
            repo: LocalReminderRepository(),
            cacheURL: cacheURL,
            technicalCaptureStore: try TechnicalCaptureStore(fileURL: directory.appendingPathComponent("captures.json")),
            candidateOutbox: try CowboyCandidateOutbox(fileURL: directory.appendingPathComponent("outbox.json")),
            candidateClient: OfflineCandidateClient()
        )
    }

    private struct OfflineCandidateClient: CowboyCandidateSubmitting {
        struct Offline: Error {}
        func submit(_ payload: CowboyCandidateIntakePayload) async throws -> CowboyCandidateReceipt { throw Offline() }
    }
}
