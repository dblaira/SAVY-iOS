import XCTest

/// Adam, 2026-09-02: "get a form set up for me to use and improve upon when planning and
/// writing social media posts" — and posts are "to be found in the News Channel page."
/// Adam, 2026-09-13, approving the Post-on-the-entry-form mockup: "That looks good. Let's
/// build that." The test is the sentence: the bolt's Post door opens the entry form with
/// Theme + Decide above the full Reminder body, Save lands the post on the News Channel
/// page, and reopening the row brings the data back.
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

    /// Adam approved the Post mockup on the Reminder form path (2026-09-13: "That looks good.
    /// Let's build that."): the bolt's Post door opens the entry form as its fourth face —
    /// Theme, then the theme's Decide questions, then everything the Reminder form already has.
    func testBoltOpensPostFormWithThemeDecideAndFullReminderBody() {
        let fab = app.descendants(matching: .any)["chargeFab"].firstMatch
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")

        // Tap the bolt so the fan opens, then photograph the four doors.
        fab.tap()
        XCTAssertTrue(app.buttons["Post"].waitForExistence(timeout: 5), "Post door missing from the fan")
        attach("01 fan with Post")

        app.buttons["Post"].tap()

        // Theme leads, defaulting to The 5 Ws.
        let theme = app.descendants(matching: .any)["PostTheme"].firstMatch
        XCTAssertTrue(theme.waitForExistence(timeout: 10), "Theme picker missing from the Post form")
        XCTAssertTrue(app.staticTexts["The 5 Ws"].firstMatch.exists, "The 5 Ws is not the starting theme")

        // Decide shows the theme's questions as rows to answer.
        let firstAnswer = app.descendants(matching: .any)["DecideAnswer0"].firstMatch
        XCTAssertTrue(firstAnswer.waitForExistence(timeout: 5), "Decide questions missing")

        // The full Reminder body stays below — Delegate is the first of Adam's sections.
        XCTAssertTrue(app.descendants(matching: .any)["Title"].firstMatch.exists, "Delegate's 'What do I want?' row missing")
        attach("02 post form with theme, decide, delegate")

        firstAnswer.tap()
        firstAnswer.typeText("A peptide video and an AI hiring story said the same thing this morning: the cost of trying just fell to zero.")

        let who = app.descendants(matching: .any)["DecideAnswer1"].firstMatch
        who.tap()
        who.typeText("Me, this morning.")
        attach("03 post form with answers")

        app.buttons["Save"].tap()

        // Save lands the post on the News Channel page.
        let opened = app.descendants(matching: .any)["newsChannelPosts"].firstMatch.waitForExistence(timeout: 12)
        attach("04 news channel after save")
        XCTAssertTrue(opened, "News Channel page did not open after Save")
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'postEntryRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Saved post entry missing from the News Channel page")

        // Reopen: the same entry comes back with the theme and the answers intact.
        row.tap()
        XCTAssertTrue(theme.waitForExistence(timeout: 10), "Reopened post lost its Theme row")
        XCTAssertTrue(app.staticTexts["The 5 Ws"].firstMatch.exists, "Reopened post lost its theme")
        let reopenedAnswer = app.descendants(matching: .any)["DecideAnswer0"].firstMatch
        XCTAssertTrue(reopenedAnswer.waitForExistence(timeout: 5), "Reopened post lost its Decide rows")
        XCTAssertEqual(
            reopenedAnswer.value as? String,
            "A peptide video and an AI hiring story said the same thing this morning: the cost of trying just fell to zero.",
            "Reopened post lost the first answer"
        )
        attach("05 reopened post with data intact")
    }

    /// Adam: "make sure that in the Post entry box at the top of the page all 280 characters will be
    /// visible. I don't want any words cut off at the end or a ..."
    /// The 280-character box lives on the SocialPost form, now reached through the News Channel's +.
    func testPostEntryShowsAll280Characters() {
        let card = app.descendants(matching: .any)["homeContentSection-news-channel"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "News Channel card missing from Now")
        let homeScroll = app.scrollViews["editorialHomeScroll"].firstMatch
        var swipes = 0
        while !card.isHittable, swipes < 6 {
            homeScroll.swipeUp()
            swipes += 1
        }
        card.tap()

        let plus = app.descendants(matching: .any)["newPost"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 12), "News Channel + button missing")
        plus.tap()

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
