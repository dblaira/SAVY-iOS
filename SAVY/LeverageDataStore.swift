import Foundation

@MainActor
final class LeverageDataStore: ObservableObject {
    @Published private(set) var sections = LeverageContent.seed
    @Published private(set) var status = "Website seed content"
    @Published private(set) var statusDetail = "Checking gateway…"
    @Published private(set) var isLoading = false

    private var refreshGeneration = 0

    var featuredQuote: LeverageItem {
        section(id: "beliefs")?.items.dropFirst().first ?? LeverageContent.beliefs.items[1]
    }

    func section(id: String) -> LeverageSection? {
        sections.first { $0.id == id }
    }

    var isLiveContent: Bool {
        status == "Live AWS graph content"
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoading = true
        defer {
            if generation == refreshGeneration {
                isLoading = false
            }
        }

        // Network calls run detached so SwiftUI view-task cancellation cannot abort URLSession mid-flight.
        async let beliefsReport = Task.detached(priority: .utility) {
            await AWSGraphClient.fetchBeliefsReport(limit: 24)
        }.value
        async let ontologyReport = Task.detached(priority: .utility) {
            await AWSGraphClient.fetchOntologyReport()
        }.value

        let beliefs = await beliefsReport
        let ontology = await ontologyReport

        guard generation == refreshGeneration else { return }

        var nextSections = LeverageContent.seed
        nextSections.replaceSection(id: "beliefs", items: beliefs.items)
        nextSections.replaceSection(id: "ontology", items: ontology.items)
        sections = nextSections

        let beliefsLive = isLive(beliefs.source)
        let ontologyLive = isLive(ontology.source)

        status = beliefsLive || ontologyLive ? "Live AWS graph content" : "Website seed content"
        statusDetail = detailLine(beliefs: beliefs.source, ontology: ontology.source)
    }

    private func isLive(_ source: AWSGraphClient.ContentLineSource) -> Bool {
        if case .live = source { return true }
        return false
    }

    private func detailLine(
        beliefs: AWSGraphClient.ContentLineSource,
        ontology: AWSGraphClient.ContentLineSource
    ) -> String {
        "Beliefs: \(label(for: beliefs)) · Ontology: \(label(for: ontology))"
    }

    private func label(for source: AWSGraphClient.ContentLineSource) -> String {
        switch source {
        case .unconfigured:
            return "no API config — run setup-savy-secrets.sh and rebuild"
        case let .live(itemCount):
            return "live (\(itemCount))"
        case .seedBecauseEmpty:
            return "empty response"
        case let .seedBecauseFailed(message):
            return "failed (\(message))"
        }
    }

    func greatestLeverageItems(limit: Int = 4) -> [LeverageItem] {
        var items: [LeverageItem] = []
        if let beliefs = section(id: "beliefs") {
            items.append(contentsOf: beliefs.items.prefix(max(1, limit / 2)))
        }
        if let ontology = section(id: "ontology"), items.count < limit {
            items.append(contentsOf: ontology.items.prefix(limit - items.count))
        }
        return Array(items.prefix(limit))
    }
}

private extension Array where Element == LeverageSection {
    mutating func replaceSection(id: String, items: [LeverageItem]) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index] = self[index].replacingItems(items)
    }
}
