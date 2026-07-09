import Foundation

enum MetadataEntryKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case reminder
    case action
    case calendar
    /// Adam's delegation formula, captured here and landed in Harness
    /// at home ("I go into the savvy app ... I have the three step
    /// delegation when I press enter ... I would like for that to
    /// transfer automatically to the harness app").
    case delegate

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .reminder:
            "Reminder"
        case .action:
            "Action"
        case .calendar:
            "Calendar"
        case .delegate:
            "Delegate"
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
        case .delegate:
            "arrow.up.forward.circle"
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
        case .delegate:
            "arrow.up.forward.circle"
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
