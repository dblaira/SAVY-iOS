import XCTest

/// Adam, 2026-09-21: questions stay in the entry with the answers, Social Media Posts + opens
/// that same form, and any number of posts can be pinned. These tests use the app's isolated
/// UI-test repositories so physical-iPhone verification does not change Adam's saved entries.
final class SAVYPostFormUITests: XCTestCase {
    private var app: XCUIApplication!
    private let firstPrompt = "What happened?"
    private let advancedPrompts = [
        "What result requires going beyond the basics?",
        "What must already be mastered?",
        "Which advanced techniques improve that result?",
        "What additional demands or tradeoffs do those techniques introduce?",
    ]
    // The names locate the native menu's visible bounds when its later options need scrolling.
    private let themeNames = [
        "The 5 Ws", "Problem → Solution", "Before / After", "Lesson Learned", "How-To",
        "Story Arc", "Myth vs. Fact", "The Decision", "Frequently Asked Questions",
        "Customer Success Story", "Key Challenges & Solutions", "Myths vs. Facts",
        "The Ultimate Checklist", "Quick Hack or Shortcut", "Recommended Tools & Resources",
        "Essential Terminology", "Before & After Scenarios", "Audience Poll or Survey Results",
        "Core Principles Explained", "Debunking Popular Industry Beliefs", "History of the Topic",
        "Alternative Approaches", "Step-by-Step Breakdown", "Checklist for Breakdown",
        "Checklist for Beginners", "Advanced Strategies", "Frequently Misunderstood Concepts",
        "Your Personal Take & Lessons Learned",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "SAVY_UI_TEST_UNLOCKED", "SAVY_UI_TEST_RESET_REMINDERS", "SAVY_UI_TEST_COWBOY_STUB",
        ]
        app.launch()
        dismissSystemPrompt()
    }

    func testBoltOpensPostFormWithThemeDecideAndFullReminderBody() {
        let fab = element("chargeFab")
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")
        fab.tap()
        let postDoor = app.buttons["Post"].firstMatch
        XCTAssertTrue(postDoor.waitForExistence(timeout: 5), "Post door missing from the fan")
        attach("01 fan with Post")
        postDoor.tap()
        assertSharedPostForm()
        assertPrefilledQuestion(firstPrompt, at: 0)

        // The question is actual editable content before anything is typed.
        let answer = "Synthetic bolt acceptance answer."
        appendAnswer(answer, at: 0)
        let firstValue = firstPrompt + "\n\n" + answer
        XCTAssertEqual(element("DecideAnswer0").value as? String, firstValue)
        savePost()
        let row = postRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Saved post missing from Social Media Posts")
        row.tap()
        XCTAssertTrue(element("PostTheme").waitForExistence(timeout: 10))
        XCTAssertEqual(element("DecideAnswer0").value as? String, firstValue)
        attach("02 bolt post reopened with question and answer")
    }

    func testThemePickerOffersAdamsNewThemesAndLoadsTheirQuestions() {
        openPostsPage()
        openNewPost()
        selectTheme("Customer Success Story")
        assertPrefilledQuestion("What did the customer want to achieve?", at: 0)
        assertPrefilledQuestion("What success can they demonstrate and describe in their own words?", at: 3)
        XCTAssertFalse(element("DecideAnswer4").exists, "Customer Success Story asks exactly four questions")
        attach("03 customer success story prefilled questions")
    }

    /// Replaces the older + → 280-character SocialPost composer requirement.
    func testPostsPlusOpensSharedFormAndPreservesExpandedQuestions() {
        openPostsPage()
        openNewPost()
        assertSharedPostForm()
        assertPrefilledQuestion(firstPrompt, at: 0)
        selectTheme("Advanced Strategies")

        for (index, prompt) in advancedPrompts.enumerated() {
            assertPrefilledQuestion(prompt, at: index)
        }
        let lastQuestion = element("DecideAnswer3")
        scrollTo(lastQuestion)
        XCTAssertGreaterThan(lastQuestion.frame.height, 50, "The complete question needs multiple visible lines")
        attach("10 advanced questions expanded before typing")

        let firstAnswer = element("DecideAnswer0")
        scrollTo(firstAnswer, upward: false)
        let initialHeight = firstAnswer.frame.height
        let answer = "Synthetic acceptance answer: connect several related examples, explain their differences, "
            + "and preserve every sentence alongside the full question when the post is reopened."
        appendAnswer(answer, at: 0)
        let expected = advancedPrompts[0] + "\n\n" + answer
        XCTAssertEqual(firstAnswer.value as? String, expected, "Typing must retain the entire question above the answer")
        XCTAssertGreaterThan(firstAnswer.frame.height, initialHeight + 10, "The field did not grow with the answer")
        attach("11 question and answer visible in expanded field")
        savePost()

        let row = postRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Saved post missing")
        row.tap()
        XCTAssertTrue(element("PostTheme").waitForExistence(timeout: 10), "Saved post did not reopen in the shared form")
        XCTAssertTrue(app.staticTexts["Advanced Strategies"].firstMatch.exists, "Saved theme changed")
        XCTAssertEqual(element("DecideAnswer0").value as? String, expected, "Save/reopen lost question or answer")
        assertPrefilledQuestion(advancedPrompts[3], at: 3)
        attach("12 reopened post retains full questions and answer")
    }

    func testMultiplePostsStayPinnedAboveUnpinnedAfterRelaunch() {
        openPostsPage()
        let firstID = createPost(answer: "Synthetic pin A.")
        let secondID = createPost(answer: "Synthetic pin B.")
        let unpinnedID = createPost(answer: "Synthetic unpinned C.")
        XCTAssertEqual(Set([firstID, secondID, unpinnedID]).count, 3, "Each save must create a separate post")

        // Pin two older posts; the newer unpinned post must move below both of them.
        setPinned(true, rowID: firstID)
        setPinned(true, rowID: secondID)
        assertPinsAndOrder(pinned: [firstID, secondID], unpinned: unpinnedID)
        attach("20 two pinned posts above newer unpinned post")

        app.terminate()
        app.launchArguments.removeAll { $0 == "SAVY_UI_TEST_RESET_REMINDERS" }
        app.launch()
        dismissSystemPrompt()
        openPostsPage()
        assertPinsAndOrder(pinned: [firstID, secondID], unpinned: unpinnedID)
        attach("21 multiple pins survive relaunch")

        // Unpinning one leaves the other pinned, rather than resetting the whole list.
        setPinned(false, rowID: firstID)
        XCTAssertEqual(pinButton(rowID: secondID).label, "Unpin post")
        XCTAssertEqual(pinButton(rowID: firstID).label, "Pin post")
    }

    func testStoriesPlusOpensStoryFormAndSaves() {
        openPostsPage()
        let plus = element("newStory")
        XCTAssertTrue(plus.waitForExistence(timeout: 12), "Stories plus button missing")
        scrollTo(plus)
        plus.tap()

        let title = element("StoryTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Story form did not open")
        title.tap()
        title.typeText("Synthetic story acceptance title")
        let subtitle = element("StorySubtitle")
        subtitle.tap()
        subtitle.typeText("Synthetic story acceptance subtitle")
        let body = element("StoryBody")
        XCTAssertTrue(body.waitForExistence(timeout: 5), "Story body missing")
        body.tap()
        body.typeText("• Synthetic bullet\n1. Synthetic list item\n> Synthetic quotation.")
        attach("30 story form retains formatted writing")
        app.buttons["Save"].firstMatch.tap()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'storyRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12), "Saved story did not appear")
    }

    func testNewsChannelCardOpensPosts() {
        openPostsPage()
        let header = element("socialMediaPostsHeader")
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Social Media Posts needs the shared navy header")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Social Media Posts")).count, 1,
                       "The page title should appear once")
        XCTAssertFalse(app.staticTexts["SOCIAL MEDIA POSTS"].firstMatch.exists, "The redundant red eyebrow remains")
        XCTAssertFalse(app.buttons["Listen"].exists, "Audio control is still on the page")
        attach("40 social media posts navy header without duplicate eyebrow")
        let back = element("socialMediaPostsBack")
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(element("homeContentSection-news-channel").waitForExistence(timeout: 5))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var postRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'postEntryRow-'"))
    }

    private func pinButton(rowID: String) -> XCUIElement {
        let id = rowID.replacingOccurrences(of: "postEntryRow-", with: "pinPostEntry-")
        return app.buttons.matching(identifier: id).firstMatch
    }

    private func openPostsPage() {
        let card = element("homeContentSection-news-channel")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Social Media Posts card missing from Now")
        let homeScroll = app.scrollViews["editorialHomeScroll"].firstMatch
        for _ in 0..<8 where !card.isHittable { homeScroll.swipeUp() }
        XCTAssertTrue(card.isHittable, "Social Media Posts card did not scroll into view")
        card.tap()
        XCTAssertTrue(element("newsChannelPosts").waitForExistence(timeout: 12), "Social Media Posts did not open")
    }

    private func openNewPost() {
        let plus = element("newPost")
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "Posts plus button missing")
        scrollTo(plus, upward: false)
        plus.tap()
        XCTAssertTrue(element("PostTheme").waitForExistence(timeout: 10), "Posts plus did not open the shared Post form")
    }

    private func assertSharedPostForm() {
        XCTAssertTrue(element("PostTheme").waitForExistence(timeout: 10), "Theme picker missing")
        XCTAssertTrue(app.staticTexts["The 5 Ws"].firstMatch.exists, "The 5 Ws is not the starting theme")
        XCTAssertTrue(element("DecideAnswer0").waitForExistence(timeout: 5), "Decide questions missing")
        let title = element("Title")
        scrollTo(title)
        XCTAssertTrue(title.exists, "The shared Delegate fields are missing")
        scrollTo(element("PostTheme"), upward: false)
    }

    private func assertPrefilledQuestion(_ prompt: String, at index: Int) {
        let field = element("DecideAnswer\(index)")
        scrollTo(field)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Decide question \(index) missing")
        XCTAssertEqual(field.value as? String, prompt + "\n\n", "Question \(index) must be editable saved content")
        XCTAssertTrue(field.placeholderValue?.isEmpty ?? true, "Question \(index) must not be placeholder text")
    }

    private func appendAnswer(_ answer: String, at index: Int) {
        let field = element("DecideAnswer\(index)")
        scrollTo(field, upward: false)
        XCTAssertTrue(field.isHittable, "Answer field is not reachable")
        // Tap the blank final line, placing the insertion point below the prefilled question.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.9)).tap()
        field.typeText(answer)
    }

    private func selectTheme(_ name: String) {
        let picker = element("PostTheme")
        scrollTo(picker, upward: false)
        picker.tap()
        attach("Framework menu with red form icons")
        let menuButtons = app.buttons.matching(NSPredicate(format: "label IN %@", themeNames))
        for _ in 0..<10 {
            let screen = app.frame.insetBy(dx: 12, dy: 12)
            let visible = menuButtons.allElementsBoundByIndex.compactMap { button -> (element: XCUIElement, frame: CGRect)? in
                let frame = button.frame
                guard button.isHittable, !frame.isEmpty, screen.contains(frame) else { return nil }
                return (button, frame)
            }.sorted { $0.frame.minY < $1.frame.minY }
            // The native menu reports partly clipped first/last rows as hittable. Their
            // centers can lie outside the rounded menu and drag the form behind it instead.
            let interior = Array(visible.dropFirst().dropLast())
            guard let top = interior.first, let bottom = interior.last else {
                XCTFail("Theme menu did not expose enough fully visible options to scroll")
                return
            }
            let left = interior.map { $0.frame.minX }.max() ?? screen.minX
            let right = interior.map { $0.frame.maxX }.min() ?? screen.maxX
            let x = (left + right) / 2
            let topY = top.frame.midY
            let bottomY = bottom.frame.midY
            let origin = app.coordinate(withNormalizedOffset: .zero)

            // Wait until the target has moved inside the menu, away from either clipped edge.
            if let target = interior.first(where: { $0.element.label == name }) {
                target.element.tap()
                XCTAssertTrue(element("DecideAnswer0").waitForExistence(timeout: 5))
                return
            }

            // At the actual beginning/end of the catalog, its edge item is also selectable.
            if let target = visible.first(where: { $0.element.label == name }),
               name == themeNames.first || name == themeNames.last {
                target.element.tap()
                XCTAssertTrue(element("DecideAnswer0").waitForExistence(timeout: 5))
                return
            }

            let targetIndex = themeNames.firstIndex(of: name) ?? themeNames.count
            let firstInteriorIndex = themeNames.firstIndex(of: top.element.label) ?? 0
            let movingDown = targetIndex >= firstInteriorIndex
            let startY = movingDown ? bottomY : topY
            let endY = movingDown ? topY : bottomY
            let start = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: endY - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTFail("\(name) was not reachable in the 28-theme menu")
    }

    @discardableResult
    private func createPost(answer: String) -> String {
        let previousIDs = Set(postRows.allElementsBoundByIndex.map { $0.identifier })
        openNewPost()
        assertPrefilledQuestion(firstPrompt, at: 0)
        appendAnswer(answer, at: 0)
        XCTAssertEqual(element("DecideAnswer0").value as? String, firstPrompt + "\n\n" + answer)
        savePost()
        let newRow = postRows.matching(NSPredicate(format: "NOT (identifier IN %@)", Array(previousIDs))).firstMatch
        XCTAssertTrue(newRow.waitForExistence(timeout: 10), "Saving did not create a new post entry")
        return newRow.identifier
    }

    private func savePost() {
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(element("newsChannelPosts").waitForExistence(timeout: 12), "Save did not return to the post list")
        XCTAssertTrue(app.buttons["Save"].firstMatch.waitForNonExistence(timeout: 8), "Post form did not close after Save")
    }

    private func setPinned(_ pinned: Bool, rowID: String) {
        let button = pinButton(rowID: rowID)
        scrollTo(button)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Post pin button missing")
        XCTAssertEqual(button.label, pinned ? "Pin post" : "Unpin post")
        button.tap()
        let expected = NSPredicate(format: "label == %@", pinned ? "Unpin post" : "Pin post")
        let changed = XCTNSPredicateExpectation(predicate: expected, object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    private func assertPinsAndOrder(pinned: [String], unpinned: String) {
        // Scroll until the newest unpinned row is visible; the short pinned rows precede it.
        let unpinnedRow = element(unpinned)
        scrollTo(unpinnedRow)
        XCTAssertTrue(unpinnedRow.exists, "Unpinned post disappeared")
        XCTAssertEqual(pinButton(rowID: unpinned).label, "Pin post")
        for id in pinned {
            let row = element(id)
            XCTAssertTrue(row.exists, "Pinned post disappeared")
            XCTAssertEqual(pinButton(rowID: id).label, "Unpin post", "Pin state was not retained")
            XCTAssertLessThan(row.frame.minY, unpinnedRow.frame.minY, "Every pinned post must appear above unpinned posts")
        }
    }

    private func scrollTo(_ target: XCUIElement, upward: Bool = true) {
        for _ in 0..<8 where !target.isHittable {
            // Pinning changes row order while retaining the current scroll position. Follow
            // the target's observed position so a newly pinned row can be reached above us.
            let shouldSwipeUp: Bool
            if target.exists && !target.frame.isEmpty {
                shouldSwipeUp = target.frame.midY > app.frame.midY
            } else {
                shouldSwipeUp = upward
            }
            if shouldSwipeUp { app.swipeUp() } else { app.swipeDown() }
        }
    }

    private func dismissSystemPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
