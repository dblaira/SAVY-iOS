import XCTest
@testable import SAVY

final class SAVYVisualTemplateTests: XCTestCase {
    func testApprovedFormatsHaveFourRowsAndMatricesStartsSelected() {
        XCTAssertEqual(VisualTemplateCatalog.formats.map(\.name), [
            "Summarize", "Tables", "Matrices", "Node Trees", "Graphic Imagery",
            "Slides", "Charts", "Images", "Video", "Audio", "Music", "Example"
        ])
        XCTAssertTrue(VisualTemplateCatalog.formats.allSatisfy { $0.questions.count == 4 })
        XCTAssertTrue(VisualTemplateCatalog.formats.prefix(5).allSatisfy { $0.questions.allSatisfy { !$0.isEmpty } })
        XCTAssertTrue(VisualTemplateCatalog.formats.dropFirst(5).allSatisfy { $0.questions.allSatisfy(\.isEmpty) })
        let draft = VisualTemplateDraft()
        XCTAssertEqual(draft.selectedFormatID, "Matrices")
        XCTAssertEqual(draft.questions[0], "What relationship should this matrix make clear?")
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
        draft.selectFormat("Matrices")
        draft.setAnswer("Known Format writing", at: 0)
        var restored = try JSONDecoder().decode(VisualTemplateDraft.self, from: JSONEncoder().encode(draft))
        restored.selectFormat("Future Format")
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
        XCTAssertTrue(text.contains("What relationship should this matrix make clear?\n" + answer("Matrices", 0)))
        XCTAssertTrue(text.contains("Why would a table help explain this?\n" + answer("Tables", 0)))
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
