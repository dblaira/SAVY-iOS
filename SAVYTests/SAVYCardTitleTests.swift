import XCTest
@testable import SAVY

final class SAVYCardTitleTests: XCTestCase {
    @MainActor
    func testTitlesKeepIdentityExactWritingAndOriginalContentAcrossRelaunch() throws {
        let suite = "savy-title-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var reminder = Reminder()
        reminder.title = "Original entry"
        reminder.notes = "Original writing.\nDo not change it."
        let before = try SyncJSON.encode(reminder)
        let card = SavyCardTitle.reminder(reminder)
        let store = SavyCardTitleStore(defaults: defaults)
        let chosen = "My title — “exactly” ✨"
        XCTAssertTrue(store.rename(card, to: chosen))
        let reopened = SavyCardTitleStore(defaults: defaults)
        XCTAssertEqual(reopened.title(for: card), chosen)
        XCTAssertEqual(reopened.title(for: .reminder(reminder, title: "Home Theme answer")), chosen)
        XCTAssertEqual(reopened.title(for: SavyCardTitle(id: "other", original: card.original)), card.original)
        XCTAssertEqual(try SyncJSON.encode(reminder), before)
        XCTAssertFalse(reopened.rename(card, to: " \n "))
        XCTAssertEqual(reopened.title(for: card), chosen)
        reopened.restoreOriginal(card)
        XCTAssertEqual(SavyCardTitleStore(defaults: defaults).title(for: card), "Original entry")
    }

    @MainActor
    func testIndependentOfflineTitlesAndResetMergeThroughCloudJournal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("savy-titles-\(UUID())")
        let phoneSuite = "savy-title-phone-\(UUID())"
        let macSuite = "savy-title-mac-\(UUID())"
        let phoneDefaults = try XCTUnwrap(UserDefaults(suiteName: phoneSuite))
        let macDefaults = try XCTUnwrap(UserDefaults(suiteName: macSuite))
        defer {
            phoneDefaults.removePersistentDomain(forName: phoneSuite)
            macDefaults.removePersistentDomain(forName: macSuite)
            try? FileManager.default.removeItem(at: folder)
        }
        let phone = SavyCardTitleStore(defaults: phoneDefaults)
        let mac = SavyCardTitleStore(defaults: macDefaults)
        let phoneAdapter = CardTitlesSyncAdapter(store: phone)
        let macAdapter = CardTitlesSyncAdapter(store: mac)
        let phoneState = try SavyCloudSyncState(fileURL: folder.appendingPathComponent("phone/state.json"))
        let macState = try SavyCloudSyncState(fileURL: folder.appendingPathComponent("mac/state.json"))
        try phoneState.accountChanged(to: "test-owner")
        try macState.accountChanged(to: "test-owner")
        let first = SavyCardTitle(id: "home:beliefs", original: "Connection")
        let second = SavyCardTitle(id: "source:example", original: "Source title")
        _ = try phoneState.observeLocal(adapter: phoneAdapter, legacyDevice: false, now: 10)
        _ = try macState.observeLocal(adapter: macAdapter, legacyDevice: false, now: 10)
        phone.rename(first, to: "My connections")
        mac.rename(second, to: "My source title")
        let phoneChanges = try phoneState.observeLocal(adapter: phoneAdapter, legacyDevice: false, now: 20)
        let macChanges = try macState.observeLocal(adapter: macAdapter, legacyDevice: false, now: 21)
        try phoneState.retainIncoming(macChanges, generation: phoneState.generation)
        try macState.retainIncoming(phoneChanges, generation: macState.generation)
        _ = try phoneState.replayIncoming(using: [phoneAdapter.documentKey: phoneAdapter], generation: phoneState.generation)
        _ = try macState.replayIncoming(using: [macAdapter.documentKey: macAdapter], generation: macState.generation)
        XCTAssertEqual(phone.title(for: second), "My source title")
        XCTAssertEqual(mac.title(for: first), "My connections")
        XCTAssertEqual(phone.titles, mac.titles)
        mac.restoreOriginal(first)
        let reset = try macState.observeLocal(adapter: macAdapter, legacyDevice: false, now: 30)
        try phoneState.retainIncoming(reset, generation: phoneState.generation)
        _ = try phoneState.replayIncoming(using: [phoneAdapter.documentKey: phoneAdapter], generation: phoneState.generation)
        XCTAssertEqual(phone.title(for: first), "Connection")
        XCTAssertEqual(phone.title(for: second), "My source title")
    }
}
