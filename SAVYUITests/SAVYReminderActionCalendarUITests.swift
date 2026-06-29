import XCTest

final class SAVYReminderActionCalendarUITests: XCTestCase {
    private var app: XCUIApplication!

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

    private func dismissNotificationPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    private func openComposer(_ kind: ComposerKind) {
        let fab = app.descendants(matching: .any)["chargeFab"].firstMatch
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")
        let center = fab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.2, thenDragTo: center.withOffset(kind.dragOffset))
    }

    private func createItem(_ kind: ComposerKind, title: String) {
        openComposer(kind)
        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Entry form did not open")
        titleField.tap()
        titleField.typeText(title)

        if kind == .calendar {
            enableDueDateIfNeeded()
        }

        app.buttons["Save"].tap()
        if kind == .calendar {
            openTab("Calendar")
            let today = Calendar.current.component(.day, from: Date())
            let todayCell = app.buttons["calendarDay-\(today)"]
            XCTAssertTrue(todayCell.waitForExistence(timeout: 10), "Today marker missing after save")
            XCTAssertTrue(todayCell.label.contains("scheduled items"), "Today marker did not show the saved event")
            todayCell.tap()
            scrollUntilVisible(elementLabeled(title), direction: .downThenUp)
        }
        let savedElement = kind == .calendar ? elementLabeled(title) : app.staticTexts[title]
        XCTAssertTrue(savedElement.waitForExistence(timeout: 12), "\(title) did not appear after save")
    }

    private func enableDueDateIfNeeded() {
        let dueSwitch = app.switches["Due"]
        if dueSwitch.waitForExistence(timeout: 3), dueSwitch.value as? String == "0" {
            dueSwitch.tap()
        }
    }

    private func reopenItem(_ title: String) {
        let item = app.staticTexts[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "\(title) missing before reopen")
        item.tap()
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 10), "Form did not reopen for \(title)")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "\(title) missing after reopen/save")
    }

    private func gentlySwipeRightThenLeft(_ title: String) {
        let item = app.staticTexts[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "\(title) missing before swipe")
        gentlySwipeRightThenLeft(item, title: title)
    }

    private func gentlySwipeRightThenLeft(_ item: XCUIElement, title: String) {
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: item.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))

        let start = item.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: item.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        XCTAssertTrue(app.buttons["swipeDone"].waitForExistence(timeout: 5), "Done action did not reveal")
        XCTAssertTrue(app.buttons["swipePin"].exists || app.buttons["swipeUnpin"].exists, "Pin action did not reveal")
        XCTAssertTrue(app.buttons["swipeDelete"].exists, "Delete action did not reveal")
        item.tap()
    }

    private func pinAndUnpin(_ title: String) {
        revealActions(title)
        tapVisibleButton("swipePin")
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "\(title) missing after pin")
        revealActions(title)
        XCTAssertTrue(app.buttons["swipeUnpin"].waitForExistence(timeout: 5), "Unpin action did not replace Pin")
        tapVisibleButton("swipeUnpin")
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "\(title) missing after unpin")
    }

    private func completeAndDelete(_ title: String, completedSectionId: String) {
        revealActions(title)
        tapVisibleButton("swipeDone")
        let completedSection = app.descendants(matching: .any)[completedSectionId].firstMatch
        scrollUntilVisible(completedSection, direction: .downThenUp)
        XCTAssertTrue(completedSection.waitForExistence(timeout: 10), "Completed section missing")
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "\(title) missing after Done")

        let completedItem = app.staticTexts[title].firstMatch
        completedItem.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: completedItem.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(app.buttons.matching(identifier: "swipeDelete").firstMatch.waitForExistence(timeout: 5), "Delete action missing for completed item")
        tapVisibleButton("swipeDelete")
        XCTAssertFalse(app.staticTexts[title].waitForExistence(timeout: 3), "\(title) still visible after delete")
    }

    private func completeAndDeleteCalendarEvent(_ title: String) {
        revealCalendarActions(title)
        tapVisibleButton("swipeDone")
        XCTAssertTrue(elementLabeled(title).waitForExistence(timeout: 10), "\(title) missing after Done")

        revealCalendarActions(title)
        XCTAssertTrue(actionButton("swipeDelete").waitForExistence(timeout: 5), "Delete action missing for calendar event")
        tapVisibleButton("swipeDelete")
        XCTAssertFalse(elementLabeled(title).waitForExistence(timeout: 3), "\(title) still visible after delete")
    }

    private enum ScrollSearchDirection { case up, downThenUp }

    private func scrollUntilVisible(
        _ element: XCUIElement,
        maxSwipes: Int = 6,
        direction: ScrollSearchDirection = .up
    ) {
        let scroll = app.scrollViews.firstMatch
        if direction == .downThenUp {
            for _ in 0..<2 {
                if element.exists && element.isHittable { return }
                scroll.swipeDown()
            }
        }
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return }
            scroll.swipeUp()
        }
    }

    private func revealActions(_ title: String) {
        let item = app.staticTexts[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "\(title) missing before reveal")
        revealActions(item, title: title)
    }

    private func revealActions(_ item: XCUIElement, title: String) {
        dragOpenActions(from: item)
    }

    private func elementLabeled(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[title].firstMatch
    }

    private func tapVisibleButton(_ identifier: String) {
        let matches = app.buttons.matching(identifier: identifier).allElementsBoundByIndex
            + app.buttons.matching(identifier: visibleActionTitle(for: identifier)).allElementsBoundByIndex
        guard let button = matches.first(where: { $0.exists && $0.isHittable }) else {
            XCTFail("No visible \(identifier) button")
            return
        }
        button.tap()
    }

    private func openTab(_ title: String) {
        app.buttons[title].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "\(title) tab did not open")
    }

    func testReminderCreateReopenSwipePinDoneDelete() {
        let title = "UI Test Reminder \(Int(Date().timeIntervalSince1970))"
        createItem(.reminder, title: title)
        openTab("Reminders")
        reopenItem(title)
        gentlySwipeRightThenLeft(title)
        pinAndUnpin(title)
        completeAndDelete(title, completedSectionId: "completedRemindersSection")
    }

    func testActionCreateReopenSwipePinDoneDelete() {
        let title = "UI Test Action \(Int(Date().timeIntervalSince1970))"
        createItem(.action, title: title)
        openTab("Actions")
        reopenItem(title)
        gentlySwipeRightThenLeft(title)
        pinAndUnpin(title)
        completeAndDelete(title, completedSectionId: "completedActionsSection")
    }

    func testCalendarEventCreateReopenAndCalendarShowsImportanceMarker() {
        let title = "UI Test Event \(Int(Date().timeIntervalSince1970))"
        createItem(.calendar, title: title)
        openTab("Calendar")
        let event = elementLabeled(title)
        XCTAssertTrue(event.waitForExistence(timeout: 10), "Calendar event not visible")
        let today = Calendar.current.component(.day, from: Date())
        XCTAssertTrue(app.buttons["calendarDay-\(today)"].label.contains("scheduled items"))
        event.tap()
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 10), "Calendar event did not reopen")
        app.buttons["Save"].tap()
        let savedEvent = elementLabeled(title)
        XCTAssertTrue(savedEvent.waitForExistence(timeout: 10), "Calendar event missing after reopen/save")
        gentlySwipeRightThenLeftCalendarEvent(savedEvent, title: title)
        revealCalendarActions(title)
        tapVisibleButton("swipePin")
        XCTAssertTrue(elementLabeled(title).waitForExistence(timeout: 10), "\(title) missing after pin")
        revealCalendarActions(title)
        XCTAssertTrue(actionButton("swipeUnpin").waitForExistence(timeout: 5), "Unpin action did not replace Pin")
        tapVisibleButton("swipeUnpin")
        completeAndDeleteCalendarEvent(title)
    }

    func testReminderLongPressReorderMovesWithinFeed() {
        let stamp = Int(Date().timeIntervalSince1970)
        let first = "Reorder First \(stamp)"
        let second = "Reorder Second \(stamp)"
        createItem(.reminder, title: first)
        createItem(.reminder, title: second)
        openTab("Reminders")

        let firstText = app.staticTexts[first].firstMatch
        let secondText = app.staticTexts[second].firstMatch
        XCTAssertTrue(firstText.waitForExistence(timeout: 10))
        XCTAssertTrue(secondText.waitForExistence(timeout: 10))
        XCTAssertLessThan(firstText.frame.minY, secondText.frame.minY, "Precondition: first item should start above second")

        secondText.press(forDuration: 0.6)
        let up = app.buttons["reorderUp"].firstMatch
        XCTAssertTrue(up.waitForExistence(timeout: 5), "Long press did not arm reorder controls")
        up.tap()

        XCTAssertLessThan(secondText.frame.minY, firstText.frame.minY, "Second reminder did not move above first")
    }

    private func gentlySwipeRightThenLeftCalendarEvent(_ item: XCUIElement, title: String) {
        dragOpenActions(from: item)
        XCTAssertTrue(actionButton("swipeDone").waitForExistence(timeout: 5), "Done action did not reveal")
        XCTAssertTrue(actionButton("swipePin").exists || actionButton("swipeUnpin").exists, "Pin action did not reveal")
        XCTAssertTrue(actionButton("swipeDelete").exists, "Delete action did not reveal")
        item.tap()
    }

    private func dragOpenActions(from item: XCUIElement) {
        let start = item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.withOffset(CGVector(dx: -12, dy: 0))
            .press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 230, dy: 0)))
    }

    private func revealCalendarActions(_ title: String) {
        let item = elementLabeled(title)
        XCTAssertTrue(item.waitForExistence(timeout: 10), "\(title) missing before calendar reveal")
        dragOpenActions(from: item)
    }

    private func actionButton(_ identifier: String) -> XCUIElement {
        let identified = app.buttons[identifier].firstMatch
        if identified.exists { return identified }
        return app.buttons[visibleActionTitle(for: identifier)].firstMatch
    }

    private func visibleActionTitle(for identifier: String) -> String {
        switch identifier {
        case "swipeDone": return "Done"
        case "swipePin": return "Pin"
        case "swipeUnpin": return "Unpin"
        case "swipeDelete": return "Delete"
        case "swipeReopen": return "Reopen"
        default: return identifier
        }
    }

}

private enum ComposerKind {
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
