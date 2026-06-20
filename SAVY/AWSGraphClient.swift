import Foundation

// Aurora SQL schema: docs/schema/aurora.sql
// Neo4j Cypher schema: docs/schema/neo4j.cypher

struct AWSGraphConfiguration: Equatable {
    let apiBaseURL: URL
    let apiKey: String

    init?(baseURLString: String, apiKey: String) {
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedKey.isEmpty,
            let url = URL(string: trimmedURL),
            url.scheme?.hasPrefix("http") == true,
            let host = url.host,
            !host.isEmpty
        else {
            return nil
        }

        self.apiBaseURL = url
        self.apiKey = trimmedKey
    }

    static func fromBundle() -> AWSGraphConfiguration? {
        let baseURL = Bundle.main.object(forInfoDictionaryKey: "AWS_API_BASE_URL") as? String
        let key = Bundle.main.object(forInfoDictionaryKey: "AWS_API_KEY") as? String
        guard
            let baseURL,
            let key,
            !baseURL.hasPrefix("$("),
            !key.hasPrefix("$(")
        else {
            return nil
        }

        return AWSGraphConfiguration(baseURLString: baseURL, apiKey: key)
    }
}

actor AWSGraphClient {
    private let configuration: AWSGraphConfiguration
    private let session: URLSession

    init(configuration: AWSGraphConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 45
            config.timeoutIntervalForResource = 60
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
    }

    func healthURL() -> URL {
        configuration.apiBaseURL.appending(path: "v1/health")
    }

    func authorizedRequest(path: String, method: String = "GET", accessToken: String? = nil) -> URLRequest {
        var request = URLRequest(url: configuration.apiBaseURL.appending(path: path))
        request.httpMethod = method
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func fromBundleConfiguration(session: URLSession = .shared) -> AWSGraphClient? {
        guard let configuration = AWSGraphConfiguration.fromBundle() else { return nil }
        return AWSGraphClient(configuration: configuration, session: session)
    }

    // MARK: - Live fetch stubs (v1 API)

    func fetchEntries(limit: Int = 24, accessToken: String? = nil) async throws -> [LeverageItem] {
        let rows: [EntryRow] = try await fetch(
            path: "v1/entries",
            queryItems: [URLQueryItem(name: "limit", value: "\(limit)")],
            accessToken: accessToken
        )

        return rows.compactMap { $0.leverageItem }
    }

    func fetchCaptures(limit: Int = 20, accessToken: String? = nil) async throws -> [CaptureEntry] {
        let rows: [CaptureRow] = try await fetch(
            path: "v1/captures",
            queryItems: [URLQueryItem(name: "limit", value: "\(limit)")],
            accessToken: accessToken
        )

        return rows.compactMap { $0.captureEntry }
    }

    func fetchCorrelations(accessToken: String? = nil) async throws -> OntologySnapshot {
        try await fetch(
            path: "v1/correlations/latest",
            queryItems: [],
            accessToken: accessToken
        )
    }

    // MARK: - Seed fallback

    func entriesOrSeed(limit: Int = 24, accessToken: String? = nil) async -> [LeverageItem] {
        await loadOrSeed(
            seed: AWSGraphSeed.entries,
            loader: { try await fetchEntries(limit: limit, accessToken: accessToken) }
        )
    }

    func capturesOrSeed(limit: Int = 20, accessToken: String? = nil) async -> [CaptureEntry] {
        await loadOrSeed(
            seed: AWSGraphSeed.captures,
            loader: { try await fetchCaptures(limit: limit, accessToken: accessToken) }
        )
    }

    func correlationsOrSeed(accessToken: String? = nil) async -> OntologySnapshot {
        do {
            let live = try await fetchCorrelations(accessToken: accessToken)
            return live.correlations.isEmpty ? AWSGraphSeed.correlations : live
        } catch {
            return AWSGraphSeed.correlations
        }
    }

    static func entriesOrSeed(limit: Int = 24, accessToken: String? = nil) async -> [LeverageItem] {
        guard let client = fromBundleConfiguration() else { return AWSGraphSeed.entries }
        return await client.entriesOrSeed(limit: limit, accessToken: accessToken)
    }

    static func capturesOrSeed(limit: Int = 20, accessToken: String? = nil) async -> [CaptureEntry] {
        guard let client = fromBundleConfiguration() else { return AWSGraphSeed.captures }
        return await client.capturesOrSeed(limit: limit, accessToken: accessToken)
    }

    static func correlationsOrSeed(accessToken: String? = nil) async -> OntologySnapshot {
        guard let client = fromBundleConfiguration() else { return AWSGraphSeed.correlations }
        return await client.correlationsOrSeed(accessToken: accessToken)
    }

    func ontologyItemsOrSeed(accessToken: String? = nil) async -> [LeverageItem] {
        let snapshot = await correlationsOrSeed(accessToken: accessToken)
        guard snapshot != AWSGraphSeed.correlations else { return AWSGraphSeed.ontologyItems }
        let items = Self.leverageItems(from: snapshot)
        return items.isEmpty ? AWSGraphSeed.ontologyItems : items
    }

    static func ontologyItemsOrSeed(accessToken: String? = nil) async -> [LeverageItem] {
        guard let client = fromBundleConfiguration() else { return AWSGraphSeed.ontologyItems }
        return await client.ontologyItemsOrSeed(accessToken: accessToken)
    }

    // MARK: - Fetch diagnostics (for visible status on device)

    enum ContentLineSource: Equatable {
        case unconfigured
        case live(itemCount: Int)
        case seedBecauseEmpty
        case seedBecauseFailed(String)
    }

    struct BeliefsFetchReport: Equatable {
        let items: [LeverageItem]
        let source: ContentLineSource
    }

    struct OntologyFetchReport: Equatable {
        let items: [LeverageItem]
        let source: ContentLineSource
    }

    static func fetchBeliefsReport(limit: Int = 24) async -> BeliefsFetchReport {
        guard let client = fromBundleConfiguration() else {
            return BeliefsFetchReport(items: AWSGraphSeed.entries, source: .unconfigured)
        }

        for attempt in 1...2 {
            do {
                let live = try await client.fetchEntries(limit: limit)
                if live.isEmpty {
                    return BeliefsFetchReport(items: AWSGraphSeed.entries, source: .seedBecauseEmpty)
                }
                return BeliefsFetchReport(items: live, source: .live(itemCount: live.count))
            } catch {
                if attempt == 1, shouldRetryGatewayFetch(error) {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    continue
                }
                return BeliefsFetchReport(items: AWSGraphSeed.entries, source: .seedBecauseFailed(compactFetchError(error)))
            }
        }

        return BeliefsFetchReport(items: AWSGraphSeed.entries, source: .seedBecauseFailed("request failed"))
    }

    static func fetchOntologyReport() async -> OntologyFetchReport {
        guard fromBundleConfiguration() != nil else {
            return OntologyFetchReport(items: AWSGraphSeed.ontologyItems, source: .unconfigured)
        }

        return OntologyFetchReport(
            items: AWSGraphSeed.ontologyItems,
            source: .seedBecauseFailed("awaits validated RDF export")
        )
    }

    func fetchBeliefGraphTrace(entryId: String, accessToken: String? = nil) async throws -> BeliefGraphTraceResult {
        try await fetch(
            path: "v1/rdf/belief-trace",
            queryItems: [URLQueryItem(name: "entryId", value: entryId)],
            accessToken: accessToken
        )
    }

    func fetchReminders(accessToken: String) async throws -> [Reminder] {
        let rows: [GatewayReminderRow] = try await fetch(
            path: "v1/reminders",
            queryItems: [],
            accessToken: accessToken
        )
        return rows.map(\.reminder)
    }

    func upsertReminder(_ reminder: Reminder, accessToken: String, email: String? = nil) async throws {
        let payload = GatewayReminderPayload(reminder: reminder, email: email)
        let _: GatewayReminderMutationResponse = try await fetch(
            path: "v1/reminders",
            method: "POST",
            queryItems: [],
            accessToken: accessToken,
            body: payload
        )
    }

    func deleteReminder(id: UUID, accessToken: String) async throws {
        let _: GatewayReminderMutationResponse = try await fetch(
            path: "v1/reminders/\(id.uuidString.lowercased())",
            method: "DELETE",
            queryItems: [],
            accessToken: accessToken
        )
    }

    func uploadReminderImage(reminderID: UUID, imageData: Data, accessToken: String) async throws {
        let payload = GatewayReminderImageUpload(
            imageBase64: imageData.base64EncodedString(),
            contentType: "image/jpeg"
        )
        let _: GatewayReminderMutationResponse = try await fetch(
            path: "v1/reminders/\(reminderID.uuidString.lowercased())/image",
            method: "POST",
            queryItems: [],
            accessToken: accessToken,
            body: payload
        )
    }

    static func beliefGraphTraceOrNil(entryId: String) async -> BeliefGraphTraceResult? {
        guard let client = fromBundleConfiguration() else { return nil }
        do {
            return try await client.fetchBeliefGraphTrace(entryId: entryId)
        } catch {
            return nil
        }
    }

    private static func compactFetchError(_ error: Error) -> String {
        if error is CancellationError {
            return "cancelled"
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return "cancelled"
        }
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        if let awsError = error as? AWSGraphClientError {
            switch awsError {
            case .httpError(let statusCode, let body):
                if statusCode == 401 {
                    return "API key rejected — rebuild in Xcode"
                }
                if let body, body.localizedCaseInsensitiveContains("x-api-key") {
                    return "API key rejected — rebuild in Xcode"
                }
                return awsError.localizedDescription ?? "HTTP \(statusCode)"
            default:
                return awsError.localizedDescription ?? "request failed"
            }
        }
        return error.localizedDescription
    }

    private static func shouldRetryGatewayFetch(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        if case AWSGraphClientError.httpError(let statusCode, _) = error {
            return statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504
        }
        return false
    }

    private static func leverageItems(from snapshot: OntologySnapshot) -> [LeverageItem] {
        let summary = LeverageItem(
            id: "live-ontology-summary",
            kicker: "\(snapshot.totalWeeks) WEEKS",
            title: "\(snapshot.categoryStats.count) categories, \(snapshot.totalExtractions.formatted()) extractions",
            summary: "Latest live ontology analysis from Aurora + Neo4j.",
            body: "The current analysis includes \(snapshot.correlations.count) relationships across \(snapshot.totalWeeks) weeks and \(snapshot.totalExtractions.formatted()) extractions."
        )

        let correlations = snapshot.correlations
            .sorted { abs($0.coefficient) > abs($1.coefficient) }
            .prefix(8)
            .map { correlation in
                LeverageItem(
                    id: "live-\(correlation.categoryA)-\(correlation.categoryB)",
                    kicker: String(format: "%.3f", correlation.coefficient),
                    title: "\(correlation.categoryA) moves with \(correlation.categoryB)",
                    summary: "\(correlation.type.capitalized) relationship from the latest ontology run.",
                    body: "\(correlation.categoryA) and \(correlation.categoryB) have a \(correlation.type) coefficient of \(String(format: "%.3f", correlation.coefficient))."
                )
            }

        return [summary] + correlations
    }

    private func loadOrSeed<T>(
        seed: T,
        loader: () async throws -> T
    ) async -> T where T: Collection {
        do {
            let live = try await loader()
            return live.isEmpty ? seed : live
        } catch {
            return seed
        }
    }

    private func fetch<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem],
        accessToken: String?,
        body: (any Encodable)? = nil
    ) async throws -> T {
        var components = URLComponents(
            url: configuration.apiBaseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.awsGraph.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AWSGraphClientError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8)
            throw AWSGraphClientError.httpError(statusCode: http.statusCode, body: responseBody)
        }

        return try JSONDecoder.awsGraph.decode(T.self, from: data)
    }
}

