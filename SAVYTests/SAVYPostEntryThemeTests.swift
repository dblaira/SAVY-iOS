import XCTest
@testable import SAVY

/// Adam approved the Post mockup on the Reminder form path (2026-09-13: "That looks good.
/// Let's build that."). The test is the sentence: pick Post, pick a Theme, answer the Decide
/// questions, keep every Reminder field, save, and reopen with the data intact.
final class SAVYPostEntryThemeTests: XCTestCase {

    // MARK: - Theme catalog

    func testCatalogLeadsWithTheFiveWsAndItsFiveQuestions() {
        let fiveWs = PostThemeCatalog.defaultTheme
        XCTAssertEqual(fiveWs.id, "five-ws")
        XCTAssertEqual(fiveWs.name, "The 5 Ws")
        XCTAssertEqual(fiveWs.questions.count, 5, "The 5 Ws asks five questions")
        // The mockup's rows, verbatim.
        XCTAssertEqual(fiveWs.questions[0].prompt, "What happened?")
        XCTAssertEqual(fiveWs.questions[1].prompt, "Who was involved?")
        XCTAssertEqual(fiveWs.questions[2].prompt, "When and where did it happen?")
        XCTAssertEqual(fiveWs.questions[3].prompt, "Why did it happen?")
    }

    func testEveryThemeHasAtLeastFourQuestionsAndAUniqueID() {
        XCTAssertGreaterThanOrEqual(PostThemeCatalog.themes.count, 5, "Seed catalog ships 5–10 themes")
        for theme in PostThemeCatalog.themes {
            XCTAssertGreaterThanOrEqual(
                theme.questions.count, 4,
                "\(theme.name) needs at least four questions"
            )
        }
        let ids = PostThemeCatalog.themes.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Theme ids must be unique")
    }

    func testThemeLookupByIDAndUnknownIDFallsThrough() {
        XCTAssertEqual(PostThemeCatalog.theme(id: "five-ws")?.name, "The 5 Ws")
        XCTAssertNil(PostThemeCatalog.theme(id: "not-a-theme"))
        XCTAssertNil(PostThemeCatalog.theme(id: nil))
    }

    // MARK: - Post is the fourth face of the same form

    func testReminderKindHasPostWithCalendarSegmentLabel() {
        XCTAssertEqual(ReminderKind.allCases, [.reminder, .action, .event, .post], "No fifth type")
        XCTAssertEqual(ReminderKind.post.label, "Post")
        // The control shows Calendar (Adam's mockup); the model keeps `event` underneath.
        XCTAssertEqual(ReminderKind.event.segmentLabel, "Calendar")
        XCTAssertEqual(ReminderKind.event.rawValue, "event")
        XCTAssertEqual(ReminderKind.post.segmentLabel, "Post")
    }

    // MARK: - Persistence: theme id/name + ordered answers + every Reminder field

    private func makePostEntry() -> Reminder {
        var entry = Reminder()
        entry.kind = .post
        entry.title = "The cost of trying fell to zero"
        entry.postThemeID = "five-ws"
        entry.postThemeName = "The 5 Ws"
        entry.postAnswers = [
            "A peptide video and an AI hiring story said the same thing.",
            "Me, this morning.",
            "This morning, on my phone.",
            "Because the cost of trying fell to zero.",
            "One story at a time.",
        ]
        // The Reminder fields Adam fought for ride along unchanged.
        entry.whenIAm = "reading the news...I like to connect the dots"
        entry.outcome = "A post ready for X"
        entry.priority = .high
        entry.energy = .low
        entry.context = .clearSign
        entry.listName = "Leverage"
        entry.tags = ["news", "advertising"]
        entry.subtasks = [Subtask(title: "Draft"), Subtask(title: "Trim to 280")]
        return entry
    }

