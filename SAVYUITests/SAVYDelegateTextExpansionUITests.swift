import XCTest

/// Acceptance: Delegate entry fields expand so all entered text is visible — no "..." cutoff.
final class SAVYDelegateTextExpansionUITests: XCTestCase {
    private var app: XCUIApplication!

    private let longTitle =
        "Answer the question: can Claude build a business from scratch that makes money?"
    private let longWhen =
        "When I am reviewing a long delegation prompt that must wrap across several lines without cutting words"
    private let longDone =
        "A business idea was taken from inception to fruition by Claude Fable 5 that made $50. My only role was oversight, funding, and steering — every word of this outcome stays on screen."

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "SAVY_UI_TEST_UNLOCKED",
            "SAVY_UI_TEST_RESET_REMINDERS",
        ]
        app.launch()
        dismissNotificationPrompt()
    }

    func testDelegateFieldsExpandInReminderActionAndCalendarForms() {
        for kind in ExpansionComposerKind.allCases {
            assertDelegateFieldsExpand(kind)
        }
    }

    private func assertDelegateFieldsExpand(_ kind: ExpansionComposerKind) {
        openComposer(kind)

        XCTAssertTrue(field("Title").waitForExistence(timeout: 10), "\(kind.rawValue) form missing Title")
        XCTAssertTrue(field("WhenIAm").waitForExistence(timeout: 5), "\(kind.rawValue) form missing WhenIAm")
        XCTAssertTrue(field("DoneLooksLike").waitForExistence(timeout: 5), "\(kind.rawValue) form missing DoneLooksLike")

        let titleBefore = field("Title").frame.height
        typeInto(field("Title"), longTitle)
        assertExpanded(field("Title"), expected: longTitle, minGrowthOver: titleBefore, kind: kind, name: "Title")

        let whenBefore = field("WhenIAm").frame.height
        typeInto(field("WhenIAm"), longWhen)
        assertExpanded(field("WhenIAm"), expected: longWhen, minGrowthOver: whenBefore, kind: kind, name: "WhenIAm")

        let doneBefore = field("DoneLooksLike").frame.height
        typeInto(field("DoneLooksLike"), longDone)
        assertExpanded(field("DoneLooksLike"), expected: longDone, minGrowthOver: doneBefore, kind: kind, name: "DoneLooksLike")

        // Capture while still on the form — proves Reminder / Action / Event all expand.
        let liveShot = XCTAttachment(screenshot: app.screenshot())
        liveShot.name = "delegate-expand-live-\(kind.rawValue)"
        liveShot.lifetime = .keepAlways
        add(liveShot)
        try? app.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: "/tmp/delegate-expand-\(kind.rawValue).png"))

        // Reminder + Action: reopen without keyboard for a clean read-back shot.
        if kind != .calendar {
            app.buttons["Save"].tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["chargeFab"].firstMatch.waitForExistence(timeout: 12),
                "Shell missing after save for \(kind.rawValue)"
            )
            openSaved(kind)
            XCTAssertTrue(field("Title").waitForExistence(timeout: 10), "\(kind.rawValue) reopen missing Title")
            XCTAssertEqual(stringValue(field("Title")), longTitle)
            XCTAssertEqual(stringValue(field("WhenIAm")), longWhen)
            XCTAssertEqual(stringValue(field("DoneLooksLike")), longDone)

            let reopenShot = XCTAttachment(screenshot: app.screenshot())
            reopenShot.name = "delegate-expand-reopen-\(kind.rawValue)"
            reopenShot.lifetime = .keepAlways
            add(reopenShot)
            try? app.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: "/tmp/delegate-expand-reopen-\(kind.rawValue).png"))
        }

        if app.buttons["Cancel"].waitForExistence(timeout: 2) {
            app.buttons["Cancel"].tap()
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["chargeFab"].firstMatch.waitForExistence(timeout: 8),
            "Did not return to shell after \(kind.rawValue)"
        )
    }

    private func openSaved(_ kind: ExpansionComposerKind) {
        switch kind {
        case .reminder:
            app.buttons["Reminders"].tap()
        case .action:
            app.buttons["Actions"].tap()
        case .calendar:
            return
        }
        let predicate = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "Claude build a business",
            "Claude build a business"
        )
        let item = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Saved \(kind.rawValue) item not found")
        item.tap()
    }

    private func assertExpanded(
        _ element: XCUIElement,
        expected: String,
        minGrowthOver beforeHeight: CGFloat,
        kind: ExpansionComposerKind,
        name: String
    ) {
        XCTAssertTrue(element.exists, "\(kind.rawValue) \(name) missing after typing")
        let value = stringValue(element)
        XCTAssertEqual(value, expected, "\(kind.rawValue) \(name) truncated in value")
        XCTAssertFalse(
            value.contains("…") || value.contains("..."),
            "\(kind.rawValue) \(name) still shows ellipsis: \(value)"
        )
        XCTAssertGreaterThan(
            element.frame.height,
            max(beforeHeight + 6, 34),
            "\(kind.rawValue) \(name) did not expand vertically (was \(beforeHeight), now \(element.frame.height))"
        )
    }

    private func openComposer(_ kind: ExpansionComposerKind) {
        let fab = app.descendants(matching: .any)["chargeFab"].firstMatch
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")
        let center = fab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.2, thenDragTo: center.withOffset(kind.dragOffset))
    }

    private func field(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func typeInto(_ element: XCUIElement, _ text: String) {
        element.tap()
        element.typeText(text)
    }

    private func stringValue(_ element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    private func dismissNotificationPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }
}

private enum ExpansionComposerKind: String, CaseIterable {
    case reminder
    case action
    case calendar

    var dragOffset: CGVector {
        switch self {
        case .reminder: return CGVector(dx: -120, dy: 0)
        case .action: return CGVector(dx: 0, dy: -140)
        case .calendar: return CGVector(dx: 120, dy: 0)
        }
    }
}
