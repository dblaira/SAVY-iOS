import Foundation

enum MetadataEntryKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case reminder
    case action
    case calendar

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .reminder:
            "Reminder"
        case .action:
            "Action"
        case .calendar:
            "Calendar"
        }
    }

    var symbolName: String {
        switch self {
        case .reminder:
            "bell"
        case .action:
            "checkmark.circle"
        case .calendar:
            "calendar"
        }
    }

    /// Icons used in the radial FAB fan — matches Notorious Recall.
    var fabMenuSymbolName: String {
        switch self {
        case .reminder:
            "clock"
        case .action:
            "bolt.fill"
        case .calendar:
            "calendar"
        }
    }
}

enum MetadataEntryPriority: String, CaseIterable, Codable, Equatable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum MetadataSyncState: String, Codable, Equatable {
    case localOnly
    case pendingSync
    case synced
    case failed
}

struct MetadataEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: MetadataEntryKind
    var title: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var scheduledAt: Date?
    var tags: [String]
    var context: String
    var priority: MetadataEntryPriority
    var cadence: String
    var syncState: MetadataSyncState

    init(
        id: UUID = UUID(),
        kind: MetadataEntryKind,
        title: String,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        scheduledAt: Date? = nil,
        tags: [String] = [],
        context: String = "",
        priority: MetadataEntryPriority = .medium,
        cadence: String = "",
        syncState: MetadataSyncState = .pendingSync
    ) {
        self.id = id
        self.kind = kind
        self.title = title.trimmedForMetadata()
        self.notes = notes.trimmedForMetadata()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduledAt = scheduledAt
        self.tags = tags
            .map { $0.trimmedForMetadata() }
            .filter { !$0.isEmpty }
        self.context = context.trimmedForMetadata()
        self.priority = priority
        self.cadence = cadence.trimmedForMetadata()
        self.syncState = syncState
    }
}

private extension String {
    func trimmedForMetadata() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
