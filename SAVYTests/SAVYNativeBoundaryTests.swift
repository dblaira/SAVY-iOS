import XCTest
@testable import SAVY

final class SAVYNativeBoundaryTests: XCTestCase {
    func testAppRuntimeDeclaresNativeOnlyBoundary() {
        XCTAssertEqual(AppRuntimeBoundary.allowedRuntime, .nativeSwift)
        XCTAssertTrue(AppRuntimeBoundary.disallowedTechnologies.contains(.webViewShell))
        XCTAssertTrue(AppRuntimeBoundary.backendSurfaces.contains(.supabase))
        XCTAssertTrue(AppRuntimeBoundary.backendSurfaces.contains(.vercel))
    }

    func testCaptureEntryTrimsTitleAndKeepsMeaning() {
        let entry = CaptureEntry(title: "  Momentum is information  ", meaning: "Avoid stagnant loops.")

        XCTAssertEqual(entry.title, "Momentum is information")
        XCTAssertEqual(entry.meaning, "Avoid stagnant loops.")
        XCTAssertEqual(entry.status, .active)
    }

    func testSupabaseConfigurationRequiresConcreteBackendValues() {
        XCTAssertNil(SupabaseConfiguration(urlString: "", anonKey: "abc"))
        XCTAssertNil(SupabaseConfiguration(urlString: "https://example.supabase.co", anonKey: ""))
        XCTAssertNotNil(SupabaseConfiguration(urlString: "https://example.supabase.co", anonKey: "anon"))
    }

    func testHomeLayoutIsNativeIPhoneFirstWithBottomCenteredCaptureButton() {
        XCTAssertEqual(RootHomeLayout.leverageGridColumnCount, 2)
        XCTAssertEqual(RootHomeLayout.floatingCaptureAlignment, .bottom)
        XCTAssertEqual(RootHomeLayout.floatingCaptureBackground, SavyTheme.crimson)
        XCTAssertEqual(RootHomeLayout.floatingCaptureSize, 72)
        XCTAssertEqual(RootHomeLayout.heroTopPadding, 92)
        XCTAssertEqual(RootHomeLayout.latestSectionBandHeight, 80)
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
