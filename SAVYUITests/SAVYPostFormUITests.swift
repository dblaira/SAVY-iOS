import XCTest

/// Adam, 2026-09-02: "get a form set up for me to use and improve upon when planning and
/// writing social media posts" — and posts are "to be found in the News Channel page."
/// The test is the sentence: the bolt opens a Post form, his words go in whole, Save lands
/// the post on the News Channel page, and the News Channel card on Now opens the same page.
final class SAVYPostFormUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["SAVY_UI_TEST_UNLOCKED", "SAVY_UI_TEST_RESET_REMINDERS"]
        app.launch()
        dismissSystemPrompt()
    }

    private func dismissSystemPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A tap right after a swipe can land as a scroll-stop touch, and a tap while the
    /// keyboard moves can miss — retap until this element itself holds keyboard focus.
    private func focus(_ element: XCUIElement) {
        for _ in 0..<4 {
            if (element.value(forKey: "hasKeyboardFocus") as? Bool) == true { return }
            element.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertEqual(element.value(forKey: "hasKeyboardFocus") as? Bool, true, "Field never took keyboard focus")
    }

    /// Flip a toggle and confirm it actually flipped — a tap during scroll deceleration
    /// only stops the scroll.
    private func setToggleOn(_ element: XCUIElement) {
        for _ in 0..<3 {
            if (element.value as? String) == "1" { return }
            // The knob sits at the right edge — a tap on the row's center hits the label.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertEqual(element.value as? String, "1", "Toggle did not flip on")
    }

    /// The Form is lazy — an element scrolled past no longer exists in the hierarchy,
    /// so look down the page first, then come back up if we overshot.
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        swipes = 0
        while !(element.exists && element.isHittable), swipes < maxSwipes {
            app.swipeDown()
            swipes += 1
        }
    }

    func testBoltOpensPostFormAndSaveLandsOnNewsChannel() {
        let fab = app.descendants(matching: .any)["chargeFab"].firstMatch
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")

        // Tap the bolt so the fan opens, then photograph the four doors.
        fab.tap()
        XCTAssertTrue(app.buttons["Post"].waitForExistence(timeout: 5), "Post door missing from the fan")
        attach("01 fan with Post")

        app.buttons["Post"].tap()

        let field = app.descendants(matching: .any)["PostText"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Post form did not open")
        attach("02 empty post form")

        field.tap()
        field.typeText("A peptide video and an AI hiring story said the same thing this morning: the cost of trying just fell to zero.")

        let count = app.descendants(matching: .any)["PostCharacterCount"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5), "Character count missing")
        XCTAssertTrue(app.descendants(matching: .any)["CopyPost"].firstMatch.waitForExistence(timeout: 5), "Copy button missing once there is text")
        attach("03 post form with words")

        app.buttons["Save"].tap()

        let opened = app.descendants(matching: .any)["newsChannelPosts"].firstMatch.waitForExistence(timeout: 12)
        attach("04 news channel after save")
        XCTAssertTrue(opened, "News Channel page did not open after Save")
        XCTAssertTrue(app.staticTexts["STORIES"].firstMatch.waitForExistence(timeout: 5), "Stories still missing below the posts")
    }

    /// Adam: "make sure that in the Post entry box at the top of the page all 280 characters will be
    /// visible. I don't want any words cut off at the end or a ..."
    func testPostEntryShowsAll280Characters() {
        let fab = app.descendants(matching: .any)["chargeFab"].firstMatch
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")
        fab.tap()
        XCTAssertTrue(app.buttons["Post"].waitForExistence(timeout: 5), "Post door missing from the fan")
        app.buttons["Post"].tap()

        let field = app.descendants(matching: .any)["PostText"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Post form did not open")
        field.tap()

        let sentence = "Peptides and AI hiring moved the same direction this morning and nobody said so out loud. "
        var text = ""
        while text.count < 280 { text += sentence }
        text = String(text.prefix(280))
        XCTAssertEqual(text.count, 280)
        field.typeText(text)

        let count = app.descendants(matching: .any)["PostCharacterCount"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5), "Character count missing")
        XCTAssertEqual(count.label, "280 / 280")
        XCTAssertEqual(field.value as? String, text, "The entry box does not hold all 280 characters")

        // Put the keyboard away, then bring the whole box on screen to measure it —
        // with Delegate and Steps above, the box sits low while the keyboard is up.
        app.swipeDown()
        scrollTo(field)
        XCTAssertTrue(field.isHittable)
        XCTAssertGreaterThan(field.frame.height, 120, "The entry box did not grow for 280 characters")
        attach("20 post entry with 280 characters")
    }

    /// Adam: "Add a plus button to the Stories area of the News Channel page and have that open to
    /// different form ... The Form for Stories should have Title, Subtitle Forms and the ability to
    /// past formatted writing (bullet points, numbers lists, quotes, in the body portion of the form."
    func testStoriesPlusOpensStoryFormAndSaves() {
        let card = app.descendants(matching: .any)["homeContentSection-news-channel"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "News Channel card missing from Now")
        let homeScroll = app.scrollViews["editorialHomeScroll"].firstMatch
        var swipes = 0
        while !card.isHittable, swipes < 6 {
            homeScroll.swipeUp()
            swipes += 1
        }
        card.tap()

        let plus = app.descendants(matching: .any)["newStory"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 12), "Stories plus button missing")
        var swipesUp = 0
        while !plus.isHittable, swipesUp < 6 {
            app.swipeUp()
            swipesUp += 1
        }
        plus.tap()

        let title = app.descendants(matching: .any)["StoryTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Story form did not open")
        title.tap()
        title.typeText("What the cost of trying falling to zero does to a career")

        let subtitle = app.descendants(matching: .any)["StorySubtitle"].firstMatch
        subtitle.tap()
        subtitle.typeText("Three things I saw this week that point the same way")

        let body = app.descendants(matching: .any)["StoryBody"].firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5), "Story body missing")
        body.tap()
        body.typeText("• A peptide video\n• An AI hiring story\n1. First\n2. Second\n> The cost of trying just fell to zero.")
        attach("21 story form with pasted shapes")

        app.buttons["Save"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'storyRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12), "Saved story did not appear in the Stories area")
        attach("22 news channel with a story")
    }

    /// The post form carries the Reminder metadata: Delegate first, then Steps, then the
    /// Pattern block (Pattern / Clear Signs of Success / Compounding / Lift / Tags) and
    /// Priority + Energy under Choose. Save keeps every part; reopening shows them whole.
    func testPostFormCarriesReminderMetadata() {
        let fab = app.descendants(matching: .any)["chargeFab"].firstMatch
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")
        fab.tap()
        XCTAssertTrue(app.buttons["Post"].waitForExistence(timeout: 5), "Post door missing from the fan")
        app.buttons["Post"].tap()

        // Delegate comes first — the same three sentences as the Reminder form.
        let want = app.descendants(matching: .any)["PostWant"].firstMatch
        XCTAssertTrue(want.waitForExistence(timeout: 10), "What do I want? missing")
        focus(want)
        want.typeText("A post that connects peptides and AI hiring")
        let whenIAm = app.descendants(matching: .any)["PostWhenIAm"].firstMatch
        focus(whenIAm)
        whenIAm.typeText("reading in the morning")
        let done = app.descendants(matching: .any)["PostDoneLooksLike"].firstMatch
        focus(done)
        done.typeText("posted on X with a clear point of view")
        attach("30 delegate on the post form")

        // A step. (The post text itself is covered by the other tests on this form.)
        let addStep = app.buttons["Add Step"].firstMatch
        scrollTo(addStep)
        XCTAssertTrue(addStep.isHittable, "Add Step missing")
        addStep.tap()
        app.typeText("Find the exact line")

        // Pattern block: both toggles on, one tag in (the comma commits it).
        let clearSigns = app.switches["Clear Signs of Success"].firstMatch
        scrollTo(clearSigns)
        XCTAssertTrue(clearSigns.waitForExistence(timeout: 5), "Clear Signs of Success toggle missing")
        setToggleOn(clearSigns)
        let compounding = app.switches["Compounding"].firstMatch
        scrollTo(compounding)
        setToggleOn(compounding)
        XCTAssertTrue(app.staticTexts["Lift"].firstMatch.exists, "Lift picker missing")

        let tagField = app.textFields["Add a tag"].firstMatch
        scrollTo(tagField)
        XCTAssertTrue(tagField.waitForExistence(timeout: 5), "Tag field missing")
        focus(tagField)
        tagField.typeText("peptides,")
        attach("31 pattern block on the post form")

        // Choose carries Priority and Energy like the Reminder form. The menu pickers
        // read as one element whose label starts with the row name.
        let priority = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Priority'")).firstMatch
        scrollTo(priority)
        XCTAssertTrue(priority.waitForExistence(timeout: 5), "Priority missing from Choose")
        let energy = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Energy'")).firstMatch
        XCTAssertTrue(energy.waitForExistence(timeout: 5), "Energy missing from Choose")
        attach("32 choose with priority and energy")

        app.buttons["Save"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["newsChannelPosts"].firstMatch.waitForExistence(timeout: 12),
            "News Channel page did not open after Save"
        )

        // Reopen the saved post — every part is still there.
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'postRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Saved post missing from News Channel")
        row.tap()
        let wantAgain = app.descendants(matching: .any)["PostWant"].firstMatch
        XCTAssertTrue(wantAgain.waitForExistence(timeout: 10), "Post form did not reopen")
        XCTAssertEqual(
            wantAgain.value as? String,
            "A post that connects peptides and AI hiring",
            "Delegate answer was not kept"
        )
        attach("33 reopened post keeps the delegate answers")

        // The Pattern block came back whole: both markers on, the tag still there.
        let clearSignsAgain = app.switches["Clear Signs of Success"].firstMatch
        scrollTo(clearSignsAgain)
        XCTAssertTrue(clearSignsAgain.waitForExistence(timeout: 5), "Clear Signs of Success missing after reopen")
        XCTAssertEqual(clearSignsAgain.value as? String, "1", "Clear Signs of Success was not kept")
        XCTAssertEqual(app.switches["Compounding"].firstMatch.value as? String, "1", "Compounding was not kept")
        XCTAssertTrue(app.staticTexts["peptides"].firstMatch.exists, "Tag was not kept")
        attach("34 reopened post keeps the pattern block")
    }

    func testNewsChannelCardOpensPosts() {
        let card = app.descendants(matching: .any)["homeContentSection-news-channel"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "News Channel card missing from Now")
        let homeScroll = app.scrollViews["editorialHomeScroll"].firstMatch
        var swipes = 0
        while !card.isHittable, swipes < 6 {
            homeScroll.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(card.isHittable, "News Channel card never scrolled into view")
        attach("05 now with news channel card")
        card.tap()
        let opened = app.descendants(matching: .any)["newsChannelPosts"].firstMatch.waitForExistence(timeout: 12)
        attach("06 news channel with posts")
        XCTAssertTrue(opened, "News Channel card did not open the posts")
        XCTAssertFalse(app.buttons["Listen"].exists, "Audio control is still on the page")
    }
}
