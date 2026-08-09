import XCTest
import UIKit
@testable import SAVY

final class SAVYNativeBoundaryTests: XCTestCase {
    func testCowboyAIRequestPreservesSavyWordsAndAuthorityBoundary() throws {
        let exactWords = """
        What do I want?
        Use SAVY every day.

        When I am...I like to
        Sharpen the plan before I work.

        Done looks like...
        CowboyAI returns the next action inside SAVY.
        """
        let request = SavyCowboyAIRequest(
            requestID: "request-1",
            conversationID: "conversation-1",
            rawWords: exactWords
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["raw_words"] as? String, exactWords)
        XCTAssertEqual(json["current_app_surface"] as? String, "savy_ios")
        XCTAssertEqual(json["requested_operation"] as? String, "reason")
        XCTAssertEqual(json["attachments"] as? [String], [])
        XCTAssertNil(json["adam_directly_asserted"], "A SAVY request must not approve authority")
    }

    func testCowboyAIAnswerDecodesUsefulResultAndReceipt() throws {
        let data = """
        {
          "request_id": "request-1",
          "conversation_id": "conversation-1",
          "adam_facing_story": {
            "story": "The work is ready to begin.",
            "why_it_matters": "The next action is visible.",
            "what_changes_now": "Open SAVY and start the first step."
          },
          "final_answer": "Complete the smallest unfinished action.",
          "route": "self_hosted_graph_plus_qwen",
          "graph_revision": "revision-1"
        }
        """.data(using: .utf8)!

        let answer = try JSONDecoder().decode(SavyCowboyAIAnswer.self, from: data)

        XCTAssertEqual(answer.whatChangesNow, "Open SAVY and start the first step.")
        XCTAssertEqual(answer.finalAnswer, "Complete the smallest unfinished action.")
        XCTAssertTrue(answer.noteText.contains(answer.finalAnswer))
        XCTAssertEqual(answer.graphRevision, "revision-1")
    }

    func testPersonalAuthorityFormatterPreservesDelegationHierarchy() {
        let blocks = PersonalAuthorityTextFormatter.blocks(from: """
        What I want?
        Objective proof I know how to update my ontology.
        How I think about it?
        Standardize before optimizing.
        Objective Measurements: The task flow is unconscious.
        """)

        XCTAssertEqual(
            blocks.map(\.style),
            [.heading, .body, .heading, .body, .heading, .body]
        )
        XCTAssertEqual(blocks[0].text, "What I want?")
        XCTAssertEqual(blocks[4].text, "Objective Measurements:")
        XCTAssertEqual(blocks[5].text, "The task flow is unconscious.")
    }

    func testPersonalAuthorityPayloadKeepsCandidatesOutsideAcceptedAuthority() throws {
        let data = """
        {
          "generatedAt": "2026-07-17",
          "candidateCount": 1,
          "candidates": [{
            "index": 1,
            "id": "candidate-1",
            "text": "What I want?\\nA dependable personal model.",
            "source": "cursor-data-export",
            "sourceHash": "hash",
            "signalScore": 13,
            "reason": "first-person judgment",
            "reviewStatus": "unreviewed",
            "authorityStatus": "candidate-only"
          }]
        }
        """.data(using: .utf8)!

        let payload = try PersonalAuthorityReviewStore.decodeCandidates(from: data)

        XCTAssertEqual(payload.candidateCount, 1)
        XCTAssertEqual(payload.candidates.first?.authorityStatus, "candidate-only")
        XCTAssertEqual(payload.candidates.first?.sourceLabel, "Cursor")
    }

    func testPersonalAuthorityConferenceRemovesCursorSystemPrefixWithoutChangingAdamWords() {
        let text = """
        <system_reminder>
        IMPORTANT: injected Cursor instruction.
        </system_reminder>
        These are Adam's exact words.
        """

        XCTAssertTrue(PersonalAuthorityConferenceClassifier.containsInjectedSystemPrefix(text))
        XCTAssertEqual(
            PersonalAuthorityConferenceClassifier.authoredText(from: text),
            "These are Adam's exact words."
        )
    }

    func testPersonalAuthorityConferenceFlagsEmbeddedSourceMaterial() {
        XCTAssertEqual(
            PersonalAuthorityConferenceClassifier.status(for: "I especially like these suggestions: quoted material"),
            .sourceCheck
        )
        XCTAssertEqual(
            PersonalAuthorityConferenceClassifier.status(for: "I know what I believe and I said it directly."),
            .ready
        )
    }

