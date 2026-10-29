import Foundation

/// A text-only snapshot. Exporting never saves an entry or reads its image.
struct EntryShareContent {
    let entireForm: String

    init(entry: Reminder, sourceApp: String, entryLabel: String, whenIAm: String,
         scheduleMetadata: [String]? = nil, additionalMetadata: [String] = []) {
        let heading = "\(sourceApp) · \(entryLabel)"
        let delegation = """
        Delegate

        What do I want?
        \(entry.title)

        When I am...I like to
        \(whenIAm)

        Done looks like...
        \(entry.outcome)
        """
        var metadata: [String] = []
        func field(_ label: String, _ value: String) {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            metadata.append("\(label): \(value)")
        }
        field("Theme", entry.postThemeName ?? "")
        if entry.context != .none { field("Pattern", entry.context.label) }
        field("Lift", entry.listName)
        if entry.priority != .none { field("Priority", entry.priority.label) }
        if entry.energy != .none { field("Energy", entry.energy.label) }
        if entry.effort != .none { field("Effort", entry.effort.label) }
        field("Tags", entry.tags.joined(separator: ", "))
        if entry.flag { field("Flagged", "Yes") }
        if entry.urgent { field("Urgent", "Yes") }
        if entry.pinned { field("Pinned", "Yes") }
        field("Status", entry.status.rawValue.capitalized)
        field("Notes", entry.notes)
        field("Link", entry.url)
        field("Location", entry.locationName)
        field("Waiting on / delegate to", entry.waitingOn)
        if let scheduleMetadata {
            metadata += scheduleMetadata
        } else {
            if let start = entry.deferDate { field("Start", Self.dateText(start)) }
            if let due = entry.dueDate {
                // Older entries store the day and clock time separately.
                let calendar = Calendar.current
                let clock = calendar.dateComponents([.hour, .minute], from: entry.dueTime ?? due)
                let combined = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0,
                                             second: 0, of: due) ?? due
                field("Due", Self.dateText(combined, includesTime: entry.dueTime != nil))
            } else if let time = entry.dueTime {
                field("Time", Self.dateText(time))
            }
            if let end = entry.endTime { field("End", Self.dateText(end)) }
            if entry.dueDate != nil || entry.dueTime != nil || entry.deferDate != nil {
                field("Time zone", TimeZone.current.identifier)
            }
        }
        if entry.repeatRule != .none { field("Repeat", entry.repeatRule.label) }
        if let completed = entry.completedAt { field("Completed", Self.dateText(completed)) }
        metadata += additionalMetadata
        let metadataText = "Metadata\n\n" + metadata.joined(separator: "\n")

        var whole = [heading]
        let fields = PostThemeCatalog.theme(id: entry.postThemeID)?.questionAndAnswers(
            from: entry.postAnswers, containQuestions: entry.postAnswersContainQuestions == true
        ) ?? entry.postAnswers ?? []
        let decisions = fields.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !decisions.isEmpty { whole.append("Decide\n\n" + decisions.joined(separator: "\n\n")) }
        if let visualTemplates = entry.visualTemplates { whole.append(visualTemplates.shareText) }
        whole.append(delegation)
        let steps = entry.subtasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !steps.isEmpty {
            whole.append("Steps\n\n" + steps.map { "\($0.done ? "[x]" : "[ ]") \($0.title)" }.joined(separator: "\n"))
        }
        whole.append(metadataText)
        entireForm = whole.joined(separator: "\n\n")
    }

    /// Include a tag still being typed without changing the form or committing it.
    static func tags(_ saved: [String], pending: String) -> [String] {
        let tag = pending.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        return tag.isEmpty || saved.contains(tag) ? saved : saved + [tag]
    }

    static func dateText(_ date: Date, includesTime: Bool = true, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = includesTime ? .short : .none
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
