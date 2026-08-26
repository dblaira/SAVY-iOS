import SwiftUI

enum CandidateAuthorityStatus: String, Codable, Equatable {
    case candidateOnly = "candidate-only"
}

struct CowboyCandidateIntakePayload: Codable, Equatable, Sendable {
    let requestID: String
    let captureID: UUID
    let reminderID: UUID
    let sourceAppSurface: String
    let authorityStatus: CandidateAuthorityStatus
    let promptText: String
    let exactWords: TechnicalCaptureExactWords
    let metadata: TechnicalCaptureMetadata
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case captureID = "capture_id"
        case reminderID = "reminder_id"
        case sourceAppSurface = "source_app_surface"
        case authorityStatus = "authority_status"
        case promptText = "prompt_text"
        case exactWords = "exact_words"
        case metadata
        case createdAt = "created_at"
    }

    init(
        requestID: String = UUID().uuidString,
        capture: TechnicalCapture,
        createdAt: Date = Date()
    ) {
        self.requestID = requestID
        self.captureID = capture.id
        self.reminderID = capture.reminderID
        self.sourceAppSurface = "savy_ios"
        self.authorityStatus = .candidateOnly
        self.promptText = capture.promptText
        self.exactWords = capture.exactWords
        self.metadata = capture.metadata
        self.createdAt = createdAt
    }
}

struct CowboyCandidateReceipt: Codable, Equatable, Sendable {
    let requestID: String
    let candidateID: String?
    let conversationID: String?
    let status: String
    let receivedAt: Date

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case candidateID = "candidate_id"
        case conversationID = "conversation_id"
        case status
        case receivedAt = "received_at"
    }
}

enum CowboyCandidateOutboxState: String, Codable, Equatable {
    case pending
    case retryScheduled = "retry_scheduled"
    case delivered
}

struct CowboyCandidateOutboxItem: Identifiable, Codable, Equatable {
    var id: UUID
    var captureID: UUID
    var payload: CowboyCandidateIntakePayload
    var state: CowboyCandidateOutboxState
    var attemptCount: Int
    var nextAttemptAt: Date?
    var lastAttemptAt: Date?
    var lastError: String?
    var receipt: CowboyCandidateReceipt?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        captureID: UUID,
        payload: CowboyCandidateIntakePayload,
        state: CowboyCandidateOutboxState = .pending,
        attemptCount: Int = 0,
        nextAttemptAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil,
        receipt: CowboyCandidateReceipt? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.captureID = captureID
        self.payload = payload
        self.state = state
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
        self.receipt = receipt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
final class CowboyCandidateOutbox: ObservableObject {
    @Published private(set) var items: [CowboyCandidateOutboxItem]

    private let fileURL: URL

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.items = try Self.load(from: fileURL)
    }

    static func live() -> CowboyCandidateOutbox {
        do {
            return try CowboyCandidateOutbox(fileURL: defaultFileURL)
        } catch {
            return CowboyCandidateOutbox(items: [], fileURL: defaultFileURL)
        }
    }

    @discardableResult
    func enqueue(
        _ capture: TechnicalCapture,
        now: Date = Date()
    ) -> CowboyCandidateOutboxItem {
        let payload = CowboyCandidateIntakePayload(capture: capture, createdAt: now)
        if let index = items.firstIndex(where: { $0.captureID == capture.id }) {
            items[index].payload = payload
            items[index].state = .pending
            items[index].attemptCount = 0
            items[index].nextAttemptAt = now
            items[index].lastAttemptAt = nil
            items[index].lastError = nil
            items[index].receipt = nil
            items[index].updatedAt = now
            persist()
            return items[index]
        }

        let item = CowboyCandidateOutboxItem(
            captureID: capture.id,
            payload: payload,
            state: .pending,
            nextAttemptAt: now,
            createdAt: now,
            updatedAt: now
        )
        items.insert(item, at: 0)
        persist()
        return item
    }

