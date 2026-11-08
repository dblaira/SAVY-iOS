import XCTest

/// Adam, 2026-11-08: "You have control of everything. Don't ask me to do anything." This runs on
/// the phone with the isolated test store: opens a Social form, writes one synthetic answer,
/// taps Send to AI, and waits for the Mac's reply to land under Answer. The reply travels over
/// Tailscale to the helper on Adam's Mac. Nothing touches his saved entries.
@MainActor
final class SAVYSendToAIUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["SAVY_UI_TEST_UNLOCKED", "SAVY_UI_TEST_RESET_REMINDERS", "SAVY_UI_TEST_COWBOY_STUB"]
            app.launch()
        }
    }

    func testSendToAIBringsTheMacReplyIntoTheForm() {
        let fab = element("chargeFab")
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")
        fab.tap()
        let door = app.buttons["Social"].firstMatch
        XCTAssertTrue(door.waitForExistence(timeout: 5), "Social door missing")
        door.tap()
        let first = element("DecideAnswer0")
        XCTAssertTrue(first.waitForExistence(timeout: 10), "Decide questions missing")
        first.tap()
        first.typeText("Synthetic phone check. One video a week, filmed the same morning.")
        app.buttons["KeyboardRowDone"].firstMatch.tap()

        let send = element("SendToAI")
        scrollTo(send)
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Send to AI missing")
        attach("01 phone form before send")
        send.tap()

        // The Answer section sits between Delegate and Steps; list rows off screen do not exist,
        // so look for it by scrolling through that part of the form until it appears.
        let answer = element("Answer0")
        let deadline = Date().addingTimeInterval(600)
        var landed = false
        while !landed && Date() < deadline {
            if answer.exists { landed = true; break }
            app.swipeDown(); app.swipeDown()
            for _ in 0..<3 where !answer.exists { app.swipeUp() }
            if answer.exists { landed = true; break }
            Thread.sleep(forTimeInterval: 10)
        }
        attach(landed ? "02 phone reply from the Mac" : "02 no reply")
        XCTAssertTrue(landed, "No reply reached the phone from the Mac helper")
        let text = answer.value as? String ?? ""
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Answer box is empty")

        app.buttons["Cancel"].firstMatch.tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func scrollTo(_ target: XCUIElement) {
        for _ in 0..<8 where !(target.exists && target.isHittable) {
            app.swipeUp()
        }
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
