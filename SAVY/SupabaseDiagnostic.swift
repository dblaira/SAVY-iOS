import Foundation

struct SupabaseDiagnostic: Equatable {
    let stage: String
    let endpoint: String?
    let statusCode: Int?
    let requestID: String?
    let errorCode: String?
    let missingField: String?
    let responseKeys: [String]
    let underlyingMessage: String?

    var displayText: String {
        var lines = ["Trace: \(stage)"]

        if let endpoint {
            lines.append("Endpoint: \(endpoint)")
        }

        if let statusCode {
            lines.append("HTTP: \(statusCode)")
        }

        if let errorCode {
            lines.append("Supabase code: \(errorCode)")
        }

        if let requestID {
            lines.append("Request ID: \(requestID)")
        }

        if let missingField {
            lines.append("Missing field: \(missingField)")
        }

        if !responseKeys.isEmpty {
            lines.append("Response keys: \(responseKeys.joined(separator: ", "))")
        }

        if let underlyingMessage {
            lines.append("Detail: \(underlyingMessage)")
        }

        return lines.joined(separator: "\n")
    }
}
