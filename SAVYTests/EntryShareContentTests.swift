import XCTest
@testable import SAVY

final class EntryShareContentTests: XCTestCase {
    private var entry: Reminder {
        var entry = Reminder()
        entry.kind = .action
        entry.title = "My exact words — including “quotes”.\nAnother line.  "
        entry.whenIAm = "Context stays intact."
        entry.outcome = "Done looks exactly like this."
        entry.postThemeID = "habit"
        entry.postThemeName = "Habit"
        entry.postAnswersContainQuestions = true
        entry.postAnswers = ["My edited question\nMy full answer 🧠\n  Indented writing."]
        entry.subtasks = [Subtask(title: "First step"), Subtask(title: "Finished step", done: true)]
        entry.context = .clearSign
        entry.listName = "Inspiration"
        entry.tags = ["Connection", "AI"]
        entry.priority = .medium
        entry.energy = .high
        entry.notes = "Exact metadata note.\nSecond line."
        entry.url = "https://example.com/context"
        entry.locationName = "At home"
        entry.waitingOn = "A collaborator"
        entry.imageLocalPath = "NEVER_SHARE_IMAGE.png"
        return entry
    }

    private func content(_ entry: Reminder) -> EntryShareContent {
        EntryShareContent(entry: entry, sourceApp: "Test App", entryLabel: "Action",
                          whenIAm: "Context stays intact.")
    }

    func testEntireFormPreservesWritingStepsAndMetadataWithoutImages() {
        let value = content(entry).entireForm
        XCTAssertTrue(value.contains(entry.title))
        XCTAssertTrue(value.contains("My edited question\nMy full answer 🧠\n  Indented writing."))
        XCTAssertTrue(value.contains("[ ] First step\n[x] Finished step"))
        assertMetadata(value)
        XCTAssertFalse(value.contains("NEVER_SHARE_IMAGE"))
        XCTAssertFalse(value.contains(entry.id.uuidString))
    }

    func testEntireFormIncludesEveryDelegateField() {
        let value = content(entry).entireForm
        XCTAssertTrue(value.contains(entry.title))
        XCTAssertTrue(value.contains("Context stays intact."))
        XCTAssertTrue(value.contains(entry.outcome))
        assertMetadata(value)
        XCTAssertTrue(value.contains("My full answer"))
        XCTAssertTrue(value.contains("My edited question"))
        XCTAssertTrue(value.contains("First step"))
        XCTAssertFalse(value.contains("NEVER_SHARE_IMAGE"))
    }

    func testLegacyAnswersRetainTheirQuestionAndEveryCharacter() {
        var legacy = entry
        legacy.postAnswersContainQuestions = nil
        legacy.postAnswers = ["  Original answer.\nSecond line.  "]
        let value = content(legacy).entireForm
        XCTAssertTrue(value.contains("Make it Obvious\n\n  Original answer.\nSecond line.  "))
    }

    func testPendingTagsAreIncludedWithoutMutatingSavedTags() {
        let saved = ["Connection"]
        XCTAssertEqual(EntryShareContent.tags(saved, pending: " #AI "), ["Connection", "AI"])
        XCTAssertEqual(EntryShareContent.tags(saved, pending: "Connection"), ["Connection"])
        XCTAssertEqual(saved, ["Connection"])
    }

    func testScheduleMetadataIsPresentInEntireForm() {
        let snapshot = EntryShareContent(
            entry: entry, sourceApp: "Test App", entryLabel: "Action", whenIAm: "",
            scheduleMetadata: ["Starts: Oct 20, 2026 at 9:00 AM", "Alert: Hourly", "Time zone: America/Los_Angeles"]
        )
        let value = snapshot.entireForm
        XCTAssertTrue(value.contains("Starts: Oct 20, 2026 at 9:00 AM"))
        XCTAssertTrue(value.contains("Alert: Hourly"))
        XCTAssertTrue(value.contains("Time zone: America/Los_Angeles"))
    }

