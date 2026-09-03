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
