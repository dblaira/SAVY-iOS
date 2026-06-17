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
}
