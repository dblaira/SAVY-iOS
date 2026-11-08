import XCTest
@testable import SAVY

/// The reply shape and the frozen questions, checked without any model.
final class SendToAITests: XCTestCase {
    func testListMarkersComeOffButNumbersStayWhole() {
        let reply = "1. One video a week.\n- Camera on the tripod.\n3.5 hours per week.\n-5 degrees is the threshold."
        XCTAssertEqual(SendToAI.answers(from: reply, questionCount: 4),
                       ["One video a week.", "Camera on the tripod.", "3.5 hours per week.", "-5 degrees is the threshold."])
    }

    func testShortRepliesPadAndLongRepliesFoldIntoTheLastBox() {
        XCTAssertEqual(SendToAI.answers(from: "a\nb", questionCount: 3), ["a", "b", ""])
        XCTAssertEqual(SendToAI.answers(from: "a\nb\nc\nd", questionCount: 2), ["a", "b c d"])
    }

    func testFrozenQuestionsAreTheEditedDecidePromptsWithCatalogIcons() {
        var entry = Reminder()
        entry.postThemeID = "habit"
        entry.postThemeName = "Habit"
        entry.postAnswersContainQuestions = true
        entry.postAnswers = ["Make it Obvious\nOne video a week.", "Make it Stupid Easy\nTripod stays up.", "Make it Attractive\n", "Make it Satisfying\n"]
        let questions = SendToAI.questions(for: entry)
        XCTAssertEqual(questions.count, 8)
        XCTAssertEqual(questions[1].prompt, "Make it Stupid Easy")
        XCTAssertEqual(questions[1].symbol, PostThemeCatalog.theme(id: "habit")!.questions[1].symbol)
        XCTAssertEqual(questions[4].prompt, "What goes across the top?")
    }

    func testChainWalksFromTheFirstReplyToTheOneAsked() {
        let first = AIExchange(answers: ["a"])
        let second = AIExchange(parentID: first.id, followUp: ["more"], answers: ["b"])
        let third = AIExchange(parentID: second.id, followUp: ["again"], answers: ["c"])
        let chain = SendToAI.chain(to: third.id, in: [third, first, second])
        XCTAssertEqual(chain.map(\.id), [first.id, second.id, third.id])
        let message = SendToAI.message(form: "FORM", chain: chain, followUp: ["next", "part", "stay"])
        XCTAssertTrue(message.contains("Respond 2\n\nWhat do you want next?\nmore"))
        XCTAssertTrue(message.contains("What must stay?\nstay"))
    }

    func testOlderSavedRepliesStillDecode() throws {
        let old = #"{"id":"6C1AED6E-C9B1-4A2F-9C9B-2B4F3D4E5F60","sentAt":815000000,"followUp":[],"answers":["x"]}"#
        let exchange = try JSONDecoder().decode(AIExchange.self, from: Data(old.utf8))
        XCTAssertEqual(exchange.provider, "Claude")
        XCTAssertEqual(exchange.answers, ["x"])
        XCTAssertNil(exchange.parentID)
    }
}