enum AWSGraphClientError: LocalizedError {
    case authFailed(message: String, diagnostic: AWSGraphDiagnostic?)
    case requestFailed
    case httpError(statusCode: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .authFailed(let message, _):
            return message
        case .requestFailed:
            return "AWS graph request failed."
        case .httpError(let statusCode, let body):
            if let body, !body.isEmpty {
                let trimmed = body.prefix(120)
                return "HTTP \(statusCode): \(trimmed)"
            }
            return "HTTP \(statusCode)"
        }
    }

    var diagnostic: AWSGraphDiagnostic? {
        switch self {
        case .authFailed(_, let diagnostic):
            return diagnostic
        case .requestFailed:
            return nil
        case .httpError:
            return nil
        }
    }
}

private struct AuthCredentialRequest: Encodable {
    let email: String
    let password: String
}

private struct AWSGraphAuthErrorResponse: Decodable {
    let message: String?
    let error: String?
    let errorDescription: String?
    let errorCode: String?

    var friendlyMessage: String? {
        if errorCode == "user_already_exists" {
            return "That account already exists. Switch to Sign In and use your password."
        }

        if errorCode == "activation_pending" {
            return message ?? "Your account was created but Cognito has not activated it yet. AWS needs a one-time permission fix."
        }

        if errorCode == "account_not_confirmed" {
            return message ?? "Check your email for the confirmation message from AWS, then try again."
        }

        if errorCode == "invalid_credentials" {
            return "Email or password did not match. Try again."
        }

        if errorCode == "auth_unavailable" {
            return "Sign-in is not live on the gateway yet. Try again in a minute."
        }

        if errorCode == "sign_up_failed" {
            return message ?? "Could not create account. Try Sign In if you already registered."
        }

        return [message, errorDescription, error]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var rawMessage: String? {
        [message, errorDescription, error]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case message
        case error
        case errorDescription = "error_description"
        case errorCode = "error_code"
    }
}

private struct EntryRow: Decodable {
    let id: String
    let headline: String
    let content: String
    let connectionType: String?
    let entryType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case headline
        case content
        case connectionType = "connection_type"
        case entryType = "entry_type"
    }

