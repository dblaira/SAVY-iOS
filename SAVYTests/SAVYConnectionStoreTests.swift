import XCTest
@testable import SAVY

final class SAVYConnectionStoreTests: XCTestCase {
    @MainActor
    func testNewlyPinnedConnectionsMoveAboveExistingPinsAndKeepSeparatePostOrder() throws {
        let suite = "connection-pin-order-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let postIDs = ["entry-post-a", "legacy-post-b", "entry-post-c"]
        let postPins: Set<String> = ["entry-post-a"]
        let posts = PostCardOrderStore(defaults: defaults)
        XCTAssertTrue(posts.move("entry-post-c", direction: -1, defaultOrder: postIDs, pinnedIDs: postPins))
        let originalPostOrder = posts.orderedIDs(defaultOrder: postIDs, pinnedIDs: postPins)
        let originalPostPreference = defaults.stringArray(forKey: PostCardOrderStore.defaultsKey)

        let connectionKey = "savy.connections.cardOrder.v1"
        let connections = PostCardOrderStore(defaults: defaults, key: connectionKey)
        let ids = ["source-a", "source-b", "entry-c", "source-d", "source-e"]
        var pins: Set<String> = ["source-a", "source-b"]
        XCTAssertEqual(connections.orderedIDs(defaultOrder: ids, pinnedIDs: pins), ids)

        pins.insert("source-d")
        connections.moveToFrontOfPinGroup("source-d", defaultOrder: ids, pinnedIDs: pins)
        XCTAssertEqual(connections.orderedIDs(defaultOrder: ids, pinnedIDs: pins),
                       ["source-d", "source-a", "source-b", "entry-c", "source-e"])

        pins.insert("source-e")
        connections.moveToFrontOfPinGroup("source-e", defaultOrder: ids, pinnedIDs: pins)
        XCTAssertEqual(connections.orderedIDs(defaultOrder: ids, pinnedIDs: pins),
                       ["source-e", "source-d", "source-a", "source-b", "entry-c"])

        pins.remove("source-d")
        connections.moveToFrontOfPinGroup("source-d", defaultOrder: ids, pinnedIDs: pins)
        let expected = ["source-e", "source-a", "source-b", "source-d", "entry-c"]
        XCTAssertEqual(connections.orderedIDs(defaultOrder: ids, pinnedIDs: pins), expected)
        let reopened = PostCardOrderStore(defaults: defaults, key: connectionKey)
        XCTAssertEqual(reopened.orderedIDs(defaultOrder: ids, pinnedIDs: pins), expected)
        XCTAssertEqual(defaults.stringArray(forKey: PostCardOrderStore.defaultsKey), originalPostPreference)
        XCTAssertEqual(PostCardOrderStore(defaults: defaults).orderedIDs(defaultOrder: postIDs, pinnedIDs: postPins),
                       originalPostOrder)
    }

    @MainActor
    func testCompleteMetadataAndEditedQuestionsSurviveSaveEditAndRelaunch() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("connections.json")
        let store = ConnectionStore(fileURL: fileURL, launchArguments: [])
        let original = completeEntry()
        XCTAssertTrue(store.save(original))
        let saved = try XCTUnwrap(store.entries.first)

        var expected = original
        expected.postThemeID = ConnectionEntry.theme.id
        expected.postThemeName = ConnectionEntry.theme.name
        expected.updatedAt = saved.metadata.updatedAt
        XCTAssertEqual(saved.metadata, expected)
        let reloaded = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertEqual(reloaded.entries.first?.metadata, try cacheNormalized(expected))
        XCTAssertEqual(reloaded.entries.first?.metadata.postAnswers, original.postAnswers)