    @MainActor
    func testPersonalAuthorityApprovalIsExplicitAndPersists() throws {
        let suiteName = "SAVYNativeBoundaryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PersonalAuthorityReviewStore(defaults: defaults)
        let directCount = store.candidates.filter { $0.conferenceStatus == .ready }.count
        XCTAssertEqual(store.approvedCount, directCount)

        let candidate = try XCTUnwrap(
            store.candidates.first { $0.conferenceStatus == .sourceCheck }
        )

        store.decide(.mine, candidate: candidate)

        XCTAssertEqual(store.decision(for: candidate), .mine)
        XCTAssertEqual(store.approvedCount, directCount + 1)
        XCTAssertEqual(store.disapprovedCount, 0)
        XCTAssertEqual(store.decidedCount, directCount + 1)

        let reloadedStore = PersonalAuthorityReviewStore(defaults: defaults)
        let reloadedCandidate = try XCTUnwrap(
            reloadedStore.candidates.first { $0.id == candidate.id }
        )
        XCTAssertEqual(reloadedStore.decision(for: reloadedCandidate), .mine)

        reloadedStore.decide(.evidenceOnly, candidate: reloadedCandidate)
        XCTAssertEqual(reloadedStore.approvedCount, directCount)
        XCTAssertEqual(reloadedStore.disapprovedCount, 1)
    }

    func testAppRuntimeDeclaresNativeOnlyBoundary() {
        XCTAssertEqual(AppRuntimeBoundary.allowedRuntime, .nativeSwift)
        XCTAssertTrue(AppRuntimeBoundary.disallowedTechnologies.contains(.webViewShell))
        XCTAssertTrue(AppRuntimeBoundary.backendSurfaces.contains(.awsGraph))
        XCTAssertTrue(AppRuntimeBoundary.backendSurfaces.contains(.vercel))
    }

    func testCaptureEntryTrimsTitleAndKeepsMeaning() {
        let entry = CaptureEntry(title: "  Momentum is information  ", meaning: "Avoid stagnant loops.")

        XCTAssertEqual(entry.title, "Momentum is information")
        XCTAssertEqual(entry.meaning, "Avoid stagnant loops.")
        XCTAssertEqual(entry.status, .active)
    }

    func testTechnicalCaptureFlagsAllowClearSignAndCompoundTogether() {
        let flags = TechnicalCaptureFlags(isClearSignOfSuccess: true, isCompound: true)

        XCTAssertTrue(flags.isClearSignOfSuccess)
        XCTAssertTrue(flags.isCompound)
    }

    func testReminderCreatesOneCaptureWithBothSuccessMarkers() {
        var reminder = Reminder(
            kind: .action,
            title: "Notice what already works.",
            whenIAm: "Reviewing recent entries.",
            outcome: "The pattern is obvious."
        )
        reminder.marksClearSignOfSuccess = true
        reminder.marksCompounding = true

        let capture = TechnicalCapture.from(reminder: reminder)

        XCTAssertTrue(capture.flags.isClearSignOfSuccess)
        XCTAssertTrue(capture.flags.isCompound)
    }

