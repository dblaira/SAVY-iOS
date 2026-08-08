import SwiftUI

struct SavyCowboyAIAnswer: Decodable, Equatable, Sendable {
    let requestID: String
    let conversationID: String
    let story: String
    let whyItMatters: String
    let whatChangesNow: String
    let finalAnswer: String
    let route: String
    let graphRevision: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case conversationID = "conversation_id"
        case adamFacingStory = "adam_facing_story"
        case finalAnswer = "final_answer"
        case route
        case graphRevision = "graph_revision"
    }

    enum StoryCodingKeys: String, CodingKey {
        case story
        case whyItMatters = "why_it_matters"
        case whatChangesNow = "what_changes_now"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(String.self, forKey: .requestID)
        conversationID = try container.decode(String.self, forKey: .conversationID)
        finalAnswer = try container.decode(String.self, forKey: .finalAnswer)
        route = try container.decode(String.self, forKey: .route)
        graphRevision = try container.decode(String.self, forKey: .graphRevision)

        let storyContainer = try container.nestedContainer(
            keyedBy: StoryCodingKeys.self,
            forKey: .adamFacingStory
        )
        story = try storyContainer.decode(String.self, forKey: .story)
        whyItMatters = try storyContainer.decode(String.self, forKey: .whyItMatters)
        whatChangesNow = try storyContainer.decode(String.self, forKey: .whatChangesNow)
    }

    var noteText: String {
        [whatChangesNow, finalAnswer]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

struct SavyCowboyAIRequest: Encodable, Equatable, Sendable {
    let requestID: String
    let conversationID: String
    let rawWords: String
    let attachments: [String] = []
    let currentAppSurface = "savy_ios"
    let connectivityState = "online"
    let requestedOperation = "reason"

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case conversationID = "conversation_id"
        case rawWords = "raw_words"
        case attachments
        case currentAppSurface = "current_app_surface"
        case connectivityState = "connectivity_state"
        case requestedOperation = "requested_operation"
    }
}

private struct SavyCowboyAIEmptyBody: Encodable {}

private struct SavyCowboyAIConversation: Decodable {
    let conversationID: String

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
    }
}

enum SavyCowboyAIError: LocalizedError {
    case invalidResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "CowboyAI returned an unreadable answer."
        case let .server(_, message):
            message
        }
    }
}

protocol SavyCowboyAIHTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: SavyCowboyAIHTTPDataLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

struct SavyCowboyAIClient: Sendable {
    static let authorityHubURL = URL(string: "http://100.102.153.54:8765")!

    let baseURL: URL
    let session: any SavyCowboyAIHTTPDataLoading

    init(
        baseURL: URL = Self.authorityHubURL,
        session: any SavyCowboyAIHTTPDataLoading = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func ask(rawWords: String) async throws -> SavyCowboyAIAnswer {
        let exactWords = rawWords.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversation: SavyCowboyAIConversation = try await post(
            path: "/v1/hub/conversations",
            body: SavyCowboyAIEmptyBody()
        )
        let request = SavyCowboyAIRequest(
            requestID: UUID().uuidString,
            conversationID: conversation.conversationID,
            rawWords: exactWords
        )
        return try await post(path: "/v1/hub/decide", body: request)
    }

    private func post<Response: Decodable, Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(
            url: baseURL.appending(path: path),
            timeoutInterval: 300
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SavyCowboyAIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "CowboyAI could not answer."
            throw SavyCowboyAIError.server(status: http.statusCode, message: message)
        }
        guard let value = try? JSONDecoder().decode(Response.self, from: data) else {
            throw SavyCowboyAIError.invalidResponse
        }
        return value
    }
}

@MainActor
final class SavyCowboyAIController: ObservableObject {
    @Published private(set) var answer: SavyCowboyAIAnswer?
    @Published private(set) var isAsking = false
    @Published private(set) var errorMessage: String?

    private let client: SavyCowboyAIClient

    init(client: SavyCowboyAIClient = SavyCowboyAIClient()) {
        self.client = client
    }

    func ask(rawWords: String) async {
        guard !rawWords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isAsking = true
        errorMessage = nil
        defer { isAsking = false }

        if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_COWBOY_STUB") {
            answer = Self.stubAnswer
            return
        }

        do {
            answer = try await client.ask(rawWords: rawWords)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearAnswer() {
        answer = nil
    }

    private static var stubAnswer: SavyCowboyAIAnswer {
        let data = """
        {
          "request_id": "ui-test-request",
          "conversation_id": "ui-test-conversation",
          "adam_facing_story": {
            "story": "SAVY sent the delegation to CowboyAI.",
            "why_it_matters": "The result returned inside SAVY.",
            "what_changes_now": "Take the first visible step."
          },
          "final_answer": "Open the project and complete its smallest unfinished action.",
          "route": "self_hosted_graph_plus_qwen",
          "graph_revision": "ui-test-revision"
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(SavyCowboyAIAnswer.self, from: data)
    }
}

struct SavyCowboyAIAnswerView: View {
    @Environment(\.dismiss) private var dismiss

    let answer: SavyCowboyAIAnswer
    let onKeepInNotes: () -> Void

    @State private var keptInNotes = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("COWBOYAI")
                            .font(SavyTheme.readingLabel(12))
                            .tracking(1.6)
                            .foregroundStyle(SavyTheme.crimson)
                        Text("What changes now")
                            .font(SavyTheme.readingTitle(30))
                            .foregroundStyle(SavyTheme.deepNavy)
                        Text(answer.whatChangesNow)
                            .font(SavyTheme.readingBody(20))
                            .foregroundStyle(SavyTheme.deepNavy)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Answer")
                            .font(SavyTheme.readingTitle(22))
                            .foregroundStyle(SavyTheme.crimson)
                        Text(answer.finalAnswer)
                            .font(SavyTheme.readingBody(18))
                            .foregroundStyle(SavyTheme.deepNavy)
                            .textSelection(.enabled)
                    }

                    CowboyNaturalVoicePanel(
                        text: answer.noteText,
                        accessibilityIdentifier: "cowboyAIAnswerVoice"
                    )

                    Button {
                        onKeepInNotes()
                        keptInNotes = true
                        SavyHapticFeedback.primaryImpact()
                    } label: {
                        Label(
                            keptInNotes ? "Kept in notes" : "Keep in notes",
                            systemImage: keptInNotes ? "checkmark.circle.fill" : "square.and.pencil"
                        )
                        .font(SavyTheme.readingTitle(17))
                        .foregroundStyle(Brand.card)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(SavyTheme.deepNavy, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(keptInNotes)
                    .accessibilityIdentifier("keepCowboyAIAnswer")

                    Text("Authority Hub · \(answer.route) · graph \(answer.graphRevision)")
                        .font(SavyTheme.readingBody(11))
                        .foregroundStyle(SavyTheme.deepNavy.opacity(0.55))
                        .textSelection(.enabled)
                }
                .padding(22)
            }
            .background(Brand.card.ignoresSafeArea())
            .navigationTitle("CowboyAI answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SavyTheme.crimson)
                }
            }
        }
        .preferredColorScheme(.light)
        .accessibilityIdentifier("cowboyAIAnswer")
    }
}
