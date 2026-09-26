import Foundation

enum Priority: String, Codable, CaseIterable, Identifiable {
    case none, low, medium, high
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
    var marks: String {
        switch self {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }
}

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, monthly, yearly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }
}

/// Alert cadence is independent of an entry's calendar recurrence. Hourly always ends at
/// the selected end date, even when the entry itself repeats.
enum ReminderAlert: String, Codable, CaseIterable, Identifiable {
    case none, atStart, fiveMinutesBefore, fifteenMinutesBefore, thirtyMinutesBefore
    case oneHourBefore, oneDayBefore, hourly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .atStart: return "At time of event"
        case .fiveMinutesBefore: return "5 minutes before"
        case .fifteenMinutesBefore: return "15 minutes before"
        case .thirtyMinutesBefore: return "30 minutes before"
        case .oneHourBefore: return "1 hour before"
        case .oneDayBefore: return "1 day before"
        case .hourly: return "Hourly"
        }
    }

    var leadTime: TimeInterval? {
        switch self {
        case .none, .hourly: return nil
        case .atStart: return 0
        case .fiveMinutesBefore: return 300
        case .fifteenMinutesBefore: return 900
        case .thirtyMinutesBefore: return 1_800
        case .oneHourBefore: return 3_600
        case .oneDayBefore: return 86_400
        }
    }
}

/// Optional on Reminder so old caches continue to decode unchanged. A schedule stores
/// concrete instants and its chosen time zone; legacy date/time mirrors remain available.
struct ReminderSchedule: Codable, Equatable {
    static let maximumHourlyDuration: TimeInterval = 24 * 3_600

    var startDate: Date
    var endDate: Date
    var isAllDay: Bool = false
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var alert: ReminderAlert = .atStart
    var travelTimeMinutes: Int = 0
    var calendarIdentifier: String? = nil
    var calendarEventIdentifier: String? = nil
    var invitees: [String]? = nil
    var organizerEmail: String? = nil

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return value
    }

    var validationMessage: String? {
        guard endDate > startDate else { return "Choose an end after the start." }
        guard travelTimeMinutes >= 0 else { return "Travel time cannot be negative." }
        if isAllDay, alert == .hourly { return "Turn off All-day to use hourly alerts." }
        if alert == .hourly, endDate.timeIntervalSince(startDate) > Self.maximumHourlyDuration {
            return "Choose an hourly reminder period of 24 hours or less."
        }
        return nil
    }
}

enum ReminderStatus: String, Codable { case active, completed, deleted }

/// What an item *is*: a timed nudge, a thing you do, a time block, or a post draft.
/// One model, four faces. Post rides the same form with Theme + Decide added on top.
enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case reminder, action, event, post
    var id: String { rawValue }
    var label: String {
        switch self {
        case .reminder: return "Reminder"
        case .action: return "Action"
        case .event: return "Event"
        case .post: return "Post"
        }
    }

    /// What the entry form's segmented control shows. Adam's approved Post mockup names the
    /// third door "Calendar" (matching the bolt fan); the model keeps `event` underneath.
    var segmentLabel: String {
        self == .event ? "Calendar" : label
    }
}

/// Rough time an action takes — for picking what to do by the window you have.
enum Effort: String, Codable, CaseIterable, Identifiable {
    case none, m5, m15, m30, h1, h2plus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "—"
        case .m5: return "5m"
        case .m15: return "15m"
        case .m30: return "30m"
        case .h1: return "1h"
        case .h2plus: return "2h+"
        }
    }
}

/// How much gas an action needs — for matching work to how you feel.
enum Energy: String, Codable, CaseIterable, Identifiable {
    case none, low, medium, high
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "—"
        case .low: return "Low"
        case .medium: return "Med"
        case .high: return "High"
        }
    }
}

