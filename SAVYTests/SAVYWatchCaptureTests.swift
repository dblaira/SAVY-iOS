import CloudKit
import WatchConnectivity
import XCTest
@testable import SAVY

/// The Watch plan's promise, as tests: what Adam says on the wrist arrives on the iPhone and Mac
/// as the entry type he chose, in the box he would have typed it into, with any day or hour he
/// said, its recording kept, and nothing he did not say. Values only; no store, iCloud or Watch.
final class SAVYWatchCaptureTests: XCTestCase {
    private let fixedMoment = Date(timeIntervalSince1970: 1_795_000_000)

    func testActionWordsBecomeWhatDoIWant() {
        let capture = WatchCapture(kind: .action, words: "  Email Dr Plants about the group lesson  ",
                                   source: .wrist, capturedAt: fixedMoment)
        let entry = Reminder(watchCapture: capture)
        XCTAssertEqual(entry.id, capture.id)
        XCTAssertEqual(entry.kind, .action)
        XCTAssertEqual(entry.title, "Email Dr Plants about the group lesson")
        XCTAssertEqual(entry.createdAt, fixedMoment)
        XCTAssertNil(entry.schedule)
        XCTAssertNil(entry.postAnswers)
        XCTAssertEqual(entry.notes, "")
        XCTAssertEqual(entry.tags, [])
    }

    func testSocialWordsAnswerTheFirstGeneralizationQuestion() throws {
        let words = "Blue's Clues pauses for the kid to answer. That is the group lesson."
        let entry = Reminder(watchCapture: WatchCapture(kind: .post, words: words, source: .shortcut,
                                                        capturedAt: fixedMoment))
        let theme = try XCTUnwrap(PostThemeCatalog.theme(id: "generalization"))
        XCTAssertEqual(entry.kind, .post)
        XCTAssertEqual(entry.postThemeID, "generalization")
        XCTAssertEqual(entry.postThemeName, theme.name)
        XCTAssertEqual(entry.postAnswersContainQuestions, true)
        XCTAssertEqual(entry.postAnswers?.count, theme.questions.count)
        XCTAssertEqual(entry.postAnswers?.first, "What shining example caught my attention?\n" + words)
        XCTAssertEqual(Array(entry.postAnswers?.dropFirst() ?? []), Array(theme.prefilledAnswers.dropFirst()))
        XCTAssertEqual(entry.firstThemeAnswer, words)
        XCTAssertEqual(entry.postAnsweredCount, 1)
        // The name comes from his words, never a generic one.
        XCTAssertEqual(entry.title, entry.autoTitle())
        XCTAssertFalse(entry.title.isEmpty)
        XCTAssertNil(entry.schedule)
    }

    func testActionAndSocialNeverReadADay() {
        XCTAssertNil(WatchCapture(kind: .action, words: "Call Sam tomorrow at 3 PM", source: .wrist).cue)
        XCTAssertNil(WatchCapture(kind: .post, words: "Saw this tomorrow at 3 PM", source: .wrist).cue)
    }

    func testCalendarHearsADayAndHour() throws {
        let capture = WatchCapture(kind: .event, words: "Lunch with Sam tomorrow at 3 PM", source: .wrist)
        let cue = try XCTUnwrap(capture.cue)
        XCTAssertFalse(cue.isDayOnly)
        XCTAssertGreaterThan(cue.start, capture.capturedAt)
        XCTAssertEqual(Calendar.current.component(.hour, from: cue.start), 15)

        let entry = Reminder(watchCapture: capture)
        let schedule = try XCTUnwrap(entry.schedule)
        XCTAssertEqual(entry.kind, .event)
        XCTAssertEqual(entry.title, "Lunch with Sam tomorrow at 3 PM")
        XCTAssertFalse(schedule.isAllDay)
        XCTAssertEqual(schedule.startDate, cue.start)
        XCTAssertEqual(schedule.endDate, cue.start.addingTimeInterval(3_600))
        XCTAssertEqual(schedule.alert, .atStart)
        XCTAssertNil(schedule.calendarIdentifier)
        XCTAssertNil(schedule.validationMessage)
        XCTAssertEqual(entry.scheduleSyncVersion, 1)
        XCTAssertEqual(entry.dueDate, schedule.startDate)
        XCTAssertEqual(entry.dueTime, schedule.startDate)
        XCTAssertEqual(entry.endTime, schedule.endDate)
    }

