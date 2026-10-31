import XCTest
@testable import SAVY

final class SAVYVisualTemplateTests: XCTestCase {
    func testApprovedFormatsHaveFourRowsAndMatricesStartsSelected() {
        XCTAssertEqual(VisualTemplateCatalog.formats.map(\.name), [
            "Summarize", "Tables", "Matrices", "Node Trees", "Graphic Imagery",
            "Slides", "Charts", "Images", "Video", "Audio", "Music", "Example"
        ])
        XCTAssertTrue(VisualTemplateCatalog.formats.allSatisfy { $0.questions.count == 4 })
        XCTAssertTrue(VisualTemplateCatalog.formats.allSatisfy { $0.questions.allSatisfy { !$0.isEmpty } })
        let draft = VisualTemplateDraft()
        XCTAssertEqual(draft.selectedFormatID, "Matrices")
        XCTAssertEqual(draft.questions[0], "What goes across the top?")
        XCTAssertEqual(draft.answers, ["", "", "", ""])
        XCTAssertFalse(draft.hasUserContent, "The question labels are not user writing")
    }

    func testAllFormatsRetainExactLongAnswersAcrossSwitchingAndCodable() throws {
        var draft = VisualTemplateDraft()
        for format in VisualTemplateCatalog.formats {
            draft.selectFormat(format.id)
            for index in 0..<4 { draft.setAnswer(answer(format.id, index), at: index) }
        }
        var restored = try JSONDecoder().decode(VisualTemplateDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft)
        for format in VisualTemplateCatalog.formats {
            restored.selectFormat(format.id)
            XCTAssertEqual(restored.questions, format.questions)
            XCTAssertEqual(restored.answers, (0..<4).map { answer(format.id, $0) })
        }
        restored.selectFormat("Matrices")
        for index in 0..<4 { restored.setAnswer("", at: index) }
        XCTAssertTrue(restored.hasUserContent, "Writing in another Format must keep an unfinished entry recoverable")
    }

    func testEveryEntryKindRoundTripsWithoutChangingExistingWriting() throws {
        for kind in ReminderKind.allCases {
            var entry = Reminder()
            entry.kind = kind
            entry.title = "Existing title  \n"
            entry.notes = "Notes stay exactly as written."
            entry.visualTemplates = populatedDraft()
            let restored = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(entry))
            XCTAssertEqual(restored, entry)
        }
        var metadata = Reminder()
        metadata.visualTemplates = populatedDraft()
        let connection = ConnectionEntry(metadata: metadata)
        XCTAssertEqual(try JSONDecoder().decode(ConnectionEntry.self, from: JSONEncoder().encode(connection)), connection)
    }

    func testOldEntriesWithoutVisualTemplatesDecodeUnchanged() throws {
        var entry = Reminder()
        entry.title = "Saved before Visual templates"
        entry.postAnswers = ["An existing answer\n  Still here.  "]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        json.removeValue(forKey: "visualTemplates")
        let data = try JSONSerialization.data(withJSONObject: json)
        let restored = try JSONDecoder().decode(Reminder.self, from: data)
        XCTAssertEqual(restored, entry)
        XCTAssertNil(restored.visualTemplates)
    }

    func testUnknownFormatAndAdditionalFieldsSurviveEditingKnownFormats() throws {
        let data = Data("""
        {"selectedFormatID":"Future Format","fieldsByFormat":{"Future Format":[
          {"question":"Saved question?","answer":"  Exact future writing.\\nSecond line.  "},
          {"question":"","answer":""},{"question":"","answer":""},{"question":"","answer":""},
          {"question":"Additional question?","answer":"Additional writing must survive."}
        ]}}
        """.utf8)
        var draft = try JSONDecoder().decode(VisualTemplateDraft.self, from: data)
        XCTAssertEqual(draft.format.name, "Future Format")
        XCTAssertEqual(draft.questions, ["Saved question?", "", "", ""])
        draft.selectFormat("Matrices")
        draft.setAnswer("Known Format writing", at: 0)
        var restored = try JSONDecoder().decode(VisualTemplateDraft.self, from: JSONEncoder().encode(draft))
        restored.selectFormat("Future Format")
        XCTAssertEqual(restored.questions, ["Saved question?", "", "", ""])
        XCTAssertEqual(restored.answers[0], "  Exact future writing.\nSecond line.  ")
        XCTAssertTrue(restored.shareText.contains("Additional question?\nAdditional writing must survive."))
        XCTAssertTrue(restored.shareText.contains("Known Format writing"))
    }

    func testLegacyMergeKeepsVisualWritingAndNewerRemoteDelegateWriting() {
        var local = Reminder()
        local.visualTemplates = populatedDraft()
        var remote = local
        remote.visualTemplates = nil
        remote.title = "Newer remote title"
        remote.needsSync = false
        let merged = ReminderScheduleSync.merging(remote: remote, local: local)
        XCTAssertEqual(merged.title, remote.title)
        XCTAssertEqual(merged.visualTemplates, local.visualTemplates)
        XCTAssertTrue(merged.needsSync)

        remote.visualTemplates = VisualTemplateDraft()
        let cleared = ReminderScheduleSync.merging(remote: remote, local: local)
        XCTAssertEqual(cleared.visualTemplates, remote.visualTemplates)
        XCTAssertFalse(cleared.visualTemplates?.hasUserContent ?? true,
                       "An explicitly empty draft must clear old answers instead of resurrecting them")
        remote.visualTemplates = nil
        XCTAssertNil(ReminderScheduleSync.merging(remote: remote, local: nil).visualTemplates)
    }

    func testEntireFormShareIncludesEveryExploredFormatInOrderWithoutMutation() throws {
        var entry = Reminder()
        entry.postThemeID = "habit"
        entry.postAnswers = ["Existing Decide writing"]
        entry.title = "Existing Delegate writing"
        entry.visualTemplates = populatedDraft()
        let before = entry
        let text = EntryShareContent(entry: entry, sourceApp: "SAVY", entryLabel: "Action", whenIAm: "").entireForm
        let decide = try XCTUnwrap(text.range(of: "Decide\n\n"))
        let visual = try XCTUnwrap(text.range(of: "Visual templates\n\nFormat: Tables"))
        let delegate = try XCTUnwrap(text.range(of: "Delegate\n\n"))
        XCTAssertLessThan(decide.lowerBound, visual.lowerBound)
        XCTAssertLessThan(visual.lowerBound, delegate.lowerBound)
        XCTAssertTrue(text.contains("What goes across the top?\n" + answer("Matrices", 0)))
        XCTAssertTrue(text.contains("What am I comparing?\n" + answer("Tables", 0)))
        XCTAssertEqual(entry, before)
        entry.visualTemplates = nil
        XCTAssertFalse(EntryShareContent(entry: entry, sourceApp: "SAVY", entryLabel: "Action", whenIAm: "").entireForm.contains("Visual templates"))
    }

    private func populatedDraft() -> VisualTemplateDraft {
        var draft = VisualTemplateDraft()
        draft.setAnswer(answer("Matrices", 0), at: 0)
        draft.selectFormat("Tables")
        draft.setAnswer(answer("Tables", 0), at: 0)
        return draft
    }

    private func answer(_ format: String, _ index: Int) -> String {
        "  \(format) answer \(index) — “exact words” 🧠\n\n" + String(repeating: "Long writing stays visible.\n", count: 40) + "  Last line.  "
    }
}

