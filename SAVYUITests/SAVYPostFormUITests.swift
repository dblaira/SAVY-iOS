import XCTest

/// Adam, 2026-09-21: questions stay in the entry with the answers, Social Media Posts + opens
/// that same form, and any number of posts can be pinned. These tests use the app's isolated
/// UI-test repositories so physical-iPhone verification does not change Adam's saved entries.
@MainActor
final class SAVYPostFormUITests: XCTestCase {
    private var app: XCUIApplication!
    private let firstPrompt = "Make it Obvious"
    private let advancedPrompts = [
        "What result requires going beyond the basics?",
        "What must already be mastered?",
        "Which advanced techniques improve that result?",
        "What additional demands or tradeoffs do those techniques introduce?",
    ]
    // The names locate the native menu's visible bounds when its later options need scrolling.
    private let themeNames = [
        "Habit", "A Strong Yes", "Pattern Recognition", "Inductive Reasoning", "Mental Model",
        "Personal Lessons", "The 5 Ws", "Problem → Solution", "Before / After", "Lesson Learned",
        "How-To", "Story Arc", "Myth vs. Fact", "The Decision", "Frequently Asked Questions",
        "Customer Success Story", "Key Challenges & Solutions", "Myths vs. Facts",
        "The Ultimate Checklist", "Quick Hack or Shortcut", "Recommended Tools & Resources",
        "Essential Terminology", "Before & After Scenarios", "Audience Poll or Survey Results",
        "Core Principles Explained", "Debunking Popular Industry Beliefs", "History of the Topic",
        "Alternative Approaches", "Step-by-Step Breakdown", "Checklist for Breakdown",
        "Checklist for Beginners", "Advanced Strategies", "Frequently Misunderstood Concepts",
    ]

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = [
                "SAVY_UI_TEST_UNLOCKED", "SAVY_UI_TEST_RESET_REMINDERS", "SAVY_UI_TEST_COWBOY_STUB",
            ]
            if name.contains("testNumberedPostCardsShowFiftyGoalAndKeepReferences") {
                app.launchArguments.append("SAVY_UI_TEST_DEMO_REMINDERS")
                app.launchEnvironment["SAVY_UI_TEST_SEED_POST_COUNT"] = "50"
            }
            app.launch()
            dismissSystemPrompt()
        }
    }

    func testBoltOpensPostFormWithThemeDecideAndFullReminderBody() {
        let fab = element("chargeFab")
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")
        fab.tap()
        let postDoor = app.buttons["Social"].firstMatch
        XCTAssertTrue(postDoor.waitForExistence(timeout: 5), "Post door missing from the fan")
        attach("01 fan with Post")
        postDoor.tap()
        assertSharedPostForm()
        assertPrefilledQuestion(firstPrompt, at: 0)

        // The question is actual editable content before anything is typed.
        let answer = "Synthetic bolt acceptance answer."
        appendAnswer(answer, at: 0)
        let firstValue = firstPrompt + "\n" + answer
        XCTAssertEqual(element("DecideAnswer0").value as? String, firstValue)
        savePost()
        let row = postRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Saved post missing from Social Media Posts")
        row.tap()
        XCTAssertTrue(element("PostTheme").waitForExistence(timeout: 10))
        XCTAssertEqual(element("DecideAnswer0").value as? String, firstValue)
        attach("02 bolt post reopened with question and answer")
    }

    /// Adam, 2026-09-26: "a row of buttons that could be used for quickly navigating different
    /// sections with a form without leaving the keyboard area". The row rides on the keyboard:
    /// the Decide icons jump the cursor, up and down step it, Done drops the keyboard and the row.
    func testKeyboardRowMovesTheCursorWithoutLeavingTheKeyboard() {
        let fab = element("chargeFab")
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")
        fab.tap()
        let postDoor = app.buttons["Social"].firstMatch
        XCTAssertTrue(postDoor.waitForExistence(timeout: 5), "Post door missing from the fan")
        postDoor.tap()
        assertSharedPostForm()

        // Tapping the first question raises the keyboard, and the row with it.
        let first = element("DecideAnswer0")
        scrollTo(first, upward: false)
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.9)).tap()
        let jumpToSecond = element("KeyboardRowDecide1")
        XCTAssertTrue(jumpToSecond.waitForExistence(timeout: 5), "Keyboard row missing")
        attach("01 keyboard row above the keyboard")

        // The question's own icon jumps straight to its box.
        jumpToSecond.tap()
        let second = element("DecideAnswer1")
        XCTAssertTrue(hasKeyboardFocus(second), "Decide icon did not move the cursor")
        // The cursor lands on the line right under the question, not a line lower.
        second.typeText("Answer")
        // A gray continuation may trail the typed word, so check what was typed and where.
        XCTAssertTrue((second.value as? String ?? "").hasPrefix("Make it Easy\nAnswer"),
                      "The jump did not land right under the question")
        attach("02 cursor right under the question, row on the keys")

        // Down steps one box; up steps back.
        element("KeyboardRowDown").tap()
        XCTAssertTrue(hasKeyboardFocus(element("DecideAnswer2")), "Down did not step to the next box")
        element("KeyboardRowUp").tap()
        XCTAssertTrue(hasKeyboardFocus(element("DecideAnswer1")), "Up did not step back")

        // Step through Visual templates between Decide and Delegate, in both directions.
        element("KeyboardRowDecide3").tap()
        XCTAssertTrue(hasKeyboardFocus(element("DecideAnswer3")), "The last Decide icon did not move the cursor")
        for index in 0..<4 {
            element("KeyboardRowDown").tap()
            XCTAssertTrue(hasKeyboardFocus(element("VisualAnswer\(index)")),
                          "Down did not step into Visual templates answer \(index + 1)")
        }
        element("KeyboardRowDown").tap()
        XCTAssertTrue(hasKeyboardFocus(element("Title")), "Down did not step from Visual templates to What do I want?")
        for index in (0..<4).reversed() {
            element("KeyboardRowUp").tap()
            XCTAssertTrue(hasKeyboardFocus(element("VisualAnswer\(index)")),
                          "Up did not step back into Visual templates answer \(index + 1)")
        }
        element("KeyboardRowUp").tap()
        XCTAssertTrue(hasKeyboardFocus(element("DecideAnswer3")), "Up did not step back into the last question")

        // Done drops the keyboard and the row goes with it.
        let done = element("KeyboardRowDone")
        XCTAssertTrue(done.isHittable, "Done is not reachable in the keyboard row")
        done.tap()
        XCTAssertTrue(jumpToSecond.waitForNonExistence(timeout: 5), "Done did not drop the keyboard row")
        attach("03 keyboard and row gone after Done")
    }

    func testThemePickerOffersAdamsNewThemesAndLoadsTheirQuestions() {
        openPostsPage()
        openNewPost()
        selectTheme("Customer Success Story")
        assertPrefilledQuestion("What did the customer want to achieve?", at: 0)
        assertPrefilledQuestion("What success can they demonstrate and describe in their own words?", at: 3)
        XCTAssertFalse(element("DecideAnswer4").exists, "Customer Success Story asks exactly four questions")
        attach("03 customer success story prefilled questions")

        selectTheme("Mental Model")
        let mentalModelQuestions = [
            "What situation do I want to approach differently?",
            "Which mental model have I chosen to adopt?",
            "How do I intend this new perspective to help?",
        ]
        for (index, question) in mentalModelQuestions.enumerated() {
            assertPrefilledQuestion(question, at: index)
        }
        XCTAssertFalse(element("DecideAnswer3").exists, "Mental Model asks exactly three questions")
        attach("04 mental model prefilled questions")

        // Adam, 2026-10-15: the Habit form leads the list with his four directives.
        selectTheme("Habit")
        let habitDirectives = ["Make it Obvious", "Make it Easy", "Make it Attractive", "Make it Satisfying"]
        for (index, directive) in habitDirectives.enumerated() {
            assertPrefilledQuestion(directive, at: index)
        }
        XCTAssertFalse(element("DecideAnswer4").exists, "Habit asks exactly four directives")
        attach("05 habit prefilled directives")
    }

    func testStrongYesThemePreservesLabelsQuestionsAndAnswersAfterRelaunch() {
        openPostsPage()
        openNewPost()
        selectTheme("A Strong Yes")
        let prompts = [
            "Problem\nWhat part of the process creates the most cognitive load?",
            "Pattern Interrupt\nWhat new data interrupts the pattern, by offering a new possibility?",
            "Opportunity\nIs this an A+ opportunity. While trying to implement the new process does my energy rise, fall, or remain undisturbed?",
            "Pay off\nDoes thinking, and working on this new process create a sense of FLOW that pulls me and yet also leaves me more capable and ambitious? I just can't get enough?",
        ]
        for (index, prompt) in prompts.enumerated() {
            assertPrefilledQuestion(prompt, at: index)
            attach("A Strong Yes field \(index + 1)")
        }
        XCTAssertFalse(element("DecideAnswer4").exists)
        appendAnswer("Synthetic process answer.", at: 0)
        let expected = prompts[0] + "\nSynthetic process answer."
        XCTAssertEqual(element("DecideAnswer0").value as? String, expected)
        savePost()

        app.terminate()
        app.launchArguments.removeAll { $0 == "SAVY_UI_TEST_RESET_REMINDERS" }
        app.launch()
        dismissSystemPrompt()
        openPostsPage()
        let row = postRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(element("PostTheme").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A Strong Yes"].firstMatch.exists)
        XCTAssertEqual(element("DecideAnswer0").value as? String, expected)
        for index in 1..<prompts.count {
            assertPrefilledQuestion(prompts[index], at: index)
        }
        attach("A Strong Yes reopened after relaunch")
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
        let expected = advancedPrompts[0] + "\n" + answer
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
        XCTAssertEqual(postContainer(rowID: secondID).value as? String, "Pinned")
        XCTAssertEqual(postContainer(rowID: firstID).value as? String, "Unpinned")
    }

    @MainActor
    func testStoriesPlusOpensStoryFormAndSaves() {
        openPostsPage()
        let plus = element("newStory")
        XCTAssertTrue(plus.waitForExistence(timeout: 12), "Stories plus button missing")
        scrollTo(plus)
        plus.tapOrClick()

        let title = element("StoryTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Story form did not open")
        title.tapOrClick()
        title.typeText("Synthetic story acceptance title")
        let subtitle = element("StorySubtitle")
        subtitle.tapOrClick()
        subtitle.typeText("Synthetic story acceptance subtitle")
        let body = element("StoryBody")
        XCTAssertTrue(body.waitForExistence(timeout: 5), "Story body missing")
        body.tapOrClick()
        body.typeText("• Synthetic bullet\n1. Synthetic list item\n> Synthetic quotation.")
        attach("30 story form retains formatted writing")
        app.buttons["Save"].firstMatch.tapOrClick()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'storyRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12), "Saved story did not appear")
        XCTAssertLessThanOrEqual(row.frame.height, 84, "Story list cards stay thin: a type label and one title line")
        XCTAssertFalse(app.staticTexts["Synthetic story acceptance subtitle"].exists,
                       "An unpinned Story card should show only its title")
        assertCardSwipeBehavior(in: app, card: row,
                                actions: ["Posted", "Delete"], name: "Draft Story")
        row.tapOrClick()
        XCTAssertTrue(element("StoryBody").waitForExistence(timeout: 8))
        XCTAssertEqual(element("StorySubtitle").value as? String, "Synthetic story acceptance subtitle")
        XCTAssertEqual(element("StoryBody").value as? String,
                       "• Synthetic bullet\n1. Synthetic list item\n> Synthetic quotation.",
                       "Compact Story cards must retain the full saved writing")
        app.buttons["Save"].firstMatch.tapOrClick()
        dragCard(in: app, card: row, distance: 146)
        let posted = app.buttons["swipePosted"].firstMatch
        XCTAssertTrue(posted.waitForExistence(timeout: 5))
        posted.tapOrClick()
        XCTAssertTrue(posted.waitForNonExistence(timeout: 5))
        assertCardSwipeBehavior(in: app, card: row, actions: ["Delete"], name: "Posted Story")
        dragCard(in: app, card: row, distance: 82)
        app.buttons["swipeDelete"].firstMatch.tapOrClick()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    func testNumberedPostCardsShowFiftyGoalAndKeepReferences() {
        app.buttons["Reminders"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["One of the most productive days of my life."].waitForExistence(timeout: 8))
        attach("49 Reminders retain the original shared card layout")
        app.buttons["Now"].firstMatch.tap()
        openPostsPage()
        XCTAssertEqual(element("postSavedCount").label, "50 / 50")
        XCTAssertFalse(app.images["Harnessed"].firstMatch.exists, "Post cards must not show Cowboy AI hats")

        func rowID(_ number: Int) -> String {
            "postEntryRow-" + String(format: "00000000-0000-0000-0000-%012d", number)
        }
        let firstPinned = element(rowID(2))
        let secondPinned = element(rowID(1))
        XCTAssertTrue(firstPinned.waitForExistence(timeout: 5))
        XCTAssertEqual(postContainer(rowID: rowID(2)).value as? String, "Pinned")
        XCTAssertEqual(postContainer(rowID: rowID(1)).value as? String, "Pinned")
        XCTAssertTrue(app.staticTexts["Synthetic post 2 starts with a clear observation."].exists,
                      "The card must show the authored first sentence, without a template question")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "SOCIAL #2")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "#Synthetic")).firstMatch.exists)
        let pinnedHeight = firstPinned.frame.height
        XCTAssertGreaterThanOrEqual(pinnedHeight, 186)
        XCTAssertLessThan(firstPinned.frame.minY, secondPinned.frame.minY)
        attach("50 numbered white and red pinned Post cards")

        let ordinary = element(rowID(50))
        scrollTo(ordinary)
        XCTAssertTrue(ordinary.isHittable)
        XCTAssertLessThan(ordinary.frame.height, pinnedHeight,
                          "Equal-length first sentences should have more room when pinned")
        XCTAssertLessThanOrEqual(ordinary.frame.height, 84, "Unpinned Post cards stay thin: a type label and one title line")
        let ordinaryCard = postContainer(rowID: rowID(50))
        XCTAssertEqual(ordinaryCard.value as? String, "Unpinned")
        XCTAssertEqual(ordinaryCard.label, "#50", "The saved reference remains available to accessibility")
        // Adam, 2026-10-15: "I want the labels back in the SAVY app."
        XCTAssertEqual(ordinaryCard.staticTexts.allElementsBoundByIndex.map { $0.label },
                       ["SOCIAL #50", "Synthetic post 50 starts with a clear observation."],
                       "Unpinned Post cards show their type label and title, without metadata rows")
        scrollTo(element(rowID(49)))
        app.swipeUp()
        attach("51 numbered sand and navy regular Post cards")

        // Moving a post into the pinned group must preserve its reference and saved content.
        setPinned(true, rowID: rowID(50))
        scrollTo(element(rowID(50)), upward: false)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "SOCIAL #50")).firstMatch.exists)
        element(rowID(50)).tap()
        let question = element("DecideAnswer0")
        XCTAssertTrue(question.waitForExistence(timeout: 8))
        let fullValue = question.value as? String ?? ""
        XCTAssertTrue(fullValue.contains("\n\nSynthetic post 50 starts with a clear observation. This additional synthetic sentence"),
                      "The compact first-sentence card must retain the full question and answer in storage")
        attach("52 full original question and answer behind numbered card")
        app.buttons["Cancel"].firstMatch.tap()

        app.terminate()
        app.launchArguments.removeAll { $0 == "SAVY_UI_TEST_RESET_REMINDERS" }
        app.launchEnvironment.removeValue(forKey: "SAVY_UI_TEST_SEED_POST_COUNT")
        app.launch()
        dismissSystemPrompt()
        openPostsPage()
        XCTAssertEqual(element("postSavedCount").label, "50 / 50")
        XCTAssertEqual(postContainer(rowID: rowID(50)).value as? String, "Pinned")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "SOCIAL #50")).firstMatch.exists)
        attach("53 numbered pinned Post survives relaunch")

        // Position never enlarges an unpinned post, including the first card in the list.
        for number in [50, 2, 1] { setPinned(false, rowID: rowID(number)) }
        scrollTo(element("postSavedCount"), upward: false)
        let firstUnpinned = element(rowID(50))
        XCTAssertLessThanOrEqual(firstUnpinned.frame.height, 84)
        XCTAssertEqual(postContainer(rowID: rowID(50)).label, "#50",
                       "Unpinning must retain the saved reference without a visible metadata row")
        let firstHeadline = element("postEntryHeadline-00000000-0000-0000-0000-000000000050")
        XCTAssertLessThanOrEqual(firstHeadline.frame.height, 34, "Unpinned preview must be one line with tail truncation")
        let visibleIDs = Set(postRows.allElementsBoundByIndex.filter { row in
            row.isHittable && row.frame.minY >= element("postSavedCount").frame.maxY
                && row.frame.maxY <= app.frame.maxY - 20
        }.map { $0.identifier })
        XCTAssertGreaterThanOrEqual(visibleIDs.count, 4, "At least four complete unpinned cards should fit below the page header")
        attach("54 four to five compact unpinned Posts including first card")
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

    func testDraftRecoversAfterTerminationWithoutPressingSave() {
        let fab = element("chargeFab")
        XCTAssertTrue(fab.waitForExistence(timeout: 15))
        fab.tap()
        let postDoor = app.buttons["Social"].firstMatch
        XCTAssertTrue(postDoor.waitForExistence(timeout: 5))
        postDoor.tap()
        assertSharedPostForm()
        let answer = "Synthetic autosave recovery: exact words 123."
        appendAnswer(answer, at: 0)
        XCTAssertEqual(element("DecideAnswer0").value as? String, firstPrompt + "\n" + answer)
        // No Save, dismissal, or focus change: terminate directly while typing.
        app.terminate()
        app.launchArguments.append("SAVY_UI_TEST_KEEP_DRAFTS")
        app.launch()
        XCTAssertTrue(element("DecideAnswer0").waitForExistence(timeout: 15), "Unfinished editor was not restored automatically")
        XCTAssertEqual(element("DecideAnswer0").value as? String, firstPrompt + "\n" + answer)
        attach("Autosaved writing restored after termination without Save")
        #if targetEnvironment(macCatalyst)
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        #else
        XCUIDevice.shared.press(.home)
        #endif
        app.terminate()
        app.launch()
        XCTAssertTrue(element("DecideAnswer0").waitForExistence(timeout: 15))
        XCTAssertEqual(element("DecideAnswer0").value as? String, firstPrompt + "\n" + answer)
        app.buttons["Cancel"].firstMatch.tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(element("chargeFab").waitForExistence(timeout: 15))
        XCTAssertFalse(element("sharedEntryForm").exists, "Explicit Cancel must discard this draft")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// True once the cursor has landed in the field. Focus moves take a moment to settle.
    private func hasKeyboardFocus(_ field: XCUIElement) -> Bool {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let landed = XCTNSPredicateExpectation(predicate: focused, object: field)
        return XCTWaiter.wait(for: [landed], timeout: 5) == .completed
    }

    private var postRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'postEntryRow-'"))
    }

    private func postContainer(rowID: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'postCard-'"))
            .containing(.any, identifier: rowID)
            .firstMatch
    }

    private func openPostsPage() {
        let card = element("homeContentSection-news-channel")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Social Media Posts card missing from Now")
        let homeScroll = app.scrollViews["editorialHomeScroll"].firstMatch
        for _ in 0..<8 where !card.isHittable { homeScroll.swipeUp() }
        XCTAssertTrue(card.isHittable, "Social Media Posts card did not scroll into view")
        card.tapOrClick()
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
        XCTAssertTrue(app.staticTexts["Habit"].firstMatch.exists, "Habit is not the starting theme")
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
        XCTAssertEqual(field.value as? String, prompt + "\n", "Question \(index) must be editable saved content")
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
        XCTFail("\(name) was not reachable in the \(themeNames.count)-theme menu")
    }

    @discardableResult
    private func createPost(answer: String) -> String {
        let previousIDs = Set(postRows.allElementsBoundByIndex.map { $0.identifier })
        openNewPost()
        assertPrefilledQuestion(firstPrompt, at: 0)
        appendAnswer(answer, at: 0)
        XCTAssertEqual(element("DecideAnswer0").value as? String, firstPrompt + "\n" + answer)
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
        let row = element(rowID)
        let container = postContainer(rowID: rowID)
        XCTAssertEqual(container.value as? String, pinned ? "Unpinned" : "Pinned")
        scrollTo(row)
        // A taller labeled card can rest under the navigation bar while still reporting as reachable.
        for _ in 0..<6 where row.frame.minY < 200 || row.frame.maxY > app.frame.height - 160 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let offset: CGFloat = row.frame.minY < 200 ? 150 : -150
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)))
        }
        XCTAssertTrue(row.isHittable, "The selected Post card is not reachable")
        let actionID = pinned ? "swipePin" : "swipeUnpin"
        XCTAssertFalse(container.buttons[actionID].firstMatch.isHittable,
                       "Post pin actions should only be available after a right swipe")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
            .press(forDuration: 0.05,
                   thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        let button = container.buttons[actionID].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Right swipe did not reveal the Post pin action")
        XCTAssertTrue(button.isHittable, "The Post pin action is covered by the card")
        button.tap()
        let expected = NSPredicate(format: "value == %@", pinned ? "Pinned" : "Unpinned")
        let changed = XCTNSPredicateExpectation(predicate: expected, object: container)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    private func assertPinsAndOrder(pinned: [String], unpinned: String) {
        // Scroll until the newest unpinned row is visible; the short pinned rows precede it.
        let unpinnedRow = element(unpinned)
        scrollTo(unpinnedRow)
        XCTAssertTrue(unpinnedRow.exists, "Unpinned post disappeared")
        XCTAssertEqual(postContainer(rowID: unpinned).value as? String, "Unpinned")
        for id in pinned {
            let row = element(id)
            XCTAssertTrue(row.exists, "Pinned post disappeared")
            XCTAssertEqual(postContainer(rowID: id).value as? String, "Pinned", "Pin state was not retained")
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
        #if !targetEnvironment(macCatalyst)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        #endif
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
