import XCTest

@MainActor
extension XCUIElement {
    func tapOrClick() {
        #if targetEnvironment(macCatalyst)
        click()
        #else
        tap()
        #endif
    }
}

@MainActor
extension XCUICoordinate {
    func tapOrClick() {
        #if targetEnvironment(macCatalyst)
        click()
        #else
        tap()
        #endif
    }

    #if targetEnvironment(macCatalyst)
    func trackpadSwipe(right: Bool) {
        hover()
        if right { swipeRight(velocity: .slow) } else { swipeLeft(velocity: .slow) }
    }
    #endif
}

@MainActor
extension XCUIApplication {
    var interactionFrame: CGRect {
        #if targetEnvironment(macCatalyst)
        windows.firstMatch.frame
        #else
        frame
        #endif
    }

    var cardPageScrollView: XCUIElement {
        // iOS exposes the keyboard's prediction strip as the first scroll view.
        // Choose the page by visible area instead of scrolling that strip.
        scrollViews.allElementsBoundByIndex.max {
            let first = $0.frame.intersection(interactionFrame)
            let second = $1.frame.intersection(interactionFrame)
            return first.width * first.height < second.width * second.height
        } ?? self
    }

    var cardPageViewport: CGRect {
        var viewport = cardPageScrollView.frame.intersection(interactionFrame)
        #if !targetEnvironment(macCatalyst)
        let keyboard = keyboards.firstMatch
        if keyboard.exists {
            // Keyboard's frame covers its keys; its prediction/accessory strip
            // is a separate accessibility element immediately above them.
            for surface in [keyboard, otherElements["inputView"].firstMatch,
                            otherElements["SystemInputAssistantView"].firstMatch]
                where surface.exists && surface.frame.intersects(viewport) {
                viewport.size.height = max(0, surface.frame.minY - viewport.minY)
            }
        }
        #endif
        return viewport
    }

    func scrollPage(up: Bool) {
        #if targetEnvironment(macCatalyst)
        // Catalyst's application frame is infinite; target the actual window.
        let center = windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        if up { center.swipeUp() } else { center.swipeDown() }
        #else
        // The application midpoint can land on the keyboard or the bottom bar
        // during inline editing. Start the gesture inside the actual scroll view.
        let target = cardPageScrollView
        if up { target.swipeUp() } else { target.swipeDown() }
        #endif
    }
}

