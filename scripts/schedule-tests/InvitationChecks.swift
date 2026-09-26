import Foundation

@main
struct InvitationChecks {
    static func main() throws {
        let iso = ISO8601DateFormatter()
        let start = iso.date(from: "2026-09-26T04:00:00Z")!
        let end = iso.date(from: "2026-09-26T07:00:00Z")!
        var entry = Reminder()
        entry.id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        entry.title = "Review, plan; next\\step\nPriority"
        entry.notes = String(repeating: "🧩 café ", count: 24)
        entry.locationName = "Desk\r\nATTENDEE:injected@example.com"
        entry.schedule = ReminderSchedule(startDate: start, endDate: end,
                                          timeZoneIdentifier: "America/Los_Angeles",
                                          invitees: ["Adam@example.com", " adam@example.com ", "a#b@example.com"])
        let data = try ScheduleInvitation.invitationData(for: entry, organizerEmail: "owner@example.com", now: start)
        let raw = String(decoding: data, as: UTF8.self)
        let unfolded = raw.replacingOccurrences(of: "\r\n ", with: "")

        precondition(unfolded.contains("METHOD:REQUEST\r\n"))
        precondition(unfolded.contains("UID:11111111-2222-3333-4444-555555555555@savy\r\n"))
        precondition(unfolded.contains("DTSTAMP:20260926T040000Z\r\n"))
        precondition(unfolded.contains("DTSTART:20260926T040000Z\r\nDTEND:20260926T070000Z"))
        precondition(unfolded.contains("SUMMARY:Review\\, plan\\; next\\\\step\\nPriority"))
        precondition(unfolded.contains("LOCATION:Desk\\nATTENDEE:injected@example.com"))
        precondition(unfolded.contains("ORGANIZER:mailto:owner@example.com"))
        precondition(unfolded.contains("mailto:a%23b@example.com"))
        precondition(unfolded.components(separatedBy: "\r\nATTENDEE;").count == 3)
        precondition(raw.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        precondition(!raw.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        precondition(unfolded.contains(entry.notes))
        precondition(raw.hasSuffix("END:VCALENDAR\r\n"))

        precondition(ScheduleInvitation.validationMessage(for: entry, organizerEmail: "bad\r\nATTENDEE:evil@example.com") != nil)
        entry.schedule?.invitees = ["bad\nATTENDEE:evil@example.com"]
        precondition(ScheduleInvitation.validationMessage(for: entry, organizerEmail: "owner@example.com") != nil)
        for invalid in ["a@", "@example.com", "a..b@example.com", "a@example..com", "name@example.com,evil@example.com"] {
            precondition(!ScheduleInvitation.isValidEmail(invalid), "Accepted malformed email: \(invalid)")
        }
        entry.schedule?.invitees = []
        precondition(ScheduleInvitation.validationMessage(for: entry, organizerEmail: "owner@example.com") != nil)
        entry.schedule?.invitees = ["person@example.com"]

        // Local midnight changes from UTC-7 to UTC-8 during this all-day event.
        entry.schedule?.isAllDay = true
        entry.schedule?.startDate = iso.date(from: "2026-11-01T07:00:00Z")!
        entry.schedule?.endDate = iso.date(from: "2026-11-02T08:00:00Z")!
        let allDay = String(decoding: try ScheduleInvitation.invitationData(for: entry, organizerEmail: "owner@example.com"), as: UTF8.self)
        precondition(allDay.contains("DTSTART;VALUE=DATE:20261101\r\nDTEND;VALUE=DATE:20261102"))
        precondition(!allDay.contains("DTSTART:20261101"))

        entry.repeatRule = .weekdays
        let repeating = String(decoding: try ScheduleInvitation.invitationData(for: entry, organizerEmail: "owner@example.com"), as: UTF8.self)
        precondition(repeating.contains("RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"))
        precondition(repeating.contains("UID:11111111-2222-3333-4444-555555555555@savy\r\n"))

        let invalidEnd = entry.schedule!.startDate.addingTimeInterval(-1)
        entry.schedule?.endDate = invalidEnd
        do {
            _ = try ScheduleInvitation.invitationData(for: entry, organizerEmail: "owner@example.com")
            preconditionFailure("Invalid schedule produced an invitation")
        } catch ScheduleIntegrationError.invalidInvitation { }

        print("PASS: invitation UTC times, exclusive all-day dates across DST, Unicode folding, escaping, email validation, recipient deduplication, REQUEST fields, recurrence, stable UID.")
    }
}