    private func assertMetadata(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        for expected in ["Theme: Habit", "Pattern: Clear Sign of Success", "Lift: Inspiration",
                         "Tags: Connection, AI", "Priority: Medium", "Energy: High",
                         "Notes: Exact metadata note.\nSecond line.", "Link: https://example.com/context",
                         "Location: At home", "Waiting on / delegate to: A collaborator"] {
            XCTAssertTrue(value.contains(expected), "Missing \(expected)", file: file, line: line)
        }
    }
}


extension EntryShareContentTests {
    func testEveryEntryKindExportsCreationAndChangeAsAbsoluteInstants() throws {
        for kind in ReminderKind.allCases {
            var entry = Reminder()
            entry.kind = kind
            entry.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            entry.updatedAt = Date(timeIntervalSince1970: 1_700_086_400)
            entry.dueDate = Date(timeIntervalSince1970: 1_900_000_000)
            let before = try JSONEncoder.recall.encode(entry)
            let text = EntryShareContent(entry: entry, sourceApp: "Test", entryLabel: kind.label, whenIAm: "").entireForm
            XCTAssertTrue(text.contains("Created: 2023-11-14T22:13:20Z"), kind.rawValue)
            XCTAssertTrue(text.contains("Changed: 2023-11-15T22:13:20Z"), kind.rawValue)
            XCTAssertEqual(try JSONDecoder.recall.decode(Reminder.self, from: before), entry)
            XCTAssertEqual(entry.updatedAt, Date(timeIntervalSince1970: 1_700_086_400), "Reading or sharing must not change the timestamp")
            let draft = EntryShareContent(entry: entry, sourceApp: "Test", entryLabel: kind.label, whenIAm: "", isDraft: true).entireForm
            XCTAssertTrue(draft.contains("Unsaved draft"))
        }
    }
}

