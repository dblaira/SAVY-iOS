import Foundation

enum CaptureStatus: String, Codable, Equatable {
    case active
    case archived
}

struct CaptureEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var meaning: String
    var createdAt: Date
    var status: CaptureStatus

    init(
        id: UUID = UUID(),
        title: String,
        meaning: String,
        createdAt: Date = Date(),
        status: CaptureStatus = .active
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.status = status
    }
}
