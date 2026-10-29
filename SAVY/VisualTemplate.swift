import Foundation

/// Exact Format labels and prompts from the approved Visual templates preview.
struct VisualTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let questions: [String]

    var symbol: String {
        switch id {
        case "Summarize": return "text.alignleft"
        case "Tables": return "tablecells"
        case "Matrices": return "square.grid.2x2"
        case "Node Trees": return "point.3.connected.trianglepath.dotted"
        case "Graphic Imagery": return "photo.on.rectangle.angled"
        case "Slides": return "rectangle.on.rectangle"
        case "Charts": return "chart.bar"
        case "Images": return "photo"
        case "Video": return "video"
        case "Audio": return "waveform"
        case "Music": return "music.note"
        default: return "doc.text"
        }
    }
}

enum VisualTemplateCatalog {
    static let formats: [VisualTemplate] = [
        VisualTemplate(id: "Summarize", name: "Summarize", questions: [
            "Why does this need to be summarized?",
            "What is being summarized?",
            "Why is summarization helpful compared to more visual outputs?",
            "How should this summary be fully taken advantage of by the audience?"
        ]),
        VisualTemplate(id: "Tables", name: "Tables", questions: [
            "Why would a table help explain this?",
            "What should go in the rows and columns?",
            "Which exact values or differences should be easy to find?",
            "What should the audience be able to do with this table?"
        ]),
        VisualTemplate(id: "Matrices", name: "Matrices", questions: [
            "What relationship should this matrix make clear?",
            "Which two sets of things belong across the top and down the side?",
            "What should each intersection show?",
            "How should the audience use what the matrix reveals?"
        ]),
        VisualTemplate(id: "Node Trees", name: "Node Trees", questions: [
            "What should this tree help the audience understand?",
            "Where should it start, and what belongs under each branch?",
            "What determines how the branches connect or where they split?",
            "What should the audience be able to follow or choose using this tree?"
        ]),
        VisualTemplate(id: "Graphic Imagery", name: "Graphic Imagery", questions: [
            "What should this image make clear at a glance?",
            "What needs to be shown in the image?",
            "How should the arrangement make the important pattern or relationship visible?",
            "What should the audience understand or do after seeing it?"
        ])
    ] + ["Slides", "Charts", "Images", "Video", "Audio", "Music", "Example"].map {
        VisualTemplate(id: $0, name: $0, questions: Array(repeating: "", count: 4))
    }

    static let defaultFormat = formats[2]

    static func format(id: String) -> VisualTemplate? {
        formats.first { $0.id == id }
    }
}

/// Keep every explored Format on the entry, including when another Format is selected.
/// Prompt snapshots also let an older app share a newer, unknown Format without losing text.
struct VisualTemplateDraft: Codable, Equatable {
    private struct Field: Codable, Equatable {
        let question: String
        var answer: String
    }

    private(set) var selectedFormatID: String
    private var fieldsByFormat: [String: [Field]]

    init() {
        selectedFormatID = VisualTemplateCatalog.defaultFormat.id
        fieldsByFormat = [selectedFormatID: Self.emptyFields(for: selectedFormatID)]
    }

    var format: VisualTemplate {
        VisualTemplateCatalog.format(id: selectedFormatID)
            ?? VisualTemplate(id: selectedFormatID, name: selectedFormatID, questions: questions)
    }

    var questions: [String] { Array(fields(for: selectedFormatID).prefix(4)).map(\.question) }
    var answers: [String] { Array(fields(for: selectedFormatID).prefix(4)).map(\.answer) }

    mutating func selectFormat(_ id: String) {
        guard VisualTemplateCatalog.format(id: id) != nil || fieldsByFormat[id] != nil else { return }
        if fieldsByFormat[id] == nil { fieldsByFormat[id] = Self.emptyFields(for: id) }
        selectedFormatID = id
    }

    mutating func setAnswer(_ text: String, at index: Int) {
        guard (0..<4).contains(index) else { return }
        var values = fields(for: selectedFormatID)
        values[index].answer = text
        fieldsByFormat[selectedFormatID] = values
    }

    var hasUserContent: Bool {
        fieldsByFormat.values.joined().contains {
            !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The visible Format comes first, followed by all other explored Formats.
    /// Sharing is a snapshot: neither answers nor the selected Format are changed.
    var shareText: String {
        let knownIDs = VisualTemplateCatalog.formats.map(\.id)
        let unknownIDs = fieldsByFormat.keys.filter { !knownIDs.contains($0) }.sorted()
        let orderedIDs = [selectedFormatID] + (knownIDs + unknownIDs).filter {
            $0 != selectedFormatID && fieldsByFormat[$0] != nil
        }
        let sections = orderedIDs.map { id in
            let name = VisualTemplateCatalog.format(id: id)?.name ?? id
            let writing = fields(for: id).map { field in
                field.question.isEmpty ? field.answer : "\(field.question)\n\(field.answer)"
            }.joined(separator: "\n\n")
            return "Format: \(name)\n\n\(writing)"
        }
        return "Visual templates\n\n" + sections.joined(separator: "\n\n")
    }

    private static func emptyFields(for id: String) -> [Field] {
        let questions = VisualTemplateCatalog.format(id: id)?.questions ?? Array(repeating: "", count: 4)
        return questions.map { Field(question: $0, answer: "") }
    }

    private func fields(for id: String) -> [Field] {
        var fields = fieldsByFormat[id] ?? Self.emptyFields(for: id)
        // Keep any additional fields from a future version; only the four current
        // entry rows are editable here, while sharing and Codable retain them all.
        while fields.count < 4 { fields.append(Field(question: "", answer: "")) }
        return fields
    }
}