    func testCalendarDayWithoutHourIsAllDay() throws {
        let capture = WatchCapture(kind: .event, words: "Mom's birthday next Friday", source: .wrist)
        let cue = try XCTUnwrap(capture.cue)
        XCTAssertTrue(cue.isDayOnly)
        let schedule = try XCTUnwrap(Reminder(watchCapture: capture).schedule)
        XCTAssertTrue(schedule.isAllDay)
        XCTAssertEqual(schedule.alert, ReminderAlert.none)
        XCTAssertNil(schedule.validationMessage)
        XCTAssertEqual(schedule.calendar.component(.hour, from: schedule.startDate), 0)
    }

    func testReminderDayWithoutHourStartsAtNine() throws {
        let capture = WatchCapture(kind: .reminder, words: "Renew the passport next Friday", source: .wrist)
        let window = try XCTUnwrap(capture.proposedWindow)
        XCTAssertFalse(window.isAllDay)
        XCTAssertEqual(Calendar.current.component(.hour, from: window.start), 9)
        XCTAssertEqual(Reminder(watchCapture: capture).schedule?.startDate, window.start)
    }

    func testWordsWithoutADayKeepNoSchedule() {
        let entry = Reminder(watchCapture: WatchCapture(kind: .reminder, words: "Buy more tennis balls", source: .wrist))
        XCTAssertNil(entry.schedule)
        XCTAssertNil(entry.scheduleSyncVersion)
        XCTAssertNil(entry.dueDate)
    }

    func testClockTimeWording() {
        XCTAssertTrue(WatchTimeCueReader.namesClockTime("tomorrow at 3 PM"))
        XCTAssertTrue(WatchTimeCueReader.namesClockTime("3:30"))
        XCTAssertTrue(WatchTimeCueReader.namesClockTime("Friday at 9"))
        XCTAssertTrue(WatchTimeCueReader.namesClockTime("tonight"))
        XCTAssertFalse(WatchTimeCueReader.namesClockTime("December 3"))
        XCTAssertFalse(WatchTimeCueReader.namesClockTime("next Friday"))
        XCTAssertFalse(WatchTimeCueReader.namesClockTime("the 25th"))
    }

