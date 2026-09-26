import Foundation

@main
@MainActor
struct PlannerChecks {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    static func main() throws {
        let start = date("2026-09-26T16:00:00Z")
        let now = start.addingTimeInterval(-60)
        var item = Reminder(title: "Synthetic scheduled entry")
        item.schedule = ReminderSchedule(
            startDate: start, endDate: start.addingTimeInterval(3 * 3_600),
            timeZoneIdentifier: "America/Los_Angeles", alert: .hourly
        )
        let hourly = ReminderNotificationPlan.requests(for: item, now: now)
        expect(hourly.count == 4, "Start and three subsequent hours must all be included")
        expect(hourly.compactMap(\.fireDate) == (0...3).map { start.addingTimeInterval(Double($0) * 3_600) }, "Hourly instants must match the requested window")
        expect(hourly.allSatisfy { !$0.repeats }, "Hourly must never become an endless repeating trigger")
        expect(hourly.allSatisfy { $0.dateComponents.calendar?.date(from: $0.dateComponents) == $0.fireDate }, "Each concrete date must survive trigger component conversion")
        expect(item.fireDate == start, "Schedule start must drive the existing calendar/date consumers")
        let future = ReminderNotificationPlan.requests(for: item, now: start.addingTimeInterval(90 * 60))
        expect(future.compactMap(\.fireDate) == [start.addingTimeInterval(7_200), start.addingTimeInterval(10_800)], "Passed slots must not catch up immediately")
        expect(ReminderNotificationPlan.requests(for: item, now: item.schedule!.endDate).isEmpty, "Nothing may fire after the selected end")
        item.repeatRule = .daily
        expect(ReminderNotificationPlan.requests(for: item, now: now) == hourly, "Repeat must not extend the explicit hourly window")
        item.schedule!.endDate = start.addingTimeInterval(5_400)
        expect(ReminderNotificationPlan.requests(for: item, now: now).count == 2, "A fractional last hour must not overshoot the end")
        item.schedule!.endDate = start.addingTimeInterval(86_400)
        expect(ReminderNotificationPlan.requests(for: item, now: now).count == 25, "The maximum 24-hour window must have 25 inclusive slots")
        item.schedule!.endDate = start.addingTimeInterval(86_401)
        expect(item.schedule!.validationMessage != nil, "Long hourly windows need a visible validation error")
        expect(ReminderNotificationPlan.requests(for: item, now: now).isEmpty, "Invalid windows must not be partially scheduled")
        item.schedule!.endDate = start
        expect(item.schedule!.validationMessage != nil, "End must be after start")
        item.schedule!.endDate = start.addingTimeInterval(10_800)
        item.schedule!.isAllDay = true
        expect(item.schedule!.validationMessage != nil, "All-day plus hourly must fail validation even when loaded from external data")
        expect(ReminderNotificationPlan.requests(for: item, now: now).isEmpty, "Invalid all-day hourly schedules must not enqueue alerts")
        item.schedule!.isAllDay = false

        for (label, springStart) in [
            ("Spring", "2026-03-08T09:30:00Z"),
            ("Fall", "2026-11-01T07:30:00Z")
        ] {
            let boundary = date(springStart)
            item.schedule!.startDate = boundary
            item.schedule!.endDate = boundary.addingTimeInterval(4 * 3_600)
            let plans = ReminderNotificationPlan.requests(for: item, now: boundary.addingTimeInterval(-60))
            expect(plans.count == 5, "\(label) DST window must retain every real elapsed hour")
            expect(zip(plans, plans.dropFirst()).allSatisfy { $1.fireDate!.timeIntervalSince($0.fireDate!) == 3_600 }, "\(label) DST intervals must stay exactly 3600 seconds")
            expect(Set(plans.map(\.dateComponents)).count == 5, "\(label) DST trigger dates must not collapse duplicate clock hours")
        }
        item.schedule!.startDate = start
        item.schedule!.endDate = start.addingTimeInterval(10_800)
        item.repeatRule = .none
        item.schedule!.alert = .fifteenMinutesBefore
        item.schedule!.travelTimeMinutes = 30
        let departure = ReminderNotificationPlan.requests(for: item, now: start.addingTimeInterval(-7_200))
        expect(departure.first?.fireDate == start.addingTimeInterval(-2_700), "Travel and alert lead times must both move the notification earlier")
        expect(ReminderNotificationPlan.requests(for: item, now: start).isEmpty, "Expired one-shot alert must be skipped")
        item.schedule!.alert = .none
        expect(ReminderNotificationPlan.requests(for: item, now: now).isEmpty, "None must genuinely schedule zero alerts")
        item.schedule!.alert = .hourly
        for status in [ReminderStatus.completed, .deleted] {
            item.status = status
            expect(ReminderNotificationPlan.requests(for: item, now: now).isEmpty, "Inactive entries cannot schedule alerts")
        }
        item.status = .active
        let removal = Set(ReminderNotificationPlan.cancellationIdentifiers(for: item.id))
        expect(hourly.allSatisfy { removal.contains($0.identifier) }, "Cancellation must remove every hourly slot")
        expect(removal.contains(ReminderNotificationPlan.identifier(for: item.id)), "Cancellation must remove the legacy one-shot ID")
        expect((2...6).allSatisfy { removal.contains("\(ReminderNotificationPlan.identifier(for: item.id)).\($0)") }, "Cancellation must remove every legacy weekday ID")
        expect((0...24).allSatisfy { removal.contains("\(ReminderNotificationPlan.identifier(for: item.id)).hourly.\($0)") }, "Editing a shorter period must still remove all former slots")

