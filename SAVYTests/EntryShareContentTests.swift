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