/// Exercises real card gestures on iPhone and Mac Catalyst. Every launch
/// uses the isolated SAVYUITests repositories; fixture creation never reaches live data.
@MainActor
final class SAVYCardReorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = [
                "SAVY_UI_TEST_UNLOCKED", "SAVY_UI_TEST_RESET_REMINDERS", "SAVY_UI_TEST_COWBOY_STUB",
            ]
            if name.contains("testPostsReorderBothPinGroupsAndKeepTheirNumbersAfterRelaunch")
                || name.contains("testSocialCardsUseTheReminderSwipeBehavior")
                || name.contains("testHomeCardsReorderBelowPinnedCardAndOpenAfterRelaunch")
                || name.contains("testHomeCardsCanAllRemainPinnedAndKeepTheirOrderAfterRelaunch") {
                app.launchEnvironment["SAVY_UI_TEST_SEED_POST_COUNT"] = "4"
            }
            if name.contains("testActionsMovePastVisibleNeighborAndKeepPinGroupsAfterRelaunch") {
                app.launchArguments.append("SAVY_UI_TEST_SEED_REORDER_ACTIONS")
            }
            if name.contains("testMacTrackpadVerticalScrollKeepsSwipeActionsClosed") {
                app.launchEnvironment["SAVY_UI_TEST_SEED_POST_COUNT"] = "40"
            }
            app.launch()
            dismissSystemPrompt()
        }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    func testHomeCardsReorderBelowPinnedCardAndOpenAfterRelaunch() {
        let initial = ["news-channel", "beliefs", "ontology", "field-essays"]
        let moved = ["news-channel", "ontology", "beliefs", "field-essays"]
        assertHomeCardDetails()
        attach("00 Home pinned Post summary and compact destination cards")
        reveal(homeRow("ontology"))
        assertOrder(initial.map(homeRow))

        arm(element("homeReorder-ontology"))
        attach("01 Home card held with inline title and move arrows")
        moveUp()
        assertOrder(moved.map(homeRow))

        // The first unpinned card cannot displace the pinned Social Media Posts card.
        moveUp()
        assertOrder(moved.map(homeRow))
        attach("02 Home card moved below the pinned card")

        // Holding now edits the title directly. Finish that edit before navigating
        // the list, then verify moving a card has not changed normal scrolling.
        disarm(element("homeReorder-ontology"))
        let ontologyRow = homeRow("ontology")
        let ontologyBeforeScroll = ontologyRow.frame.minY
        app.scrollViews["editorialHomeScroll"].firstMatch.swipeUp()
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(ontologyRow.frame.minY - ontologyBeforeScroll) > 20
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 5), .completed,
                       "A reordered card prevented normal vertical Home scrolling")
        XCTAssertTrue(app.buttons["reorderUp"].firstMatch.waitForNonExistence(timeout: 5),
                      "Finishing the inline edit did not dismiss its move controls")
        reveal(homeRow("field-essays"))
        assertOrder(moved.map(homeRow))
        attach("02b Home scroll reaches Field Essays without changing card order")

        relaunchKeepingIsolatedData()
        assertHomeCardDetails()
        reveal(homeRow("ontology"))
        assertOrder(moved.map(homeRow))
        attach("03 Home order retained after relaunch")

        element("homeReorder-ontology").tap()
        let header = element("sectionPageHeader")
        XCTAssertTrue(header.waitForExistence(timeout: 10), "The moved Home card did not open its page")
        XCTAssertEqual(header.label, "Adam's Ontology", "The moved Home card opened a different page")
    }

    func testAllHomeCardsUseTheReminderSwipeBehavior() {
        for section in ["news-channel", "beliefs", "ontology", "field-essays"] {
            let action = homeRow(section).value as? String == "Pinned" ? "Unpin" : "Pin"
            assertCardSwipeBehavior(in: app, card: element("homeReorder-\(section)"),
                                    actions: [action], name: "Home \(section)")
        }
    }

    func testTappingOutsideCardSavesAndClosesKeyboard() {
        let card = element("homeReorder-beliefs")
        reveal(card)
        openCardTitleEditor(in: app, card: card)
        let field = app.textFields["cardTitleField"].firstMatch
        let original = field.value as? String ?? ""
        #if targetEnvironment(macCatalyst)
        field.typeText("s")
        #else
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.keyboards.keys["s"].tap()
        #endif
        XCTAssertEqual(field.value as? String, original + "s", "Keyboard input must not finish editing")
        field.tapOrClick()
        XCTAssertTrue(field.exists, "A tap inside the card must keep editing")
        XCTAssertEqual(field.value as? String, original + "s")
        attach("Title remains editable with the software keyboard")
        tapOutsideCardTitle(in: app)
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        #if !targetEnvironment(macCatalyst)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "The outside tap must close the keyboard")
        #endif
        XCTAssertTrue(card.exists, "Tapping the page header must keep the current page open")
        XCTAssertEqual(element("homeCardTitle-beliefs").label, original + "s")
        attach("Outside tap saves the title and closes the keyboard")

        relaunchKeepingIsolatedData()
        reveal(card)
        XCTAssertEqual(element("homeCardTitle-beliefs").label, original + "s", "The outside tap must persist the title")
        openCardTitleEditor(in: app, card: card)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count + 1))
        tapOutsideCardTitle(in: app)
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(card.exists, "Finishing an empty title must keep the current page open")
        XCTAssertEqual(element("homeCardTitle-beliefs").label, original + "s", "An empty draft must retain the saved title")
    }

    func testCardTitlesPersistAcrossRelaunchAndSourcePages() {
        let home = element("homeReorder-beliefs")
        reveal(home)
        openCardTitleEditor(in: app, card: home)
        let title = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", "Card title", XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue)).firstMatch
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (title.value as? String ?? "").count))
        title.typeText("My connections")
        app.buttons["Save"].tapOrClick()
        relaunchKeepingIsolatedData()
        reveal(home)
        XCTAssertEqual(element("homeCardTitle-beliefs").label, "My connections")
        home.tapOrClick()
        XCTAssertTrue(element("connectionScreen").waitForExistence(timeout: 10),
                      "Renaming a destination must preserve its navigation")

        for section in ["ontology", "field-essays", "news-channel"] {
            relaunchKeepingIsolatedData()
            let row = element("homeReorder-\(section)")
            reveal(row)
            row.tapOrClick()
            let source = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'sourceCard-'")).firstMatch
            XCTAssertTrue(source.waitForExistence(timeout: 10))
            for _ in 0..<8 where !source.isHittable { app.scrollPage(up: true) }
            assertCardTitleEditing(in: app, card: source, name: "Source \(section)")
        }

        relaunchKeepingIsolatedData()
        let carousel = element("greatestLeverageEntry")
        XCTAssertTrue(carousel.waitForExistence(timeout: 10))
        assertCardTitleEditing(in: app, card: carousel, name: "Home carousel")
    }

    #if targetEnvironment(macCatalyst)
    func testMacTrackpadVerticalScrollKeepsSwipeActionsClosed() {
        openPostsPage()
        let card = postRow(2)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let original = card.frame
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).swipeUp(velocity: .slow)
        XCTAssertLessThan(card.frame.minY, original.minY - 20,
                          "A vertical trackpad swipe over a card must scroll the page")
        XCTAssertEqual(card.frame.minX, original.minX, accuracy: 2)
        for action in ["Posted", "Unpin", "Pin", "Delete"] {
            XCTAssertFalse(app.buttons["swipe\(action)"].exists,
                           "Vertical scrolling must not reveal card actions")
        }
        XCTAssertFalse(app.buttons["reorderUp"].exists)
        attach("Mac vertical trackpad scroll preserves closed card actions")
    }
    #endif

    func testSocialCardsUseTheReminderSwipeBehavior() {
        openPostsPage()
        assertCardSwipeBehavior(in: app, card: postRow(2),
                                actions: ["Posted", "Unpin", "Delete"], name: "Pinned Social")
        assertCardSwipeBehavior(in: app, card: postRow(3),
                                actions: ["Posted", "Pin", "Delete"], name: "Compact Social")
    }

    func testHomeCardsCanAllRemainPinnedAndKeepTheirOrderAfterRelaunch() {
        let sections = ["news-channel", "beliefs", "ontology", "field-essays"]
        var pinned: Set<String> = ["news-channel"]
        var order = sections
        func assertSwipeActionsAreClosed() {
            for section in sections {
                for identifier in ["swipePin", "swipeUnpin"] {
                    XCTAssertFalse(homeRow(section).buttons[identifier].firstMatch.isHittable,
                                   "Home pin actions should only be available after a right swipe")
                }
            }
        }
        reveal(homeRow("news-channel"))
        assertHomePins(pinned, sections: sections)
        assertSwipeActionsAreClosed()

        for section in sections.dropFirst() {
            setHomePinned(true, section: section)
            pinned.insert(section)
            order.removeAll { $0 == section }
            order.insert(section, at: 0)
            assertOrder(order.map(homeRow))
            assertHomePins(pinned, sections: sections)
            assertSwipeActionsAreClosed()
        }
        attach("04 All four Home cards retain independent pins")

        // Each new pin must be first, above all prior pins. Manual reorder remains
        // available within that group after the new-pin placement is verified.
        let movedSection = order[1]
        arm(element("homeReorder-\(movedSection)"))
        moveUp()
        order.swapAt(0, 1)
        assertOrder(order.map(homeRow))
        assertHomePins(pinned, sections: sections)
        attach("05 A pinned Home card moves within the pinned group")
        disarm(element("homeReorder-\(movedSection)"))

        let unpinnedSection = order[1]
        setHomePinned(false, section: unpinnedSection)
        pinned.remove(unpinnedSection)
        order = order.filter { $0 != unpinnedSection } + [unpinnedSection]
        assertHomePins(pinned, sections: sections)
        assertOrder(order.map(homeRow))

        arm(element("homeReorder-\(unpinnedSection)"))
        moveUp()
        assertOrder(order.map(homeRow))
        assertHomePins(pinned, sections: sections)
        attach("06 Unpinning one Home card leaves the other three pinned")
        disarm(element("homeReorder-\(unpinnedSection)"))

        // A second unpin must become the first unpinned card, ahead of the one
        // already in that group, while preserving every remaining independent pin.
        let secondUnpinnedSection = order[1]
        setHomePinned(false, section: secondUnpinnedSection)
        pinned.remove(secondUnpinnedSection)
        order = order.filter { pinned.contains($0) }
            + [secondUnpinnedSection]
            + order.filter { !pinned.contains($0) && $0 != secondUnpinnedSection }
        assertHomePins(pinned, sections: sections)
        assertOrder(order.map(homeRow))
        assertSwipeActionsAreClosed()
        attach("06b New unpin leads the unpinned Home cards below the remaining pins")

        relaunchKeepingIsolatedData()
        reveal(homeRow(unpinnedSection))
        assertHomePins(pinned, sections: sections)
        assertOrder(order.map(homeRow))
        assertSwipeActionsAreClosed()
        attach("07 Independent Home pins and pinned order survive relaunch")
    }

    func testPostsReorderBothPinGroupsAndKeepTheirNumbersAfterRelaunch() {
        openPostsPage()
        XCTAssertEqual(element("postSavedCount").label, "4 / 50")
        reveal(postRow(3))
        assertOrder([2, 1, 4, 3].map(postRow))
        let numbers = Dictionary(uniqueKeysWithValues: (1...4).map { number in
            (number, postContainer(number).label)
        })
        for number in 1...4 {
            XCTAssertEqual(numbers[number], "#\(number)", "Every post needs its stored reference before moving")
        }

        arm(postRow(1))
        attach("10 Pinned Post held with inline title and move arrows")
        moveUp()
        assertOrder([1, 2, 4, 3].map(postRow))
        attach("11 Pinned Post moved within pinned cards")
        disarm(postRow(1))

        arm(postRow(3))
        attach("12 Unpinned Post held with inline title and move arrows")
        moveUp()
        assertOrder([1, 2, 3, 4].map(postRow))
        // A second upward move is blocked at the boundary rather than pinning the post.
        moveUp()
        assertOrder([1, 2, 3, 4].map(postRow))
        XCTAssertEqual(postContainer(3).value as? String, "Unpinned")
        attach("13 Unpinned Post moved below pinned cards")

        disarm(postRow(3))
        let movedPost = postRow(3)
        let postBeforeScroll = movedPost.frame.minY
        app.swipeUp()
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(movedPost.frame.minY - postBeforeScroll) > 20
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 5), .completed,
                       "A reordered Post prevented normal vertical scrolling")
        XCTAssertTrue(app.buttons["reorderUp"].firstMatch.waitForNonExistence(timeout: 5),
                      "Finishing the inline edit did not dismiss its move controls")
        assertOrder([1, 2, 3, 4].map(postRow))
        attach("13b Posts scroll normally and retain their order")

        relaunchKeepingIsolatedData()
        openPostsPage()
        reveal(postRow(4))
        assertOrder([1, 2, 3, 4].map(postRow))
        XCTAssertEqual(element("postSavedCount").label, "4 / 50")
        for number in 1...4 {
            XCTAssertEqual(postContainer(number).label, numbers[number],
                           "Moving or relaunching changed a stored Post number")
            XCTAssertEqual(postContainer(number).value as? String, number <= 2 ? "Pinned" : "Unpinned",
                           "Moving or relaunching changed a Post's pin state")
        }
        attach("14 Post order, pins, and numbers retained after relaunch")

        reveal(postRow(3))
        postRow(3).tap()
        let answer = element("DecideAnswer0")
        XCTAssertTrue(answer.waitForExistence(timeout: 10), "The moved Post did not open its saved entry")
        let savedText = answer.value as? String ?? ""
        XCTAssertTrue(savedText.contains("\n\nSynthetic post 3 starts with a clear observation."))
        XCTAssertTrue(savedText.contains("This additional synthetic sentence"),
                      "Moving a card must retain its full saved question and answer")
    }

    func testActionsMovePastVisibleNeighborAndKeepPinGroupsAfterRelaunch() {
        openActions()
        reveal(actionGesture(4))
        assertOrder([1, 2, 3, 4].map(actionTitle))

        // The isolated fixture contains a hidden Reminder/Event between the Actions in
        // each pin group's stored ranks. One move must still pass the visible neighbor.
        arm(actionGesture(2))
        attach("20 Pinned Action held with inline title and move arrows")
        moveUp()
        assertOrder([2, 1, 3, 4].map(actionTitle))
        attach("21 Pinned Action moved past its visible neighbor")
        disarm(actionGesture(2))

        arm(actionGesture(4))
        attach("22 Unpinned Action held with inline title and move arrows")
        moveUp()
        assertOrder([2, 1, 4, 3].map(actionTitle))
        moveUp()
        assertOrder([2, 1, 4, 3].map(actionTitle))
        attach("23 Unpinned Action moved and stopped below pinned cards")

        relaunchKeepingIsolatedData()
        openActions()
        reveal(actionGesture(3))
        assertOrder([2, 1, 4, 3].map(actionTitle))
        attach("24 Action order retained after relaunch")

        reveal(actionGesture(4))
        actionGesture(4).tap()
        let title = element("Title")
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The moved Action did not open its saved entry")
        XCTAssertEqual(title.value as? String, "Synthetic unpinned action 2")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func homeRow(_ section: String) -> XCUIElement {
        element("homeContentSection-\(section)")
    }

    private func setHomePinned(_ pinned: Bool, section: String) {
        let row = homeRow(section)
        XCTAssertEqual(row.value as? String, pinned ? "Unpinned" : "Pinned")
        let gesture = element("homeReorder-\(section)")
        reveal(gesture)
        gesture.swipeRight()
        let button = row.buttons[pinned ? "swipePin" : "swipeUnpin"].firstMatch
        reveal(button)
        button.tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", pinned ? "Pinned" : "Unpinned"),
            object: row
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
                       "The selected Home card did not change its pin state")
    }

    private func assertHomePins(_ pinned: Set<String>, sections: [String]) {
        for section in sections {
            XCTAssertEqual(homeRow(section).value as? String, pinned.contains(section) ? "Pinned" : "Unpinned",
                           "Pinning or unpinning one Home card changed another card's pin")
        }
    }

    private func assertHomeCardDetails() {
        let pinned = homeRow("news-channel")
        reveal(pinned)
        XCTAssertTrue(pinned.staticTexts["4 / 50 saved posts"].waitForExistence(timeout: 5),
                      "The pinned Home card should show the saved Post count")
        XCTAssertTrue(pinned.staticTexts["Posts #2 · #1 · #4"].exists,
                      "The Home summary should retain the first three stored Post references in list order")
        XCTAssertTrue(pinned.staticTexts["Synthetic post 2 starts with a clear observation."].exists,
                      "The pinned Home card should preview the first Post's authored sentence")
        XCTAssertEqual(pinned.staticTexts.matching(NSPredicate(format: "label == %@", "Social Media Posts")).count, 1,
                       "The Home card should show its title once")
        XCTAssertFalse(pinned.staticTexts["SOCIAL MEDIA POSTS"].exists,
                       "The Home card should not repeat its title in an eyebrow")
        let pinnedHeight = pinned.frame.height

        let compactCards = [
            ("beliefs", "Connection"),
            ("ontology", "Adam's Ontology"),
            ("field-essays", "Field Essays"),
        ]
        for (sectionID, title) in compactCards {
            let row = homeRow(sectionID)
            XCTAssertTrue(row.exists)
            XCTAssertLessThan(row.frame.height, pinnedHeight,
                              "Only the pinned Home card should expand to show saved details")
            // Reorder rows also contain their hidden swipe action. Ignore that control
            // when checking the actual destination card's title-only content.
            let text = row.staticTexts.allElementsBoundByIndex.map(\.label).filter {
                !$0.isEmpty && !["Pin", "Unpin", "Move up", "Move down"].contains($0)
            }
            XCTAssertEqual(text, [title], "An unpinned Home card should show its title once, without an eyebrow or detail")
        }
    }

    private func postUUID(_ number: Int) -> String {
        String(format: "00000000-0000-0000-0000-%012d", number)
    }

    private func postRow(_ number: Int) -> XCUIElement {
        element("postEntryRow-\(postUUID(number))")
    }

    private func postContainer(_ number: Int) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'postCard-'"))
            .containing(.any, identifier: "postEntryRow-\(postUUID(number))")
            .firstMatch
    }

    private func actionGesture(_ number: Int) -> XCUIElement {
        let uuid = String(format: "10000000-0000-0000-0000-%012d", number)
        return element("reminderReorderGesture-\(uuid)")
    }

    private func actionTitle(_ number: Int) -> XCUIElement {
        // The title becomes a text field while held; card identity and position
        // remain stable throughout editing and moving.
        actionGesture(number)
    }

    private func arm(_ target: XCUIElement) {
        reveal(target)
        target.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["reorderUp"].firstMatch.waitForExistence(timeout: 5),
                      "Long press did not show the upper reorder chevron")
        XCTAssertTrue(app.buttons["reorderDown"].firstMatch.exists,
                      "Long press did not show the lower reorder chevron")
    }

    private func disarm(_ target: XCUIElement) {
        app.buttons["saveCardTitle"].tapOrClick()
        XCTAssertTrue(app.buttons["reorderUp"].firstMatch.waitForNonExistence(timeout: 5),
                      "Finishing title editing should dismiss its reorder controls")
    }

    private func moveUp() {
        let up = app.buttons["reorderUp"].firstMatch
        XCTAssertTrue(up.waitForExistence(timeout: 5), "Reorder controls disappeared before the move")
        // SwiftUI can report an inline button as not hittable even when its
        // pixels are visible inside the card. Send a real tap to the visible
        // arrow; the callers verify that the saved card order actually changes.
        for _ in 0..<8 {
            let viewport = app.cardPageViewport
            let center = CGPoint(x: up.frame.midX, y: up.frame.midY)
            if viewport.contains(center) { break }
            app.scrollPage(up: center.y > viewport.midY)
        }
        XCTAssertTrue(app.cardPageViewport
            .contains(CGPoint(x: up.frame.midX, y: up.frame.midY)), "The move arrow is outside the visible card list")
        // A disabled boundary chevron and an enabled chevron with a no-op boundary are
        // both valid; either must leave the card in its existing pin group.
        if up.isEnabled { up.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tapOrClick() }
    }

    private func assertOrder(_ rows: [XCUIElement], file: StaticString = #filePath, line: UInt = #line) {
        let order = NSPredicate { _, _ in
            guard rows.allSatisfy({ $0.exists && !$0.frame.isEmpty }) else { return false }
            return zip(rows, rows.dropFirst()).allSatisfy { first, second in
                first.frame.minY < second.frame.minY
            }
        }
        let expectation = XCTNSPredicateExpectation(predicate: order, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 6), .completed,
                       "Cards did not appear in the expected visible order", file: file, line: line)
    }

    private func reveal(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        guard target.waitForExistence(timeout: 20) else {
            XCTFail("Expected card or control is missing", file: file, line: line)
            return
        }
        for _ in 0..<8 {
            // Inline editing can bring up the software keyboard. Use the real
            // scrolling viewport rather than the full screen behind the keyboard.
            let viewport = app.cardPageViewport
            let y = target.frame.midY
            if target.isHittable && y > viewport.minY + 120 && y < viewport.maxY - 20 { break }
            app.scrollPage(up: target.frame.isEmpty || y > viewport.midY)
        }
        XCTAssertTrue(target.isHittable, "Card or control could not be reached", file: file, line: line)
    }

    private func openPostsPage() {
        let card = homeRow("news-channel")
        reveal(card)
        card.tapOrClick()
        XCTAssertTrue(element("newsChannelPosts").waitForExistence(timeout: 12),
                      "The Home card did not open Social Media Posts")
    }

    private func openActions() {
        let tab = app.buttons["Actions"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        XCTAssertTrue(element("actionsHome").waitForExistence(timeout: 10), "Actions did not open")
    }

    private func relaunchKeepingIsolatedData() {
        app.terminate()
        app.launchArguments.removeAll {
            $0 == "SAVY_UI_TEST_RESET_REMINDERS" || $0 == "SAVY_UI_TEST_SEED_REORDER_ACTIONS"
        }
        app.launchEnvironment.removeValue(forKey: "SAVY_UI_TEST_SEED_POST_COUNT")
        app.launch()
        dismissSystemPrompt()
    }

    private func dismissSystemPrompt() {
        #if !targetEnvironment(macCatalyst)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        #endif
    }

    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

/// Runs the same physical gestures against each real screen, including one-, two-,
/// and three-action trays. No fixture data is written outside the isolated UI-test store.
@MainActor
extension XCTestCase {
    func assertCardSwipeBehavior(in app: XCUIApplication, card: XCUIElement,
                                 actions: [String], name: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        #if targetEnvironment(macCatalyst)
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5),
                      "The editor must finish closing before swiping \(name)", file: file, line: line)
        #endif
        XCTAssertTrue(card.waitForExistence(timeout: 10), "\(name) is missing", file: file, line: line)
        for _ in 0..<8 {
            let y = card.frame.midY
            if card.isHittable && y > 160 && y < app.interactionFrame.maxY - 210 { break }
            app.scrollPage(up: y > app.interactionFrame.midY)
        }
        XCTAssertTrue(card.isHittable, "\(name) is not reachable", file: file, line: line)
        let original = card.frame
        let width = CGFloat(actions.count) * 64

        func settled(_ offset: CGFloat) {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                abs(card.frame.minX - original.minX - offset) < 2
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                           "\(name) did not settle at \(offset); actual offset \(card.frame.minX - original.minX)",
                           file: file, line: line)
            XCTAssertEqual(card.frame.minY, original.minY, accuracy: 1,
                           "\(name) jumped vertically", file: file, line: line)
            XCTAssertEqual(card.frame.height, original.height, accuracy: 1,
                           "\(name) changed height during a swipe", file: file, line: line)
        }

        for action in actions {
            XCTAssertFalse(app.buttons["swipe\(action)"].exists,
                           "\(name) exposes a closed action", file: file, line: line)
        }
        #if targetEnvironment(macCatalyst)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).trackpadSwipe(right: true)
        settled(width)
        for action in actions {
            XCTAssertTrue(app.buttons["swipe\(action)"].firstMatch.isHittable,
                          "\(name) trackpad swipe covers \(action)", file: file, line: line)
        }
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).trackpadSwipe(right: false)
        settled(0)
        #endif
        dragCard(in: app, card: card, distance: width / 4)
        settled(0)
        dragCard(in: app, card: card, distance: width + 18)
        settled(width)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(name) swipe open"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        for action in actions {
            XCTAssertTrue(app.buttons["swipe\(action)"].firstMatch.isHittable,
                          "\(name) covers \(action)", file: file, line: line)
        }
        dragCard(in: app, card: card, distance: width / 4)
        settled(width)
        dragCard(in: app, card: card, distance: -width / 4)
        settled(width)
        dragCard(in: app, card: card, distance: -width * 0.8)
        settled(0)
        dragCard(in: app, card: card, distance: width + 18)
        settled(width)
        #if targetEnvironment(macCatalyst)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 20, dy: 0)).click()
        #else
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: card.frame.minX + 20, dy: card.frame.midY)).tap()
        #endif
        settled(0)
        XCTAssertTrue(card.isHittable, "\(name) opened instead of closing its tray", file: file, line: line)
        for action in actions {
            XCTAssertFalse(app.buttons["swipe\(action)"].exists,
                           "\(name) left a closed action accessible", file: file, line: line)
        }
        assertCardTitleEditing(in: app, card: card, name: name, file: file, line: line)
    }

    func openCardTitleEditor(in app: XCUIApplication, card: XCUIElement,
                             file: StaticString = #filePath, line: UInt = #line) {
        #if targetEnvironment(macCatalyst)
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5), file: file, line: line)
        let point = card.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        point.click(forDuration: 0.7, thenDragTo: point)
        #else
        card.press(forDuration: 0.7)
        #endif
        let field = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", "Card title", XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue)).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Holding the card did not place a cursor in its title", file: file, line: line)
        XCTAssertFalse(app.alerts["Change Title"].exists, "Title editing must stay inside the card", file: file, line: line)

    }

    func assertCardTitleEditing(in app: XCUIApplication, card: XCUIElement, name: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        openCardTitleEditor(in: app, card: card, file: file, line: line)
        let field = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", "Card title", XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue)).firstMatch
        let original = field.value as? String
        XCTAssertFalse((original ?? "").isEmpty, "The inline editor must begin with the existing title", file: file, line: line)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, original.map { String($0.dropLast()) },
                       "The cursor must start at the end, so Backspace removes only the last character", file: file, line: line)
        let editingProof = XCTAttachment(screenshot: app.screenshot())
        editingProof.name = "\(name) inline title and cursor"
        editingProof.lifetime = .keepAlways
        add(editingProof)
        let renamed = "Renamed \(name)"
        func titleIsVisible() -> Bool {
            card.label.contains(renamed) || app.staticTexts[renamed].exists
        }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count))
        field.typeText("Renamed \(name)")
        app.buttons["Cancel"].tapOrClick()
        XCTAssertFalse(titleIsVisible(), "Cancel changed the card", file: file, line: line)
        openCardTitleEditor(in: app, card: card, file: file, line: line)
        XCTAssertEqual(field.value as? String, original, "Cancel did not retain the original title", file: file, line: line)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count))
        field.typeText("Renamed \(name)")
        tapOutsideCardTitle(in: app)
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "An outside tap must finish title editing", file: file, line: line)
        #if !targetEnvironment(macCatalyst)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), file: file, line: line)
        #endif
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in titleIsVisible() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed,
                       "The new title did not appear on the card", file: file, line: line)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "\(name) renamed card"
        proof.lifetime = .keepAlways
        add(proof)
        openCardTitleEditor(in: app, card: card, file: file, line: line)
        XCTAssertEqual(field.value as? String, "Renamed \(name)", file: file, line: line)
        app.buttons["Use Original Title"].tapOrClick()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !titleIsVisible() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed, file: file, line: line)
    }

    func tapOutsideCardTitle(in app: XCUIApplication) {
        let frame = app.interactionFrame
        #if targetEnvironment(macCatalyst)
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        #else
        let origin = app.coordinate(withNormalizedOffset: .zero)
        #endif
        // The header's middle is outside the cards and keyboard. The narrow
        // page margins can fall inside iOS's expanded button hit targets.
        origin.withOffset(CGVector(dx: frame.width / 2, dy: 100)).tapOrClick()
    }

    func dragCard(in app: XCUIApplication, card: XCUIElement, distance: CGFloat) {
        #if targetEnvironment(macCatalyst)
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5),
                      "The editor must finish closing before dragging a card")
        // Precise partial distances use a native mouse drag. The shared assertion
        // separately opens and closes every card with native trackpad swipe events.
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 24, dy: 0))
        start.click(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.15)
        #else
        let x = min(card.frame.minX + 24, app.frame.maxX - 44)
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: card.frame.midY))
        start.press(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.15)
        #endif
    }
}