final class SAVYVisualTemplateBackfillTests: XCTestCase {
    func testLegacyEmptyMediaPromptsBackfillWithoutMutatingSavedDrafts() throws {
        for id in ["Slides", "Charts", "Images", "Video", "Audio", "Music", "Example"] {
            let fields = Array(repeating: ["question": "", "answer": ""], count: 4)
            let draft = try legacyDraft(id: id, fields: fields)
            let before = draft
            let approved = try XCTUnwrap(VisualTemplateCatalog.format(id: id))

            XCTAssertEqual(draft.selectedFormatID, id)
            XCTAssertEqual(draft.questions, approved.questions)
            XCTAssertEqual(draft.answers, ["", "", "", ""])
            XCTAssertFalse(draft.hasUserContent)
            for question in approved.questions {
                XCTAssertTrue(draft.shareText.contains(question))
            }
            XCTAssertEqual(draft, before, "Reading or sharing must not rewrite the saved draft")
            XCTAssertEqual(try storedFields(in: draft, id: id), fields)

            let restored = try JSONDecoder().decode(VisualTemplateDraft.self, from: JSONEncoder().encode(draft))
            XCTAssertEqual(restored.questions, approved.questions)
            XCTAssertEqual(try storedFields(in: restored, id: id), fields)
        }
    }

    func testBackfillPreservesEveryExistingQuestionAndAnswerExactly() throws {
        let fields = [
            ["question": "", "answer": "  Writing without a prompt.\nSecond line. 🧠  "],
            ["question": "My saved question?", "answer": ""],
            ["question": "", "answer": ""],
            ["question": " \n ", "answer": "\t  "]
        ]
        var draft = try legacyDraft(id: "Slides", fields: fields)
        let approved = try XCTUnwrap(VisualTemplateCatalog.format(id: "Slides"))
        XCTAssertEqual(draft.questions, ["", "My saved question?", approved.questions[2], " \n "])
        XCTAssertEqual(draft.answers, fields.map { $0["answer"]! })

        draft.setAnswer("New writing below the new question.", at: 2)
        let restored = try JSONDecoder().decode(VisualTemplateDraft.self, from: JSONEncoder().encode(draft))
        let stored = try storedFields(in: restored, id: "Slides")
        for index in [0, 1, 3] {
            XCTAssertEqual(stored[index], fields[index], "Backfill replaced saved text at index \(index)")
        }
        XCTAssertEqual(stored[2], ["question": approved.questions[2], "answer": "New writing below the new question."])
        XCTAssertTrue(restored.shareText.contains(fields[0]["answer"]!))
    }