@MainActor
final class EntryTimestampPersistenceTests: XCTestCase {
    func testCalendarInvitationCarriesEntryDatesSeparatelyFromEventAndExportDates() throws {
        var entry = Reminder()
        entry.kind = .event
        entry.title = "Calendar fixture"
        entry.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        entry.updatedAt = Date(timeIntervalSince1970: 1_700_086_400)
        entry.schedule = ReminderSchedule(startDate: Date(timeIntervalSince1970: 1_900_000_000),
            endDate: Date(timeIntervalSince1970: 1_900_003_600), invitees: ["guest@example.com"])
        let data = try ScheduleInvitation.invitationData(for: entry, organizerEmail: "owner@example.com",
            now: Date(timeIntervalSince1970: 1_800_000_000))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("CREATED:20231114T221320Z\r\n"))
        XCTAssertTrue(text.contains("LAST-MODIFIED:20231115T221320Z\r\n"))
        XCTAssertTrue(text.contains("DTSTAMP:20270115T080000Z\r\n"))
        XCTAssertEqual(entry.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    private struct Offline: Error {}
    private struct NoNetwork: CowboyCandidateSubmitting {
        func submit(_ payload: CowboyCandidateIntakePayload) async throws -> CowboyCandidateReceipt { throw Offline() }
    }

    func testAllAuthoredStoresPreserveCreationAndPersistChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let oldChange = created.addingTimeInterval(60)
        let captures = try TechnicalCaptureStore(fileURL: root.appendingPathComponent("captures.json"))
        let outbox = try CowboyCandidateOutbox(fileURL: root.appendingPathComponent("outbox.json"))
        let cache = root.appendingPathComponent("reminders.json")
        var originals: [Reminder] = []
        for kind in ReminderKind.allCases {
            var entry = Reminder()
            entry.kind = kind; entry.title = "Timestamp fixture"; entry.createdAt = created; entry.updatedAt = oldChange
            originals.append(entry)
        }
        try JSONEncoder.recall.encode(originals).write(to: cache)
        let store = ReminderStore(cacheURL: cache, technicalCaptureStore: captures, candidateOutbox: outbox, candidateClient: NoNetwork())
        XCTAssertEqual(store.reminders, originals, "Loading must not stamp an edit")
        for original in originals {
            var edited = original
            edited.title = "Changed fixture"; edited.createdAt = Date()
            XCTAssertTrue(store.save(edited))
            let saved = try XCTUnwrap(store.reminders.first { $0.id == original.id })
            XCTAssertEqual(saved.createdAt, created)
            XCTAssertGreaterThan(saved.updatedAt, oldChange)
            let capture = try XCTUnwrap(captures.capture(forReminderID: original.id))
            XCTAssertEqual(capture.metadata.createdAt, created)
            XCTAssertEqual(capture.metadata.updatedAt, saved.updatedAt)
            XCTAssertTrue(capture.promptText.contains("Created: 2023-11-14T22:13:20Z"))
            store.complete(saved)
            XCTAssertEqual(store.reminders.first { $0.id == original.id }?.createdAt, created)
        }
        let titleChange = Date(timeIntervalSince1970: 2_000_000_000)
        NotificationCenter.default.post(name: Notification.Name("EntryCardTitleDidChange"), object: nil,
            userInfo: ["id": "reminder:\(originals[0].id.uuidString)", "date": titleChange])
        let renamed = try XCTUnwrap(store.reminders.first { $0.id == originals[0].id })
        XCTAssertEqual(renamed.updatedAt, titleChange)
        XCTAssertTrue(renamed.needsSync, "Title change dates must survive the next repository refresh")
        let reloaded = try JSONDecoder.recall.decode([Reminder].self, from: Data(contentsOf: cache))
        XCTAssertEqual(reloaded.count, originals.count)
        XCTAssertTrue(reloaded.allSatisfy { $0.createdAt == created && $0.updatedAt > oldChange })

        var post = SocialPost(); post.text = "Post fixture"; post.createdAt = created; post.updatedAt = oldChange
        let postsFile = root.appendingPathComponent("posts.json")
        try JSONEncoder.recall.encode([post]).write(to: postsFile)
        let posts = try SocialPostStore(fileURL: postsFile)
        post.createdAt = Date(); XCTAssertTrue(posts.save(post))
        let savedPost = try XCTUnwrap(posts.posts.first)
        XCTAssertEqual(savedPost.createdAt, created); XCTAssertGreaterThan(savedPost.updatedAt, oldChange)
        XCTAssertTrue(savedPost.aiForm.contains("Created: 2023-11-14T22:13:20Z"))
        XCTAssertTrue(savedPost.aiForm.contains("Changed: "))

        var story = Story(); story.body = "Story fixture"; story.createdAt = created; story.updatedAt = oldChange
        let storiesFile = root.appendingPathComponent("stories.json")
        try JSONEncoder.recall.encode([story]).write(to: storiesFile)
        let stories = try StoryStore(fileURL: storiesFile)
        story.createdAt = Date(); XCTAssertTrue(stories.save(story))
        XCTAssertEqual(stories.stories.first?.createdAt, created)
        XCTAssertGreaterThan(try XCTUnwrap(stories.stories.first?.updatedAt), oldChange)
        XCTAssertTrue(try XCTUnwrap(stories.stories.first).aiForm.contains("Created: 2023-11-14T22:13:20Z"))

        let connections = ConnectionStore(fileURL: root.appendingPathComponent("connections.json"), launchArguments: [])
        XCTAssertTrue(connections.save(originals[0]))
        let connection = try XCTUnwrap(connections.entries.first)
        XCTAssertTrue(connections.togglePin(connection))
        XCTAssertEqual(connections.entries.first?.metadata.createdAt, created)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(connections.entries.first?.metadata.updatedAt), connection.metadata.updatedAt)

        let metadata = try MetadataEntryStore(fileURL: root.appendingPathComponent("metadata.json"))
        var entry = MetadataEntry(kind: .action, title: "Metadata fixture", createdAt: created, updatedAt: oldChange)
        try metadata.save(entry); entry.createdAt = Date(); try metadata.save(entry)
        XCTAssertEqual(metadata.entries.first?.createdAt, created)
        XCTAssertGreaterThan(try XCTUnwrap(metadata.entries.first?.updatedAt), oldChange)

        NotificationCenter.default.post(name: Notification.Name("EntryCardTitleDidChange"), object: nil,
            userInfo: ["id": "post:\(post.id.uuidString)", "date": Date(timeIntervalSince1970: 2_000_000_000)])
        XCTAssertEqual(posts.posts.first?.updatedAt, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(try SocialPostStore(fileURL: postsFile).posts.first?.createdAt, created)
    }
}
