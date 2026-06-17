import Foundation

struct SupabaseConfiguration: Equatable {
    let url: URL
    let anonKey: String

    init?(urlString: String, anonKey: String) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, let url = URL(string: trimmedURL), url.scheme?.hasPrefix("http") == true else {
            return nil
        }

        self.url = url
        self.anonKey = trimmedKey
    }

    static func fromBundle() -> SupabaseConfiguration? {
        let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        guard
            let url,
            let key,
            !url.hasPrefix("$("),
            !key.hasPrefix("$(")
        else {
            return nil
        }

        return SupabaseConfiguration(urlString: url, anonKey: key)
    }
}

actor SupabaseClient {
    private let configuration: SupabaseConfiguration
    private let session: URLSession

    init(configuration: SupabaseConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func healthURL() -> URL {
        configuration.url.appending(path: "rest/v1/")
    }

    func authorizedRequest(path: String) -> URLRequest {
        var request = URLRequest(url: configuration.url.appending(path: path))
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func fromBundleConfiguration(session: URLSession = .shared) -> SupabaseClient? {
        guard let configuration = SupabaseConfiguration.fromBundle() else { return nil }
        return SupabaseClient(configuration: configuration, session: session)
    }

    func fetchBeliefItems(limit: Int = 24) async throws -> [LeverageItem] {
        let rows: [BeliefEntryRow] = try await fetch(
            table: "entries",
            queryItems: [
                URLQueryItem(name: "select", value: "id,headline,content,connection_type,pinned_at,created_at"),
                URLQueryItem(name: "entry_type", value: "eq.connection"),
                URLQueryItem(name: "order", value: "pinned_at.desc.nullslast,created_at.desc"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )

        return rows.compactMap { row in
            let title = row.headline.trimmedNonEmpty ?? row.content.trimmedNonEmpty
            guard let title else { return nil }
            let body = row.content.trimmedNonEmpty ?? title

            return LeverageItem(
                id: row.id,
                kicker: row.connectionType?.displayLabel ?? "BELIEF",
                title: title,
                summary: body == title ? "" : body,
                body: body
            )
        }
    }

    func fetchOntologyItems() async throws -> [LeverageItem] {
        let rows: [CorrelationAnalysisRow] = try await fetch(
            table: "correlation_analyses",
            queryItems: [
                URLQueryItem(name: "select", value: "total_weeks,total_extractions,correlations,category_stats"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )

        guard let row = rows.first else { return [] }
        let summary = LeverageItem(
            id: "live-ontology-summary",
            kicker: "\(row.totalWeeks) WEEKS",
            title: "\(row.categoryStats.count) categories, \(row.totalExtractions.formatted()) extractions",
            summary: "Latest live ontology analysis from Supabase.",
            body: "The current analysis includes \(row.correlations.count) relationships across \(row.totalWeeks) weeks and \(row.totalExtractions.formatted()) extractions."
        )

        let correlations = row.correlations
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

    func signIn(email: String, password: String) async throws -> AuthSession {
        try await authRequest(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            body: AuthCredentialRequest(email: email, password: password)
        )
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        try await signUpRequest(
            path: "auth/v1/signup",
            queryItems: [],
            body: AuthCredentialRequest(email: email, password: password)
        )
    }

    func signOut(accessToken: String) async throws {
        var request = URLRequest(url: configuration.url.appending(path: "auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseClientError.requestFailed
        }
    }

    private func fetch<T: Decodable>(table: String, queryItems: [URLQueryItem]) async throws -> T {
        var components = URLComponents(
            url: configuration.url.appending(path: "rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder.supabase.decode(T.self, from: data)
    }

    private func authRequest<T: Encodable>(
        path: String,
        queryItems: [URLQueryItem],
        body: T
    ) async throws -> AuthSession {
        var components = URLComponents(
            url: configuration.url.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseClientError.authFailed(
                message: "Supabase did not return an HTTP response.",
                diagnostic: SupabaseDiagnostic(
                    stage: "auth transport",
                    endpoint: path,
                    statusCode: nil,
                    requestID: nil,
                    errorCode: nil,
                    missingField: nil,
                    responseKeys: [],
                    underlyingMessage: nil
                )
            )
        }

        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder.supabase.decode(SupabaseAuthErrorResponse.self, from: data)
            throw SupabaseClientError.authFailed(
                message: error?.friendlyMessage ?? "Supabase authentication failed.",
                diagnostic: SupabaseDiagnostic(
                    stage: "auth response",
                    endpoint: path,
                    statusCode: http.statusCode,
                    requestID: http.supabaseRequestID,
                    errorCode: error?.errorCode,
                    missingField: nil,
                    responseKeys: data.topLevelJSONKeys,
                    underlyingMessage: error?.rawMessage
                )
            )
        }

        do {
            return try JSONDecoder.supabase.decode(AuthSession.self, from: data)
        } catch {
            throw SupabaseClientError.authFailed(
                message: "Supabase returned a response the app could not read.",
                diagnostic: SupabaseDiagnostic(
                    stage: "auth decode",
                    endpoint: path,
                    statusCode: http.statusCode,
                    requestID: http.supabaseRequestID,
                    errorCode: nil,
                    missingField: error.missingDecodingField,
                    responseKeys: data.topLevelJSONKeys,
                    underlyingMessage: error.localizedDescription
                )
            )
        }
    }

    private func signUpRequest<T: Encodable>(
        path: String,
        queryItems: [URLQueryItem],
        body: T
    ) async throws -> AuthSession {
        do {
            return try await authRequest(path: path, queryItems: queryItems, body: body)
        } catch SupabaseClientError.authFailed(_, let diagnostic)
            where diagnostic?.stage == "auth decode" {
            throw SupabaseClientError.authFailed(
                message: "Account created. Check your email to confirm it, then sign in.",
                diagnostic: diagnostic
            )
        }
    }
}

enum SupabaseClientError: LocalizedError {
    case authFailed(message: String, diagnostic: SupabaseDiagnostic?)
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .authFailed(let message, _):
            return message
        case .requestFailed:
            return "Supabase request failed."
        }
    }

    var diagnostic: SupabaseDiagnostic? {
        switch self {
        case .authFailed(_, let diagnostic):
            return diagnostic
        case .requestFailed:
            return nil
        }
    }
}

private struct AuthCredentialRequest: Encodable {
    let email: String
    let password: String
}

private struct SupabaseAuthErrorResponse: Decodable {
    let message: String?
    let msg: String?
    let error: String?
    let errorDescription: String?
    let errorCode: String?

    var friendlyMessage: String? {
        if errorCode == "user_already_exists" {
            return "That account already exists. Switch to Sign In and use your password."
        }

        if errorCode == "invalid_credentials" {
            return "Email or password did not match. Try again."
        }

        return [message, msg, errorDescription, error]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var rawMessage: String? {
        [message, msg, errorDescription, error]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case message
        case msg
        case error
        case errorDescription = "error_description"
        case errorCode = "error_code"
    }
}

private struct BeliefEntryRow: Decodable {
    let id: String
    let headline: String
    let content: String
    let connectionType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case headline
        case content
        case connectionType = "connection_type"
    }
}

private struct CorrelationAnalysisRow: Decodable {
    let totalWeeks: Int
    let totalExtractions: Int
    let correlations: [OntologyCorrelation]
    let categoryStats: [OntologyCategoryStat]

    enum CodingKeys: String, CodingKey {
        case totalWeeks = "total_weeks"
        case totalExtractions = "total_extractions"
        case correlations
        case categoryStats = "category_stats"
    }
}

extension JSONDecoder {
    static var supabase: JSONDecoder {
        JSONDecoder()
    }
}

private extension HTTPURLResponse {
    var supabaseRequestID: String? {
        let headers = allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String else { return }
            result[key.lowercased()] = "\(pair.value)"
        }

        return headers["x-request-id"] ?? headers["sb-request-id"] ?? headers["cf-ray"]
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
