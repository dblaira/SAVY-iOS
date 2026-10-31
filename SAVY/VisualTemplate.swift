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
            "What am I comparing?",
            "What goes in the rows?",
            "What goes in the columns?",
            "What difference should people see?"
        ]),
        VisualTemplate(id: "Matrices", name: "Matrices", questions: [
            "What goes across the top?",
            "What goes down the side?",
            "What goes where they meet?",
            "What connection should people see?"
        ]),
        VisualTemplate(id: "Node Trees", name: "Node Trees", questions: [
            "What goes first?",
            "What comes under it?",
            "How are they connected?",
            "What order should people follow?"
        ]),
        VisualTemplate(id: "Graphic Imagery", name: "Graphic Imagery", questions: [
            "What idea am I showing?",
            "What needs to be in the image?",
            "What should people notice first?",
            "What should this make clear while I talk?"
        ]),
        VisualTemplate(id: "Slides", name: "Slides", questions: [
            "What are the steps or elements?",
            "What goes on each slide?",
            "What should be shown together?",
            "What text keeps people on topic?"
        ]),
        VisualTemplate(id: "Charts", name: "Charts", questions: [
            "What's X?",
            "What's Y?",
            "Is there a trend or an outlier?",
            "What context do people need?"
        ]),
        VisualTemplate(id: "Images", name: "Images", questions: [
            "What still image do I want?",
            "What should people notice in it?",
            "What does it help people understand?",
            "Is there a feeling I want the image to create?"
        ]),
        VisualTemplate(id: "Video", name: "Video", questions: [
            "What do I want people to see happening?",
            "What part of the story does it show?",
            "What am I saying while it plays?",
            "Where does the clip start and end?"
        ]),
        VisualTemplate(id: "Audio", name: "Audio", questions: [
            "What do I want people to hear?",
            "What does the sound help explain?",
            "What should be on screen while it plays?",
            "Where does it belong in the story?"
        ]),
        VisualTemplate(id: "Music", name: "Music", questions: [
            "Is music going to be an important part of it?",
            "What feeling should it create?",
            "Where should it come in?",
            "Where should it stop?"
        ]),
        VisualTemplate(id: "Example", name: "Example", questions: [
            "What am I showing an example of?",
            "What happens from beginning to end?",
            "What will people see and hear?",
            "How could they use it in their own circumstances?"
        ])
    ]

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
        // Older media formats saved empty prompt slots. Supply the current prompt
        // only when both strings are empty, preserving all writing and snapshots.
        if let format = VisualTemplateCatalog.format(id: id) {
            for (index, question) in format.questions.prefix(4).enumerated()
                where fields[index].question.isEmpty && fields[index].answer.isEmpty {
                fields[index] = Field(question: question, answer: "")
            }
        }
        return fields
    }
}
