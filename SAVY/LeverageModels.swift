import Foundation

struct LeverageSection: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let eyebrow: String
    let headline: String
    let summary: String
    let items: [LeverageItem]

    func replacingItems(_ items: [LeverageItem]) -> LeverageSection {
        LeverageSection(
            id: id,
            title: title,
            eyebrow: eyebrow,
            headline: headline,
            summary: summary,
            items: items
        )
    }
}

struct LeverageItem: Identifiable, Codable, Equatable {
    let id: String
    let kicker: String
    let title: String
    let summary: String
    let body: String
}

struct OntologyCorrelation: Codable, Equatable {
    let categoryA: String
    let categoryB: String
    let coefficient: Double
    let lag: Int
    let type: String
}

struct OntologyCategoryStat: Codable, Equatable {
    let category: String
    let mean: Double
    let stdDev: Double
    let weeksWithData: Int
    let totalCount: Int
    let coveragePercent: Double
}

struct OntologySnapshot: Codable, Equatable {
    let totalWeeks: Int
    let totalExtractions: Int
    let correlations: [OntologyCorrelation]
    let categoryStats: [OntologyCategoryStat]
}
