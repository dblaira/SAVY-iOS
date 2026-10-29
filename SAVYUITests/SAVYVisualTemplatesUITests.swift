import XCTest

/// Visual templates uses separate questions and growing answers in the isolated UI-test store.
@MainActor
final class SAVYVisualTemplatesUITests: XCTestCase {
    private var app: XCUIApplication!
    private let matrixQuestion = "What relationship should this matrix make clear?"
    private let summaryQuestion = "Why does this need to be summarized?"

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = [
                "SAVY_UI_TEST_UNLOCKED", "SAVY_UI_TEST_RESET_REMINDERS", "SAVY_UI_TEST_COWBOY_STUB",
            ]
            app.launch()
            dismissSystemPrompt()
        }
    }

    func testQuestionTapStartsAnswerImmediatelyBelowAndLongTextExpands() {
        openPost()
        XCTAssertEqual(element("VisualFormat").value as? String, "Matrices")
        let question = app.staticTexts["VisualQuestion0"]
        let answer = app.textViews["VisualAnswer0"]
        reveal(question)
        XCTAssertEqual(question.label, matrixQuestion)
        XCTAssertTrue(answer.exists, "The question needs a separate answer field")
        XCTAssertEqual(answer.value as? String, "", "The question must not be editable answer content")
        XCTAssertGreaterThanOrEqual(answer.frame.minY, question.frame.maxY - 1,
                                    "The answer must begin below the question")
        XCTAssertLessThanOrEqual(answer.frame.minY - question.frame.maxY, 4,
                                 "The answer must begin immediately below the question")
        let emptyHeight = answer.frame.height
        attach("Visual templates before writing")

        question.tap()
        XCTAssertTrue(hasKeyboardFocus(answer), "Tapping the question must focus its answer")
        let firstLine = "Synthetic matrix answer."
        answer.typeText(firstLine)
        dismissKeyboard()
        XCTAssertEqual(answer.value as? String, firstLine,
                       "Typing must start on the first answer line, without a leading blank line")
        XCTAssertEqual(question.label, matrixQuestion, "Typing an answer changed the question")

        let additionalLines = (2...9).map { "Line \($0) stays fully visible." }.joined(separator: "\n")
        reveal(question)
        question.tap()
        XCTAssertTrue(hasKeyboardFocus(answer))
        answer.typeText("\n" + additionalLines)
        dismissKeyboard()
        let expected = firstLine + "\n" + additionalLines
        XCTAssertEqual(answer.value as? String, expected, "The complete answer must survive expansion")
        XCTAssertEqual(question.label, matrixQuestion, "The question must remain separate and unchanged")
        XCTAssertGreaterThan(answer.frame.height, emptyHeight * 3,
                             "Nine answer lines must grow beyond the original two-line entry field")
        reveal(question)
        attach("Visual templates question and full answer")
    }

    func testFormatAnswersSurviveSwitchingDraftRecoveryAndSaveReopen() {
        openPost()
        let matrixAnswer = "Synthetic matrix relationship answer."
        let summaryAnswer = "Synthetic summary purpose answer."
        enterAnswer(matrixAnswer, question: matrixQuestion)
        selectFormat("Summarize")
        enterAnswer(summaryAnswer, question: summaryQuestion)
        selectFormat("Matrices")
        assertAnswer(matrixAnswer, question: matrixQuestion)

        // Terminate while the answer has focus: no Save or editor dismissal first.
        reveal(app.staticTexts["VisualQuestion0"])
        app.staticTexts["VisualQuestion0"].tap()
        XCTAssertTrue(hasKeyboardFocus(app.textViews["VisualAnswer0"]))
        app.terminate()
        app.launchArguments.append("SAVY_UI_TEST_KEEP_DRAFTS")
        app.launch()
        XCTAssertTrue(element("VisualFormat").waitForExistence(timeout: 15),
                      "The unfinished Visual templates editor was not restored")
        XCTAssertEqual(element("VisualFormat").value as? String, "Matrices")
        assertAnswer(matrixAnswer, question: matrixQuestion)
        selectFormat("Summarize")
        assertAnswer(summaryAnswer, question: summaryQuestion)
        attach("Visual templates recovered draft")

        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(element("newsChannelPosts").waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Save"].firstMatch.waitForNonExistence(timeout: 8))
        app.terminate()
        app.launchArguments.removeAll { $0 == "SAVY_UI_TEST_RESET_REMINDERS" }
        app.launch()
        dismissSystemPrompt()
        openPostsPage()
        let savedPost = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'postEntryRow-'"))
            .firstMatch
        XCTAssertTrue(savedPost.waitForExistence(timeout: 10), "The saved Visual templates entry is missing")
        savedPost.tap()
        XCTAssertTrue(element("VisualFormat").waitForExistence(timeout: 10))
        XCTAssertEqual(element("VisualFormat").value as? String, "Summarize",
                       "Save/reopen must retain the selected Format")
        assertAnswer(summaryAnswer, question: summaryQuestion)
        selectFormat("Matrices")
        assertAnswer(matrixAnswer, question: matrixQuestion)
        attach("Visual templates saved and reopened")
    }

    private func openPost() {
        let fab = element("chargeFab")
        XCTAssertTrue(fab.waitForExistence(timeout: 20))
        fab.tap()
        let social = app.buttons["Social"].firstMatch
        XCTAssertTrue(social.waitForExistence(timeout: 5))
        social.tap()
        XCTAssertTrue(element("VisualFormat").waitForExistence(timeout: 10))
    }

    private func openPostsPage() {
        let card = element("homeContentSection-news-channel")
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        let homeScroll = app.scrollViews["editorialHomeScroll"].firstMatch
        for _ in 0..<8 where !card.isHittable { homeScroll.swipeUp() }
        XCTAssertTrue(card.isHittable)
        card.tapOrClick()
        XCTAssertTrue(element("newsChannelPosts").waitForExistence(timeout: 12))
    }

    private func enterAnswer(_ text: String, question: String) {
        let label = app.staticTexts["VisualQuestion0"]
        reveal(label)
        XCTAssertEqual(label.label, question)
        label.tap()
        let answer = app.textViews["VisualAnswer0"]
        XCTAssertTrue(hasKeyboardFocus(answer))
        answer.typeText(text)
        dismissKeyboard()
        assertAnswer(text, question: question)
    }

    private func assertAnswer(_ text: String, question: String) {
        let label = app.staticTexts["VisualQuestion0"]
        reveal(label)
        XCTAssertEqual(label.label, question)
        XCTAssertEqual(app.textViews["VisualAnswer0"].value as? String, text)
    }

    private func selectFormat(_ name: String) {
        let format = element("VisualFormat")
        reveal(format)
        format.tap()
        let option = app.buttons[name].firstMatch
        let optionExists = option.waitForExistence(timeout: 5)
        if !optionExists {
            attach("Visual templates Format menu")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Visual templates Format menu accessibility"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(optionExists, "The Format menu is missing \(name)")
        option.tap()
        XCTAssertEqual(format.value as? String, name)
    }

    private func reveal(_ target: XCUIElement) {
        dismissKeyboard()
        let form = element("sharedEntryForm")
        for _ in 0..<10 {
            let frame = target.frame
            let visibleTop = visibleNavigationBottom + 10
            if target.isHittable && frame.minY >= visibleTop && frame.maxY < app.frame.maxY - 155 { return }
            if target.exists && frame.minY < visibleTop { form.swipeDown() }
            else { form.swipeUp() }
        }
        XCTAssertTrue(target.isHittable, "The requested Visual templates control is not reachable")
        XCTAssertGreaterThanOrEqual(target.frame.minY, visibleNavigationBottom + 10,
                                    "The control remains behind the navigation bar")
        XCTAssertLessThan(target.frame.maxY, app.frame.maxY - 155,
                          "The control remains behind the bottom controls")
    }

    private var visibleNavigationBottom: CGFloat {
        // A presented editor can leave an underlying navigation bar in the hierarchy.
        // Use only bars that can actually receive a touch in the current viewport.
        app.navigationBars.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && !$0.frame.isEmpty && app.frame.intersects($0.frame) }
            .map { $0.frame.maxY }
            .max() ?? app.frame.minY + 100
    }

    private func dismissKeyboard() {
        let done = element("KeyboardRowDone")
        if done.exists {
            done.tap()
            XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        }
    }

    private func hasKeyboardFocus(_ field: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func dismissSystemPrompt() {
        #if !targetEnvironment(macCatalyst)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        #endif
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
