import Foundation

enum BeliefEntryDisplay {
    static func title(headline: String, content: String) -> String {
        let trimmedHeadline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedHeadline.isEmpty, !isTruncatedHeadline(trimmedHeadline, trimmedContent) {
            return trimmedHeadline
        }

        if !trimmedContent.isEmpty {
            return trimmedContent
        }

        return trimmedHeadline
    }

    static func isTruncatedHeadline(_ headline: String, _ content: String) -> Bool {
        if headline.hasSuffix("...") || headline.hasSuffix("…") {
            return true
        }

        let headlineStem = headline
            .replacingOccurrences(of: "\\.{3}$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "…$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !headlineStem.isEmpty, !content.isEmpty else {
            return false
        }

        return content.hasPrefix(headlineStem) && content.count > headline.count
    }
}
