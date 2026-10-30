import XCTest

/// Acceptance: Delegate entry fields expand so all entered text is visible — no "..." cutoff.
@MainActor
final class SAVYDelegateTextExpansionUITests: XCTestCase {
    private var app: XCUIApplication!

    private let longTitle =
        "Answer the question: can Claude build a business from scratch that makes money?\n"
        + (2...9).map { "Title line \($0) stays fully visible." }.joined(separator: "\n")
    private let longWhen =
        "When I am reviewing a long delegation prompt that must wrap across several lines without cutting words\n"
        + (2...9).map { "Context line \($0) stays fully visible." }.joined(separator: "\n")
    private let longDone =
        "A business idea was taken from inception to fruition by Claude Fable 5 that made $50. My only role was oversight, funding, and steering — every word of this outcome stays on screen.\n"
        + (2...9).map { "Outcome line \($0) stays fully visible." }.joined(separator: "\n")

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = [
                "SAVY_UI_TEST_UNLOCKED", "SAVY_UI_TEST_RESET_REMINDERS", "SAVY_UI_TEST_COWBOY_STUB",
            ]
            app.launch()
            dismissNotificationPrompt()
        }
    }

    func testDelegateFieldsExpandInReminderActionAndCalendarForms() {
        for kind in ExpansionComposerKind.allCases {
            assertDelegateFieldsExpand(kind)
        }
    }

    func testDelegatePromptsRemainVisibleWhenAnswersAreEntered() {
        openComposer(.reminder)
        for (identifier, prompt, answer) in [
            ("Title", "What do I want?", "The first answer.\nIts next line."),
            ("WhenIAm", "When I am...I like to", "The context answer.\nIts next line."),
            ("DoneLooksLike", "Done looks like...", "The outcome answer.\nIts next line.")
        ] {
            let question = field("DelegateQuestion" + identifier)
            reveal(question)
            XCTAssertEqual(question.label, prompt)
            let input = field(identifier)
            XCTAssertTrue(input.exists)
            XCTAssertGreaterThanOrEqual(input.frame.minY, question.frame.maxY - 1)
            XCTAssertLessThanOrEqual(input.frame.minY - question.frame.maxY, 4,
                                     "Delegate writing must start directly below its question")
            question.tapOrClick()
            let focused = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: input
            )
            XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed,
                           "Tapping the question must focus its answer")
            app.typeText(answer)
            dismissKeyboard()
            XCTAssertEqual(stringValue(input), answer)
            XCTAssertTrue(question.exists, "The Delegate question must remain after typing")
            XCTAssertEqual(question.label, prompt, "Typing must not replace the question")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Delegate"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Cancel"].tapOrClick()
    }

    private func assertDelegateFieldsExpand(_ kind: ExpansionComposerKind) {
        openComposer(kind)

        for identifier in ["Title", "WhenIAm", "DoneLooksLike"] {
            reveal(field(identifier))
            XCTAssertTrue(field(identifier).waitForExistence(timeout: 10), "\(kind.rawValue) form missing \(identifier)")
        }

        reveal(field("Title"), towardTopWhenMissing: true)
        let titleBefore = field("Title").frame.height
        typeInto(field("Title"), longTitle)
        assertExpanded(field("Title"), expected: longTitle, minGrowthOver: titleBefore, kind: kind, name: "Title")

        reveal(field("WhenIAm"))
        let whenBefore = field("WhenIAm").frame.height
        typeInto(field("WhenIAm"), longWhen)
        assertExpanded(field("WhenIAm"), expected: longWhen, minGrowthOver: whenBefore, kind: kind, name: "WhenIAm")

        reveal(field("DoneLooksLike"))
        let doneBefore = field("DoneLooksLike").frame.height
        typeInto(field("DoneLooksLike"), longDone)
        assertExpanded(field("DoneLooksLike"), expected: longDone, minGrowthOver: doneBefore, kind: kind, name: "DoneLooksLike")

        // Capture while still on the form — proves Reminder / Action / Event all expand.
        let liveShot = XCTAttachment(screenshot: app.screenshot())
        liveShot.name = "delegate-expand-live-\(kind.rawValue)"
        liveShot.lifetime = .keepAlways
        add(liveShot)
        try? app.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: "/tmp/delegate-expand-\(kind.rawValue).png"))

        // Reminder + Action: reopen without keyboard for a clean read-back shot.
        if kind != .calendar {
            app.buttons["Save"].tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["chargeFab"].firstMatch.waitForExistence(timeout: 12),
                "Shell missing after save for \(kind.rawValue)"
            )
            openSaved(kind)
            reveal(field("Title"))
            XCTAssertTrue(field("Title").waitForExistence(timeout: 10), "\(kind.rawValue) reopen missing Title")
            XCTAssertEqual(stringValue(field("Title")), longTitle)
            reveal(field("WhenIAm"))
            XCTAssertEqual(stringValue(field("WhenIAm")), longWhen)
            reveal(field("DoneLooksLike"))
            XCTAssertEqual(stringValue(field("DoneLooksLike")), longDone)

            let reopenShot = XCTAttachment(screenshot: app.screenshot())
            reopenShot.name = "delegate-expand-reopen-\(kind.rawValue)"
            reopenShot.lifetime = .keepAlways
            add(reopenShot)
            try? app.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: "/tmp/delegate-expand-reopen-\(kind.rawValue).png"))
        }

        if app.buttons["Cancel"].waitForExistence(timeout: 2) {
            app.buttons["Cancel"].tap()
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["chargeFab"].firstMatch.waitForExistence(timeout: 8),
            "Did not return to shell after \(kind.rawValue)"
        )
    }

    private func openSaved(_ kind: ExpansionComposerKind) {
        switch kind {
        case .reminder:
            app.buttons["Reminders"].tap()
        case .action:
            app.buttons["Actions"].tap()
        case .calendar:
            return
        }
        let predicate = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "Claude build a business",
            "Claude build a business"
        )
        let item = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Saved \(kind.rawValue) item not found")
        item.tap()
    }

    private func assertExpanded(
        _ element: XCUIElement,
        expected: String,
        minGrowthOver beforeHeight: CGFloat,
        kind: ExpansionComposerKind,
        name: String
    ) {
        XCTAssertTrue(element.exists, "\(kind.rawValue) \(name) missing after typing")
        let value = stringValue(element)
        XCTAssertEqual(value, expected, "\(kind.rawValue) \(name) truncated in value")
        XCTAssertFalse(
            value.contains("…") || value.contains("..."),
            "\(kind.rawValue) \(name) still shows ellipsis: \(value)"
        )
        XCTAssertGreaterThan(
            element.frame.height,
            max(beforeHeight + 6, 34),
            "\(kind.rawValue) \(name) did not expand vertically (was \(beforeHeight), now \(element.frame.height))"
        )
    }

    private func openComposer(_ kind: ExpansionComposerKind) {
        let fab = app.descendants(matching: .any)["chargeFab"].firstMatch
        XCTAssertTrue(fab.waitForExistence(timeout: 20), "Charge FAB missing")
        let center = fab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.2, thenDragTo: center.withOffset(kind.dragOffset))
    }

    private func field(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func typeInto(_ element: XCUIElement, _ text: String) {
        reveal(element)
        element.tapOrClick()
        element.typeText(text)
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        let done = field("KeyboardRowDone")
        if done.exists && done.isHittable {
            done.tapOrClick()
            XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        }
    }

    private func reveal(_ target: XCUIElement, towardTopWhenMissing: Bool = false) {
        dismissKeyboard()
        let form = field("sharedEntryForm")
        for _ in 0..<24 {
            let exists = target.exists
            let frame = exists ? target.frame : .zero
            #if targetEnvironment(macCatalyst)
            let visible = form.frame.intersection(app.interactionFrame).insetBy(dx: 0, dy: 20)
            #else
            let top = app.navigationBars.allElementsBoundByIndex
                .filter { $0.exists && $0.isHittable && !$0.frame.isEmpty }
                .map { $0.frame.maxY }.max() ?? app.frame.minY + 100
            let share = field("shareForm")
            let bottom = share.exists && share.isHittable ? share.frame.minY - 12 : app.frame.maxY - 155
            let visible = CGRect(x: app.frame.minX, y: top + 10,
                                 width: app.frame.width, height: bottom - top - 10)
            #endif
            if exists && target.isHittable && frame.minY >= visible.minY
                && (frame.maxY <= visible.maxY || frame.height > visible.height) { return }
            let down = exists ? frame.minY < visible.minY : towardTopWhenMissing
            #if targetEnvironment(macCatalyst)
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .scroll(byDeltaX: 0, deltaY: down ? 140 : -140)
            #else
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.width * 0.85,
                                                   dy: visible.midY - app.frame.minY))
            start.press(forDuration: 0.05,
                        thenDragTo: start.withOffset(CGVector(dx: 0, dy: down ? 140 : -140)))
            #endif
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Delegate entry fields"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("The Delegate field was not reachable")
    }

    private func stringValue(_ element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    private func dismissNotificationPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }
}

private enum ExpansionComposerKind: String, CaseIterable {
    case reminder
    case action
    case calendar

    var dragOffset: CGVector {
        switch self {
        case .reminder: return CGVector(dx: -120, dy: 0)
        case .action: return CGVector(dx: 0, dy: -140)
        case .calendar: return CGVector(dx: 120, dy: 0)
        }
    }
}
