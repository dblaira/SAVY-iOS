import XCTest

/// Adam, 2026-09-02: "get a form set up for me to use and improve upon when planning and
/// writing social media posts." The test is the sentence: the bolt opens a Post form, his
/// words go in whole, Save lands the post on the Posts screen, and Now carries a Posts card.
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

    func testBoltOpensPostFormAndSaveLandsOnPostsScreen() {
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

        let opened = app.descendants(matching: .any)["postsHome"].firstMatch.waitForExistence(timeout: 12)
        attach("04 after save")
        XCTAssertTrue(opened, "Posts screen did not open after Save")
        XCTAssertTrue(app.staticTexts["Building meaning in public."].firstMatch.waitForExistence(timeout: 5))
    }

    func testNowCarriesPostsCard() {
        let card = app.descendants(matching: .any)["homeContentSection-posts"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Posts card missing from Now")
        let homeScroll = app.scrollViews["editorialHomeScroll"].firstMatch
        var swipes = 0
        while !card.isHittable, swipes < 6 {
            homeScroll.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(card.isHittable, "Posts card never scrolled into view")
        attach("05 now with posts card")
        card.tap()
        let opened = app.descendants(matching: .any)["postsHome"].firstMatch.waitForExistence(timeout: 12)
        attach("06 posts screen from card")
        XCTAssertTrue(opened, "Posts card did not open the Posts screen")
    }
}
