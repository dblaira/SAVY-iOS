import Foundation

@MainActor
final class LeverageDataStore: ObservableObject {
    @Published private(set) var sections = LeverageContent.seed
    @Published private(set) var status = "Website seed content"
    @Published private(set) var isLoading = false

    var featuredQuote: LeverageItem {
        section(id: "beliefs")?.items.dropFirst().first ?? LeverageContent.beliefs.items[1]
    }

    func section(id: String) -> LeverageSection? {
        sections.first { $0.id == id }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let liveEntries = AWSGraphClient.entriesOrSeed(limit: 24)
        async let liveOntology = AWSGraphClient.ontologyItemsOrSeed()

        var nextSections = LeverageContent.seed
        let entries = await liveEntries
        if entries != AWSGraphSeed.entries {
            nextSections.replaceSection(id: "beliefs", items: entries)
        }

        let ontology = await liveOntology
        if ontology != AWSGraphSeed.ontologyItems {
            nextSections.replaceSection(id: "ontology", items: ontology)
        }

        sections = nextSections
        status = entries == AWSGraphSeed.entries && ontology == AWSGraphSeed.ontologyItems
            ? "Website seed content"
            : "Live AWS graph content"
    }
}

private extension Array where Element == LeverageSection {
    mutating func replaceSection(id: String, items: [LeverageItem]) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index] = self[index].replacingItems(items)
    }
}
