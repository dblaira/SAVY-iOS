import XCTest
import UIKit
@testable import SAVY

final class SAVYNativeBoundaryTests: XCTestCase {
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

    func testAWSGraphConfigurationRequiresConcreteBackendValues() {
        XCTAssertNil(AWSGraphConfiguration(baseURLString: "", apiKey: "abc"))
        XCTAssertNil(AWSGraphConfiguration(baseURLString: "https://api.example.com", apiKey: ""))
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

    func testHomeLayoutIsNativeIPhoneFirstWithBottomCenteredCaptureButton() {
        XCTAssertEqual(RootHomeLayout.leverageGridColumnCount, 2)
        XCTAssertEqual(RootHomeLayout.floatingCaptureAlignment, .bottom)
        XCTAssertEqual(RootHomeLayout.floatingCaptureBackground, SavyTheme.deepNavy)
        XCTAssertEqual(RootHomeLayout.floatingCaptureSize, 72)
        XCTAssertEqual(RootHomeLayout.floatingCaptureBottomPadding, 90)
        XCTAssertEqual(RootHomeLayout.heroTopPadding, 0)
        XCTAssertEqual(RootHomeLayout.heroHeight, 230)
        XCTAssertEqual(RootHomeLayout.heroContentTopPadding, 34)
        XCTAssertEqual(RootHomeLayout.heroWordmarkEyebrowSpacing, 12)
        XCTAssertEqual(RootHomeLayout.heroDividerHeight, 3)
        XCTAssertEqual(RootHomeLayout.heroWordmarkFontSize, 48)
        XCTAssertEqual(RootHomeLayout.carouselTopPadding, 20)
        XCTAssertEqual(RootHomeLayout.carouselHorizontalPadding, 2)
        XCTAssertEqual(RootHomeLayout.carouselCardWidth, 282)
        XCTAssertEqual(RootHomeLayout.carouselCardHeight, 236)
        XCTAssertEqual(RootHomeLayout.bottomNavigationHeight, 112)
        XCTAssertEqual(RootHomeLayout.bottomNavigationTopPadding, 28)
        XCTAssertEqual(RootHomeLayout.bottomNavigationIconSize, 34)
        XCTAssertEqual(RootHomeLayout.accountMenuSymbolName, "line.3.horizontal")
        XCTAssertEqual(RootHomeLayout.accountMenuTopPadding, 88)
        XCTAssertEqual(RootHomeLayout.radialMenuButtonSize, 66)
        XCTAssertEqual(RootHomeLayout.radialMenuIconSize, 29)
        XCTAssertEqual(RootHomeLayout.latestSectionBandHeight, 92)
        XCTAssertEqual(RootHomeLayout.pinnedEntryRowHeight, 81)
        XCTAssertEqual(RootHomeLayout.pinnedEntryTrailingInset, 17)
        XCTAssertEqual(RootHomeLayout.pinnedEntryFontSize, 32)
        XCTAssertEqual(SavyHapticFeedback.primaryImpactIntensity, 1.0)
        XCTAssertEqual(HomePinnedEntry.referenceRows.map(\.title), [
            "Top Pinned entry",
            "2nd top Pinned entry"
        ])
        XCTAssertEqual(HomeLeverageCard.referenceCards.map(\.title), [
            "News\nChannel",
            "Field\nEssays",
            "Adam's\nOntology",
            "Belief\nLibrary"
        ])
        XCTAssertEqual(HomeLeverageCard.referenceCards.map(\.sectionID), [
            "news-channel",
            "field-essays",
            "ontology",
            "beliefs"
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
            "ACTION",
            "Essays",
            "Beliefs",
            "News"
        ])
        XCTAssertFalse(SavyNavigationSection.allCases.map(\.title).contains("Reminders"))
        XCTAssertFalse(SavyNavigationSection.allCases.map(\.title).contains("Actions"))
        XCTAssertFalse(SavyNavigationSection.allCases.map(\.title).contains("Calendar"))
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
}