    var leverageItem: LeverageItem? {
        let body = content.trimmedNonEmpty ?? headline.trimmedNonEmpty
        guard let body else { return nil }

        return LeverageItem(
            id: id,
            kicker: connectionType?.displayLabel ?? entryType?.displayLabel ?? "ENTRY",
            title: BeliefEntryDisplay.title(headline: headline, content: body),
            summary: "",
            body: body
        )
    }
}

private struct GatewayReminderMutationResponse: Decodable {
    let ok: Bool?
    let id: String?
}

private struct GatewayReminderImageUpload: Encodable {
    let imageBase64: String
    let contentType: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case contentType = "content_type"
    }
}

private struct GatewayReminderSubtaskRow: Codable {
    let id: String
    let title: String
    let done: Bool
    let position: Int
}

private struct GatewayReminderPayload: Encodable {
    let id: String
    let title: String
    let notes: String
    let url: String
    let imagePath: String?
    let dueDate: String?
    let dueTime: String?
    let urgent: Bool
    let repeatRule: String
    let earlyReminder: String
    let listName: String
    let flag: Bool
    let priority: String
    let locationName: String
    let whenMessagingPerson: String
    let kind: String
    let endTime: String?
    let outcome: String?
    let effort: String?
    let energy: String?
    let context: String?
    let deferDate: String?
    let waitingOn: String?
    let pinned: Bool
    let upNextOrder: Int?
    let seededFromTemplateID: String?
    let status: String
    let completedAt: String?
    let tags: [String]
    let subtasks: [GatewayReminderSubtaskRow]
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id, title, notes, url, urgent, kind, outcome, effort, energy, context, pinned, status, tags, subtasks, email
        case imagePath = "image_path"
        case dueDate = "due_date"
        case dueTime = "due_time"
        case repeatRule = "repeat_rule"
        case earlyReminder = "early_reminder"
        case listName = "list_name"
        case flag
        case priority
        case locationName = "location_name"
        case whenMessagingPerson = "when_messaging_person"
        case endTime = "end_time"
        case deferDate = "defer_date"
        case waitingOn = "waiting_on"
        case upNextOrder = "up_next_order"
        case seededFromTemplateID = "seeded_from_template_id"
        case completedAt = "completed_at"
    }

    init(reminder: Reminder, email: String?) {
        id = reminder.id.uuidString.lowercased()
        title = reminder.title
        notes = reminder.notes
        url = reminder.url
        imagePath = nil
        dueDate = GatewayReminderDates.dateOnly(reminder.dueDate)
        dueTime = GatewayReminderDates.timeOnly(reminder.dueTime)
        urgent = reminder.urgent
        repeatRule = reminder.repeatRule.rawValue
        earlyReminder = reminder.earlyReminder.rawValue
        listName = reminder.listName
        flag = reminder.flag
        priority = reminder.priority.rawValue
        locationName = reminder.locationName
        whenMessagingPerson = reminder.whenMessagingPerson
        kind = reminder.kind.rawValue
        endTime = GatewayReminderDates.timeOnly(reminder.endTime)
        outcome = reminder.outcome.nilIfEmpty
        effort = reminder.effort == .none ? nil : reminder.effort.rawValue
        energy = reminder.energy == .none ? nil : reminder.energy.rawValue
        context = reminder.context == .none ? nil : reminder.context.rawValue
        deferDate = GatewayReminderDates.dateOnly(reminder.deferDate)
        waitingOn = reminder.waitingOn.nilIfEmpty
        pinned = reminder.pinned
        upNextOrder = reminder.upNextOrder
        seededFromTemplateID = reminder.seededFromTemplateID
        status = reminder.status.rawValue
        completedAt = reminder.completedAt.map(GatewayReminderDates.timestamp)
        tags = reminder.tags
        subtasks = reminder.subtasks.enumerated().map { index, subtask in
            GatewayReminderSubtaskRow(
                id: subtask.id.uuidString.lowercased(),
                title: subtask.title,
                done: subtask.done,
                position: index
            )
        }
        self.email = email
    }
}

