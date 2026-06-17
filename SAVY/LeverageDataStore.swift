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
        guard let client = SupabaseClient.fromBundleConfiguration() else {
            status = "Website seed content"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            async let liveBeliefs = client.fetchBeliefItems(limit: 24)
            async let liveOntology = client.fetchOntologyItems()

            var nextSections = LeverageContent.seed
            let beliefs = try await liveBeliefs
            if !beliefs.isEmpty {
                nextSections.replaceSection(id: "beliefs", items: beliefs)
            }

            let ontology = try await liveOntology
            if !ontology.isEmpty {
                nextSections.replaceSection(id: "ontology", items: ontology)
            }

            sections = nextSections
            status = "Live Supabase content"
        } catch {
            status = "Website seed content"
        }
    }
}

private extension Array where Element == LeverageSection {
    mutating func replaceSection(id: String, items: [LeverageItem]) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index] = self[index].replacingItems(items)
    }
}