/// Adam's 8-step success architecture (the "Adam Pattern") — a reverse-engineered list of the
/// elements that must happen for him to succeed. Tag any item with the step it advances; the same
/// list is shown on every entry form for constant review. Clean labels (no @/#) feed the rec system.
enum SuccessStep: String, Codable, CaseIterable, Identifiable {
    case none, context, circle, closeGap, chooseSuccess, codePattern, killSwitch, clearSign, compound
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .context: return "Context"
        case .circle: return "Circle"
        case .closeGap: return "Close the Gap"
        case .chooseSuccess: return "Choose Success"
        case .codePattern: return "Code the Pattern"
        case .killSwitch: return "Create Kill Switch"
        case .clearSign: return "Clear Sign of Success"
        case .compound: return "Compound"
        }
    }
}

struct Subtask: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var done: Bool = false
}

/// The domain model. Codable for the on-device cache; mapped to/from DB rows in the repository.
/// Every "part" from the entry form is a field here so nothing the user enters is dropped.
struct Reminder: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: ReminderKind = .reminder         // reminder / action / event (local-first for now)
    // Core
    var title: String = ""
    var notes: String = ""
    var url: String = ""
    var imageLocalPath: String? = nil          // local filename; cloud upload is 1.0.1
    // Date & Time
    var dueDate: Date? = nil                    // calendar date (date-only meaning)
    var dueTime: Date? = nil                    // clock time (time-only meaning)
    var endTime: Date? = nil                    // event end (time-only meaning); local-first for now
    var schedule: ReminderSchedule? = nil       // absent on older saved entries
    var urgent: Bool = false
    var repeatRule: RepeatRule = .none
    // Organization
    var listName: String = ""           // no list until the user picks one
    var flag: Bool = false
    var priority: Priority = .none
    // Action (local-first for now)
    var whenIAm: String? = nil
    var outcome: String = ""
    var effort: Effort = .none
    var energy: Energy = .none
    var context: SuccessStep = .none      // the Adam Pattern step this item advances (DB column: context)
    var marksClearSignOfSuccess: Bool? = nil
    var marksCompounding: Bool? = nil
    var deferDate: Date? = nil
    var waitingOn: String = ""
    // Places & People
    var locationName: String = ""
    // Post (kind == .post; local-first like whenIAm). Theme id + name from PostThemeCatalog,
    // and the editable Decide fields in question order (question, blank line, answer).
    // Optionals so cached JSON written before Post existed still decodes.
    var postNumber: Int? = nil
    var postThemeID: String? = nil
    var postThemeName: String? = nil
    var postAnswers: [String]? = nil
    // Missing/false means a legacy answer-only record. True preserves even edited questions.
    var postAnswersContainQuestions: Bool? = nil
    // Graph + lifecycle
    var seededFromTemplateID: String? = nil
    var pinned: Bool = false                    // sorts to the top of the list
    var upNextOrder: Int? = nil                 // manual Up Next rank within pinned/unpinned block
    var tags: [String] = []
    var subtasks: [Subtask] = []
    var status: ReminderStatus = .active
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date? = nil
    var needsSync: Bool = false
}

extension Reminder {
    /// Complete Decide context, including catalog questions for answer-only legacy posts.
    var postQuestionAndAnswers: [String] {
        guard kind == .post else { return [] }
        guard let theme = PostThemeCatalog.theme(id: postThemeID) else { return postAnswers ?? [] }
        return theme.questionAndAnswers(from: postAnswers, containQuestions: postAnswersContainQuestions == true)
    }

