import XCTest

/// Reproduces the exposed backdrop while a finger holds a page below its top edge.
/// The DEBUG app hook captures the window during negative scroll offset, before
/// this synchronous gesture returns and the page springs back. Its PNG and measured
/// offset are kept in Application Support/SAVY/HeaderOverscrollTest for pixel review.
/// All authored content and card preferences use SAVY's existing isolated test stores.
@MainActor
final class SAVYHeaderOverscrollUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = [
                "SAVY_UI_TEST_UNLOCKED",
                "SAVY_UI_TEST_RESET_REMINDERS",
                "SAVY_UI_TEST_COWBOY_STUB",
                "SAVY_UI_TEST_SEED_REORDER_ACTIONS",
                "SAVY_UI_TEST_CAPTURE_HEADER_OVERSCROLL",
            ]
            app.launchEnvironment["SAVY_UI_TEST_SEED_POST_COUNT"] = "4"
            app.launch()
            dismissSystemPrompt()
            XCTAssertTrue(element("editorialHomeScroll").waitForExistence(timeout: 20),
                          "The isolated signed-in Home did not open")
        }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    func testHomeCapturesBackdropDuringHeldPull() {
        captureHeldPull(screen: "home")
    }

    func testActionsCapturesBackdropDuringHeldPull() {
        openTab("Actions", screenIdentifier: "actionsHome")
        captureHeldPull(screen: "actions")
    }

    func testRemindersCapturesBackdropDuringHeldPull() {
        openTab("Reminders", screenIdentifier: "remindersHome")
        captureHeldPull(screen: "reminders")
    }

    func testCalendarCapturesBackdropDuringHeldPull() {
        openTab("Calendar", screenIdentifier: nil)
        let today = app.buttons["Today"].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 10), "Calendar's Today control is missing")
        // Calendar can open at the current time in its long timeline. Bring its
        // own header back to the top without tapping Today (which scrolls to now).
        returnToTop(anchor: today)
        captureHeldPull(screen: "calendar")
    }

    func testConnectionCapturesBackdropDuringHeldPull() {
        openHomeSection("beliefs", destinationIdentifier: "connectionScreen")
        captureHeldPull(screen: "connection")
    }

    func testPostsCapturesBackdropDuringHeldPull() {
        openHomeSection("news-channel", destinationIdentifier: "socialMediaPostsHeader")
        XCTAssertEqual(element("postSavedCount").label, "4 / 50",
                       "Expected the four synthetic Posts from isolated test storage")
        captureHeldPull(screen: "news-channel")
    }

    func testOntologyCapturesBackdropDuringHeldPull() {
        openHomeSection("ontology", destinationIdentifier: "sectionPageHeader")
        XCTAssertEqual(element("sectionPageHeader").label, "Adam's Ontology")
        captureHeldPull(screen: "ontology")
    }

    func testFieldEssaysCapturesBackdropDuringHeldPull() {
        openHomeSection("field-essays", destinationIdentifier: "sectionPageHeader")
        XCTAssertEqual(element("sectionPageHeader").label, "Field Essays")
        captureHeldPull(screen: "field-essays")
    }

    private func captureHeldPull(screen: String, file: StaticString = #filePath, line: UInt = #line) {
        attach("\(screen) — resting page")

        // Start in the header's central area, away from back/account buttons and
        // the cards' long-press reorder targets. The short initial press lets the
        // vertical ScrollView claim the gesture before the final hold.
        let scroll = app.scrollViews.firstMatch
        let navigationBottom = app.navigationBars.allElementsBoundByIndex
            .filter(\.isHittable).map(\.frame.maxY).max() ?? 0
        let startY = max(100, scroll.frame.minY + 24, navigationBottom + 24)
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width * 0.50, dy: startY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.66))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.5)

        // This receipt must be emitted only after the app hook writes a PNG and
        // metadata from a genuinely negative content offset. A released-page
        // screenshot alone cannot prove the overscroll appearance.
        let receipt = element("headerOverscrollCapture-\(screen)")
        XCTAssertTrue(receipt.waitForExistence(timeout: 8),
                      "No held-overscroll capture was written for \(screen)", file: file, line: line)
        let captureReceipt = XCTAttachment(string: "screen: \(screen)\n\(receipt.label)\n\(receipt.value ?? "")")
        captureReceipt.name = "\(screen) — app capture receipt"
        captureReceipt.lifetime = .keepAlways
        add(captureReceipt)
        attach("\(screen) — released page; held frame is in the app capture directory")
    }

    private func openTab(_ title: String, screenIdentifier: String?) {
        let tab = app.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "The \(title) tab is missing")
        tab.tap()
        if let screenIdentifier {
            XCTAssertTrue(element(screenIdentifier).waitForExistence(timeout: 10), "\(title) did not open")
        }
    }

    private func openHomeSection(_ section: String, destinationIdentifier: String) {
        let row = element("homeContentSection-\(section)")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "The \(section) Home card is missing")
        let scroll = app.scrollViews["editorialHomeScroll"].firstMatch
        for _ in 0..<8 where !row.isHittable {
            scroll.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "The \(section) Home card could not be reached")
        element("homeReorder-\(section)").tap()
        XCTAssertTrue(element(destinationIdentifier).waitForExistence(timeout: 12),
                      "The \(section) Home card did not open its page")
    }

    private func returnToTop(anchor: XCUIElement) {
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "The page scroll view is missing")
        for _ in 0..<14 {
            let previousY = anchor.frame.minY
            scroll.swipeDown()
            if anchor.isHittable && abs(anchor.frame.minY - previousY) < 2 { break }
        }
        XCTAssertTrue(anchor.isHittable && anchor.frame.minY < app.frame.height * 0.25,
                      "Calendar did not return to its header before the held pull")
    }

    private func dismissSystemPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
