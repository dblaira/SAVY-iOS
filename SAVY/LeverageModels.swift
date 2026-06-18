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

    enum CodingKeys: String, CodingKey {
        case categoryA = "category_a"
        case categoryB = "category_b"
        case coefficient
        case lag
        case type
    }
}

struct OntologyCategoryStat: Codable, Equatable {
    let category: String
    let mean: Double
    let stdDev: Double
    let weeksWithData: Int
    let totalCount: Int
    let coveragePercent: Double

    enum CodingKeys: String, CodingKey {
        case category
        case mean
        case stdDev = "std_dev"
        case weeksWithData = "weeks_with_data"
        case totalCount = "total_count"
        case coveragePercent = "coverage_percent"
    }
}

struct OntologySnapshot: Codable, Equatable {
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
