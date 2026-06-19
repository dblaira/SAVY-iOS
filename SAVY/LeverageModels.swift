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

struct BeliefGraphTraceTriplePath: Codable, Equatable {
    let axiomIri: String
    let antecedentLabel: String?
    let consequentLabel: String?
    let relationshipType: String?
    let supportedBy: String
}

struct BeliefGraphTrace: Codable, Equatable {
    let matchedAxiomIris: [String]
    let evidenceEntryIri: String
    let paths: [String]
    let triplePaths: [BeliefGraphTraceTriplePath]
    let rankingMethod: String
}

struct BeliefGraphTraceResult: Codable, Equatable {
    let decision: String
    let confidence: String
    let entryId: String
    let graphTrace: BeliefGraphTrace?
    let reason: String

    var hasGraphPath: Bool {
        decision == "belief-graph-match" || decision == "connection-graph-match"
            ? graphTrace != nil
            : false
    }
}

struct OntologyCorrelation: Codable, Equatable {
    let categoryA: String
    let categoryB: String
    let coefficient: Double
    let lag: Int
    let type: String

    init(categoryA: String, categoryB: String, coefficient: Double, lag: Int, type: String) {
        self.categoryA = categoryA
        self.categoryB = categoryB
        self.coefficient = coefficient
        self.lag = lag
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        categoryA = try container.decodeString(forAnyOf: ["category_a", "categoryA"])
        categoryB = try container.decodeString(forAnyOf: ["category_b", "categoryB"])
        coefficient = try container.decode(Double.self, forKey: DynamicCodingKey("coefficient"))
        lag = try container.decode(Int.self, forKey: DynamicCodingKey("lag"))
        type = try container.decode(String.self, forKey: DynamicCodingKey("type"))
    }
}

struct OntologyCategoryStat: Codable, Equatable {
    let category: String
    let mean: Double
    let stdDev: Double
    let weeksWithData: Int
    let totalCount: Int
    let coveragePercent: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        category = try container.decode(String.self, forKey: DynamicCodingKey("category"))
        mean = try container.decode(Double.self, forKey: DynamicCodingKey("mean"))
        stdDev = try container.decodeDouble(forAnyOf: ["std_dev", "stdDev"])
        weeksWithData = try container.decodeInt(forAnyOf: ["weeks_with_data", "weeksWithData"])
        totalCount = try container.decodeInt(forAnyOf: ["total_count", "totalCount"])
        coveragePercent = try container.decodeDouble(forAnyOf: ["coverage_percent", "coveragePercent"])
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

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == DynamicCodingKey {
    func decodeString(forAnyOf keys: [String]) throws -> String {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: DynamicCodingKey(key)) {
                return value
            }
        }
        throw DecodingError.keyNotFound(
            DynamicCodingKey(keys[0]),
            .init(codingPath: codingPath, debugDescription: "Missing one of: \(keys.joined(separator: ", "))")
        )
    }

    func decodeInt(forAnyOf keys: [String]) throws -> Int {
        for key in keys {
            if let value = try decodeIfPresent(Int.self, forKey: DynamicCodingKey(key)) {
                return value
            }
        }
        throw DecodingError.keyNotFound(
            DynamicCodingKey(keys[0]),
            .init(codingPath: codingPath, debugDescription: "Missing one of: \(keys.joined(separator: ", "))")
        )
    }

    func decodeDouble(forAnyOf keys: [String]) throws -> Double {
        for key in keys {
            if let value = try decodeIfPresent(Double.self, forKey: DynamicCodingKey(key)) {
                return value
            }
        }
        throw DecodingError.keyNotFound(
            DynamicCodingKey(keys[0]),
            .init(codingPath: codingPath, debugDescription: "Missing one of: \(keys.joined(separator: ", "))")
        )
    }
}