    func testLegacyReminderCacheStillDecodesWithoutIndependentSuccessMarkers() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "kind": "action",
          "title": "Existing clear sign",
          "notes": "",
          "url": "",
          "urgent": false,
          "repeatRule": "none",
          "listName": "",
          "flag": false,
          "priority": "none",
          "outcome": "",
          "effort": "none",
          "energy": "none",
          "context": "clearSign",
          "waitingOn": "",
          "locationName": "",
          "pinned": false,
          "tags": [],
          "subtasks": [],
          "status": "active",
          "createdAt": "2026-08-08T12:00:00Z",
          "updatedAt": "2026-08-08T12:00:00Z",
          "needsSync": false
        }
        """

        let reminder = try JSONDecoder.recall.decode(Reminder.self, from: Data(json.utf8))

        XCTAssertTrue(reminder.isClearSignOfSuccess)
        XCTAssertFalse(reminder.isCompounding)
    }

    func testCandidatePayloadUsesCowboyAIGatewayFieldNames() throws {
        var reminder = Reminder(
            kind: .action,
            title: "Use SAVY every day.",
            whenIAm: "Closing loops at the end of the day.",
            outcome: "CowboyAI returns the next action inside SAVY."
        )
        reminder.marksClearSignOfSuccess = true
        reminder.marksCompounding = true
        let payload = CowboyCandidateIntakePayload(
            requestID: "savy-capture-contract",
            capture: TechnicalCapture.from(reminder: reminder),
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let data = try JSONEncoder.recall.encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exactWords = try XCTUnwrap(json["exact_words"] as? [String: Any])
        let metadata = try XCTUnwrap(json["metadata"] as? [String: Any])
        let flags = try XCTUnwrap(metadata["flags"] as? [String: Any])

        XCTAssertEqual(exactWords["when_i_am"] as? String, "Closing loops at the end of the day.")
        XCTAssertEqual(exactWords["done_looks_like"] as? String, "CowboyAI returns the next action inside SAVY.")
        XCTAssertNil(exactWords["whenIAm"])
        XCTAssertNil(exactWords["doneLooksLike"])
        XCTAssertEqual(flags["clear_sign"] as? Bool, true)
        XCTAssertEqual(flags["compound"] as? Bool, true)
    }

    func testTechnicalCapturePromptPreservesExactWordsAndStableMetadataOrder() {
        var reminder = Reminder(
            kind: .action,
            title: "Use SAVY every day.",
            notes: "Keep the proof local.",
            dueDate: Date(timeIntervalSince1970: 1_234),
            urgent: true,
            listName: "Delegation",
            priority: .high,
            whenIAm: "Sharpening the plan before I work.",
            outcome: "CowboyAI returns the next action inside SAVY.",
            energy: .medium,
            waitingOn: "Studio",
            locationName: "Mac Studio",
            pinned: true,
            tags: ["focus", "native"]
        )
        reminder.context = .clearSign

        let capture = TechnicalCapture.from(reminder: reminder)

        XCTAssertEqual(
            capture.promptText,
            """
            What do I want?
            Use SAVY every day.

            When I am...I like to
            Sharpening the plan before I work.

            Done looks like...
            CowboyAI returns the next action inside SAVY.

            Metadata
            Kind: action
            Priority: high
            Energy: medium
            Success Flags: clear_sign=true compound=false
            Lift: Delegation
            Pinned: true
            Urgent: true
            Tags: focus, native
            Due At: 1970-01-01T00:20:34Z
            Defer Until: none
            Waiting On: Studio
            Location: Mac Studio
            URL: none
            Notes: Keep the proof local.
            Steps: none
            """
        )
    }

    @MainActor
    func testSavingReminderAlsoCreatesLocalTechnicalCaptureAndOutboxItem() throws {
        let directory = try makeTemporaryDirectory()
        let reminderURL = directory.appendingPathComponent("reminders.json")
        let captureURL = directory.appendingPathComponent("technical-captures.json")
        let outboxURL = directory.appendingPathComponent("cowboy-candidate-outbox.json")

        let store = ReminderStore(
            repo: LocalReminderRepository(),
            cacheURL: reminderURL,
            technicalCaptureStore: try TechnicalCaptureStore(fileURL: captureURL),
            candidateOutbox: try CowboyCandidateOutbox(fileURL: outboxURL),
            candidateClient: StubCowboyCandidateClient()
        )
        var reminder = Reminder(
            kind: .action,
            title: "Protect the native save path.",
            notes: "Keep Adam's exact words.",
            whenIAm: "Closing loops at the end of the day.",
            outcome: "The candidate queue has a durable local receipt."
        )
        reminder.context = .compound
        reminder.pinned = true
        reminder.tags = ["exact-words"]

        store.save(reminder)

        XCTAssertEqual(store.reminders.count, 1)
        XCTAssertEqual(store.technicalCaptures.count, 1)
        XCTAssertEqual(store.candidateOutboxItems.count, 1)
        XCTAssertEqual(store.technicalCaptures[0].reminderID, reminder.id)
        XCTAssertTrue(store.technicalCaptures[0].flags.isCompound)
        XCTAssertEqual(store.candidateOutboxItems[0].payload.authorityStatus, .candidateOnly)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reminderURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: captureURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outboxURL.path))
    }

    @MainActor
    func testOutboxRetryStatePersistsReceiptAndFailureMetadata() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("cowboy-candidate-outbox.json")
        let outbox = try CowboyCandidateOutbox(fileURL: fileURL)
        var reminder = Reminder(
            kind: .action,
            title: "Retry without losing the capture.",
            whenIAm: "The network is gone.",
            outcome: "The queue keeps the exact words."
        )
        reminder.context = .clearSign

        let capture = TechnicalCapture.from(reminder: reminder)
        let item = outbox.enqueue(capture, now: Date(timeIntervalSince1970: 100))
        outbox.recordFailure(
            itemID: item.id,
            message: "offline",
            now: Date(timeIntervalSince1970: 160)
        )

        let reloaded = try CowboyCandidateOutbox(fileURL: fileURL)
        let persisted = try XCTUnwrap(reloaded.items.first)

        XCTAssertEqual(persisted.attemptCount, 1)
        XCTAssertEqual(persisted.lastError, "offline")
        XCTAssertEqual(persisted.state, .retryScheduled)
        XCTAssertEqual(persisted.nextAttemptAt, Date(timeIntervalSince1970: 460))
        XCTAssertNil(persisted.receipt)
    }

    @MainActor
    func testReminderStoreQueriesRecentClearSignAndCompoundEntriesIndependently() throws {
        let directory = try makeTemporaryDirectory()
        let store = ReminderStore(
            repo: LocalReminderRepository(),
            cacheURL: directory.appendingPathComponent("reminders.json"),
            technicalCaptureStore: try TechnicalCaptureStore(
                fileURL: directory.appendingPathComponent("technical-captures.json")
            ),
            candidateOutbox: try CowboyCandidateOutbox(
                fileURL: directory.appendingPathComponent("cowboy-candidate-outbox.json")
            ),
            candidateClient: StubCowboyCandidateClient()
        )

        var clear = Reminder(kind: .action, title: "Clear sign")
        clear.context = .clearSign
        clear.updatedAt = Date(timeIntervalSince1970: 10)

        var compound = Reminder(kind: .action, title: "Compound")
        compound.context = .compound
        compound.updatedAt = Date(timeIntervalSince1970: 20)

        store.save(clear)
        store.save(compound)

        XCTAssertEqual(store.recentClearSignEntries(limit: 10).map(\.exactWords.want), ["Clear sign"])
        XCTAssertEqual(store.recentCompoundEntries(limit: 10).map(\.exactWords.want), ["Compound"])
        XCTAssertEqual(
            store.recentClearSignOrCompoundEntries(limit: 10).map(\.exactWords.want),
            ["Compound", "Clear sign"]
        )
    }

    @MainActor
    func testPinnedHomepageEntriesPreservePinnedFeedOrdering() throws {
        let directory = try makeTemporaryDirectory()
        let store = ReminderStore(
            repo: LocalReminderRepository(),
            cacheURL: directory.appendingPathComponent("reminders.json"),
            technicalCaptureStore: try TechnicalCaptureStore(
                fileURL: directory.appendingPathComponent("technical-captures.json")
            ),
            candidateOutbox: try CowboyCandidateOutbox(
                fileURL: directory.appendingPathComponent("cowboy-candidate-outbox.json")
            ),
            candidateClient: StubCowboyCandidateClient()
        )

        var first = Reminder(kind: .action, title: "First pinned")
        first.pinned = true
        first.upNextOrder = 0

        var second = Reminder(kind: .action, title: "Second pinned")
        second.pinned = true
        second.upNextOrder = 1

        var third = Reminder(kind: .action, title: "Unpinned")
        third.pinned = false

        store.save(first)
        store.save(second)
        store.save(third)

        XCTAssertEqual(store.pinnedHomepageEntries(limit: 2).map(\.title), ["First pinned", "Second pinned"])
    }

    @MainActor
    func testGreatestLeverageRowRetainsItsOriginalReminder() throws {
        let directory = try makeTemporaryDirectory()
        let store = ReminderStore(
            repo: LocalReminderRepository(),
            cacheURL: directory.appendingPathComponent("reminders.json"),
            technicalCaptureStore: try TechnicalCaptureStore(
                fileURL: directory.appendingPathComponent("technical-captures.json")
            ),
            candidateOutbox: try CowboyCandidateOutbox(
                fileURL: directory.appendingPathComponent("cowboy-candidate-outbox.json")
            ),
            candidateClient: StubCowboyCandidateClient()
        )

        var reminder = Reminder(kind: .action, title: "Open the original")
        reminder.pinned = true
        reminder.dueDate = Date(timeIntervalSince1970: 1_800)
        store.save(reminder)

        let row = try XCTUnwrap(
            HomeFeedRow.rows(
                reminderStore: store,
                leverageStore: LeverageDataStore(),
                limit: 1
            ).first
        )
        guard case let .reminder(original) = row.source else {
            return XCTFail("Pinned Greatest Leverage row lost its original reminder")
        }
        XCTAssertEqual(original.id, reminder.id)
        XCTAssertEqual(original.title, reminder.title)
        XCTAssertEqual(row.subtitle, reminder.whenLabel)
    }

    func testAWSGraphConfigurationRequiresConcreteBackendValues() {
        XCTAssertNil(AWSGraphConfiguration(baseURLString: "", apiKey: "abc"))
        XCTAssertNil(AWSGraphConfiguration(baseURLString: "https://api.example.com", apiKey: ""))
        XCTAssertNil(AWSGraphConfiguration(baseURLString: "https:", apiKey: "key"))
        XCTAssertNotNil(AWSGraphConfiguration(baseURLString: "https://api.example.com", apiKey: "key"))
    }

    func testAWSGraphSeedFallbackMatchesWebsiteContent() {
        XCTAssertEqual(AWSGraphSeed.entries, LeverageContent.beliefs.items)
        XCTAssertEqual(AWSGraphSeed.captures, CaptureSeed.entries)
        XCTAssertEqual(AWSGraphSeed.ontologyItems, LeverageContent.ontology.items)
        XCTAssertEqual(AWSGraphSeed.correlations.totalWeeks, 92)
        XCTAssertEqual(AWSGraphSeed.correlations.totalExtractions, 4873)
        XCTAssertEqual(AWSGraphSeed.correlations.correlations.count, 3)
    }

    func testAWSGraphCorrelationsDecodeSnakeCasePayload() throws {
        let data = """
        {
          "total_weeks": 92,
          "total_extractions": 4873,
          "correlations": [
            {
              "category_a": "Affect",
              "category_b": "Learning",
              "coefficient": 0.67,
              "lag": 0,
              "type": "co-movement"
            }
          ],
          "category_stats": []
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder.awsGraph.decode(OntologySnapshot.self, from: data)

        XCTAssertEqual(snapshot.totalWeeks, 92)
        XCTAssertEqual(snapshot.correlations.first?.categoryA, "Affect")
        XCTAssertEqual(snapshot.correlations.first?.categoryB, "Learning")
    }

    func testAWSGraphCorrelationsDecodeProductionCategoryStats() throws {
        let data = """
        {
          "total_weeks": 92,
          "total_extractions": 4873,
          "correlations": [
            {
              "category_a": "Affect",
              "category_b": "Learning",
              "coefficient": 0.67,
              "lag": 0,
              "type": "co-movement"
            }
          ],
          "category_stats": [
            {
              "category": "Exercise",
              "mean": 29.52,
              "std_dev": 6.76,
              "weeks_with_data": 92,
              "total_count": 2716,
              "coverage_percent": 100
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder.awsGraph.decode(OntologySnapshot.self, from: data)

        XCTAssertEqual(snapshot.categoryStats.first?.coveragePercent, 100)
        XCTAssertEqual(snapshot.categoryStats.first?.totalCount, 2716)
    }

    func testAWSGraphCorrelationsDecodeCamelCasePayload() throws {
        let data = """
        {
          "total_weeks": 92,
          "total_extractions": 4873,
          "correlations": [
            {
              "categoryA": "Affect",
              "categoryB": "Learning",
              "coefficient": 0.67,
              "lag": 0,
              "type": "co-movement"
            }
          ],
          "category_stats": []
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder.awsGraph.decode(OntologySnapshot.self, from: data)

        XCTAssertEqual(snapshot.correlations.first?.categoryA, "Affect")
        XCTAssertEqual(snapshot.correlations.first?.categoryB, "Learning")
    }

    func testBodoniModaFontLoadsInAppBundle() {
        let audit = SavyTypography.performAudit()

        XCTAssertNotNil(Bundle.main.url(forResource: "BodoniModa-Regular", withExtension: "ttf"))
        XCTAssertTrue(audit.bodoniModaBundled)
        XCTAssertNotNil(UIFont(name: "BodoniModa-Regular", size: 20))
        XCTAssertNotNil(Bundle.main.url(forResource: "Roboto-Medium", withExtension: "ttf"))
        XCTAssertTrue(audit.robotoMediumBundled)
        XCTAssertNotNil(UIFont(name: "Roboto-Medium", size: 22))
        XCTAssertTrue(audit.bodoni72OldstyleAvailable, "Bodoni 72 Oldstyle should be available on iOS")
        XCTAssertEqual(audit.displaySerifSource, "Bodoni 72 Oldstyle")
    }

    func testBeliefEntryDisplayUsesFullContentWhenHeadlineTruncated() {
        let headline = "The 10 minutes exporting your judgment builds a system th..."
        let content =
            "The 10 minutes exporting your judgment builds a system that compounds. The 10 minutes just doing the task is gone forever."

        XCTAssertTrue(BeliefEntryDisplay.isTruncatedHeadline(headline, content))
        XCTAssertEqual(BeliefEntryDisplay.title(headline: headline, content: content), content)
    }

    func testAuthUserDisplayEmailHidesCognitoUUID() {
        let uuidUser = AuthUser(
            id: "f8d1c3b0-8031-701b-6ee0-76f1cc7041b9",
            email: "f8d1c3b0-8031-701b-6ee0-76f1cc7041b9"
        )
        let emailUser = AuthUser(id: "user-id", email: "adam@example.com")

        XCTAssertNil(uuidUser.displayEmail)
        XCTAssertEqual(emailUser.displayEmail, "adam@example.com")
    }

    func testAWSGraphBeliefGraphTraceDecodesGatewayPayload() throws {
        let data = """
        {
          "decision": "belief-graph-match",
          "confidence": "high",
          "entryId": "entry-1",
          "graphTrace": {
            "matchedAxiomIris": ["https://understood.app/ontology/axiom/axiom-learning-affect"],
            "evidenceEntryIri": "https://understood.app/entry/entry-1",
            "paths": ["High Learning -> predicts -> Higher Affect"],
            "triplePaths": [
              {
                "axiomIri": "https://understood.app/ontology/axiom/axiom-learning-affect",
                "antecedentLabel": "High Learning",
                "consequentLabel": "Higher Affect",
                "relationshipType": "predicts",
                "supportedBy": "https://understood.app/entry/entry-1"
              }
            ],
            "rankingMethod": "evidence-supportedBy-entry — deterministic personal graph only"
          },
          "reason": "1 axiom path(s) cite this entry as evidence."
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder.awsGraph.decode(BeliefGraphTraceResult.self, from: data)

        XCTAssertTrue(result.hasGraphPath)
        XCTAssertEqual(result.graphTrace?.paths.first, "High Learning -> predicts -> Higher Affect")
    }

    func testAWSGraphStaticFallbackReturnsSeedWithoutConfiguredClient() async {
        let entries = await AWSGraphClient.entriesOrSeed()
        let captures = await AWSGraphClient.capturesOrSeed()
        let correlations = await AWSGraphClient.correlationsOrSeed()
        let ontology = await AWSGraphClient.ontologyItemsOrSeed()

        XCTAssertEqual(entries, AWSGraphSeed.entries)
        XCTAssertEqual(captures, AWSGraphSeed.captures)
        XCTAssertEqual(correlations, AWSGraphSeed.correlations)
        XCTAssertEqual(ontology, AWSGraphSeed.ontologyItems)
    }

    func testAuthSessionBuildsBearerAuthorizationHeader() {
        let session = AuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "bearer",
            expiresIn: 3600,
            user: AuthUser(id: "user-id", email: "adam@example.com")
        )

        XCTAssertEqual(session.authorizationHeader, "Bearer access-token")
    }

    func testAWSGraphAuthSessionDecodesSnakeCaseResponse() throws {
        let data = """
        {
          "access_token": "access-token",
          "refresh_token": "refresh-token",
          "token_type": "bearer",
          "expires_in": 3600,
          "user": {
            "id": "user-id",
            "email": "adam@example.com"
          }
        }
        """.data(using: .utf8)!

        let session = try JSONDecoder.awsGraph.decode(AuthSession.self, from: data)

        XCTAssertEqual(session.accessToken, "access-token")
        XCTAssertEqual(session.refreshToken, "refresh-token")
        XCTAssertEqual(session.authorizationHeader, "Bearer access-token")
    }

    func testAWSGraphDiagnosticNamesMissingFieldWithoutSecrets() {
        let diagnostic = AWSGraphDiagnostic(
            stage: "auth decode",
            endpoint: "auth/v1/token",
            statusCode: 200,
            requestID: "request-id",
            errorCode: nil,
            missingField: "access_token",
            responseKeys: ["expires_in", "token_type", "user"],
            underlyingMessage: "No value associated with key."
        )

        let displayText = diagnostic.displayText

        XCTAssertTrue(displayText.contains("Trace: auth decode"))
        XCTAssertTrue(displayText.contains("Missing field: access_token"))
        XCTAssertFalse(displayText.contains("Bearer "))
    }

    func testAuthenticationModesExposeNativeActions() {
        XCTAssertEqual(AuthenticationMode.signIn.actionTitle, "Sign In")
        XCTAssertEqual(AuthenticationMode.signUp.actionTitle, "Create Account")
    }

    @MainActor
    func testHomeLayoutIsNativeIPhoneFirstWithBottomCenteredCaptureButton() {
        XCTAssertEqual(RootHomeLayout.leverageGridColumnCount, 2)
        XCTAssertEqual(RootHomeLayout.floatingCaptureBackground, SavyTheme.crimson)
        XCTAssertEqual(RootHomeLayout.floatingCaptureSize, 64)
        XCTAssertEqual(RootHomeLayout.floatingCaptureCenterAboveBottom, 128)
        XCTAssertEqual(RootHomeLayout.radialMenuBottomPadding, 170)
        XCTAssertEqual(RootHomeLayout.heroTopPadding, 0)
        XCTAssertEqual(RootHomeLayout.heroHeight, 204)
        XCTAssertEqual(RootHomeLayout.heroContentTopPadding, 34)
        XCTAssertEqual(RootHomeLayout.heroDividerHeight, 3)
        XCTAssertEqual(RootHomeLayout.heroWordmarkFontSize, 64)
        XCTAssertEqual(RootHomeLayout.carouselHorizontalPadding, 2)
        XCTAssertEqual(RootHomeLayout.carouselCardWidth, 282)
        XCTAssertEqual(RootHomeLayout.carouselCardHeight, 182)
        XCTAssertEqual(RootHomeLayout.contentSectionMinHeight, 220)
        XCTAssertEqual(RootHomeLayout.bottomNavigationHeight, 128)
        XCTAssertEqual(RootHomeLayout.bottomNavigationTopPadding, 8)
        XCTAssertEqual(RootHomeLayout.bottomNavigationBottomPadding, 28)
        XCTAssertEqual(RootHomeLayout.bottomNavigationIconSize, 34)
        XCTAssertEqual(RootHomeLayout.bottomNavigationIconWeight, .regular)
        XCTAssertEqual(RootHomeLayout.bottomNavigationLabelSize, 15)
        XCTAssertEqual(RootHomeLayout.bottomNavigationIconLabelSpacing, 7)
        XCTAssertEqual(RootHomeLayout.bottomNavigationHorizontalPadding, 0)
        XCTAssertEqual(RootHomeLayout.accountMenuSymbolName, "line.3.horizontal")
        XCTAssertEqual(RootHomeLayout.accountMenuTopPadding, 88)
        XCTAssertEqual(RootHomeLayout.radialMenuButtonSize, 56)
        XCTAssertEqual(RootHomeLayout.radialMenuIconSize, 20)
        XCTAssertEqual(RootHomeLayout.latestSectionBandHeight, 80)
        XCTAssertEqual(RootHomeLayout.pinnedEntryRowHeight, 96)
        XCTAssertEqual(RootHomeLayout.pinnedEntryTrailingInset, 17)
        XCTAssertEqual(RootHomeLayout.pinnedEntryFontSize, 24)
        XCTAssertEqual(SavyHapticFeedback.primaryImpactIntensity, 1.0)
        XCTAssertEqual(HomeFeedRow.rows(
            reminderStore: ReminderStore(),
            leverageStore: LeverageDataStore(),
            limit: 4
        ).count, 4)
        XCTAssertEqual(HomeLeverageCard.referenceCards.map(\.title), [
            "Connection",
            "Adam's Ontology",
            "Field Essays",
            "News Channel"
        ])
        XCTAssertEqual(HomeLeverageCard.referenceCards.map(\.sectionID), [
            "beliefs",
            "ontology",
            "field-essays",
            "news-channel"
        ])
    }

    func testMetadataEntryNormalizesRequiredFieldsAndStartsPendingSync() {
        let scheduledAt = Date(timeIntervalSince1970: 1_800)
        let entry = MetadataEntry(
            kind: .reminder,
            title: "  Text Noah  ",
            notes: "  Confirm dinner  ",
            scheduledAt: scheduledAt,
            tags: ["  friend  ", " ", "dinner"],
            context: "  personal  ",
            priority: .high,
            cadence: "  weekly  "
        )

        XCTAssertEqual(entry.kind, .reminder)
        XCTAssertEqual(entry.title, "Text Noah")
        XCTAssertEqual(entry.notes, "Confirm dinner")
        XCTAssertEqual(entry.scheduledAt, scheduledAt)
        XCTAssertEqual(entry.tags, ["friend", "dinner"])
        XCTAssertEqual(entry.context, "personal")
        XCTAssertEqual(entry.priority, .high)
        XCTAssertEqual(entry.cadence, "weekly")
        XCTAssertEqual(entry.syncState, .pendingSync)
    }

    func testMetadataStoreSavesAndReloadsEntriesFromJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("metadata-entries.json")

        let store = try MetadataEntryStore(fileURL: fileURL)
        let entry = MetadataEntry(kind: .action, title: "Draft leverage note", notes: "Use the field essay frame.")
        try store.save(entry)

        let reloadedStore = try MetadataEntryStore(fileURL: fileURL)

        XCTAssertEqual(reloadedStore.entries, [entry])
    }

    func testNavigationStateDeclaresLeverageSectionsInsteadOfProductivityTabs() {
        XCTAssertEqual(SavyNavigationSection.allCases.map(\.title), [
            "Now",
            "Reminders",
            "Actions",
            "Calendar"
        ])
        XCTAssertEqual(SavyNavigationSection.leadingSections.map(\.title), ["Now", "Reminders"])
        XCTAssertEqual(SavyNavigationSection.trailingSections.map(\.title), ["Actions", "Calendar"])
        XCTAssertEqual(SavyNavigationSection.allCases.map(\.symbolName), [
            "house",
            "bell",
            "bolt",
            "calendar"
        ])
    }

    func testRadialFabMenuExposesBehaviorAndTimeMetadataOptions() {
        XCTAssertEqual(MetadataEntryKind.allCases.map(\.menuTitle), [
            "Reminder",
            "Action",
            "Calendar"
        ])
    }

    func testNativeBoundaryRejectsWebAndJavaScriptAppRuntimes() {
        XCTAssertTrue(AppRuntimeBoundary.disallowedTechnologies.contains(.webViewShell))
        XCTAssertTrue(AppRuntimeBoundary.disallowedTechnologies.contains(.progressiveWebApp))
        XCTAssertTrue(AppRuntimeBoundary.disallowedTechnologies.contains(.reactNative))
        XCTAssertTrue(AppRuntimeBoundary.disallowedTechnologies.contains(.capacitor))
        XCTAssertTrue(AppRuntimeBoundary.disallowedTechnologies.contains(.expo))
        XCTAssertTrue(AppRuntimeBoundary.disallowedTechnologies.contains(.typeScriptFrontend))
    }

    func testWebsiteContentSeedsEveryNativeLeveragePage() {
        let sections = LeverageContent.seed

        XCTAssertEqual(sections.map(\.id), ["news-channel", "field-essays", "ontology", "beliefs"])
        XCTAssertTrue(sections.allSatisfy { !$0.items.isEmpty })
        XCTAssertTrue(sections.first { $0.id == "news-channel" }?.items.contains { $0.title == "AI is becoming infrastructure" } == true)
        XCTAssertTrue(sections.first { $0.id == "field-essays" }?.items.contains { $0.id == "the-lesson-is-in-the-eye-of-the-beholder" } == true)
        XCTAssertTrue(sections.first { $0.id == "ontology" }?.items.contains { $0.title.contains("13 categories") } == true)
        XCTAssertTrue(sections.first { $0.id == "beliefs" }?.items.contains { $0.title == "Focus on What's in Your Control" } == true)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct StubCowboyCandidateClient: CowboyCandidateSubmitting {
    func submit(_ payload: CowboyCandidateIntakePayload) async throws -> CowboyCandidateReceipt {
        CowboyCandidateReceipt(
            requestID: payload.requestID,
            candidateID: "candidate-\(payload.captureID.uuidString.lowercased())",
            conversationID: nil,
            status: "candidate-only",
            receivedAt: Date(timeIntervalSince1970: 200)
        )
    }
}