    func testWhitespaceOnlyQuestionsAndAnswersRemainSavedText() throws {
        let fields = [
            ["question": " \n ", "answer": ""],
            ["question": "", "answer": "\t \n"],
            ["question": "\t", "answer": " \n "],
            ["question": "", "answer": ""]
        ]
        var draft = try legacyDraft(id: "Charts", fields: fields)
        let approved = try XCTUnwrap(VisualTemplateCatalog.format(id: "Charts"))
        XCTAssertEqual(draft.questions, [" \n ", "", "\t", approved.questions[3]])
        XCTAssertEqual(draft.answers, fields.map { $0["answer"]! })

        draft.setAnswer("New context.", at: 3)
        let stored = try storedFields(in: draft, id: "Charts")
        XCTAssertEqual(Array(stored.prefix(3)), Array(fields.prefix(3)))
        XCTAssertEqual(stored[3], ["question": approved.questions[3], "answer": "New context."])
    }

    func testBackfillPadsKnownShortDraftsAndPreservesAdditionalFields() throws {
        let approved = try XCTUnwrap(VisualTemplateCatalog.format(id: "Video"))
        var short = try legacyDraft(id: "Video", fields: [["question": "", "answer": ""]])
        XCTAssertEqual(short.questions, approved.questions)
        XCTAssertEqual(short.answers, ["", "", "", ""])
        short.setAnswer("Writing in the fourth slot.", at: 3)
        let restoredShort = try JSONDecoder().decode(VisualTemplateDraft.self, from: JSONEncoder().encode(short))
        XCTAssertEqual(restoredShort.questions, approved.questions)
        XCTAssertEqual(restoredShort.answers, ["", "", "", "Writing in the fourth slot."])

        let extras = [
            ["question": "Additional question?", "answer": "  Additional writing.\n  "],
            ["question": "", "answer": ""]
        ]
        var extended = try legacyDraft(id: "Video", fields: Array(repeating: ["question": "", "answer": ""], count: 4) + extras)
        extended.setAnswer("New first answer.", at: 0)
        let restoredExtended = try JSONDecoder().decode(VisualTemplateDraft.self, from: JSONEncoder().encode(extended))
        XCTAssertEqual(Array(try storedFields(in: restoredExtended, id: "Video").dropFirst(4)), extras)
        XCTAssertTrue(restoredExtended.shareText.contains("Additional question?\n  Additional writing.\n  "))
    }

    private func legacyDraft(id: String, fields: [[String: String]]) throws -> VisualTemplateDraft {
        let payload: [String: Any] = ["selectedFormatID": id, "fieldsByFormat": [id: fields]]
        return try JSONDecoder().decode(VisualTemplateDraft.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    private func storedFields(in draft: VisualTemplateDraft, id: String) throws -> [[String: String]] {
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        let formats = try XCTUnwrap(payload["fieldsByFormat"] as? [String: [[String: String]]])
        return try XCTUnwrap(formats[id])
    }

}

@MainActor
final class SAVYVisualTemplateRecoveryTests: XCTestCase {
    func testAllExploredFormatsRestoreFromPrivateDraftWithoutSavingAnEntry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("drafts.json")
        var entry = Reminder()
        var visual = VisualTemplateDraft()
        visual.setAnswer("  Matrix writing\nSecond line.  ", at: 0)
        visual.selectFormat("Node Trees")
        visual.setAnswer("Tree writing\n\nLast line.", at: 3)
        entry.visualTemplates = visual
        let writing = EntryRecoveryDraft.ReminderWriting(original: nil, entry: entry,
            questions: PostEntryDraft(entry: entry), subtasks: [], tagDraft: "",
            imageData: nil, connectionMode: false)
        XCTAssertTrue(EntryDraftStore(fileURL: file).save(id: "visual-draft", contents: .reminder(writing)))
        guard case .reminder(let restored) = EntryDraftStore(fileURL: file).latest?.contents else {
            return XCTFail("Private draft did not restore")
        }
        XCTAssertEqual(restored, writing)
        var restoredVisual = try XCTUnwrap(restored.entry.visualTemplates)
        XCTAssertEqual(restoredVisual.selectedFormatID, "Node Trees")
        XCTAssertEqual(restoredVisual.answers[3], "Tree writing\n\nLast line.")
        restoredVisual.selectFormat("Matrices")
        XCTAssertEqual(restoredVisual.answers[0], "  Matrix writing\nSecond line.  ")
    }
}