    /// Display-only answer portions for the post card; never use these to overwrite saved text.
    var postAnswerTexts: [String] {
        guard kind == .post else { return [] }
        let theme = PostThemeCatalog.theme(id: postThemeID)
        guard theme != nil || postAnswersContainQuestions == true else {
            return (postAnswers ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return postQuestionAndAnswers.enumerated().map { index, field in
            let prompt = theme.flatMap { $0.questions.indices.contains(index) ? $0.questions[index].prompt : nil }
            return PostTheme.answerText(in: field, originalPrompt: prompt)
        }
    }

    var postAnsweredCount: Int { postAnswerTexts.filter { !$0.isEmpty }.count }

    /// Independent success markers. The legacy single Pattern value still counts so existing
    /// entries keep their meaning, while a new entry can now carry both markers at once.
    var isClearSignOfSuccess: Bool {
        (marksClearSignOfSuccess ?? false) || context == .clearSign
    }

    var isCompounding: Bool {
        (marksCompounding ?? false) || context == .compound
    }

    /// The concrete moment a notification should fire, if this reminder carries a date and/or time.
    var fireDate: Date? {
        if let schedule { return schedule.startDate }
        if dueDate == nil && dueTime == nil { return nil }
        let cal = Calendar.current
        let base = dueDate ?? Date()
        var comps = cal.dateComponents([.year, .month, .day], from: base)
        if let t = dueTime {
            let tc = cal.dateComponents([.hour, .minute], from: t)
            comps.hour = tc.hour
            comps.minute = tc.minute
        } else {
            comps.hour = 9
            comps.minute = 0
        }
        return cal.date(from: comps)
    }

    /// All-day entries occupy calendar dates rather than time-zone-shifted instants.
    /// Timed entries appear on every display day intersected by their [start, end) span.
    func occurs(on day: Date, calendar displayCalendar: Calendar = .current) -> Bool {
        guard let schedule else {
            return dueDate.map { displayCalendar.isDate($0, inSameDayAs: day) } ?? false
        }
        guard schedule.endDate > schedule.startDate else { return false }
        let selectedDay = displayCalendar.startOfDay(for: day)
        if schedule.isAllDay {
            let scheduleCalendar = schedule.calendar
            let startParts = scheduleCalendar.dateComponents([.year, .month, .day], from: schedule.startDate)
            let endParts = scheduleCalendar.dateComponents([.year, .month, .day], from: schedule.endDate)
            guard let floatingStart = displayCalendar.date(from: startParts),
                  let floatingEnd = displayCalendar.date(from: endParts) else { return false }
            return selectedDay >= floatingStart && selectedDay < floatingEnd
        }
        guard let nextDay = displayCalendar.date(byAdding: .day, value: 1, to: selectedDay) else { return false }
        return schedule.startDate < nextDay && schedule.endDate > selectedDay
    }

    /// Compact "Jun 20 9:30 AM" style label for the row.
    var whenLabel: String? {
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "MMM d"
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "h:mm a"
        if let schedule {
            if schedule.isAllDay {
                dayFmt.calendar = schedule.calendar
                dayFmt.timeZone = schedule.calendar.timeZone
                let inclusiveEnd = schedule.calendar.date(byAdding: .day, value: -1, to: schedule.endDate)
                    ?? schedule.startDate
                let startLabel = dayFmt.string(from: schedule.startDate)
                if schedule.calendar.isDate(schedule.startDate, inSameDayAs: inclusiveEnd) { return startLabel }
                return startLabel + " – " + dayFmt.string(from: inclusiveEnd)
            }
            dayFmt.timeZone = .current
            timeFmt.timeZone = .current
            let startLabel = dayFmt.string(from: schedule.startDate) + " " + timeFmt.string(from: schedule.startDate)
            let endLabel = Calendar.current.isDate(schedule.startDate, inSameDayAs: schedule.endDate)
                ? timeFmt.string(from: schedule.endDate)
                : dayFmt.string(from: schedule.endDate) + " " + timeFmt.string(from: schedule.endDate)
            return startLabel + " – " + endLabel
        }
        if let date = dueDate, let time = dueTime {
            return dayFmt.string(from: date) + " " + timeFmt.string(from: time)
        } else if let date = dueDate {
            return dayFmt.string(from: date)
        } else if let time = dueTime {
            return timeFmt.string(from: time)
        }
        return nil
    }
}

/// Foundation-only definitions consumed directly by the notification scheduler and its tests.
/// Absolute requests use UTC components so both occurrences of a repeated DST clock hour
/// remain separate instants. Calendar recurrence keeps its existing wall-clock behavior.
struct ReminderNotificationRequestPlan: Equatable {
    var identifier: String
    var dateComponents: DateComponents
    var repeats: Bool
    var fireDate: Date?
}

enum ReminderNotificationPlan {
    static func identifier(for id: UUID) -> String { "recall.reminder.\(id.uuidString)" }

    static func cancellationIdentifiers(for id: UUID) -> [String] {
        let base = identifier(for: id)
        return [base] + (2...6).map { "\(base).\($0)" }
            + (0...24).map { "\(base).hourly.\($0)" }
    }

    static func requests(
        for reminder: Reminder,
        now: Date = Date(),
        calendar legacyCalendar: Calendar = .current
    ) -> [ReminderNotificationRequestPlan] {
        guard reminder.status == .active else { return [] }
        let base = identifier(for: reminder.id)
        let calendar = reminder.schedule?.calendar ?? legacyCalendar
        let fire: Date

        if let schedule = reminder.schedule {
            guard schedule.validationMessage == nil, schedule.alert != .none else { return [] }
            // A linked calendar event owns normal alarms. SAVY owns the bounded hourly
            // run because EventKit has no finite hourly-alert cadence for one event.
            if schedule.calendarIdentifier != nil, schedule.alert != .hourly { return [] }
            if schedule.alert == .hourly {
                return (0...24).compactMap { slot in
                    let instant = schedule.startDate.addingTimeInterval(Double(slot) * 3_600)
                    guard instant > now, instant <= schedule.endDate else { return nil }
                    return absoluteRequest(identifier: "\(base).hourly.\(slot)", fire: instant)
                }
            }
            let lead = schedule.alert.leadTime ?? 0
            fire = schedule.startDate.addingTimeInterval(-lead - Double(schedule.travelTimeMinutes) * 60)
        } else {
            guard reminder.dueDate != nil || reminder.dueTime != nil else { return [] }
            var components = calendar.dateComponents([.year, .month, .day], from: reminder.dueDate ?? now)
            let time = reminder.dueTime.map { calendar.dateComponents([.hour, .minute], from: $0) }
            components.hour = time?.hour ?? 9
            components.minute = time?.minute ?? 0
            guard let legacyFire = calendar.date(from: components) else { return [] }
            fire = legacyFire
        }

        if reminder.repeatRule == .none {
            guard fire > now else { return [] }
            return [absoluteRequest(identifier: base, fire: fire)]
        }

        if reminder.repeatRule == .weekdays {
            let time = calendar.dateComponents([.hour, .minute], from: fire)
            return (2...6).map { weekday in
                var components = DateComponents()
                components.calendar = calendar
                components.timeZone = calendar.timeZone
                components.weekday = weekday
                components.hour = time.hour
                components.minute = time.minute
                return ReminderNotificationRequestPlan(
                    identifier: "\(base).\(weekday)", dateComponents: components, repeats: true, fireDate: nil
                )
            }
        }

        let fields: Set<Calendar.Component>
        switch reminder.repeatRule {
        case .none, .weekdays: return []
        case .daily: fields = [.hour, .minute]
        case .weekly: fields = [.weekday, .hour, .minute]
        case .monthly: fields = [.day, .hour, .minute]
        case .yearly: fields = [.month, .day, .hour, .minute]
        }
        var components = calendar.dateComponents(fields, from: fire)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return [ReminderNotificationRequestPlan(
            identifier: base, dateComponents: components, repeats: true, fireDate: nil
        )]
    }

    private static func absoluteRequest(identifier: String, fire: Date) -> ReminderNotificationRequestPlan {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        components.calendar = utc
        components.timeZone = utc.timeZone
        return ReminderNotificationRequestPlan(
            identifier: identifier, dateComponents: components, repeats: false, fireDate: fire
        )
    }
}

extension JSONEncoder {
    static let recall: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
}
extension JSONDecoder {
    static let recall: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