    func dueItems(now: Date = Date()) -> [CowboyCandidateOutboxItem] {
        items.filter { item in
            item.state != .delivered && (item.nextAttemptAt ?? .distantPast) <= now
        }
    }

    func recordFailure(
        itemID: UUID,
        message: String,
        now: Date = Date()
    ) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].attemptCount += 1
        items[index].state = .retryScheduled
        items[index].lastAttemptAt = now
        items[index].lastError = message
        items[index].nextAttemptAt = now.addingTimeInterval(Self.retryDelay(for: items[index].attemptCount))
        items[index].updatedAt = now
        persist()
    }

    func recordReceipt(
        itemID: UUID,
        receipt: CowboyCandidateReceipt,
        now: Date = Date()
    ) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].attemptCount += 1
        items[index].state = .delivered
        items[index].lastAttemptAt = now
        items[index].lastError = nil
        items[index].nextAttemptAt = nil
        items[index].receipt = receipt
        items[index].updatedAt = now
        persist()
    }

    private init(items: [CowboyCandidateOutboxItem], fileURL: URL) {
        self.items = items
        self.fileURL = fileURL
    }

    private static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY", isDirectory: true)
        return directory.appendingPathComponent("cowboy-candidate-outbox.json")
    }

    private static func load(from fileURL: URL) throws -> [CowboyCandidateOutboxItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder.recall.decode([CowboyCandidateOutboxItem].self, from: data)
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.recall.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func retryDelay(for attemptCount: Int) -> TimeInterval {
        switch attemptCount {
        case 0, 1:
            return 300
        case 2:
            return 1_800
        default:
            return 7_200
        }
    }
}

protocol CowboyCandidateSubmitting: Sendable {
    func submit(_ payload: CowboyCandidateIntakePayload) async throws -> CowboyCandidateReceipt
}

protocol CowboyHTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: CowboyHTTPDataLoading {}

struct CowboyCandidateClient: CowboyCandidateSubmitting, Sendable {
    static let authorityHubURL = SavyCowboyAIClient.authorityHubURL

    let baseURL: URL
    let session: any CowboyHTTPDataLoading

    init(
        baseURL: URL = Self.authorityHubURL,
        session: any CowboyHTTPDataLoading = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = false
            return URLSession(configuration: configuration)
        }()
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func submit(_ payload: CowboyCandidateIntakePayload) async throws -> CowboyCandidateReceipt {
        var request = URLRequest(
            url: baseURL.appending(path: "/v1/hub/candidates/intake"),
            timeoutInterval: 20
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.recall.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SavyCowboyAIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "CowboyAI candidate intake failed."
            throw SavyCowboyAIError.server(status: http.statusCode, message: message)
        }
        guard let receipt = try? JSONDecoder.recall.decode(CowboyCandidateReceipt.self, from: data) else {
            throw SavyCowboyAIError.invalidResponse
        }
        return receipt
    }
}

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
    /// Where CowboyAI actually runs.
    ///
    /// This was pinned to the Mac Studio, which no longer runs CowboyAI, so the
    /// phone called a machine that could never answer and nothing said why. The
    /// address now names the MacBook Pro that runs it, and can be replaced
    /// without rebuilding the app so a move can never silently break it again.
    static let defaultAuthorityHubURL = URL(string: "http://100.111.154.126:8765")!

    static let authorityHubAddressKey = "cowboyAIAuthorityHubURL"

    static var authorityHubURL: URL {
        guard
            let saved = UserDefaults.standard.string(forKey: authorityHubAddressKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !saved.isEmpty,
            let url = URL(string: saved),
            url.scheme != nil,
            url.host != nil
        else {
            return defaultAuthorityHubURL
        }
        return url
    }

    static func useAuthorityHub(at address: String?) {
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(
            (trimmed?.isEmpty ?? true) ? nil : trimmed,
            forKey: authorityHubAddressKey
        )
    }

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
