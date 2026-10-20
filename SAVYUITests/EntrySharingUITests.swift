import XCTest
import UIKit

@MainActor
final class EntrySharingUITests: XCTestCase {
    private let isSavy = true
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        if isSavy {
            app.launchArguments = ["SAVY_UI_TEST_UNLOCKED", "SAVY_UI_TEST_RESET_REMINDERS", "SAVY_UI_TEST_COWBOY_STUB"]
        } else {
            app.launchArguments = ["RECALL_UI_TEST_ISOLATED"]
            app.launchEnvironment["RECALL_UI_TEST_SESSION"] = UUID().uuidString
        }
        app.launch()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    func testShareAlwaysOpensEntireCurrentFormAndReturnsToEditor() {
        openForm()
        let answer = element(isSavy ? "DecideAnswer0" : "themeAnswer0")
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        reveal(answer)
        answer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        answer.typeText("Current unsaved Decide writing.")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let shareWhileTyping = element("shareForm")
        XCTAssertTrue(shareWhileTyping.isHittable, "Share must remain reachable while writing")
        XCTAssertLessThan(shareWhileTyping.frame.maxY, keyboard.frame.minY)
        attach("Share stays available above the keyboard")
        dismissKeyboard()

        let title = element("Title")
        reveal(title)
        title.tap()
        title.typeText("Current unsaved delegation.")
        dismissKeyboard()
        let when = element("WhenIAm")
        reveal(when)
        when.tap()
        when.typeText("My unchanged context.")
        dismissKeyboard()
        let outcome = element(isSavy ? "DoneLooksLike" : "Outcome")
        reveal(outcome)
        outcome.tap()
        outcome.typeText("My exact done statement.")
        dismissKeyboard()

        let entire = copyEntireForm()
        XCTAssertTrue(entire.contains("Current unsaved Decide writing."))
        assertDelegationAndMetadata(entire)
        XCTAssertTrue(element("shareForm").isHittable, "Sharing must return to the current editor")

        reveal(outcome)
        outcome.tap()
        outcome.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.9)).tap()
        outcome.typeText(" Updated before sharing again.")
        dismissKeyboard()
        XCTAssertEqual(outcome.value as? String, "My exact done statement. Updated before sharing again.")
        let repeated = copyEntireForm()
        XCTAssertTrue(repeated.contains("Current unsaved Decide writing."))
        XCTAssertTrue(repeated.contains("\nDecide\n"))
        XCTAssertTrue(repeated.contains("My exact done statement. Updated before sharing again."))
        assertDelegationAndMetadata(repeated)
        XCTAssertEqual(outcome.value as? String, "My exact done statement. Updated before sharing again.")
        attach("Editor remains intact after repeated whole-form sharing")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(element("chargeFab").waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Current unsaved")).count, 0,
                       "Sharing must not save the draft as an entry")
    }

    private func openForm() {
        let fab = element("chargeFab")
        XCTAssertTrue(fab.waitForExistence(timeout: 20))
        let fabFrame = fab.frame
        if isSavy {
            fab.tap()
            app.buttons["Social"].firstMatch.tap()
        } else {
            let center = fab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            center.press(forDuration: 0.2, thenDragTo: center.withOffset(CGVector(dx: -120, dy: 0)))
        }
        let share = element("shareForm")
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars.staticTexts["Share"].exists, "The toolbar must remain icon-only")
        XCTAssertFalse(app.navigationBars.descendants(matching: .any).matching(identifier: "shareForm").firstMatch.exists)
        XCTAssertEqual(share.frame.midX, fabFrame.midX, accuracy: 1, "Share belongs at the FAB's horizontal center")
        XCTAssertEqual(share.frame.midY, fabFrame.midY, accuracy: 4, "Share belongs at the FAB's vertical position")
        XCTAssertEqual(share.frame.width, fabFrame.width, accuracy: 1, "Share must match the FAB's width")
        XCTAssertEqual(share.frame.height, fabFrame.height, accuracy: 1, "Share must match the FAB's height")
        if isSavy {
            XCTAssertTrue(app.segmentedControls.buttons["Social"].exists)
            XCTAssertFalse(app.segmentedControls.buttons["Post"].exists)
        }
        attach("Centered Share matches the FAB")
    }

    private func copyEntireForm() -> String {
        element("shareForm").tap()
        XCTAssertFalse(app.buttons["Delegate only"].exists, "Share must always use the entire form")
        XCTAssertFalse(app.buttons["Entire form"].exists, "Sharing must not ask for a scope")
        let copy = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)",
                                  "Copy", XCUIElement.ElementType.cell.rawValue,
                                  XCUIElement.ElementType.button.rawValue)).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10), "Native share sheet must offer Copy")
        attach("Entire form opens directly in the native share sheet")
        copy.tap()
        XCTAssertTrue(copy.waitForNonExistence(timeout: 5))
        // The runner is a separate app. Keep its UI automation available while
        // iOS asks permission to read the text just copied from the app under test.
        let clipboardRead = expectation(description: "Read the native Copy result")
        DispatchQueue.global().async {
            _ = UIPasteboard.general.string
            clipboardRead.fulfill()
        }
        let allowPaste = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
        if allowPaste.waitForExistence(timeout: 3) { allowPaste.tap() }
        wait(for: [clipboardRead], timeout: 10)
        return UIPasteboard.general.string ?? ""
    }

    private func assertDelegationAndMetadata(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for expected in ["Current unsaved delegation.", "My unchanged context.", "My exact done statement.",
                         "Metadata", "Theme: Habit", "Status: Active"] {
            XCTAssertTrue(text.contains(expected), "Copied text missing \(expected)", file: file, line: line)
        }
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<16 {
            let keyboard = app.keyboards.firstMatch
            let share = self.element("shareForm")
            let bottom = share.exists && share.isHittable
                ? share.frame.minY - 12
                : (keyboard.exists ? keyboard.frame.minY - 20 : app.frame.height - 100)
            if element.exists && element.isHittable && element.frame.minY > 180 && element.frame.maxY < bottom { return }
            let down = element.exists && element.frame.minY < 180
            // Drag within the form, above the onscreen keyboard.
            let point = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.4))
            point.press(forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: down ? 160 : -160)))
        }
        XCTAssertTrue(element.isHittable)
    }

    private func dismissKeyboard() {
        let done = element("KeyboardRowDone")
        if done.exists && done.isHittable { done.tap() }
        else { app.navigationBars.firstMatch.tap() }
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(isSavy ? "SAVY" : "Understood") \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