        item.locationName = "Meeting room"
        item.notes = "Schedule notes"
        item.url = "https://example.com/meeting"
        item.schedule!.calendarIdentifier = "calendar-id"
        item.schedule!.alert = .atStart
        expect(ReminderNotificationPlan.requests(for: item, now: now).isEmpty, "A calendar-backed event must not get a duplicate SAVY alarm")
        item.schedule!.alert = .hourly
        expect(ReminderNotificationPlan.requests(for: item, now: now).count == 4, "Calendar-backed hourly alerts must still be owned by SAVY")
        item.schedule!.calendarEventIdentifier = "event-id"
        item.schedule!.invitees = ["guest@example.com"]
        item.schedule!.organizerEmail = "organizer@example.com"
        item.createdAt = start
        item.updatedAt = start
        let encoded = try JSONEncoder.recall.encode(item)
        let decoded = try JSONDecoder.recall.decode(Reminder.self, from: encoded)
        expect(decoded == item, "Every schedule field must survive a real cache round trip")
        var legacyJSON = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacyJSON.removeValue(forKey: "schedule")
        let legacy = try JSONDecoder.recall.decode(Reminder.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        expect(legacy.schedule == nil && legacy.title == item.title, "A pre-schedule archive must still decode")

        var legacyCalendar = Calendar(identifier: .gregorian)
        legacyCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var oldEntry = Reminder(title: "Legacy date-only reminder")
        oldEntry.dueDate = start
        let oldPlan = ReminderNotificationPlan.requests(for: oldEntry, now: date("2026-09-25T00:00:00Z"), calendar: legacyCalendar)
        expect(oldPlan.first?.fireDate == date("2026-09-26T09:00:00Z"), "Legacy date-only reminders must retain 9 AM")
        oldEntry.repeatRule = .weekdays
        let weekdays = ReminderNotificationPlan.requests(for: oldEntry, now: now, calendar: legacyCalendar)
        expect(weekdays.count == 5 && weekdays.allSatisfy(\.repeats), "Legacy weekday recurrence must remain available")
        expect(weekdays.compactMap { $0.dateComponents.weekday } == Array(2...6), "Weekday recurrence must use Monday through Friday")

        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let september25 = losAngeles.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let september26 = losAngeles.date(byAdding: .day, value: 1, to: september25)!
        let september27 = losAngeles.date(byAdding: .day, value: 2, to: september25)!
        var span = Reminder(title: "Synthetic multi-day event")
        span.schedule = ReminderSchedule(
            startDate: september25, endDate: september27, isAllDay: true,
            timeZoneIdentifier: "America/Los_Angeles"
        )
        expect(span.occurs(on: september25, calendar: losAngeles), "Multi-day all-day entries must include the starting day")
        expect(span.occurs(on: september26, calendar: losAngeles), "Multi-day all-day entries must include each day before the exclusive end")
        expect(!span.occurs(on: september27, calendar: losAngeles), "An all-day exclusive end must not appear as another occupied day")
        expect(!span.occurs(on: september25.addingTimeInterval(-1), calendar: losAngeles), "An all-day entry must not leak into the preceding day")
        expect(span.whenLabel == "Sep 25 – Sep 26", "All-day labels must show the inclusive last occupied day")

        span.schedule!.timeZoneIdentifier = "Asia/Tokyo"
        span.schedule!.startDate = date("2026-09-24T15:00:00Z")
        span.schedule!.endDate = date("2026-09-25T15:00:00Z")
        expect(span.occurs(on: september25, calendar: losAngeles), "Tokyo September25 all-day must remain September25 on the Los Angeles calendar")
        expect(!span.occurs(on: september25.addingTimeInterval(-1), calendar: losAngeles), "A Tokyo all-day entry must not shift to the prior Los Angeles day")
        expect(!span.occurs(on: september26, calendar: losAngeles), "Single-day Tokyo all-day must exclude September26 in Los Angeles")
        expect(span.whenLabel == "Sep 25", "An all-day label must use the schedule's floating date")

        span.schedule!.isAllDay = false
        span.schedule!.startDate = losAngeles.date(byAdding: .hour, value: 23, to: september25)!
        span.schedule!.endDate = losAngeles.date(byAdding: .hour, value: 1, to: september26)!
        expect(span.occurs(on: september25, calendar: losAngeles), "An overnight timed entry must appear on its first day")
        expect(span.occurs(on: september26, calendar: losAngeles), "An overnight timed entry must also appear on its second day")
        expect(!span.occurs(on: september27, calendar: losAngeles), "A timed period must stop appearing after its end")
        span.schedule!.endDate = september26
        expect(!span.occurs(on: september26, calendar: losAngeles), "Timed entries ending exactly at midnight must not occupy the next day")

        let localCalendar = Calendar.current
        let localStart = localCalendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 23))!
        let localEnd = localCalendar.date(byAdding: .hour, value: 2, to: localStart)!
        span.schedule!.startDate = localStart
        span.schedule!.endDate = localEnd
        let days = DateFormatter(); days.dateFormat = "MMM d"
        let times = DateFormatter(); times.dateFormat = "h:mm a"
        let expectedTimedLabel = days.string(from: localStart) + " " + times.string(from: localStart)
            + " – " + days.string(from: localEnd) + " " + times.string(from: localEnd)
        expect(span.whenLabel == expectedTimedLabel, "Timed labels must use device-local times and show the date for an overnight end")
        oldEntry.dueDate = september25
        expect(oldEntry.occurs(on: september25, calendar: losAngeles), "Legacy due-date entries must retain same-day matching")
        expect(!oldEntry.occurs(on: september26, calendar: losAngeles), "Legacy entries must not gain a duration")
        print("PASS: \(checks) schedule planner and cache checks against current app sources")
    }
}
