import XCTest
import UIKit

/// Adam's Connection page reuses the Post cards and shared entry form. The four questions,
/// answers, and metadata must remain editable after saving and relaunching. All launches
/// use isolated repositories; these fixtures must never reach Adam's live data or Harness.
@MainActor
final class SAVYConnectionEntryUITests: XCTestCase {
    private var app: XCUIApplication!
    private let prompts = [
        "What did you believe before?",
        "What experience changed or confirmed your connection?",
        "What do you believe now? What is the new connection?",
        "What do you do differently because of it?",
    ]
    private let answers = [
        "Synthetic earlier belief: every idea needed to stand alone.",
        "Synthetic experience: comparing several examples exposed a shared pattern.",
        "Synthetic new connection: examples reveal relationships when viewed together.",
        "Synthetic next action: preserve the examples and their differences.",
    ]
    private let title = "Synthetic Connection acceptance entry"
    private let when = "When I compare examples, I keep their original context."
    private let outcome = "The connection and the evidence remain readable together."
    private let step = "Compare the original examples."
    private let notes = "Synthetic note with a second line.\nKeep both lines after reopening."
    private let link = "https://example.com/connection-acceptance"
    private let person = "Synthetic collaborator"
    private let place = "Synthetic reading room"
    private let tag = "connection-acceptance"

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = [
                "SAVY_UI_TEST_UNLOCKED",
                "SAVY_UI_TEST_RESET_REMINDERS",
                "SAVY_UI_TEST_COWBOY_STUB",
            ]
            app.launch()
            dismissSystemPrompt()
            openConnections()
        }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    func testConnectionAnswersAndMetadataSurviveSaveAndRelaunch() {
        let initialIDs = authoredRowIDs()
        openNewConnection()
        assertConnectionForm()
        assertWhiteFormMargin("connectionEntryForm")
        attach("01 Connection form with its fixed Personal Take theme")

        for index in prompts.indices {
            let field = element("DecideAnswer\(index)")
            reveal(field)
            XCTAssertEqual(field.value as? String, prompts[index] + "\n\n",
                           "Connection prompt \(index) must be editable text above the answer")
            // The blank final line places the insertion point below the complete prompt.
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.9)).tap()
            field.typeText(answers[index])
            XCTAssertEqual(field.value as? String, expectedAnswer(at: index))
        }

        enter(title, into: element("Title"))
        enter(when, into: element("WhenIAm"))
        enter(outcome, into: element("DoneLooksLike"))

        let addStep = app.buttons["Add Step"].firstMatch
        reveal(addStep)
        addStep.tap()
        enter(step, into: field(placeholder: "Step"))

        choose("Context", in: "Pattern")
        setToggle("Clear Signs of Success", enabled: true)
        setToggle("Compounding", enabled: true)
        choose("Learning", in: "Lift")
        enter(tag + ",", into: field(placeholder: "Add a tag"))
        XCTAssertTrue(app.staticTexts[tag].firstMatch.exists, "Tag did not become saved metadata")
        choose("High", in: "Priority")
        choose("Med", in: "Energy")
        setToggle("Start", enabled: true)
        setToggle("Due", enabled: true)
        choose("Weekly", in: "Repeat")
        enter(notes, into: field(placeholder: "Notes"))
        enter(link, into: field(placeholder: "Link"))

        // Image and place controls must remain available with the shared metadata. Tests
        // do not grant Photos/location access or read private material just to prove this.
        let image = app.staticTexts["Image"].firstMatch
        reveal(image)
        XCTAssertTrue(image.exists, "Connection form lost the shared image field")
        enter(place, into: field(placeholder: "Location"))
        enter(person, into: field(placeholder: "Waiting on / delegate to"))
        attach("02 Connection includes the shared Details and Place People metadata")

        saveConnection()
        let newRow = authoredRows.matching(
            NSPredicate(format: "NOT (identifier IN %@)", Array(initialIDs))
        ).firstMatch
        reveal(newRow)
        XCTAssertTrue(newRow.waitForExistence(timeout: 10), "The saved connection did not appear")
        let rowID = newRow.identifier
        let uuid = rowID.replacingOccurrences(of: "connectionEntryRow-", with: "")
        XCTAssertEqual(element("connectionEntryHeadline-\(uuid)").label, answers[2],
                       "The card must show the new connection, not its question or an earlier belief")
        attach("03 Saved Connection card uses the new connection as its headline")
        newRow.tap()
        assertSavedValues()
        attach("04 Reopened Connection retains questions and answers")
        cancelForm()

        app.terminate()
        app.launchArguments.removeAll { $0 == "SAVY_UI_TEST_RESET_REMINDERS" }
        app.launch()
        dismissSystemPrompt()
        openConnections()
        let persistedRow = element(rowID)
        reveal(persistedRow)
        XCTAssertTrue(persistedRow.exists, "The authored connection disappeared after relaunch")
        persistedRow.tap()
        assertSavedValues()
        attach("05 Connection metadata remains after an app relaunch")
    }

    func testCancellingAnAuthoredConnectionDoesNotCreateAnEntry() {
        let originalCount = savedCount()
        let originalIDs = authoredRowIDs()
        openNewConnection()
        let answer = element("DecideAnswer2")
        reveal(answer)
        answer.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.9)).tap()
        answer.typeText("Synthetic cancelled connection must not appear.")
        cancelForm()
        XCTAssertEqual(savedCount(), originalCount, "Cancel changed the number of saved connections")
        XCTAssertEqual(authoredRowIDs(), originalIDs, "Cancel saved a new authored connection")
        attach("06 Cancel leaves existing connections intact")
    }

    func testDismissingUntouchedQuestionsDoesNotCreateAConnection() {
        let originalCount = savedCount()
        let originalIDs = authoredRowIDs()
        openNewConnection()
        assertConnectionForm()
        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        let start = navigationBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96))
        start.press(forDuration: 0.1, thenDragTo: end)
        waitForFormToClose()
        XCTAssertEqual(savedCount(), originalCount, "Prefilled questions alone became a saved connection")
        XCTAssertEqual(authoredRowIDs(), originalIDs, "An untouched template created an authored row")
        attach("07 Dismissing the untouched template leaves the connection count unchanged")
    }

    func testOriginalPostEntryFormHasWhiteBackground() {
        // Launch Home again so this test follows the actual Social Media Posts + route.
        app.terminate()
        app.launch()
        dismissSystemPrompt()
        let card = element("homeContentSection-news-channel")
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        reveal(card)
        card.tap()
        let plus = element("newPost")
        reveal(plus)
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        XCTAssertTrue(element("PostTheme").waitForExistence(timeout: 10),
                      "Social Media Posts + did not open the original Post form")
        assertWhiteFormMargin("sharedEntryForm")
        attach("08 Original Post entry has white behind the existing cream fields")
    }

    func testRightSwipePinsMultipleConnectionsAtTheVeryTopAndSurvivesRelaunch() {
        assertNoAlwaysVisiblePinButtons()
        let sourceRowID = sourceRows.firstMatch.identifier
        XCTAssertFalse(sourceRowID.isEmpty, "The existing beliefs disappeared")
        let source = element(sourceRowID)
        reveal(source)
        XCTAssertEqual(cardContainer(for: sourceRowID).value as? String, "Pinned",
                       "The existing first belief should retain its pin")
        let sourcePinnedHeight = source.frame.height
        setPinned(false, rowID: sourceRowID)
        XCTAssertLessThan(source.frame.height, sourcePinnedHeight,
                          "An unpinned belief should use the compact Post card")
        setPinned(true, rowID: sourceRowID)
        assertFirstCard(sourceRowID)

        let first = createConnection("Synthetic pin A: several detailed examples expose a relationship that one isolated example would not reveal.")
        let second = createConnection("Synthetic pin B: a second independent connection can remain pinned beside the first connection.")
        let unpinned = createConnection("Synthetic unpinned C remains below every pinned connection.")
        let firstHeight = element(first).frame.height
        let secondHeight = element(second).frame.height
        setPinned(true, rowID: first)
        assertFirstCard(first)
        setPinned(true, rowID: second)
        assertFirstCard(second)
        XCTAssertGreaterThan(element(first).frame.height, firstHeight + 8,
                             "Pinning did not expand the first authored card")
        XCTAssertGreaterThan(element(second).frame.height, secondHeight + 8,
                             "Pinning did not expand the second authored card")
        assertPinsAboveUnpinned(pinned: [first, second, sourceRowID], unpinned: unpinned)
        XCTAssertLessThan(element(second).frame.minY, element(first).frame.minY,
                          "The newest pin must be above the previous pin")
        assertNoAlwaysVisiblePinButtons()
        reveal(element(first))
        attach("09 Right swipe pins expand and place the newest connection at the very top")

        app.terminate()
        app.launchArguments.removeAll { $0 == "SAVY_UI_TEST_RESET_REMINDERS" }
        app.launch()
        dismissSystemPrompt()
        openConnections()
        assertPinsAboveUnpinned(pinned: [first, second, sourceRowID], unpinned: unpinned)
        assertFirstCard(second)
        setPinned(false, rowID: first)
        XCTAssertEqual(cardContainer(for: second).value as? String, "Pinned",
                       "Unpinning one authored connection cleared another pin")
        XCTAssertEqual(cardContainer(for: sourceRowID).value as? String, "Pinned",
                       "Unpinning an authored connection cleared the existing belief's pin")
        XCTAssertLessThan(element(first).frame.height, element(second).frame.height,
                          "The unpinned connection did not return to its compact size")
        assertNoAlwaysVisiblePinButtons()
        reveal(element(second))
        attach("10 Saved pins persist and unpinning one leaves the other pins intact")
    }

    func testRightSwipeDeletesSelectedAuthoredAndSourceConnectionsAfterRelaunch() {
        let sourceID = sourceRows.firstMatch.identifier
        XCTAssertFalse(sourceID.isEmpty, "An existing source connection is needed for deletion")
        let deletedID = createConnection("Synthetic authored connection selected for deletion.")
        let keptID = createConnection("Synthetic connection that must remain after its neighbor is deleted.")
        deleteConnection(rowID: deletedID)
        deleteConnection(rowID: sourceID)
        XCTAssertTrue(element(keptID).exists, "Deleting a connection removed an unrelated authored entry")
        attach("11 Right swipe Delete removes the selected authored and existing source cards")

        app.terminate()
        app.launchArguments.removeAll { $0 == "SAVY_UI_TEST_RESET_REMINDERS" }
        app.launch()
        dismissSystemPrompt()
        openConnections()
        XCTAssertFalse(element(deletedID).exists, "The deleted authored connection returned after relaunch")
        XCTAssertFalse(element(sourceID).exists, "The deleted source connection returned after relaunch")
        XCTAssertTrue(element(keptID).exists, "An unrelated authored connection was not retained")
        assertNoAlwaysVisiblePinButtons()
        attach("12 Selected deletions persist after relaunch and preserve other connections")
    }

    private func assertConnectionForm() {
        XCTAssertTrue(element("connectionEntryForm").waitForExistence(timeout: 10),
                      "Connection + did not open its entry form")
        XCTAssertTrue(element("connectionTheme").exists, "The fixed Connection theme is missing")
        XCTAssertTrue(app.staticTexts["Your Personal Take & Lessons Learned"].firstMatch.exists)
        XCTAssertFalse(app.segmentedControls.firstMatch.exists,
                       "A connection must remain in Connection rather than offer a Reminder/Post destination")
        XCTAssertFalse(element("PostTheme").exists, "Connection's fixed theme must not expose the Post theme picker")
        XCTAssertTrue(element("DecideAnswer0").exists)
        XCTAssertFalse(element("DecideAnswer4").exists, "The Connection template has four questions")
    }

    private func assertSavedValues() {
        XCTAssertTrue(element("connectionEntryForm").waitForExistence(timeout: 10))
        for index in prompts.indices {
            let answer = element("DecideAnswer\(index)")
            reveal(answer)
            XCTAssertEqual(answer.value as? String, expectedAnswer(at: index),
                           "Saved question/answer \(index) changed")
        }
        assertValue(title, in: element("Title"))
        assertValue(when, in: element("WhenIAm"))
        assertValue(outcome, in: element("DoneLooksLike"))
        assertValue(step, in: field(placeholder: "Step"))
        assertChoice("Context", in: "Pattern")
        assertToggle("Clear Signs of Success", enabled: true)
        assertToggle("Compounding", enabled: true)
        assertChoice("Learning", in: "Lift")
        let savedTag = app.staticTexts[tag].firstMatch
        reveal(savedTag)
        XCTAssertTrue(savedTag.exists, "The tag was not retained")
        assertChoice("High", in: "Priority")
        assertChoice("Med", in: "Energy")
        assertToggle("Start", enabled: true)
        assertToggle("Due", enabled: true)
        assertChoice("Weekly", in: "Repeat")
        assertValue(notes, in: field(placeholder: "Notes"))
        assertValue(link, in: field(placeholder: "Link"))
        assertValue(place, in: field(placeholder: "Location"))
        assertValue(person, in: field(placeholder: "Waiting on / delegate to"))
    }

    private func expectedAnswer(at index: Int) -> String {
        prompts[index] + "\n\n" + answers[index]
    }

    private func createConnection(_ answer: String) -> String {
        let previous = authoredRowIDs()
        openNewConnection()
        let field = element("DecideAnswer2")
        reveal(field)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.9)).tap()
        field.typeText(answer)
        saveConnection()
        let row = authoredRows.matching(NSPredicate(format: "NOT (identifier IN %@)", Array(previous))).firstMatch
        reveal(row)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Saving did not create an authored connection")
        return row.identifier
    }

    private var sourceRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'connectionSourceRow-'"))
    }

    private var cardContainers: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'connectionCard-'"))
    }

    private func cardContainer(for rowID: String) -> XCUIElement {
        cardContainers.containing(.any, identifier: rowID).firstMatch
    }

    private func setPinned(_ enabled: Bool, rowID: String) {
        let container = cardContainer(for: rowID)
        XCTAssertEqual(container.value as? String, enabled ? "Unpinned" : "Pinned")
        let button = revealSwipeAction(enabled ? "swipePin" : "swipeUnpin", rowID: rowID)
        button.tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", enabled ? "Pinned" : "Unpinned"),
            object: cardContainer(for: rowID)
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    private func revealSwipeAction(_ identifier: String, rowID: String) -> XCUIElement {
        let row = element(rowID)
        reveal(row)
        XCTAssertTrue(row.isHittable, "The selected connection is not reachable")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
            .press(forDuration: 0.05,
                   thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        let container = cardContainer(for: rowID)
        let action = container.buttons[identifier].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), "Right swipe did not reveal \(identifier)")
        XCTAssertTrue(action.isHittable, "The right swipe action is covered by the card")
        XCTAssertTrue(container.buttons["swipeDelete"].firstMatch.isHittable,
                      "Right swipe must reveal Delete beside Pin or Unpin")
        return action
    }

    private func deleteConnection(rowID: String) {
        let row = element(rowID)
        revealSwipeAction("swipeDelete", rowID: rowID).tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "Delete left the selected connection in the list")
    }

    private func assertNoAlwaysVisiblePinButtons() {
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pinConnection'")).count, 0,
                       "Connections must reveal pin actions by right swipe, without permanent pin buttons")
    }

    private func assertFirstCard(_ rowID: String) {
        let selected = element(rowID)
        let rows = cardContainers.allElementsBoundByIndex
        XCTAssertFalse(rows.isEmpty)
        let firstY = rows.map { $0.frame.minY }.min() ?? .infinity
        XCTAssertEqual(cardContainer(for: rowID).frame.minY, firstY, accuracy: 1,
                       "A newly pinned connection must move above every earlier pin")
        reveal(selected, towardBottom: false)
    }

    private func assertPinsAboveUnpinned(pinned: [String], unpinned: String) {
        let unpinnedRow = element(unpinned)
        reveal(unpinnedRow)
        XCTAssertEqual(cardContainer(for: unpinned).value as? String, "Unpinned")
        for id in pinned {
            XCTAssertEqual(cardContainer(for: id).value as? String, "Pinned", "An independent pin was lost")
            XCTAssertLessThan(element(id).frame.minY, unpinnedRow.frame.minY,
                              "Pinned connections must appear above unpinned connections")
        }
    }

    private func openConnections() {
        let card = element("homeContentSection-beliefs")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Connection card is missing from Home")
        reveal(card)
        let button = element("homeReorder-beliefs")
        (button.exists ? button : card).tap()
        XCTAssertTrue(element("connectionScreen").waitForExistence(timeout: 10), "Connection did not open")
    }

    private func openNewConnection() {
        let plus = element("newConnection")
        reveal(plus, towardBottom: false)
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "Connection's + button is missing")
        plus.tap()
        XCTAssertTrue(element("DecideAnswer0").waitForExistence(timeout: 10))
    }

    private func saveConnection() {
        app.buttons["Save"].firstMatch.tap()
        waitForFormToClose()
    }

    private func cancelForm() {
        app.buttons["Cancel"].firstMatch.tap()
        waitForFormToClose()
    }

    private func waitForFormToClose() {
        XCTAssertTrue(app.buttons["Save"].firstMatch.waitForNonExistence(timeout: 10),
                      "Connection form did not close")
        XCTAssertTrue(element("connectionScreen").exists)
    }

    private func savedCount() -> String {
        let count = element("connectionSavedCount")
        reveal(count, towardBottom: false)
        XCTAssertTrue(count.exists, "Connection count is missing")
        return count.label
    }

    private var authoredRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'connectionEntryRow-'"))
    }

    private func authoredRowIDs() -> Set<String> {
        Set(authoredRows.allElementsBoundByIndex.map(\.identifier))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func field(placeholder: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "(elementType == %d OR elementType == %d) AND (placeholderValue == %@ OR label == %@)",
            XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue,
            placeholder, placeholder
        )).firstMatch
    }

    private func enter(_ text: String, into target: XCUIElement) {
        reveal(target)
        XCTAssertTrue(target.isHittable, "The metadata field is not reachable")
        target.tap()
        target.typeText(text)
    }

    private func assertValue(_ expected: String, in target: XCUIElement) {
        reveal(target)
        XCTAssertEqual(target.value as? String, expected)
    }

    private func menu(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ",")).firstMatch
    }

    private func choose(_ value: String, in label: String) {
        let picker = menu(label)
        reveal(picker)
        XCTAssertTrue(picker.isHittable, "The \(label) metadata picker is missing")
        picker.tap()
        let option = app.buttons[value].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "The \(value) choice is missing from \(label)")
        option.tap()
    }

    private func assertChoice(_ value: String, in label: String) {
        let picker = menu(label)
        reveal(picker)
        XCTAssertTrue(picker.exists, "The \(label) metadata picker is missing after reopening")
        let renderedValue = [picker.label, picker.value as? String ?? ""].joined(separator: " ")
        XCTAssertTrue(renderedValue.contains(value), "\(label) did not retain \(value): \(renderedValue)")
    }

    private func setToggle(_ label: String, enabled: Bool) {
        let toggle = app.switches[label].firstMatch
        reveal(toggle)
        XCTAssertTrue(toggle.exists, "The \(label) metadata toggle is missing")
        if (toggle.value as? String == "1") != enabled { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0")
    }

    private func assertToggle(_ label: String, enabled: Bool) {
        let toggle = app.switches[label].firstMatch
        reveal(toggle)
        XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0", "\(label) was not retained")
    }

    private func reveal(_ target: XCUIElement, towardBottom: Bool = true) {
        for _ in 0..<14 where !target.isHittable {
            let upward = target.exists && !target.frame.isEmpty
                ? target.frame.midY > app.frame.midY
                : towardBottom
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
    }

    private func dismissSystemPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    private func assertWhiteFormMargin(_ identifier: String) {
        let form = element(identifier)
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        let screenshot = app.screenshot()
        guard let image = UIImage(data: screenshot.pngRepresentation)?.cgImage else {
            XCTFail("The rendered form screenshot could not be read")
            return
        }
        // The actual Form has inset cream rows. Sample its left outer margin halfway
        // down the sheet, away from the navigation bar, rounded corners, and row text.
        let x = (form.frame.minX + 6 - app.frame.minX) * CGFloat(image.width) / app.frame.width
        let y = (form.frame.midY - app.frame.minY) * CGFloat(image.height) / app.frame.height
        guard let sample = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            XCTFail("The visible form margin could not be sampled")
            return
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let rendered = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        XCTAssertTrue(rendered, "The screenshot color sample could not be decoded")
        XCTAssertEqual(Array(pixel.prefix(3)), [255, 255, 255],
                       "The rendered form's outer background must be white, not Lapis or tan")
    }

    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