    func testPostEntryEncodesAndDecodesWithThemeAndOrderedAnswers() throws {
        let entry = makePostEntry()
        let data = try JSONEncoder.recall.encode(entry)
        let decoded = try JSONDecoder.recall.decode(Reminder.self, from: data)

        XCTAssertEqual(decoded.kind, .post)
        XCTAssertEqual(decoded.postThemeID, "five-ws")
        XCTAssertEqual(decoded.postThemeName, "The 5 Ws")
        XCTAssertEqual(decoded.postAnswers, entry.postAnswers, "Answers keep their question order")
        // Nothing on the Reminder body was dropped.
        XCTAssertEqual(decoded.whenIAm, entry.whenIAm)
        XCTAssertEqual(decoded.outcome, entry.outcome)
        XCTAssertEqual(decoded.priority, .high)
        XCTAssertEqual(decoded.energy, .low)
        XCTAssertEqual(decoded.context, .clearSign)
        XCTAssertEqual(decoded.listName, "Leverage")
        XCTAssertEqual(decoded.tags, ["news", "advertising"])
        XCTAssertEqual(decoded.subtasks.map(\.title), ["Draft", "Trim to 280"])
    }

    func testCachedRemindersFromBeforePostStillDecode() throws {
        // A reminder cached before the Post fields existed: no postThemeID / postAnswers keys.
        var legacy = Reminder()
        legacy.title = "Check on clothes and dryer"
        let encoded = try JSONEncoder.recall.encode(legacy)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "postThemeID")
        json.removeValue(forKey: "postThemeName")
        json.removeValue(forKey: "postAnswers")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder.recall.decode(Reminder.self, from: legacyData)
        XCTAssertEqual(decoded.title, "Check on clothes and dryer")
        XCTAssertEqual(decoded.kind, .reminder)
        XCTAssertNil(decoded.postThemeID)
        XCTAssertNil(decoded.postThemeName)
        XCTAssertNil(decoded.postAnswers)
    }

    @MainActor
    func testStoreSavesAndReopensPostEntryWithDataIntact() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("post-entry-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cacheURL = dir.appendingPathComponent("reminders.json")

        struct OfflineCandidateClient: CowboyCandidateSubmitting {
            struct Offline: Error {}
            func submit(_ payload: CowboyCandidateIntakePayload) async throws -> CowboyCandidateReceipt {
                throw Offline()
            }
        }

        func makeStore() throws -> ReminderStore {
            ReminderStore(
                repo: LocalReminderRepository(),
                cacheURL: cacheURL,
                technicalCaptureStore: try TechnicalCaptureStore(
                    fileURL: dir.appendingPathComponent("captures.json")
                ),
                candidateOutbox: try CowboyCandidateOutbox(
                    fileURL: dir.appendingPathComponent("outbox.json")
                ),
                candidateClient: OfflineCandidateClient()
            )
        }

        let entry = makePostEntry()
        try makeStore().save(entry)

        // A fresh store on the same cache is the reopen.
        let reopened = try makeStore()
        let loaded = try XCTUnwrap(reopened.reminders.first { $0.id == entry.id })
        XCTAssertEqual(loaded.kind, .post)
        XCTAssertEqual(loaded.postThemeID, "five-ws")
        XCTAssertEqual(loaded.postThemeName, "The 5 Ws")
        XCTAssertEqual(loaded.postAnswers, entry.postAnswers)
        XCTAssertEqual(loaded.tags, ["news", "advertising"])
        XCTAssertEqual(loaded.subtasks.map(\.title), ["Draft", "Trim to 280"])
    }

    // MARK: - Non-Post types stay as today

    func testNonPostKindsCarryNoThemeOrDecideData() throws {
        for kind in [ReminderKind.reminder, .action, .event] {
            var entry = Reminder()
            entry.kind = kind
            entry.title = "Plain \(kind.label)"
            let decoded = try JSONDecoder.recall.decode(
                Reminder.self,
                from: JSONEncoder.recall.encode(entry)
            )
            XCTAssertNil(decoded.postThemeID, "\(kind.label) must not carry a theme")
            XCTAssertNil(decoded.postAnswers, "\(kind.label) must not carry Decide answers")
        }
    }
}
