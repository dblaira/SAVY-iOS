import XCTest
@testable import SAVY

final class SAVYPostPinTests: XCTestCase {
    @MainActor
    func testOlderPostsAllowManyIndependentPinsAndPersistThem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("posts.json")
        let store = try SocialPostStore(fileURL: file)
        var saved: [SocialPost] = []
        for index in 0..<8 {
            var post = SocialPost()
            post.text = "Synthetic pinned post \(index)"
            saved.append(post)
            store.save(post)
            store.togglePin(post)
        }
        XCTAssertEqual(store.posts.filter(\.pinned).count, 8)
        let reopened = try SocialPostStore(fileURL: file)
        XCTAssertEqual(Set(reopened.posts.filter(\.pinned).map(\.id)), Set(saved.map(\.id)))
        reopened.togglePin(saved[0])
        XCTAssertEqual(reopened.posts.filter(\.pinned).count, 7)
        XCTAssertEqual(reopened.posts.first { $0.id == saved[0].id }?.text, saved[0].text)
    }

    func testLegacyPostWithoutPinStillDecodes() throws {
        let oldData = Data(#"{"text":"An existing post"}"#.utf8)
        let decoded = try JSONDecoder.recall.decode(SocialPost.self, from: oldData)
        XCTAssertFalse(decoded.pinned)
        XCTAssertEqual(decoded.text, "An existing post")
    }
}

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
        XCTAssertGreaterThanOrEqual(PostThemeCatalog.themes.count, 5, "Seed catalog ships the original 8 plus Adam's 11–30")
        for theme in PostThemeCatalog.themes {
            XCTAssertGreaterThanOrEqual(
                theme.questions.count, 4,
                "\(theme.name) needs at least four questions"
            )
        }
        let ids = PostThemeCatalog.themes.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Theme ids must be unique")
    }

    func testCatalogCarriesAdamsThemes11Through30Verbatim() {
        // Adam's list (2026-09-15): 20 themes — the image skips #14, and its two #26 titles
        // are both their own themes. They follow the original 8, in his order.
        let expectedNewNames = [
            "Frequently Asked Questions",
            "Customer Success Story",
            "Key Challenges & Solutions",
            "Myths vs. Facts",
            "The Ultimate Checklist",
            "Quick Hack or Shortcut",
            "Recommended Tools & Resources",
            "Essential Terminology",
            "Before & After Scenarios",
            "Audience Poll or Survey Results",
            "Core Principles Explained",
            "Debunking Popular Industry Beliefs",
            "History of the Topic",
            "Alternative Approaches",
            "Step-by-Step Breakdown",
            "Checklist for Breakdown",
            "Checklist for Beginners",
            "Advanced Strategies",
            "Frequently Misunderstood Concepts",
            "Your Personal Take & Lessons Learned",
        ]
        XCTAssertEqual(PostThemeCatalog.themes.count, 28, "8 original themes + Adam's 20")
        XCTAssertEqual(Array(PostThemeCatalog.themes.suffix(20).map(\.name)), expectedNewNames)
        for theme in PostThemeCatalog.themes.suffix(20) {
            XCTAssertEqual(theme.questions.count, 4, "\(theme.name) asks exactly four questions")
        }

        // Spot-checks, verbatim to his message — including the curly quotes he wrote.
        XCTAssertEqual(
            PostThemeCatalog.theme(id: "frequently-asked-questions")?.questions.map(\.prompt),
            [
                "What questions do people repeatedly ask?",
                "What uncertainty is behind each question?",
                "What is the clearest answer to each?",
                "What follow-up question naturally comes after each answer?",
            ]
        )
        XCTAssertEqual(
            PostThemeCatalog.theme(id: "before-after-scenarios")?.questions.first?.prompt,
            "What starting condition will the “before” show?"
        )
        XCTAssertEqual(
            PostThemeCatalog.theme(id: "your-personal-take-lessons-learned")?.questions.map(\.prompt),
            [
                "What did you believe before?",
                "What experience changed or confirmed your view?",
                "What do you believe now?",
                "What do you do differently because of it?",
            ]
        )

        // The two #26 titles stay distinct themes with distinct question sets.
        let stepByStep = PostThemeCatalog.theme(id: "step-by-step-breakdown")
        let checklistBreakdown = PostThemeCatalog.theme(id: "checklist-for-breakdown")
        XCTAssertEqual(stepByStep?.questions.first?.prompt, "What stages make up the process?")
        XCTAssertEqual(checklistBreakdown?.questions.first?.prompt, "Which parts of the process must be accounted for?")
        XCTAssertNotEqual(stepByStep?.questions, checklistBreakdown?.questions)
    }

    func testThemeLookupByIDAndUnknownIDFallsThrough() {
        XCTAssertEqual(PostThemeCatalog.theme(id: "five-ws")?.name, "The 5 Ws")
        XCTAssertNil(PostThemeCatalog.theme(id: "not-a-theme"))
        XCTAssertNil(PostThemeCatalog.theme(id: nil))
    }

    // MARK: - Complete editable questions and answers

    func testOpeningEveryTemplatePrefillsQuestionsWithoutAutosaveContent() {
        var draft = PostEntryDraft(entry: Reminder())
        for theme in PostThemeCatalog.themes {
            draft.selectTheme(theme.id)
            XCTAssertEqual(draft.answers, theme.questions.map { $0.prompt + "\n\n" })
            XCTAssertFalse(draft.hasUserContent, "Choosing \(theme.name) alone must not autosave a post")
        }
    }

    func testLegacyAnswersGainTheirQuestionsWithoutChangingTheAnswerText() throws {
        var entry = makePostEntry()
        entry.postAnswers?[0] = "  My exact answer.\n\nA second paragraph.  \n"
        let original = try XCTUnwrap(entry.postAnswers)
        let draft = PostEntryDraft(entry: entry)
        for index in original.indices {
            XCTAssertEqual(draft.answers[index], draft.theme.questions[index].prompt + "\n\n" + original[index])
        }
        XCTAssertTrue(draft.hasUserContent)
        XCTAssertEqual(entry.postAnsweredCount, 5)
    }

    func testLegacyAnswerThatAlreadyIncludesItsQuestionDoesNotDuplicateIt() {
        var entry = makePostEntry()
        entry.postAnswers?[0] = "What happened?\n\nI already copied this question."
        let draft = PostEntryDraft(entry: entry)
        XCTAssertEqual(draft.answers[0], entry.postAnswers?[0])
    }

    func testSavedEditedQuestionsAndBlankFieldsReopenVerbatimRepeatedly() throws {
        var entry = makePostEntry()
        var draft = PostEntryDraft(entry: entry)
        let edited = "What actually changed for me?\n\nMy answer, exactly.  \nAnother line.\n"
        draft.setAnswer(edited, at: 0)
        draft.setAnswer("", at: 1)
        draft.apply(to: &entry)

        for _ in 0..<3 {
            entry = try JSONDecoder.recall.decode(Reminder.self, from: JSONEncoder.recall.encode(entry))
            draft = PostEntryDraft(entry: entry)
            XCTAssertEqual(draft.answers[0], edited)
            XCTAssertEqual(draft.answers[1], "", "An intentionally cleared question remains cleared")
            XCTAssertEqual(entry.postAnswersContainQuestions, true)
            draft.apply(to: &entry)
        }
        XCTAssertEqual(entry.postQuestionAndAnswers[0], edited)
    }

    func testThemeSwitchingRetainsEachThemesOwnEdits() throws {
        let first = PostThemeCatalog.defaultTheme
        let second = try XCTUnwrap(PostThemeCatalog.theme(id: "advanced-strategies"))
        var draft = PostEntryDraft(entry: Reminder())
        let firstAnswer = first.questions[0].prompt + "\n\nThe first theme's answer."
        let secondAnswer = second.questions[0].prompt + "\n\nThe second theme's answer."
        draft.setAnswer(firstAnswer, at: 0)
        draft.selectTheme(second.id)
        XCTAssertEqual(draft.answers, second.prefilledAnswers)
        XCTAssertFalse(draft.hasUserContent)
        draft.setAnswer(secondAnswer, at: 0)
        draft.selectTheme(first.id)
        XCTAssertEqual(draft.answers[0], firstAnswer)
        draft.selectTheme(second.id)
        XCTAssertEqual(draft.answers[0], secondAnswer)
    }

    func testExplicitSaveKeepsUntouchedQuestionsAndCountsNoAnswers() {
        var entry = Reminder()
        entry.kind = .post
        let draft = PostEntryDraft(entry: entry)
        XCTAssertFalse(draft.hasUserContent)
        draft.apply(to: &entry)
        XCTAssertEqual(entry.postAnswers, draft.theme.prefilledAnswers)
        XCTAssertEqual(entry.postAnswersContainQuestions, true)
        XCTAssertEqual(entry.postAnsweredCount, 0)
        XCTAssertEqual(entry.postAnswerTexts, Array(repeating: "", count: draft.theme.questions.count))
    }

    func testEditedQuestionIsContentAndCardCountsOnlyItsAnswer() {
        var entry = Reminder()
        entry.kind = .post
        var draft = PostEntryDraft(entry: entry)
        draft.setAnswer("What changed in my thinking?\n\n", at: 0)
        XCTAssertTrue(draft.hasUserContent, "Editing the question itself must survive autosave")
        draft.apply(to: &entry)
        XCTAssertEqual(entry.postAnsweredCount, 0)
        draft.setAnswer("What changed in my thinking?\n\nI can now see the connection.", at: 0)
        draft.apply(to: &entry)
        XCTAssertEqual(entry.postAnswerTexts[0], "I can now see the connection.")
        XCTAssertEqual(entry.postAnsweredCount, 1)
    }

    func testMissingFieldsArePrefilledAndExtraSavedTextIsNeverDropped() {
        var entry = makePostEntry()
        entry.postAnswers = ["Only one answer was saved."]
        var draft = PostEntryDraft(entry: entry)
        XCTAssertEqual(draft.answers.count, 5)
        XCTAssertEqual(draft.answers[1], "Who was involved?\n\n")

        let extraText = "An extra saved field.\nEvery line stays."
        entry.postAnswers = (entry.postAnswers ?? []) + Array(repeating: "", count: 4) + [extraText]
        draft = PostEntryDraft(entry: entry)
        draft.apply(to: &entry)
        XCTAssertEqual(entry.postAnswers?.count, 6)
        XCTAssertEqual(entry.postAnswers?.last, extraText)
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
        XCTAssertNil(decoded.postAnswersContainQuestions)
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

    // MARK: - Refresh preserves complete Post context without reviving cleared fields

    @MainActor
    func testRemotePostOmittingFieldsPreservesLocalQuestionsAndMarkerInCache() async throws {
        var local = makePostEntry()
        var draft = PostEntryDraft(entry: local)
        let editedField = "What changed in my understanding?\n\nMy exact answer.  \nAnother paragraph.\n"
        draft.setAnswer(editedField, at: 0)
        draft.apply(to: &local)
        local.needsSync = false
        local.createdAt = Date(timeIntervalSince1970: 1_735_732_800)
        local.whenIAm = "My original situation...I like to keep my words."
        local.marksClearSignOfSuccess = true
        local.marksCompounding = false

        var remote = local
        remote.title = "A title updated remotely"
        remote.createdAt = local.createdAt.addingTimeInterval(86_400)
        remote.whenIAm = nil
        remote.marksClearSignOfSuccess = nil
        remote.marksCompounding = nil
        remote.postThemeID = nil
        remote.postThemeName = nil
        remote.postAnswers = nil
        // An omitted answer array cannot lend its format marker to the restored local array.
        remote.postAnswersContainQuestions = false

        let snapshots = try await refreshSnapshots(local: local, remote: remote)
        XCTAssertEqual(snapshots.upserts.count, 1, "Retained local context must be sent through the normal repository")
        let uploaded = try XCTUnwrap(snapshots.upserts.first)
        XCTAssertTrue(uploaded.needsSync, "Restoring absent cloud context must queue the repaired record for sync")
        for saved in [snapshots.merged, snapshots.cached, uploaded] {
            XCTAssertEqual(saved.title, remote.title, "Refresh must actually accept the remote record")
            XCTAssertEqual(saved.createdAt, local.createdAt, "An old gateway's new timestamp must not move the original Post")
            XCTAssertEqual(saved.whenIAm, local.whenIAm)
            XCTAssertEqual(saved.marksClearSignOfSuccess, local.marksClearSignOfSuccess)
            XCTAssertEqual(saved.marksCompounding, local.marksCompounding)
            XCTAssertEqual(saved.postThemeID, local.postThemeID)
            XCTAssertEqual(saved.postThemeName, local.postThemeName)
            XCTAssertEqual(saved.postAnswers, local.postAnswers)
            XCTAssertEqual(saved.postAnswersContainQuestions, true)
            XCTAssertEqual(PostEntryDraft(entry: saved).answers[0], editedField,
                           "Reopening a refreshed Post must not prepend its catalog question again")
        }
        XCTAssertFalse(snapshots.merged.needsSync, "Successful upload clears the pending state")
        XCTAssertFalse(snapshots.cached.needsSync, "The successful repair is persisted as synced")
    }

    @MainActor
    func testRemotePostWithLegacyLocalAnswersDoesNotInventAQuestionsMarker() async throws {
        let local = makePostEntry()
        var remote = local
        remote.postThemeID = nil
        remote.postThemeName = nil
        remote.postAnswers = nil
        remote.postAnswersContainQuestions = true

        let snapshots = try await refreshSnapshots(local: local, remote: remote)
        XCTAssertEqual(snapshots.upserts.count, 1, "Legacy answer-only context must also be re-sent when missing remotely")
        let uploaded = try XCTUnwrap(snapshots.upserts.first)
        XCTAssertEqual(uploaded.postAnswers, local.postAnswers)
        XCTAssertNil(uploaded.postAnswersContainQuestions)
        for saved in [snapshots.merged, snapshots.cached] {
            XCTAssertEqual(saved.postAnswers, local.postAnswers)
            XCTAssertNil(saved.postAnswersContainQuestions, "The marker follows the restored legacy answer array")
            XCTAssertEqual(PostEntryDraft(entry: saved).answers[0],
                           "What happened?\n\n" + (local.postAnswers?.first ?? ""))
        }
    }

    @MainActor
    func testRemotePostAnswersKeepTheirOwnFormatMarker() async throws {
        var local = makePostEntry()
        PostEntryDraft(entry: local).apply(to: &local)
        local.needsSync = false
        local.marksClearSignOfSuccess = true
        local.marksCompounding = false

        let markers: [Bool?] = [nil, false, true]
        for marker in markers {
            var remote = local
            remote.whenIAm = ""
            remote.marksClearSignOfSuccess = false
            remote.marksCompounding = true
            remote.postAnswersContainQuestions = marker
            remote.postAnswers = marker == true
                ? ["What did I notice remotely?\n\nA remote answer."]
                : ["A remote answer."]

            let snapshots = try await refreshSnapshots(local: local, remote: remote)
            XCTAssertTrue(snapshots.upserts.isEmpty, "Supplied remote answers must not trigger a repair upload")
            for saved in [snapshots.merged, snapshots.cached] {
                XCTAssertEqual(saved.whenIAm, "", "An explicit remote clear must not restore the local value")
                XCTAssertEqual(saved.marksClearSignOfSuccess, false)
                XCTAssertEqual(saved.marksCompounding, true)
                XCTAssertEqual(saved.postAnswers, remote.postAnswers)
                XCTAssertEqual(saved.postAnswersContainQuestions, marker,
                               "A supplied remote array must retain its own format, including absent/false markers")
                let expected = marker == true
                    ? "What did I notice remotely?\n\nA remote answer."
                    : "What happened?\n\nA remote answer."
                XCTAssertEqual(PostEntryDraft(entry: saved).answers[0], expected)
            }
        }
    }

    @MainActor
    func testRemoteKindChangeDoesNotRestorePostFields() async throws {
        var local = makePostEntry()
        PostEntryDraft(entry: local).apply(to: &local)
        local.needsSync = false

        for kind in [ReminderKind.reminder, .action, .event] {
            var remote = local
            remote.kind = kind
            remote.postThemeID = nil
            remote.postThemeName = nil
            remote.postAnswers = nil
            remote.postAnswersContainQuestions = nil

            let snapshots = try await refreshSnapshots(local: local, remote: remote)
            XCTAssertTrue(snapshots.upserts.isEmpty, "A remote type change must not re-upload cleared Post data")
            for saved in [snapshots.merged, snapshots.cached] {
                XCTAssertEqual(saved.kind, kind)
                XCTAssertNil(saved.postThemeID, "A remote \(kind.label) must not regain a Post theme")
                XCTAssertNil(saved.postThemeName)
                XCTAssertNil(saved.postAnswers, "A remote \(kind.label) must not regain Decide fields")
                XCTAssertNil(saved.postAnswersContainQuestions)
                XCTAssertEqual(saved.postQuestionAndAnswers, [])
            }
        }
    }

    private actor SnapshotReminderRepository: ReminderRepository {
        let snapshot: Reminder
        private(set) var upserts: [Reminder] = []
        init(snapshot: Reminder) { self.snapshot = snapshot }
        func ensureReady() async -> Bool { true }
        func fetchAll() async throws -> [Reminder] { [snapshot] }
        func upsert(_ reminder: Reminder) async throws { upserts.append(reminder) }
        func delete(id: UUID) async throws {}
    }

    private struct RefreshOfflineCandidateClient: CowboyCandidateSubmitting {
        struct Offline: Error {}
        func submit(_ payload: CowboyCandidateIntakePayload) async throws -> CowboyCandidateReceipt {
            throw Offline()
        }
    }

    @MainActor
    private func refreshSnapshots(local: Reminder, remote: Reminder) async throws -> (merged: Reminder, cached: Reminder, upserts: [Reminder]) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("post-refresh-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("reminders.json")
        XCTAssertFalse(local.needsSync, "The fixture must exercise remote merging rather than pending-local precedence")
        try JSONEncoder.recall.encode([local]).write(to: cacheURL)

        let repository = SnapshotReminderRepository(snapshot: remote)
        let store = ReminderStore(
            repo: repository,
            cacheURL: cacheURL,
            technicalCaptureStore: try TechnicalCaptureStore(fileURL: directory.appendingPathComponent("captures.json")),
            candidateOutbox: try CowboyCandidateOutbox(fileURL: directory.appendingPathComponent("outbox.json")),
            candidateClient: RefreshOfflineCandidateClient()
        )
        await store.refresh()

        let merged = try XCTUnwrap(store.reminders.first { $0.id == local.id })
        let cachedEntries = try JSONDecoder.recall.decode([Reminder].self, from: Data(contentsOf: cacheURL))
        let cached = try XCTUnwrap(cachedEntries.first { $0.id == local.id })
        return (merged, cached, await repository.upserts)
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
