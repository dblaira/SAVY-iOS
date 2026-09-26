import XCTest

final class SAVYReminderActionCalendarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["SAVY_UI_TEST_UNLOCKED", "SAVY_UI_TEST_COWBOY_STUB"]
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
            openSchedule()
            finishSchedule()
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

    private func entryElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func revealEntryElement(_ element: XCUIElement, towardBottom: Bool = true) {
        for _ in 0..<12 where !element.isHittable {
            let scrollDown = element.exists && !element.frame.isEmpty
                ? element.frame.midY > app.frame.midY : towardBottom
            if scrollDown { app.swipeUp() } else { app.swipeDown() }
        }
    }

    private func openSchedule() {
        let button = app.buttons["openSchedule"].firstMatch
        revealEntryElement(button)
        XCTAssertTrue(button.isHittable, "The shared Schedule entry point is missing")
        button.tap()
        XCTAssertTrue(entryElement("scheduleForm").waitForExistence(timeout: 5),
                      "Schedule did not open its separate form")
    }

    private func finishSchedule() {
        let done = app.buttons["scheduleDone"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Schedule Done did not return to the entry")
    }

    private func cancelSchedule() {
        guard let cancel = app.navigationBars.buttons.matching(identifier: "Cancel").allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("Schedule Cancel is missing")
            return
        }
        cancel.tap()
        XCTAssertTrue(app.buttons["scheduleDone"].firstMatch.waitForNonExistence(timeout: 5),
                      "Schedule Cancel did not return to the entry")
    }

    private func chooseSchedule(_ value: String, identifier: String, towardBottom: Bool = true) {
        let picker = entryElement(identifier)
        revealEntryElement(picker, towardBottom: towardBottom)
        XCTAssertTrue(picker.isHittable, "The \(identifier) picker is missing")
        picker.tap()
        let option = app.buttons[value].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "The \(value) choice is missing")
        option.tap()
    }

    private func assertScheduleChoice(_ value: String, identifier: String) {
        let picker = entryElement(identifier)
        revealEntryElement(picker)
        let renderedValue = [picker.label, picker.value as? String ?? ""].joined(separator: " ")
        XCTAssertTrue(renderedValue.contains(value), "\(identifier) did not retain \(value): \(renderedValue)")
    }

    // Compact pickers expose a combined value or separate date/time controls across iOS versions.
    private func scheduleValues(_ picker: XCUIElement) -> [String] {
        let elements = [picker] + picker.descendants(matching: .any).allElementsBoundByIndex
        let values = elements.flatMap { [$0.label, $0.value as? String ?? ""] }
            .filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }
        return Array(Set(values)).sorted()
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

    private func pinAndUnpin(_ title: String, cardIdentifier: String) {
        let card = app.descendants(matching: .any)[cardIdentifier].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let compactHeight = card.frame.height
        XCTAssertLessThanOrEqual(compactHeight, 64, "An unpinned first card must stay thin")
        revealActions(title)
        tapVisibleButton("swipePin")
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "\(title) missing after pin")
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            card.frame.height >= 186
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed,
                       "Pinning must expand the card")
        revealActions(title)
        XCTAssertTrue(app.buttons["swipeUnpin"].waitForExistence(timeout: 5), "Unpin action did not replace Pin")
        tapVisibleButton("swipeUnpin")
        let compact = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(card.frame.height - compactHeight) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [compact], timeout: 5), .completed,
                       "Unpinning must restore the original thin height even at list position zero")
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
        pinAndUnpin(title, cardIdentifier: "upNextCard0")
        completeAndDelete(title, completedSectionId: "completedRemindersSection")
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
        XCTAssertFalse(app.staticTexts["GREATEST LEVERAGE"].exists)
        let carousel = app.scrollViews["greatestLeverageCarousel"].firstMatch
        XCTAssertFalse(app.staticTexts["The Adam Pattern"].exists)
        XCTAssertTrue(carousel.waitForExistence(timeout: 12), "The homepage carousel was missing")

        let topScreenshot = XCTAttachment(screenshot: app.screenshot())
        topScreenshot.name = "homepage-carousel-without-greatest-leverage"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        let homeScroll = app.scrollViews["editorialHomeScroll"].firstMatch
        let connection = app.descendants(matching: .any)["homeContentSection-beliefs"].firstMatch
        let ontology = app.descendants(matching: .any)["homeContentSection-ontology"].firstMatch
        let essays = app.descendants(matching: .any)["homeContentSection-field-essays"].firstMatch
        let news = app.descendants(matching: .any)["homeContentSection-news-channel"].firstMatch
        XCTAssertTrue(news.waitForExistence(timeout: 5), "Social Media Posts did not begin the vertical content area")
        XCTAssertTrue(app.staticTexts["Social Media Posts"].waitForExistence(timeout: 5))
        XCTAssertLessThan(carousel.frame.maxY, news.frame.minY)
        XCTAssertFalse(app.descendants(matching: .any)["homeContentDivider-after-beliefs"].exists)

        for section in [connection, ontology, essays] {
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

        // Actual page screenshots complete the visual review. These routes only navigate;
        // they do not save entries or change the homepage's stored section-pin preference.
        for (tab, screenID) in [("Reminders", "remindersHome"), ("Actions", "actionsHome")] {
            openTab(tab)
            let screen = app.descendants(matching: .any).matching(identifier: screenID).firstMatch
            XCTAssertTrue(screen.waitForExistence(timeout: 10), "\(tab) page did not open")
            captureSettledPage("visual-\(tab.lowercased())", anchor: screen.staticTexts[tab].firstMatch)
        }

        openTab("Calendar")
        let calendarScroll = app.scrollViews.firstMatch
        let todayButton = app.buttons["Today"].firstMatch
        // Calendar initially scrolls to the current hour. Bring its header and month back
        // into view before separately photographing the timeline through its Today control.
        for _ in 0..<8 where !todayButton.isHittable { calendarScroll.swipeDown() }
        captureSettledPage("visual-calendar-header-and-month", anchor: todayButton)
        XCTAssertFalse(app.buttons["Next month"].frame.intersects(app.buttons["SAVY menu"].frame),
                       "The account menu overlaps the next-month control")
        todayButton.tap()
        let hour = max(0, Calendar.current.component(.hour, from: Date()) - 1)
        let hourDate = Calendar.current.date(from: DateComponents(hour: hour)) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let hourLabel = app.staticTexts[formatter.string(from: hourDate)].firstMatch
        captureSettledPage("visual-calendar-timeline", anchor: hourLabel)

        app.buttons["Now"].firstMatch.tap()
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 10), "Now did not reopen")
        openVisualContentSection("ontology", screenshot: "visual-ontology")
        returnFromContentPage(expected: homeScroll)
        openVisualContentSection("field-essays", screenshot: "visual-field-essays")

        // Content is read from the existing page. A row tap opens a detail without editing
        // it; no fixture words, source strings, font constants, or color constants are tested.
        let contentRow = app.scrollViews.firstMatch.buttons.firstMatch
        if contentRow.exists {
            scrollVisualTargetIntoView(contentRow, in: app.scrollViews.firstMatch)
            XCTAssertTrue(contentRow.isHittable, "Field Essays content row could not be reached")
            contentRow.tap()
            let sectionHeader = app.descendants(matching: .any).matching(identifier: "sectionPageHeader").firstMatch
            XCTAssertTrue(sectionHeader.waitForNonExistence(timeout: 10), "Content detail did not open")
            let detailText = app.scrollViews.firstMatch.staticTexts.firstMatch
            captureSettledPage("visual-field-essays-detail", anchor: detailText)
            returnFromContentPage(expected: sectionHeader)
        }
        returnFromContentPage(expected: homeScroll)
    }

    private func openVisualContentSection(_ sectionID: String, screenshot: String) {
        let home = app.scrollViews["editorialHomeScroll"].firstMatch
        let card = app.descendants(matching: .any)
            .matching(identifier: "homeContentSection-\(sectionID)").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Homepage section \(sectionID) is missing")
        scrollVisualTargetIntoView(card, in: home)
        XCTAssertTrue(card.isHittable, "Homepage section \(sectionID) could not be reached")
        card.tap()
        let header = app.descendants(matching: .any).matching(identifier: "sectionPageHeader").firstMatch
        captureSettledPage(screenshot, anchor: header)
    }

    private func returnFromContentPage(expected destination: XCUIElement) {
        // These content pages have one leading native navigation-back button.
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Content navigation back button is missing")
        back.tap()
        XCTAssertTrue(destination.waitForExistence(timeout: 10), "Content back navigation did not return")
    }

    private func scrollVisualTargetIntoView(_ target: XCUIElement, in scroll: XCUIElement) {
        for _ in 0..<8 where !target.isHittable {
            if target.exists && !target.frame.isEmpty && target.frame.midY < app.frame.midY {
                scroll.swipeDown()
            } else {
                scroll.swipeUp()
            }
        }
    }

    private func captureSettledPage(_ name: String, anchor: XCUIElement) {
        XCTAssertTrue(anchor.waitForExistence(timeout: 10), "Screenshot anchor for \(name) is missing")
        var previousFrame = CGRect.null
        var stableSamples = 0
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard anchor.exists && anchor.isHittable && !anchor.frame.isEmpty else {
                stableSamples = 0
                return false
            }
            let frame = anchor.frame
            stableSamples = frame == previousFrame ? stableSamples + 1 : 0
            previousFrame = frame
            return stableSamples >= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed,
                       "\(name) did not settle on a visible screen")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
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

        // Adam replaced the fixed first/second/third card sizes with Post-style cards:
        // any independently pinned card expands; unpinned cards remain compact. The
        // pin interaction and persistence are covered by SAVYConnectionEntryUITests.
        let screen = app.descendants(matching: .any)["connectionScreen"].firstMatch
        let count = app.descendants(matching: .any)["connectionSavedCount"].firstMatch
        let plus = app.descendants(matching: .any)["newConnection"].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 12), "Connection page is missing")
        XCTAssertTrue(count.exists, "The Connection count is missing")
        XCTAssertTrue(plus.exists, "The Connection entry button is missing")
        let source = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'connectionSourceRow-'"))
            .firstMatch
        XCTAssertTrue(source.exists, "The existing source connections disappeared")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "connection-reuses-post-cards-and-adds-entry-control"
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
        XCTAssertTrue(app.scrollViews["greatestLeverageCarousel"].waitForExistence(timeout: 10), "The left phone edge did not return to Now")
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

    func testHourlySchedulePersistsAndCancelDiscardsScheduleEdits() {
        let title = "Synthetic hourly schedule \(Int(Date().timeIntervalSince1970))"
        let location = "Synthetic reading room"
        let notes = "Synthetic schedule note.\nKeep both lines."
        openComposer(.action)
        let titleInput = titleField()
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10))
        titleInput.tap()
        titleInput.typeText(title)
        openSchedule()

        let locationInput = entryElement("scheduleLocation")
        revealEntryElement(locationInput)
        locationInput.tap()
        locationInput.typeText(location)

        // Selecting Hourly must turn an all-day entry into a bounded timed schedule.
        let allDay = app.switches["scheduleAllDay"].firstMatch
        revealEntryElement(allDay)
        if allDay.value as? String == "0" { allDay.tap() }
        XCTAssertEqual(allDay.value as? String, "1")
        chooseSchedule("Hourly", identifier: "scheduleAlert")
        let summary = entryElement("scheduleHourlySummary")
        revealEntryElement(summary)
        XCTAssertTrue(summary.label.hasPrefix("Every hour until "),
                      "Hourly must show the finite end instead of an open-ended cadence")
        XCTAssertNotNil(summary.label.rangeOfCharacter(from: .decimalDigits),
                        "The Hourly summary must include its end time")
        let expectedSummary = summary.label

        let starts = entryElement("scheduleStarts")
        let ends = entryElement("scheduleEnds")
        revealEntryElement(starts, towardBottom: false)
        XCTAssertEqual(allDay.value as? String, "0", "Hourly must use timed mode")
        let expectedStarts = scheduleValues(starts)
        let expectedEnds = scheduleValues(ends)
        XCTAssertFalse(expectedStarts.isEmpty)
        XCTAssertFalse(expectedEnds.isEmpty)
        XCTAssertNotEqual(expectedStarts, expectedEnds, "The Hourly period must have a distinct end")

        let calendar = entryElement("scheduleCalendar")
        revealEntryElement(calendar)
        XCTAssertTrue(calendar.label.contains("SAVY"), "A new schedule must stay in SAVY by default")
        // Do not open Calendar, invite anyone, or send email during isolated UI acceptance.
        let notesInput = entryElement("scheduleNotes")
        revealEntryElement(notesInput)
        notesInput.tap()
        notesInput.typeText(notes)
        finishSchedule()

        func assertSavedSchedule() {
            revealEntryElement(locationInput)
            XCTAssertEqual(locationInput.value as? String, location)
            revealEntryElement(starts)
            XCTAssertEqual(allDay.value as? String, "0")
            XCTAssertEqual(scheduleValues(starts), expectedStarts)
            XCTAssertEqual(scheduleValues(ends), expectedEnds)
            assertScheduleChoice("Hourly", identifier: "scheduleAlert")
            revealEntryElement(summary)
            XCTAssertEqual(summary.label, expectedSummary, "The finite Hourly end changed")
            revealEntryElement(notesInput)
            XCTAssertEqual(notesInput.value as? String, notes, "Schedule notes did not persist intact")
        }

        // Done applies to the entry draft; cancelling a subsequent Schedule edit must not.
        openSchedule()
        revealEntryElement(locationInput)
        locationInput.tap()
        locationInput.typeText(" cancelled change")
        chooseSchedule("None", identifier: "scheduleAlert")
        revealEntryElement(notesInput)
        notesInput.tap()
        notesInput.typeText(" cancelled change")
        cancelSchedule()
        openSchedule()
        assertSavedSchedule()
        finishSchedule()
        app.buttons["Save"].tap()

        openTab("Actions")
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments.removeAll { $0 == "SAVY_UI_TEST_RESET_REMINDERS" }
        app.launch()
        dismissNotificationPrompt()
        openTab("Actions")
        let savedEntry = app.staticTexts[title].firstMatch
        XCTAssertTrue(savedEntry.waitForExistence(timeout: 10), "The saved scheduled entry disappeared")
        savedEntry.tap()
        XCTAssertTrue(titleField().waitForExistence(timeout: 10))
        openSchedule()
        assertSavedSchedule()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "hourly-schedule-notes-persist-after-relaunch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        cancelSchedule()
    }

    func testGreatestLeverageCardUsesReminderMetadataAndOpensOriginalEntry() {
        let title = "Pinned Leverage \(Int(Date().timeIntervalSince1970))"
        let tag = "carousel-metadata"
        func revealFormElement(_ element: XCUIElement) {
            for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        }
        // The Event composer begins with a date. Changing its shared destination to Action
        // proves Home hides the schedule without deleting it from the shared entry.
        openComposer(.calendar)

        let actionDestination = app.buttons["Action"].firstMatch
        XCTAssertTrue(actionDestination.waitForExistence(timeout: 10), "Shared destination picker was missing")
        actionDestination.tap()

        let field = titleField()
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Entry form did not open")
        field.tap()
        field.typeText(title)

        let tagField = app.textFields["Add a tag"].firstMatch
        revealFormElement(tagField)
        XCTAssertTrue(tagField.isHittable, "The shared Tags field was missing")
        tagField.tap()
        tagField.typeText(tag + ",")

        openSchedule()
        let duePicker = entryElement("scheduleStarts")
        revealEntryElement(duePicker)
        XCTAssertTrue(duePicker.isHittable, "The entry's stored date and time were missing")
        let originalDueValues = scheduleValues(duePicker)
        XCTAssertFalse(originalDueValues.isEmpty, "The date picker did not expose its stored date and time")
        finishSchedule()
        app.buttons["Save"].tap()

        openTab("Actions")
        let savedTitle = app.staticTexts[title].firstMatch
        XCTAssertTrue(savedTitle.waitForExistence(timeout: 12), "Saved action did not appear")
        let actionCard = app.descendants(matching: .any)["topActionCard"].firstMatch
        XCTAssertLessThanOrEqual(actionCard.frame.height, 64, "An unpinned action must use the thin layout")
        XCTAssertFalse(actionCard.staticTexts["#" + tag].exists,
                       "Unpinned cards must not grow to display metadata")
        revealActions(title)
        tapVisibleButton("swipePin")
        let schedule = actionCard.staticTexts.matching(NSPredicate(
            format: "label MATCHES %@", ".*[0-9]:[0-9]{2}.*"
        )).firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 5), "The Actions card lost its saved schedule")
        let savedSchedule = schedule.label
        XCTAssertFalse(actionCard.staticTexts["ACTION"].exists, "The Actions card still repeats its type above the title")
        XCTAssertTrue(actionCard.staticTexts["#" + tag].exists, "The shared card metadata was missing")
        openTab("Now")
        let card = app.buttons["greatestLeverageReminder"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 12), "Pinned entry did not appear in the homepage carousel")
        XCTAssertTrue(card.label.contains(title), "The homepage carousel card did not retain the original title")
        XCTAssertFalse(card.label.contains("ACTION"), "The carousel still shows a type label above its title")
        XCTAssertTrue(card.label.contains("#" + tag), "The carousel did not show the shared card metadata")
        XCTAssertFalse(card.label.contains(savedSchedule), "The homepage carousel still shows date and time")
        XCTAssertFalse(app.descendants(matching: .any)["greatestLeverageDate"].exists,
                       "The old carousel date line is still present")
        XCTAssertEqual(card.frame.width, 282, accuracy: 1, "The carousel card width changed")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "homepage-carousel-reminder-metadata-without-schedule"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        card.tap()
        let reopenedTitle = titleField()
        XCTAssertTrue(reopenedTitle.waitForExistence(timeout: 10), "The homepage carousel card did not open its entry")
        XCTAssertEqual(reopenedTitle.value as? String, title, "The homepage carousel opened a different entry")
        openSchedule()
        revealEntryElement(duePicker)
        XCTAssertTrue(duePicker.isHittable, "The original entry's date picker did not reopen")
        XCTAssertEqual(scheduleValues(duePicker), originalDueValues,
                       "Hiding the carousel schedule changed the saved date or time")
    }

    func testActionCreateReopenSwipePinDoneDelete() {
        let title = "UI Test Action \(Int(Date().timeIntervalSince1970))"
        createItem(.action, title: title)
        openTab("Actions")
        reopenItem(title)
        gentlySwipeRightThenLeft(title)
        pinAndUnpin(title, cardIdentifier: "topActionCard")
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
