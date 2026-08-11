import XCTest

final class SAVYReminderActionCalendarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["SAVY_UI_TEST_UNLOCKED"]
        let preservesExistingData = name.contains("testEntryFormHasNoManualCowboyAIAction")
            || name.contains("testHomepageRemovesHistoricalCowboyCard")
            || name.contains("testHomepageUsesGreatestLeverageCarouselAndVerticalContentOrder")
            || name.contains("testBottomNavigationHasLargeRaisedEdgeToEdgeTargets")
        if !preservesExistingData {
            app.launchArguments.append("SAVY_UI_TEST_RESET_REMINDERS")
        }
        app.launch()
        dismissNotificationPrompt()
    }

    private func dismissNotificationPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    private func dismissLocalNetworkPrompt() {
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

    private func titleField() -> XCUIElement {
        // Vertical TextFields surface as text views; keep textFields as a fallback.
        let byId = app.descendants(matching: .any)["Title"].firstMatch
        if byId.exists { return byId }
        return app.textFields["Title"].firstMatch
    }

    private func createItem(_ kind: ComposerKind, title: String) {
        openComposer(kind)
        let field = titleField()
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Entry form did not open")
        field.tap()
        field.typeText(title)

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
        XCTAssertTrue(titleField().waitForExistence(timeout: 10), "Form did not reopen for \(title)")
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
        let toggleId = completedSectionId == "completedRemindersSection"
            ? "completedRemindersToggle"
            : "completedActionsToggle"
        let toggle = app.buttons[toggleId].firstMatch
        scrollUntilVisible(toggle, direction: .downThenUp)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Completed toggle missing")
        toggle.tap()

        let completedItem = app.descendants(matching: .any)["completedReminderRow"].firstMatch
        scrollUntilVisible(completedItem, direction: .downThenUp)
        XCTAssertTrue(completedItem.waitForExistence(timeout: 5), "Completed row missing")
        XCTAssertTrue(completedItem.label.contains(title), "\(title) missing after Done")
        completedItem.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5), "Delete action missing for completed item")
        app.buttons["Delete"].tap()
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

    private func openPersonalAuthorityReview() {
        let menu = app.buttons["SAVY menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "SAVY menu missing")
        menu.tap()

        let teachCowboyAI = app.buttons["Teach Cowboy AI"].firstMatch
        XCTAssertTrue(teachCowboyAI.waitForExistence(timeout: 5), "Teach Cowboy AI menu action missing")
        teachCowboyAI.tap()

        let review = app.descendants(matching: .any)["personalAuthorityReview"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 10), "Cowboy AI review did not open")
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

    func testSparkComposerShowsFrictionlessCaptureAndVoiceControl() {
        openComposer(.spark)

        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 10), "Spark title field missing")
        XCTAssertTrue(app.descendants(matching: .any)["sparkNotes"].firstMatch.exists, "Spark notes field missing")
        XCTAssertTrue(app.buttons["sparkVoiceRecord"].waitForExistence(timeout: 5), "Spark voice control missing")
        XCTAssertFalse(app.switches["Due"].exists, "Spark should not require a date")
        XCTAssertFalse(app.buttons["Priority"].exists, "Spark should not require a priority")
    }

    func testCowboyNaturalVoiceReachesPlayingState() {
        openPersonalAuthorityReview()
        dismissLocalNetworkPrompt()

        let firstStatement = app.descendants(matching: .any)["personalAuthorityCandidateRow1"].firstMatch
        let conferenceScroll = app.scrollViews.firstMatch
        for _ in 0..<8 where !firstStatement.isHittable { conferenceScroll.swipeUp() }
        XCTAssertTrue(firstStatement.waitForExistence(timeout: 10), "First authority statement missing")
        firstStatement.tap()

        let detail = app.descendants(matching: .any)["personalAuthorityCandidateDetail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "Authority statement detail did not open")

        let listen = app.buttons["personalAuthorityListen"].firstMatch
        for _ in 0..<8 where !listen.isHittable { app.swipeUp() }
        XCTAssertTrue(listen.waitForExistence(timeout: 10), "Natural Listen button missing")
        listen.tap()

        let pause = app.buttons["personalAuthorityListen"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 300), "Natural voice never reached playback")
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline, !pause.label.contains("Pause") {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(pause.label.contains("Pause"), "Natural voice did not begin playing")
    }

    func testHomepageRemovesHistoricalCowboyCard() {
        let historicalCard = app.descendants(matching: .any)["personalAuthorityLaunchCard"].firstMatch
        XCTAssertFalse(
            historicalCard.waitForExistence(timeout: 2),
            "Historical 709-statement card is still on the homepage"
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "homepage-without-historical-cowboy-card"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        openPersonalAuthorityReview()
    }

    func testHomepageUsesGreatestLeverageCarouselAndVerticalContentOrder() {
        let heading = app.staticTexts["GREATEST LEVERAGE"].firstMatch
        let carousel = app.scrollViews["greatestLeverageCarousel"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 12), "Greatest Leverage did not begin the white area")
        XCTAssertFalse(app.staticTexts["The Adam Pattern"].exists)
        XCTAssertTrue(carousel.waitForExistence(timeout: 12), "Greatest Leverage entries were not presented as a carousel")
        XCTAssertLessThan(heading.frame.minY, carousel.frame.minY)

        let topScreenshot = XCTAttachment(screenshot: app.screenshot())
        topScreenshot.name = "homepage-greatest-leverage-carousel"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        let homeScroll = app.scrollViews["editorialHomeScroll"].firstMatch
        let connection = app.descendants(matching: .any)["homeContentSection-beliefs"].firstMatch
        let ontology = app.descendants(matching: .any)["homeContentSection-ontology"].firstMatch
        let essays = app.descendants(matching: .any)["homeContentSection-field-essays"].firstMatch
        let news = app.descendants(matching: .any)["homeContentSection-news-channel"].firstMatch
        XCTAssertTrue(connection.waitForExistence(timeout: 5), "Connection did not begin the vertical content area")
        XCTAssertFalse(app.descendants(matching: .any)["homeContentDivider-after-beliefs"].exists)

        for section in [ontology, essays, news] {
            for _ in 0..<5 where !(section.exists && section.isHittable) {
                homeScroll.swipeUp()
            }
            XCTAssertTrue(section.exists && section.isHittable, "A vertical homepage content area could not be reached")
        }

        XCTAssertFalse(app.descendants(matching: .any)["homeContentDivider-after-field-essays"].exists)

        let contentScreenshot = XCTAttachment(screenshot: app.screenshot())
        contentScreenshot.name = "homepage-vertical-content-with-clean-spacing"
        contentScreenshot.lifetime = .keepAlways
        add(contentScreenshot)
    }

    func testConnectionUsesMeasuredReminderCardHierarchy() {
        let homeScroll = app.scrollViews["editorialHomeScroll"].firstMatch
        let connection = app.descendants(matching: .any)["homeContentSection-beliefs"].firstMatch
        XCTAssertTrue(connection.waitForExistence(timeout: 12), "Connection is missing from the homepage")

        for _ in 0..<4 where !connection.isHittable {
            homeScroll.swipeUp()
        }
        XCTAssertTrue(connection.isHittable, "Connection could not be reached")
        connection.tap()

        let full = app.descendants(matching: .any)["connectionCard-0"].firstMatch
        let medium = app.descendants(matching: .any)["connectionCard-1"].firstMatch
        let minimal = app.descendants(matching: .any)["connectionCard-2"].firstMatch
        XCTAssertTrue(full.waitForExistence(timeout: 12), "The first Connection card is missing")
        XCTAssertTrue(medium.waitForExistence(timeout: 5), "The second Connection card is missing")
        XCTAssertTrue(minimal.waitForExistence(timeout: 5), "The standard Connection card is missing")

        XCTAssertEqual(full.frame.height, 186, accuracy: 2)
        XCTAssertEqual(medium.frame.height, 167, accuracy: 2)
        XCTAssertEqual(minimal.frame.height, 124, accuracy: 2)
        XCTAssertGreaterThan(full.frame.height, medium.frame.height)
        XCTAssertGreaterThan(medium.frame.height, minimal.frame.height)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "connection-measured-reminder-card-hierarchy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testBottomNavigationHasLargeRaisedEdgeToEdgeTargets() {
        let now = app.buttons["Now"].firstMatch
        let reminders = app.buttons["Reminders"].firstMatch
        let actions = app.buttons["Actions"].firstMatch
        let calendar = app.buttons["Calendar"].firstMatch
        let buttons = [now, reminders, actions, calendar]

        for button in buttons {
            XCTAssertTrue(button.waitForExistence(timeout: 12), "A bottom navigation control is missing")
            XCTAssertGreaterThanOrEqual(button.frame.height, 100, "Bottom navigation tap target is still too short")
        }

        XCTAssertLessThanOrEqual(now.frame.minX, 1, "Now does not reach the left phone edge")
        XCTAssertGreaterThanOrEqual(calendar.frame.maxX, app.frame.maxX - 1, "Calendar does not reach the right phone edge")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "large-raised-edge-to-edge-bottom-navigation"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let calendarTapY = (calendar.frame.midY - app.frame.minY) / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: calendarTapY)).tap()
        XCTAssertTrue(app.staticTexts["Calendar"].waitForExistence(timeout: 10), "The right phone edge did not open Calendar")

        let nowTapY = (now.frame.midY - app.frame.minY) / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: nowTapY)).tap()
        XCTAssertTrue(app.staticTexts["GREATEST LEVERAGE"].waitForExistence(timeout: 10), "The left phone edge did not return to Now")
    }

    func testCowboyNaturalVoiceIsReusableAndSpeedAdjustableInEntryForm() {
        openComposer(.action)

        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Entry form did not open")
        titleField.tap()
        titleField.typeText("Hear this action in Cowboy AI")

        let listen = app.buttons["entryFormNaturalVoiceListen"].firstMatch
        for _ in 0..<6 where !listen.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(listen.waitForExistence(timeout: 10), "Reusable natural voice control missing")

        let slider = app.sliders["Voice speed"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "Voice speed slider missing")
        slider.adjust(toNormalizedSliderPosition: 0.8)

        let rate = app.staticTexts["cowboyVoicePlaybackRate"].firstMatch
        XCTAssertTrue(rate.waitForExistence(timeout: 5), "Voice speed value missing")
        XCTAssertFalse(rate.label.isEmpty, "Voice speed value did not update")
    }

    func testEntryFormHasNoManualCowboyAIAction() {
        openComposer(.action)

        let title = titleField()
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Entry form did not open")
        XCTAssertFalse(app.staticTexts["Use it"].exists)
        XCTAssertFalse(app.buttons["askCowboyAI"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "rule-5-entry-form-without-manual-cowboy-action"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testGreatestLeverageCardOpensOriginalEntry() {
        let title = "Pinned Leverage \(Int(Date().timeIntervalSince1970))"
        // The Event composer begins with a date. Changing its shared destination to Action
        // proves the common form retains that date while routing the saved entry to Actions.
        openComposer(.calendar)

        let actionDestination = app.buttons["Action"].firstMatch
        XCTAssertTrue(actionDestination.waitForExistence(timeout: 10), "Shared destination picker was missing")
        actionDestination.tap()

        let field = titleField()
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Entry form did not open")
        field.tap()
        field.typeText(title)
        app.buttons["Save"].tap()

        openTab("Actions")
        let savedTitle = app.staticTexts[title].firstMatch
        XCTAssertTrue(savedTitle.waitForExistence(timeout: 12), "Saved action did not appear")
        revealActions(title)
        tapVisibleButton("swipePin")

        openTab("Now")
        let card = app.buttons["greatestLeverageReminder"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 12), "Pinned entry did not appear under Greatest Leverage")
        XCTAssertTrue(card.label.contains(title), "Greatest Leverage card did not retain the original title")

        let date = app.descendants(matching: .any)["greatestLeverageDate"].firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 5), "Pinned entry date was not visible")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "greatest-leverage-card-left-aligned-date"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        card.tap()
        let reopenedTitle = titleField()
        XCTAssertTrue(reopenedTitle.waitForExistence(timeout: 10), "Greatest Leverage card did not open its entry")
        XCTAssertEqual(reopenedTitle.value as? String, title, "Greatest Leverage opened a different entry")
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
        XCTAssertTrue(titleField().waitForExistence(timeout: 10), "Calendar event did not reopen")
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
    case spark
    case reminder
    case action
    case calendar

    var dragOffset: CGVector {
        switch self {
        case .spark: return CGVector(dx: -145, dy: -85)
        case .reminder: return CGVector(dx: -60, dy: -145)
        case .action: return CGVector(dx: 60, dy: -145)
        case .calendar: return CGVector(dx: 145, dy: -85)
        }
    }
}
