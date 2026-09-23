import XCTest
@testable import SAVY

final class SAVYHomeCardOrderTests: XCTestCase {
    @MainActor
    func testMissingPreferencesKeepTheExistingDefaultPin() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(store.pinnedSectionIDs, ["news-channel"])
        XCTAssertTrue(store.isPinned("news-channel"))
        XCTAssertEqual(store.orderedCards().first?.sectionID, "news-channel")
        XCTAssertEqual(HomeSectionPinStore(defaults: defaults).pinnedSectionIDs, ["news-channel"])
    }

    @MainActor
    func testLegacySinglePinMigratesWithoutReplacingItWithTheDefault() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("field-essays", forKey: HomeSectionPinStore.defaultsKey)
        let store = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(store.pinnedSectionIDs, ["field-essays"])
        XCTAssertEqual(defaults.stringArray(forKey: HomeSectionPinStore.pinnedIDsDefaultsKey), ["field-essays"])
        store.pin("beliefs")
        let reopened = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(reopened.pinnedSectionIDs, ["field-essays", "beliefs"])
        XCTAssertEqual(reopened.orderedCards().map(\.sectionID), ["beliefs", "field-essays", "ontology", "news-channel"])
    }

    @MainActor
    func testLegacyExplicitUnpinnedStateMigratesAndStaysEmptyAfterRestart() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("", forKey: HomeSectionPinStore.defaultsKey)
        let store = HomeSectionPinStore(defaults: defaults)
        XCTAssertTrue(store.pinnedSectionIDs.isEmpty)
        XCTAssertEqual(defaults.stringArray(forKey: HomeSectionPinStore.pinnedIDsDefaultsKey), [])
        XCTAssertTrue(HomeSectionPinStore(defaults: defaults).pinnedSectionIDs.isEmpty)
    }

    @MainActor
    func testNewPinArrayOverridesStaleLegacyStateIncludingAnEmptyArray() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("news-channel", forKey: HomeSectionPinStore.defaultsKey)
        defaults.set(["beliefs", "ontology"], forKey: HomeSectionPinStore.pinnedIDsDefaultsKey)
        XCTAssertEqual(HomeSectionPinStore(defaults: defaults).pinnedSectionIDs, ["beliefs", "ontology"])
        defaults.set([], forKey: HomeSectionPinStore.pinnedIDsDefaultsKey)
        XCTAssertTrue(HomeSectionPinStore(defaults: defaults).pinnedSectionIDs.isEmpty)
    }

    @MainActor
    func testEveryDestinationCanBePinnedAndUnpinningOnePreservesTheOthers() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeSectionPinStore(defaults: defaults)
        let destinationIDs = HomeLeverageCard.referenceCards.map(\.sectionID)
        for id in destinationIDs { store.pin(id) }
        XCTAssertEqual(store.pinnedSectionIDs, Set(destinationIDs))
        XCTAssertTrue(destinationIDs.allSatisfy(store.isPinned))
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["field-essays", "ontology", "beliefs", "news-channel"])
        store.unpin("ontology")
        XCTAssertEqual(store.pinnedSectionIDs, Set(destinationIDs).subtracting(["ontology"]))
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["field-essays", "beliefs", "news-channel", "ontology"])
        store.toggle("ontology")
        XCTAssertEqual(store.pinnedSectionIDs, Set(destinationIDs))
        store.toggle("field-essays")
        XCTAssertEqual(HomeSectionPinStore(defaults: defaults).pinnedSectionIDs, Set(destinationIDs).subtracting(["field-essays"]))

        for id in destinationIDs { store.unpin(id) }
        XCTAssertEqual(defaults.stringArray(forKey: HomeSectionPinStore.pinnedIDsDefaultsKey), [])
        XCTAssertTrue(HomeSectionPinStore(defaults: defaults).pinnedSectionIDs.isEmpty)
    }

    @MainActor
    func testPinsHaveNoCatalogCountLimitAndFutureDestinationsKeepTheirPreference() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeSectionPinStore(defaults: defaults)
        let currentIDs = HomeLeverageCard.referenceCards.map(\.sectionID)
        let futureIDs = (1...6).map { "future-section-\($0)" }
        for id in currentIDs + futureIDs { store.pin(id) }
        let reopened = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(reopened.pinnedSectionIDs, Set(currentIDs + futureIDs))
        XCTAssertTrue(futureIDs.allSatisfy(reopened.isPinned))
        XCTAssertEqual(reopened.orderedCards().map(\.sectionID), ["field-essays", "ontology", "beliefs", "news-channel"], "Unknown IDs retain their preference without inventing navigation cards or changing the existing cards' relative order")
    }

    @MainActor
    func testPinnedAndUnpinnedGroupsReorderIndependentlyAndPersist() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeSectionPinStore(defaults: defaults)
        store.pin("beliefs")
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["beliefs", "news-channel", "ontology", "field-essays"])
        store.move("news-channel", direction: .up)
        store.move("field-essays", direction: .up)
        let expected = ["news-channel", "beliefs", "field-essays", "ontology"]
        XCTAssertEqual(store.orderedCards().map(\.sectionID), expected)
        store.move("news-channel", direction: .up)
        store.move("beliefs", direction: .down)
        store.move("field-essays", direction: .up)
        store.move("ontology", direction: .down)
        XCTAssertEqual(store.orderedCards().map(\.sectionID), expected)
        let reopened = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(reopened.orderedCards().map(\.sectionID), expected)
        XCTAssertEqual(reopened.pinnedSectionIDs, ["news-channel", "beliefs"])
    }

    @MainActor
    func testExistingPinAndMissingOrDuplicateOrderPreferencesPreserveEveryDestination() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("field-essays", forKey: HomeSectionPinStore.defaultsKey)
        defaults.set(["ontology", "ontology", "retired-section"], forKey: HomeSectionPinStore.orderDefaultsKey)
        let store = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["field-essays", "ontology", "beliefs", "news-channel"])
        store.pin("beliefs")
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["beliefs", "field-essays", "ontology", "news-channel"])
        store.unpin("field-essays")
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["beliefs", "field-essays", "ontology", "news-channel"])
        store.unpin("beliefs")
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["beliefs", "field-essays", "ontology", "news-channel"])
    }

    @MainActor
    func testNewestPinLeadsExistingPinsAndUnpinLeadsUnpinnedWithoutReorderingOthers() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["news-channel", "ontology"], forKey: HomeSectionPinStore.pinnedIDsDefaultsKey)
        defaults.set(["news-channel", "ontology", "field-essays", "beliefs"], forKey: HomeSectionPinStore.orderDefaultsKey)
        let store = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["news-channel", "ontology", "field-essays", "beliefs"])

        store.toggle("beliefs")
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["beliefs", "news-channel", "ontology", "field-essays"])
        XCTAssertEqual(store.pinnedSectionIDs, ["beliefs", "news-channel", "ontology"])
        store.toggle("field-essays")
        XCTAssertEqual(store.orderedCards().map(\.sectionID), ["field-essays", "beliefs", "news-channel", "ontology"])
        XCTAssertEqual(store.pinnedSectionIDs, Set(HomeLeverageCard.referenceCards.map(\.sectionID)))

        let allPinned = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(allPinned.orderedCards().map(\.sectionID), ["field-essays", "beliefs", "news-channel", "ontology"])
        XCTAssertEqual(allPinned.pinnedSectionIDs, store.pinnedSectionIDs)
        allPinned.toggle("beliefs")
        XCTAssertEqual(allPinned.orderedCards().map(\.sectionID), ["field-essays", "news-channel", "ontology", "beliefs"])
        allPinned.toggle("field-essays")
        let finalOrder = ["news-channel", "ontology", "field-essays", "beliefs"]
        XCTAssertEqual(allPinned.orderedCards().map(\.sectionID), finalOrder)
        XCTAssertEqual(allPinned.pinnedSectionIDs, ["news-channel", "ontology"])

        let reopened = HomeSectionPinStore(defaults: defaults)
        XCTAssertEqual(reopened.orderedCards().map(\.sectionID), finalOrder)
        XCTAssertEqual(reopened.pinnedSectionIDs, ["news-channel", "ontology"])
    }

    @MainActor
    func testRepeatedPinOrUnpinDoesNotReorderAnUnchangedCard() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeSectionPinStore(defaults: defaults)
        store.pin("beliefs")
        let expected = ["beliefs", "news-channel", "ontology", "field-essays"]
        XCTAssertEqual(store.orderedCards().map(\.sectionID), expected)
        store.pin("news-channel")
        store.unpin("field-essays")
        XCTAssertEqual(store.orderedCards().map(\.sectionID), expected)
        XCTAssertEqual(HomeSectionPinStore(defaults: defaults).orderedCards().map(\.sectionID), expected)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "savy.home-order-tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }
}