        var edited = try XCTUnwrap(reloaded.entries.first?.metadata)
        edited.postAnswers?[2] = "My new question?\n\nMy exact revised connection.  \nA second paragraph.\n"
        edited.notes = "A revised note — all metadata stays with the connection."
        XCTAssertTrue(reloaded.save(edited))
        let editedSaved = try XCTUnwrap(reloaded.entries.first)
        let reopened = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertEqual(reopened.entries.count, 1)
        XCTAssertEqual(reopened.entries.first?.metadata, try cacheNormalized(editedSaved.metadata))
        XCTAssertEqual(reopened.entries.first?.metadata.postAnswers, edited.postAnswers)
        XCTAssertEqual(reopened.entries.first?.metadata.createdAt, original.createdAt)
        XCTAssertEqual(reopened.entries.first?.preview.title, "My exact revised connection.")
    }

    @MainActor
    func testAuthoredAndSourcePinsPersistWithoutChangingAuthoredWords() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("connections.json")
        let store = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertTrue(store.save(completeEntry()))
        let original = try XCTUnwrap(store.entries.first)
        XCTAssertFalse(original.metadata.pinned)
        XCTAssertTrue(store.togglePin(original))
        XCTAssertTrue(store.sourcePinned(id: "original-first", defaultValue: true))
        XCTAssertTrue(store.setSourcePinned(id: "original-first", isPinned: false))
        XCTAssertTrue(store.setSourcePinned(id: "another-source", isPinned: true))

        let reopened = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertTrue(try XCTUnwrap(reopened.entries.first).metadata.pinned)
        XCTAssertEqual(reopened.entries.first?.metadata.postAnswers, original.metadata.postAnswers)
        XCTAssertEqual(reopened.entries.first?.metadata.updatedAt, try cacheNormalized(original.metadata).updatedAt)
        XCTAssertFalse(reopened.sourcePinned(id: "original-first", defaultValue: true))
        XCTAssertTrue(reopened.sourcePinned(id: "another-source", defaultValue: false))
        XCTAssertFalse(reopened.sourcePinned(id: "unknown-source", defaultValue: false))
        XCTAssertTrue(reopened.delete(try XCTUnwrap(reopened.entries.first)))
        let afterDelete = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertTrue(afterDelete.entries.isEmpty)
        XCTAssertFalse(afterDelete.sourcePinned(id: "original-first", defaultValue: true))
    }

    @MainActor
    func testMalformedArchiveIsPreservedAndCannotBeOverwritten() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("connections.json")
        let originalData = Data("The original file needs recovery".utf8)
        try originalData.write(to: fileURL)
        let store = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.save(completeEntry()))
        XCTAssertFalse(store.setSourcePinned(id: "source", isPinned: true))
        XCTAssertFalse(store.deleteSource(id: "source"))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.hiddenSourceIDs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
    }

    @MainActor
    func testWriteFailureDoesNotPublishAnUnsavedEntry() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockedParent = directory.appendingPathComponent("not-a-directory")
        try Data("keep this file".utf8).write(to: blockedParent)
        let store = ConnectionStore(fileURL: blockedParent.appendingPathComponent("connections.json"), launchArguments: [])
        XCTAssertFalse(store.save(completeEntry()))
        XCTAssertFalse(store.deleteSource(id: "source"))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.hiddenSourceIDs.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try String(contentsOf: blockedParent, encoding: .utf8), "keep this file")
    }

    @MainActor
    func testTestResetCannotEraseCallerSuppliedNonisolatedArchive() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("connections.json")
        let initial = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertTrue(initial.save(completeEntry()))
        let originalData = try Data(contentsOf: fileURL)
        let reopened = ConnectionStore(
            fileURL: fileURL,
            launchArguments: ["SAVY_UI_TEST_UNLOCKED", "SAVY_UI_TEST_RESET_REMINDERS"]
        )
        XCTAssertEqual(reopened.entries.count, 1)
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
        XCTAssertNotEqual(ConnectionStore.isolatedFileURL, ConnectionStore.defaultFileURL)
        XCTAssertTrue(ConnectionStore.isolatedFileURL.path.contains("SAVYUITests/connections.json"))
    }

    @MainActor
    func testConnectionPersistenceCreatesOnlyItsArchiveAndNoSyncMetadata() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("connections.json")
        let store = ConnectionStore(fileURL: fileURL, launchArguments: [])
        var input = completeEntry()
        input.kind = .post
        input.postNumber = 17
        input.needsSync = true
        XCTAssertTrue(store.save(input))
        let saved = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(saved.metadata.kind, .reminder)
        XCTAssertNil(saved.metadata.postNumber)
        XCTAssertFalse(saved.metadata.needsSync)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["connections.json"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["entries", "sourcePins", "hiddenSourceIDs"])
    }

    @MainActor
    func testOlderArchiveWithoutHiddenSourceIDsKeepsEntriesAndPins() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("connections.json")
        let original = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertTrue(original.save(completeEntry()))
        XCTAssertTrue(original.setSourcePinned(id: "old-source", isPinned: false))
        let saved = try XCTUnwrap(original.entries.first)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        legacy.removeValue(forKey: "hiddenSourceIDs")
        try JSONSerialization.data(withJSONObject: legacy).write(to: fileURL)

        let reopened = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertNil(reopened.errorMessage)
        XCTAssertTrue(reopened.hiddenSourceIDs.isEmpty)
        XCTAssertEqual(reopened.entries.first?.metadata, try cacheNormalized(saved.metadata))
        XCTAssertEqual(reopened.sourcePinOverrides, ["old-source": false])
        XCTAssertTrue(reopened.deleteSource(id: "old-source"))
        let migrated = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertEqual(migrated.hiddenSourceIDs, ["old-source"])
        XCTAssertEqual(migrated.entries.first?.metadata, try cacheNormalized(saved.metadata))
        XCTAssertEqual(migrated.sourcePinOverrides, ["old-source": false])
    }

    @MainActor
    func testSourceDeletionPersistsWithoutChangingAuthoredWordsAndSurvivesOtherWrites() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("connections.json")
        let store = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertTrue(store.save(completeEntry()))
        let saved = try XCTUnwrap(store.entries.first)
        XCTAssertTrue(store.setSourcePinned(id: "source-to-remove", isPinned: true))
        XCTAssertTrue(store.deleteSource(id: "source-to-remove"))
        XCTAssertEqual(store.entries, [saved])
        XCTAssertEqual(store.hiddenSourceIDs, ["source-to-remove"])
        XCTAssertEqual(store.sourcePinOverrides, ["source-to-remove": true])

        let reopened = ConnectionStore(fileURL: fileURL, launchArguments: [])
        let entry = try XCTUnwrap(reopened.entries.first)
        XCTAssertEqual(entry.metadata, try cacheNormalized(saved.metadata))
        XCTAssertEqual(reopened.hiddenSourceIDs, ["source-to-remove"])
        XCTAssertTrue(reopened.save(entry.metadata))
        XCTAssertTrue(reopened.togglePin(try XCTUnwrap(reopened.entries.first)))
        XCTAssertTrue(reopened.setSourcePinned(id: "other-source", isPinned: false))
        XCTAssertTrue(reopened.delete(try XCTUnwrap(reopened.entries.first)))

        let afterOtherWrites = ConnectionStore(fileURL: fileURL, launchArguments: [])
        XCTAssertTrue(afterOtherWrites.entries.isEmpty)
        XCTAssertEqual(afterOtherWrites.hiddenSourceIDs, ["source-to-remove"])
        XCTAssertEqual(afterOtherWrites.sourcePinOverrides, ["source-to-remove": true, "other-source": false])
    }

    func testConnectionThemeHasExactPromptsAndPreviewPrefersNewConnection() {
        XCTAssertEqual(ConnectionEntry.theme.questions.map(\.prompt), [
            "What did you believe before?",
            "What experience changed or confirmed your connection?",
            "What do you believe now? What is the new connection?",
            "What do you do differently because of it?",
        ])
        let entry = ConnectionEntry(metadata: completeEntry())
        XCTAssertEqual(entry.preview.title, "Volume is where patterns can be seen.")
        XCTAssertEqual(entry.answers.count, 4)
        XCTAssertEqual(entry.metadata.postAnswers?[0], "What did I actually believe?\n\nMy exact old belief.  \n")
        XCTAssertEqual(PostThemeCatalog.theme(id: "your-personal-take-lessons-learned")?.questions[1].prompt,
                       "What experience changed or confirmed your view?")
    }

    func testFixedConnectionThemeKeepsEditedFieldsAndDoesNotChangePostChoices() {
        let original = completeEntry()
        var draft = PostEntryDraft(entry: original, fixedTheme: ConnectionEntry.theme)
        XCTAssertEqual(draft.theme, ConnectionEntry.theme)
        XCTAssertEqual(draft.answers, original.postAnswers)
        draft.selectTheme("five-ws")
        XCTAssertEqual(draft.theme, ConnectionEntry.theme)
        let editedField = "My own question?\n\nMy answer stays exactly this way.  \n"
        draft.setAnswer(editedField, at: 2)
        var result = original
        draft.apply(to: &result)
        XCTAssertEqual(result.postAnswers?[2], editedField)
        XCTAssertEqual(PostEntryDraft(entry: result, fixedTheme: ConnectionEntry.theme).answers, result.postAnswers)

        let blank = PostEntryDraft(entry: Reminder(), fixedTheme: ConnectionEntry.theme)
        XCTAssertEqual(blank.answers, ConnectionEntry.theme.prefilledAnswers)
        XCTAssertFalse(blank.hasUserContent)
        XCTAssertEqual(PostThemeCatalog.themes.count, 28)
        XCTAssertNil(PostThemeCatalog.theme(id: ConnectionEntry.theme.id))
        XCTAssertEqual(ReminderKind.allCases, [.reminder, .action, .event, .post])
        XCTAssertEqual(PostEntryDraft(entry: Reminder()).theme, PostThemeCatalog.defaultTheme)
    }

    @MainActor
    func testLegacyAnswerOnlyFieldsAcquireQuestionsOnceAndTagsAreAvailable() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConnectionStore(fileURL: directory.appendingPathComponent("connections.json"), launchArguments: [])
        var entry = completeEntry()
        entry.postAnswersContainQuestions = nil
        entry.postAnswers = ["  Before.  ", "Experience.", "New connection.", "Action."]
        XCTAssertTrue(store.save(entry))
        let first = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(first.metadata.postAnswers?[0], ConnectionEntry.theme.questions[0].prompt + "\n\n  Before.  ")
        XCTAssertTrue(store.save(first.metadata))
        XCTAssertEqual(store.entries.first?.metadata.postAnswers, first.metadata.postAnswers)
        XCTAssertEqual(store.recentTags, ["breadth", "patterns"])
    }

    private func completeEntry() -> Reminder {
        var value = Reminder()
        value.title = "Connections across ideas"
        value.notes = "An exact note.  \nWith another line."
        value.url = "https://example.com/reference"
        value.imageLocalPath = "saved-image.jpg"
        value.dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        value.dueTime = Date(timeIntervalSince1970: 1_800_001_000)
        value.endTime = Date(timeIntervalSince1970: 1_800_002_000)
        value.urgent = true
        value.repeatRule = .weekly
        value.listName = "Learning"
        value.flag = true
        value.priority = .high
        value.whenIAm = "When I see many examples...I like to find the pattern.  "
        value.outcome = "A connection I can use again."
        value.effort = .h1
        value.energy = .high
        value.context = .compound
        value.marksClearSignOfSuccess = true
        value.marksCompounding = false
        value.deferDate = Date(timeIntervalSince1970: 1_700_000_000)
        value.waitingOn = "My next observation"
        value.locationName = "At home"
        value.postThemeID = ConnectionEntry.theme.id
        value.postThemeName = ConnectionEntry.theme.name
        value.postAnswers = [
            "What did I actually believe?\n\nMy exact old belief.  \n",
            ConnectionEntry.theme.questions[1].prompt + "\n\nFifty examples changed my view.",
            ConnectionEntry.theme.questions[2].prompt + "\n\nVolume is where patterns can be seen. A second sentence.",
            ConnectionEntry.theme.questions[3].prompt + "\n\nKeep collecting connections.",
        ]
        value.postAnswersContainQuestions = true
        value.seededFromTemplateID = "a-retained-template"
        value.upNextOrder = 3
        value.tags = ["patterns", "breadth"]
        value.subtasks = [Subtask(title: "Keep the exact words", done: true), Subtask(title: "Explore another idea")]
        value.status = .active
        value.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        value.updatedAt = Date(timeIntervalSince1970: 1_700_000_010)
        return value
    }

    private func cacheNormalized(_ value: Reminder) throws -> Reminder {
        try JSONDecoder.recall.decode(Reminder.self, from: JSONEncoder.recall.encode(value))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("connection-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