private struct GatewayReminderRow: Decodable {
    let id: String
    let title: String
    let notes: String
    let url: String
    let imagePath: String?
    let dueDate: String?
    let dueTime: String?
    let urgent: Bool
    let repeatRule: String
    let earlyReminder: String
    let listName: String
    let flag: Bool
    let priority: String
    let locationName: String
    let whenMessagingPerson: String
    let kind: String
    let endTime: String?
    let outcome: String?
    let effort: String?
    let energy: String?
    let context: String?
    let deferDate: String?
    let waitingOn: String?
    let pinned: Bool
    let upNextOrder: Int?
    let seededFromTemplateID: String?
    let status: String
    let completedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let tags: [String]
    let subtasks: [GatewayReminderSubtaskRow]

    enum CodingKeys: String, CodingKey {
        case id, title, notes, url, urgent, kind, outcome, effort, energy, context, pinned, status, tags, subtasks
        case imagePath = "image_path"
        case dueDate = "due_date"
        case dueTime = "due_time"
        case repeatRule = "repeat_rule"
        case earlyReminder = "early_reminder"
        case listName = "list_name"
        case flag
        case priority
        case locationName = "location_name"
        case whenMessagingPerson = "when_messaging_person"
        case endTime = "end_time"
        case deferDate = "defer_date"
        case waitingOn = "waiting_on"
        case upNextOrder = "up_next_order"
        case seededFromTemplateID = "seeded_from_template_id"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var reminder: Reminder {
        Reminder(
            id: UUID(uuidString: id) ?? UUID(),
            kind: ReminderKind(rawValue: kind) ?? .reminder,
            title: title,
            notes: notes,
            url: url,
            imageLocalPath: nil,
            dueDate: GatewayReminderDates.parseDateOnly(dueDate),
            dueTime: GatewayReminderDates.parseTimeOnly(dueTime),
            endTime: GatewayReminderDates.parseTimeOnly(endTime),
            urgent: urgent,
            repeatRule: RepeatRule(rawValue: repeatRule) ?? .none,
            earlyReminder: EarlyReminder(rawValue: earlyReminder) ?? .none,
            listName: listName,
            flag: flag,
            priority: Priority(rawValue: priority) ?? .none,
            outcome: outcome ?? "",
            effort: effort.flatMap(Effort.init(rawValue:)) ?? .none,
            energy: energy.flatMap(Energy.init(rawValue:)) ?? .none,
            context: context.flatMap(SuccessStep.init(rawValue:)) ?? .none,
            deferDate: GatewayReminderDates.parseDateOnly(deferDate),
            waitingOn: waitingOn ?? "",
            locationName: locationName,
            whenMessagingPerson: whenMessagingPerson,
            seededFromTemplateID: seededFromTemplateID,
            pinned: pinned,
            upNextOrder: upNextOrder,
            tags: tags,
            subtasks: subtasks.map {
                Subtask(id: UUID(uuidString: $0.id) ?? UUID(), title: $0.title, done: $0.done)
            },
            status: ReminderStatus(rawValue: status) ?? .active,
            createdAt: GatewayReminderDates.parseTimestamp(createdAt) ?? Date(),
            updatedAt: GatewayReminderDates.parseTimestamp(updatedAt) ?? Date(),
            completedAt: GatewayReminderDates.parseTimestamp(completedAt),
            needsSync: false
        )
    }
}

private enum GatewayReminderDates {
    static func dateOnly(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func timeOnly(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func parseDateOnly(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static func parseTimeOnly(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.date(from: value)
    }

    static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}

private struct CaptureRow: Decodable {
    let id: String
    let title: String
    let meaning: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case meaning
        case createdAt = "created_at"
    }

    var captureEntry: CaptureEntry? {
        let trimmedTitle = title.trimmedNonEmpty
        let trimmedMeaning = meaning.trimmedNonEmpty
        guard trimmedTitle != nil || trimmedMeaning != nil else { return nil }

        return CaptureEntry(
            id: UUID(uuidString: id) ?? UUID(),
            title: trimmedTitle ?? "",
            meaning: trimmedMeaning ?? "",
            createdAt: createdAt.flatMap(Self.parseTimestamp) ?? Date()
        )
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

enum AWSGraphSeed {
    static var entries: [LeverageItem] { LeverageContent.beliefs.items }
    static var captures: [CaptureEntry] { CaptureSeed.entries }
    static var ontologyItems: [LeverageItem] { LeverageContent.ontology.items }
    static var correlations: OntologySnapshot {
        OntologySnapshot(
            totalWeeks: 92,
            totalExtractions: 4873,
            correlations: [
                OntologyCorrelation(categoryA: "Affect", categoryB: "Learning", coefficient: 0.670, lag: 0, type: "co-movement"),
                OntologyCorrelation(categoryA: "Insight", categoryB: "Purchase", coefficient: 0.663, lag: 0, type: "co-movement"),
                OntologyCorrelation(categoryA: "Exercise", categoryB: "Sleep", coefficient: 0.570, lag: 0, type: "co-movement"),
            ],
            categoryStats: []
        )
    }
}

extension JSONDecoder {
    static var awsGraph: JSONDecoder {
        JSONDecoder()
    }
}

extension JSONEncoder {
    static var awsGraph: JSONEncoder {
        JSONEncoder()
    }
}

private extension HTTPURLResponse {
    var awsRequestID: String? {
        let headers = allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String else { return }
            result[key.lowercased()] = "\(pair.value)"
        }

        return headers["x-amzn-requestid"] ?? headers["x-request-id"]
    }
}

private extension Data {
    var topLevelJSONKeys: [String] {
        guard
            let object = try? JSONSerialization.jsonObject(with: self),
            let dictionary = object as? [String: Any]
        else {
            return []
        }

        return dictionary.keys.sorted()
    }
}

private extension Error {
    var missingDecodingField: String? {
        guard
            let decodingError = self as? DecodingError,
            case DecodingError.keyNotFound(let key, _) = decodingError
        else {
            return nil
        }

        return key.stringValue
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var displayLabel: String {
        replacingOccurrences(of: "_", with: " ").uppercased()
    }
}
