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

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
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
