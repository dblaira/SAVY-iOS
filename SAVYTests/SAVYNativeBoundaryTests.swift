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
    }
}