    func testReRecordingKeepsTheSameCapture() {
        let first = WatchCapture(kind: .reminder, words: "Call the vet", source: .wrist, capturedAt: fixedMoment)
        let second = first.replacingWords("Call the vet tomorrow at 9 AM")
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.capturedAt, first.capturedAt)
        XCTAssertEqual(second.words, "Call the vet tomorrow at 9 AM")
        XCTAssertNotNil(second.cue)
    }

    func testInboxRecordRoundTripsAndStaysOutOfTheEntryZone() throws {
        let capture = WatchCapture(kind: .action, words: "Film the group lesson intro", source: .wrist,
                                   capturedAt: fixedMoment)
        let record = try WatchCaptureInbox.record(for: capture)
        XCTAssertEqual(record.recordType, "SAVYWatchCaptureV1")
        XCTAssertEqual(record.recordID.zoneID.zoneName, "SAVYWatchInboxV1")
        XCTAssertNotEqual(record.recordID.zoneID, SavyCloudKitRecordCodec.zoneID)
        XCTAssertFalse(SavyCloudKitRecordCodec.owns(record.recordID))
        XCTAssertEqual(try WatchCaptureInbox.capture(from: record), capture)
    }

    // MARK: One big button: recordings (Adam, Nov 20: “I pressed the button, I record it”)

    func testPlainSaveIsSocial() {
        // Adam chose: plain Save lands as the first Generalization answer.
        XCTAssertEqual(WatchCaptureKind.saveDefault, .post)
    }

    func testRecordingTravelsWithItsAudioAndNoWordsYet() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data("not really audio".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let capture = WatchCapture(kind: .post, words: "", source: .wrist, capturedAt: fixedMoment,
                                   audioFileName: file.lastPathComponent, audioDuration: 7)
        XCTAssertTrue(capture.hasRecording)
        let record = try WatchCaptureInbox.record(for: capture, audioURL: file)
        XCTAssertEqual(WatchCaptureInbox.audioURL(in: record), file)
        XCTAssertEqual(try WatchCaptureInbox.capture(from: record), capture)
    }

    func testACaptureWithNeitherWordsNorRecordingIsRejected() throws {
        let empty = WatchCapture(kind: .action, words: "   ", source: .wrist, capturedAt: fixedMoment)
        XCTAssertThrowsError(try WatchCaptureInbox.capture(from: WatchCaptureInbox.record(for: empty)))
    }

    func testWordsWrittenOutLaterKeepTheRecordingAndReadTheDay() throws {
        let recording = WatchCapture(kind: .reminder, words: "", source: .wrist, capturedAt: Date(),
                                     audioFileName: "a.m4a", audioDuration: 4)
        XCTAssertNil(recording.cue)
        let written = recording.replacingWords("Call the vet tomorrow at 9 AM")
        XCTAssertEqual(written.id, recording.id)
        XCTAssertEqual(written.audioFileName, "a.m4a")
        XCTAssertEqual(written.audioDuration, 4)
        XCTAssertNotNil(written.cue)
        XCTAssertNotNil(Reminder(watchCapture: written).schedule)
    }

    func testChoosingATypeKeepsTheRecording() {
        let recording = WatchCapture(kind: .post, words: "", source: .wrist, capturedAt: fixedMoment,
                                     audioFileName: "b.m4a", audioDuration: 3)
        let action = recording.withKind(.action)
        XCTAssertEqual(action.kind, .action)
        XCTAssertEqual(action.id, recording.id)
        XCTAssertEqual(action.audioFileName, "b.m4a")
    }

    func testRecordingWithNoWordsWrittenGetsSAVYsGenericName() throws {
        // Speech Recognition off, or nothing heard: the entry still arrives, with the recording,
        // under the generic name the form replaces once Adam types his words.
        let social = Reminder(watchCapture: WatchCapture(kind: .post, words: "", source: .wrist, capturedAt: fixedMoment,
                                                         audioFileName: "c.m4a", audioDuration: 5))
        XCTAssertEqual(social.title, "New Social")
        XCTAssertEqual(social.titleOrigin, .generated)
        XCTAssertEqual(social.postAnswers?.first, "What shining example caught my attention?\n")
        XCTAssertEqual(social.postAnsweredCount, 0)
        // Once he writes the answer, Save names the entry from it, as for any entry SAVY named.
        var written = social
        written.postAnswers?[0] = "What shining example caught my attention?\nBlue's Clues pauses for the kid"
        written.resolveDelegateTitle(entryLabel: "Social")
        XCTAssertEqual(written.title, "Blue's Clues pauses for the kid")

        let action = Reminder(watchCapture: WatchCapture(kind: .action, words: "", source: .wrist, capturedAt: fixedMoment,
                                                         audioFileName: "d.m4a", audioDuration: 5))
        XCTAssertEqual(action.title, "New Action")
        XCTAssertEqual(action.titleOrigin, .generated)
    }

    func testSpokenWordsInWhatDoIWantAreHisWritingAndASocialNameFollowsHisAnswer() {
        // Nov 20 title rule on main: a title he wrote is kept; a name SAVY supplied follows the boxes.
        let action = Reminder(watchCapture: WatchCapture(kind: .action, words: "Email Dr Plants", source: .wrist,
                                                         capturedAt: fixedMoment))
        XCTAssertEqual(action.titleOrigin, .authored)
        let social = Reminder(watchCapture: WatchCapture(kind: .post, words: "Blue's Clues pauses for the kid",
                                                         source: .wrist, capturedAt: fixedMoment))
        XCTAssertEqual(social.titleOrigin, .generated)
    }

    func testFixListTurnsKodakIntoCodex() {
        // Adam, Nov 20: “it might change CODEX to KODAK or something like that.”
        XCTAssertEqual(WatchCaptureTranscriber.corrected("Ask KODAK to review the Watch build"),
                       "Ask Codex to review the Watch build")
        XCTAssertEqual(WatchCaptureTranscriber.corrected("kodak's answer"), "Codex's answer")
        XCTAssertEqual(WatchCaptureTranscriber.corrected("Kodaks stay as said"), "Kodaks stay as said")
    }

    func testVocabularyHintsIncludeCodex() {
        // Adam, Nov 20: dictation “might change CODEX to KODAK”.
        XCTAssertTrue(WatchCaptureConfig.vocabulary.contains("Codex"))
    }

    func testInboxRejectsARecordWhoseNameDoesNotMatchItsCapture() throws {
        let capture = WatchCapture(kind: .action, words: "One", source: .wrist, capturedAt: fixedMoment)
        let other = WatchCapture(kind: .action, words: "Two", source: .wrist, capturedAt: fixedMoment)
        let record = try WatchCaptureInbox.record(for: capture)
        let moved = CKRecord(recordType: record.recordType, recordID: WatchCaptureInbox.recordID(for: other.id))
        moved["schemaVersion"] = record["schemaVersion"]
        let payload = try XCTUnwrap(record.encryptedValues["payload"] as? Data)
        moved.encryptedValues["payload"] = payload as NSData
        XCTAssertThrowsError(try WatchCaptureInbox.capture(from: moved))
    }

    // MARK: Trail — Adam, Nov 21: “The Apple Watch SAVY app works and doesn't work. It needs a lot of testing.”

    private func temporaryTrail() -> WatchCaptureTrailFile {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SAVYWatchTrailTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return WatchCaptureTrailFile(folder: folder)
    }

    private func step(_ name: String, ok: Bool = true, capture: UUID? = nil, _ detail: String? = nil) -> WatchCaptureTrail.Event {
        WatchCaptureTrail.Event(at: fixedMoment, side: "watch", step: name, ok: ok,
                                capture: capture?.uuidString.lowercased(), detail: detail)
    }

    func testTrailKeepsEachStepInOrderWithItsReason() {
        let trail = temporaryTrail()
        let id = UUID()
        trail.append(step("keep", capture: id, "file=ab12cd34 7.2s 21KB"))
        trail.append(step("cloud.send", ok: false, capture: id, "CloudKit 9 notAuthenticated"))
        let events = trail.events()
        XCTAssertEqual(events.map(\.step), ["keep", "cloud.send"])
        XCTAssertEqual(events.map(\.ok), [true, false])
        XCTAssertEqual(events.last?.capture, id.uuidString.lowercased())
        XCTAssertEqual(events.last?.detail, "CloudKit 9 notAuthenticated")
        XCTAssertEqual(events.first?.at, fixedMoment)
    }

    func testTrailWritesARetriedFailureOnce() {
        let trail = temporaryTrail()
        let id = UUID()
        XCTAssertTrue(trail.append(step("cloud.send", ok: false, capture: id, "offline"), once: true))
        XCTAssertFalse(trail.append(step("cloud.send", ok: false, capture: id, "offline"), once: true))
        // A different reason, or the same step for another capture, is new.
        XCTAssertTrue(trail.append(step("cloud.send", capture: id, "in iCloud"), once: true))
        XCTAssertTrue(trail.append(step("cloud.send", ok: false, capture: UUID(), "offline"), once: true))
        XCTAssertEqual(trail.events().count, 3)
    }

    func testTrailStaysSmallAndKeepsTheNewestSteps() {
        let trail = temporaryTrail()
        let total = WatchCaptureTrailFile.lineLimit + 10
        for number in 1...total { trail.append(step("step", "\(number)")) }
        let events = trail.events()
        XCTAssertLessThanOrEqual(events.count, WatchCaptureTrailFile.lineLimit)
        XCTAssertGreaterThanOrEqual(events.count, WatchCaptureTrailFile.keptLines)
        XCTAssertEqual(events.last?.detail, "\(total)")
        // A new reader of the same file sees the same lines: nothing is held only in memory.
        XCTAssertEqual(WatchCaptureTrailFile(folder: trail.fileURL.deletingLastPathComponent()).events(), events)
    }

    func testTrailReasonNamesTheErrorAndLeavesOutItsDescription() {
        XCTAssertEqual(WatchCaptureTrail.reason(CKError(.notAuthenticated)), "CloudKit 9 notAuthenticated")
        XCTAssertEqual(WatchCaptureTrail.reason(CKError(.permissionFailure)), "CloudKit 10 permissionFailure")
        XCTAssertEqual(WatchCaptureTrail.reason(WCError(.notReachable)), "WatchConnectivity 7007 notReachable")
        let described = NSError(domain: "Example", code: 7, userInfo: [NSLocalizedDescriptionKey: "what Adam said"])
        XCTAssertEqual(WatchCaptureTrail.reason(described), "Example 7")
    }
}
