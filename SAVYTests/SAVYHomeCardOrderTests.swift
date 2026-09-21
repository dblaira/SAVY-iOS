import XCTest
@testable import SAVY

final class SAVYHomeCardOrderTests: XCTestCase {
    @MainActor
    func testManualOrderPersistsWithoutMovingAcrossPinnedBoundary() {
        let suite = "savy.home-order-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeSectionPinStore(defaults: defaults)

        store.move("ontology", direction: .up)
        let expected = ["news-channel", "ontology", "beliefs", "field-essays"]
        XCTAssertEqual(store.orderedCards().map(\.sectionID), expected)
        store.move("ontology", direction: .up)
        store.move("news-channel", direction: .down)
        XCTAssertEqual(store.orderedCards().map(\.sectionID), expected)
        let reopened = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(reopened.orderedCards().map(\.sectionID), expected)
        XCTAssertEqual(reopened.pinnedSectionID, "news-channel")

        reopened.unpin()
        reopened.move("news-channel", direction: .down)
        XCTAssertEqual(reopened.orderedCards().map(\.sectionID), ["ontology", "news-channel", "beliefs", "field-essays"])
        XCTAssertNil(HomeSectionPinStore(defaults: defaults).pinnedSectionID)
    }

    @MainActor
    func testExistingPinAndMissingOrDuplicatePreferencesPreserveEveryDestination() {
        let suite = "savy.home-order-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("field-essays", forKey: HomeSectionPinStore.defaultsKey)
        defaults.set(["ontology", "ontology", "retired-section"], forKey: HomeSectionPinStore.orderDefaultsKey)
        let store = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["field-essays", "ontology", "beliefs", "news-channel"])
        store.pin("beliefs")
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["beliefs", "ontology", "field-essays", "news-channel"])
        store.unpin()
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["ontology", "beliefs", "field-essays", "news-channel"])
    }
}
