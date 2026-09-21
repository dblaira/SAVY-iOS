import XCTest

/// Exercises the real card gestures and saved order on the connected iPhone. Every launch
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
            if name.contains("testPostsReorderBothPinGroupsAndKeepTheirNumbersAfterRelaunch") {
                app.launchEnvironment["SAVY_UI_TEST_SEED_POST_COUNT"] = "4"
            }
            if name.contains("testActionsMovePastVisibleNeighborAndKeepPinGroupsAfterRelaunch") {
                app.launchArguments.append("SAVY_UI_TEST_SEED_REORDER_ACTIONS")
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
        reveal(homeRow("ontology"))
        assertOrder(initial.map(homeRow))

        arm(element("homeReorder-ontology"))
        attach("01 Home card armed with glow and chevrons")
        moveUp()
        assertOrder(moved.map(homeRow))

        // The first unpinned card cannot displace the pinned Social Media Posts card.
        moveUp()
        assertOrder(moved.map(homeRow))
        attach("02 Home card moved below the pinned card")

        // Scrolling an armed Home list must release selection and move the viewport,
        // not consume the vertical gesture as another reorder or open the card.
        let ontologyRow = homeRow("ontology")
        let ontologyBeforeScroll = ontologyRow.frame.minY
        app.scrollViews["editorialHomeScroll"].firstMatch.swipeUp()
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(ontologyRow.frame.minY - ontologyBeforeScroll) > 20
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 5), .completed,
                       "An armed card prevented normal vertical Home scrolling")
        XCTAssertTrue(app.buttons["reorderUp"].firstMatch.waitForNonExistence(timeout: 5),
                      "Normal Home scrolling did not dismiss reorder controls")
        reveal(homeRow("field-essays"))
        assertOrder(moved.map(homeRow))
        attach("02b Home scroll reaches Field Essays without changing card order")

        relaunchKeepingIsolatedData()
        reveal(homeRow("ontology"))
        assertOrder(moved.map(homeRow))
        attach("03 Home order retained after relaunch")

        element("homeReorder-ontology").tap()
        let header = element("sectionPageHeader")
        XCTAssertTrue(header.waitForExistence(timeout: 10), "The moved Home card did not open its page")
        XCTAssertEqual(header.label, "Adam's Ontology", "The moved Home card opened a different page")
    }

    func testPostsReorderBothPinGroupsAndKeepTheirNumbersAfterRelaunch() {
        openPostsPage()
        XCTAssertEqual(element("postSavedCount").label, "4 / 50")
        reveal(postRow(3))
        assertOrder([2, 1, 4, 3].map(postRow))
        let numbers = Dictionary(uniqueKeysWithValues: (1...4).map { number in
            (number, element("postEntryNumber-\(postUUID(number))").label)
        })
        for number in 1...4 {
            XCTAssertEqual(numbers[number], "POST #\(number)", "Every post needs its stored reference before moving")
        }

        arm(postRow(1))
        attach("10 Pinned Post armed with glow and chevrons")
        moveUp()
        assertOrder([1, 2, 4, 3].map(postRow))
        attach("11 Pinned Post moved within pinned cards")
        disarm(postRow(1))

        arm(postRow(3))
        attach("12 Unpinned Post armed with glow and chevrons")
        moveUp()
        assertOrder([1, 2, 3, 4].map(postRow))
        // A second upward move is blocked at the boundary rather than pinning the post.
        moveUp()
        assertOrder([1, 2, 3, 4].map(postRow))
        XCTAssertEqual(postPin(3).label, "Pin post")
        attach("13 Unpinned Post moved below pinned cards")

        let movedPost = postRow(3)
        let postBeforeScroll = movedPost.frame.minY
        app.swipeUp()
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(movedPost.frame.minY - postBeforeScroll) > 20
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 5), .completed,
                       "An armed Post prevented normal vertical scrolling")
        XCTAssertTrue(app.buttons["reorderUp"].firstMatch.waitForNonExistence(timeout: 5),
                      "Normal Post scrolling did not dismiss reorder controls")
        assertOrder([1, 2, 3, 4].map(postRow))
        attach("13b Posts scroll normally and retain their order")

        relaunchKeepingIsolatedData()
        openPostsPage()
        reveal(postRow(4))
        assertOrder([1, 2, 3, 4].map(postRow))
        XCTAssertEqual(element("postSavedCount").label, "4 / 50")
        for number in 1...4 {
            XCTAssertEqual(element("postEntryNumber-\(postUUID(number))").label, numbers[number],
                           "Moving or relaunching changed a stored Post number")
            XCTAssertEqual(postPin(number).label, number <= 2 ? "Unpin post" : "Pin post",
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
        attach("20 Pinned Action armed with glow and chevrons")
        moveUp()
        assertOrder([2, 1, 3, 4].map(actionTitle))
        attach("21 Pinned Action moved past its visible neighbor")
        disarm(actionGesture(2))

        arm(actionGesture(4))
        attach("22 Unpinned Action armed with glow and chevrons")
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

    private func postUUID(_ number: Int) -> String {
        String(format: "00000000-0000-0000-0000-%012d", number)
    }

    private func postRow(_ number: Int) -> XCUIElement {
        element("postEntryRow-\(postUUID(number))")
    }

    private func postPin(_ number: Int) -> XCUIElement {
        app.buttons["pinPostEntry-\(postUUID(number))"].firstMatch
    }

    private func actionGesture(_ number: Int) -> XCUIElement {
        let uuid = String(format: "10000000-0000-0000-0000-%012d", number)
        return element("reminderReorderGesture-\(uuid)")
    }

    private func actionTitle(_ number: Int) -> XCUIElement {
        let group = number <= 2 ? "pinned" : "unpinned"
        let index = number <= 2 ? number : number - 2
        return app.staticTexts["Synthetic \(group) action \(index)"].firstMatch
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
        reveal(target)
        target.tap()
        XCTAssertTrue(app.buttons["reorderUp"].firstMatch.waitForNonExistence(timeout: 5),
                      "Tapping the armed card should dismiss its reorder controls")
    }

    private func moveUp() {
        let up = app.buttons["reorderUp"].firstMatch
        XCTAssertTrue(up.waitForExistence(timeout: 5), "Reorder controls disappeared before the move")
        reveal(up)
        // A disabled boundary chevron and an enabled chevron with a no-op boundary are
        // both valid; either must leave the card in its existing pin group.
        if up.isEnabled { up.tap() }
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
        for _ in 0..<8 where !target.isHittable {
            if target.frame.isEmpty || target.frame.midY > app.frame.midY {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
        XCTAssertTrue(target.isHittable, "Card or control could not be reached", file: file, line: line)
    }

    private func openPostsPage() {
        let card = homeRow("news-channel")
        reveal(card)
        card.tap()
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
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
