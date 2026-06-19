import Foundation

// Aurora SQL schema: docs/schema/aurora.sql
// Neo4j Cypher schema: docs/schema/neo4j.cypher

struct AWSGraphConfiguration: Equatable {
    let apiBaseURL: URL
    let apiKey: String

    init?(baseURLString: String, apiKey: String) {
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, let url = URL(string: trimmedURL), url.scheme?.hasPrefix("http") == true else {
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

    init(configuration: AWSGraphConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
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
        do {
            let live = try await client.fetchEntries(limit: limit)
            if live.isEmpty {
                return BeliefsFetchReport(items: AWSGraphSeed.entries, source: .seedBecauseEmpty)
            }
            return BeliefsFetchReport(items: live, source: .live(itemCount: live.count))
        } catch {
            return BeliefsFetchReport(items: AWSGraphSeed.entries, source: .seedBecauseFailed(compactFetchError(error)))
        }
    }

    static func fetchOntologyReport() async -> OntologyFetchReport {
        guard let client = fromBundleConfiguration() else {
            return OntologyFetchReport(items: AWSGraphSeed.ontologyItems, source: .unconfigured)
        }
        do {
            let snapshot = try await client.fetchCorrelations()
            if snapshot.correlations.isEmpty {
                return OntologyFetchReport(items: AWSGraphSeed.ontologyItems, source: .seedBecauseEmpty)
            }
            let items = leverageItems(from: snapshot)
            if items.isEmpty {
                return OntologyFetchReport(items: AWSGraphSeed.ontologyItems, source: .seedBecauseEmpty)
            }
            return OntologyFetchReport(items: items, source: .live(itemCount: items.count))
        } catch {
            return OntologyFetchReport(items: AWSGraphSeed.ontologyItems, source: .seedBecauseFailed(compactFetchError(error)))
        }
    }

    func fetchBeliefGraphTrace(entryId: String, accessToken: String? = nil) async throws -> BeliefGraphTraceResult {
        try await fetch(
            path: "v1/rdf/belief-trace",
            queryItems: [URLQueryItem(name: "entryId", value: entryId)],
            accessToken: accessToken
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
            return awsError.localizedDescription ?? "request failed"
        }
        return error.localizedDescription
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
        queryItems: [URLQueryItem],
        accessToken: String?
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
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AWSGraphClientError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw AWSGraphClientError.httpError(statusCode: http.statusCode, body: body)
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
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var displayLabel: String {
        replacingOccurrences(of: "_", with: " ").uppercased()
    }
}
