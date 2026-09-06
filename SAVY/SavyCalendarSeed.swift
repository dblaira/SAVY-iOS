import Foundation

/// Dated facts from outside SAVY that Adam asked the app to carry on his calendar — not entries he
/// typed, so they arrive with a fixed id and a delivered-once flag. Each one lands on the Calendar
/// exactly once: swipe it away and it stays away.
enum SavyCalendarSeed {
    /// One outside event, written in the time zone it was announced in.
    struct Event {
        let key: String                 // stable seed key; also the delivered-once flag
        let id: UUID                    // fixed reminder id so a second launch never duplicates it
        let components: DateComponents  // wall-clock date and time in `timeZone`
        let timeZone: TimeZone
        let title: String
        let notes: String
        let url: String
    }

    static let all: [Event] = [appleSeptember2026]

    /// Adam, 2026-09-06: "Apple's event is **Wednesday, September 9, 2026 at 10:00 a.m. Pacific** —
    /// not Tuesday. Stream at apple.com / Apple TV app."
    static let appleSeptember2026 = Event(
        key: "apple-event-2026-09-09",
        id: UUID(uuidString: "A99E0909-2026-4909-8A00-100000090910")!,
        components: DateComponents(year: 2026, month: 9, day: 9, hour: 10, minute: 0),
        timeZone: TimeZone(identifier: "America/Los_Angeles") ?? .current,
        title: "Apple Event — 10:00 a.m. Pacific",
        notes: """
        Wednesday, September 9, 2026, 10:00 a.m. Pacific. Stream at apple.com or in the Apple TV app.

        Sources: apple.com events — "Watch a special Apple Event on 9/9 at 10 a.m. PT." MacRumors — \
        Wednesday, September 9, 10:00 a.m. PT ("Surprise and Shine").
        """,
        url: "https://www.apple.com/apple-events/"
    )
}

extension SavyCalendarSeed.Event {
    /// The announced moment first, then the day and clock time the phone reads off it — so
    /// 10:00 Pacific shows at the correct local hour wherever Adam is standing.
    func reminder(calendar: Calendar = .current) -> Reminder? {
        var source = calendar
        source.timeZone = timeZone
        guard let instant = source.date(from: components) else { return nil }

        var reminder = Reminder(id: id, kind: .event, title: title)
        reminder.notes = notes
        reminder.url = url
        reminder.dueDate = calendar.startOfDay(for: instant)
        reminder.dueTime = instant
        reminder.seededFromTemplateID = key
        return reminder
    }
}
