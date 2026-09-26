import Foundation

#if canImport(UIKit)
import Combine
import EventKit
import MessageUI
import SwiftUI

/// Calendar access is requested only after the person opens the Calendar chooser.
/// Local schedules and hourly notifications never need calendar permission.
@MainActor
final class CalendarScheduleBridge: ObservableObject {
    static let shared = CalendarScheduleBridge()

    @Published private(set) var availableCalendars: [EKCalendar] = []
    @Published private(set) var authorized: Bool

    private let eventStore = EKEventStore()
    private let defaults: UserDefaults
    private struct PendingCalendarUpdate: Codable {
        let previous: Reminder
        let current: Reminder?
    }
    private let pendingSyncKey = "savy.schedule.pendingCalendarUpdates"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestFullAccess() async throws {
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorized = granted
            guard granted else { throw ScheduleIntegrationError.calendarAccessDenied }
        }
        authorized = true
    }

    func loadCalendars() async throws {
        try await requestFullAccess()
        eventStore.refreshSourcesIfNecessary()
        availableCalendars = eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func calendarLabel(id: String?) -> String {
        guard let id else { return "SAVY only" }
        if let calendar = availableCalendars.first(where: { $0.calendarIdentifier == id }) {
            return calendar.title
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return "Selected calendar"
        }
        return eventStore.calendar(withIdentifier: id)?.title ?? "Calendar unavailable"
    }

    /// Receiving account data never creates another calendar event. Only this device's
    /// existing link is updated. Failed removals are retained so a later refresh can retry.
    func reconcileSynced(previous: Reminder, current: Reminder?) async {
        var pending = pendingCalendarUpdates
        let linked = previous.schedule?.calendarEventIdentifier != nil
            ? previous : pending[previous.id.uuidString]?.previous
        guard let linked else { return }
        pending[previous.id.uuidString] = PendingCalendarUpdate(previous: linked, current: current)
        savePendingCalendarUpdates(pending)
        await retryPendingSync()
    }

    func retryPendingSync() async {
        var pending = pendingCalendarUpdates
        for (key, update) in pending {
            do {
                if let current = update.current, current.status == .active,
                   current.schedule?.calendarIdentifier != nil,
                   current.schedule?.calendarEventIdentifier != nil {
                    _ = try await saveEvent(for: current)
                } else {
                    try await disableAlertsForLinkedEvent(update.previous)
                    defaults.removeObject(forKey: "savy.schedule.event.\(update.previous.id.uuidString)")
                }
                pending.removeValue(forKey: key)
            } catch {
                NotificationScheduler.status.errorMessage = error.localizedDescription
            }
        }
        savePendingCalendarUpdates(pending)
    }

    private var pendingCalendarUpdates: [String: PendingCalendarUpdate] {
        guard let data = defaults.data(forKey: pendingSyncKey) else { return [:] }
        return (try? JSONDecoder().decode([String: PendingCalendarUpdate].self, from: data)) ?? [:]
    }

    private func savePendingCalendarUpdates(_ updates: [String: PendingCalendarUpdate]) {
        if let data = try? JSONEncoder().encode(updates) { defaults.set(data, forKey: pendingSyncKey) }
    }

    func discardPendingSync(for id: UUID) {
        var pending = pendingCalendarUpdates
        pending.removeValue(forKey: id.uuidString)
        savePendingCalendarUpdates(pending)
    }

    /// Only the explicit selected calendar is written. The caller persists the returned ID.
    /// A retry also consults the recovery ID, covering an event save followed by a local save failure.
    func saveEvent(for reminder: Reminder) async throws -> String? {
        guard let schedule = reminder.schedule, let calendarID = schedule.calendarIdentifier else { return nil }
        if let message = schedule.validationMessage { throw ScheduleIntegrationError.invalidSchedule(message) }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            authorized = false
            throw ScheduleIntegrationError.calendarAccessDenied
        }
        guard let calendar = eventStore.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else {
            throw ScheduleIntegrationError.calendarUnavailable
        }

        let recoveryKey = "savy.schedule.event.\(reminder.id.uuidString)"
        let linkedID = schedule.calendarEventIdentifier ?? defaults.string(forKey: recoveryKey)
        let event: EKEvent
        if let linkedID {
            guard let existing = eventStore.event(withIdentifier: linkedID) else {
                throw ScheduleIntegrationError.linkedEventUnavailable
            }
            guard existing.calendar.allowsContentModifications else {
                throw ScheduleIntegrationError.calendarUnavailable
            }
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
        }

        event.calendar = calendar
        event.title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? reminder.kind.label : reminder.title
        event.isAllDay = schedule.isAllDay
        event.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current
        if schedule.isAllDay {
            let range = ScheduleInvitation.allDayRange(schedule)
            event.startDate = range.start
            event.endDate = range.end
        } else {
            event.startDate = schedule.startDate
            event.endDate = schedule.endDate
        }
        event.location = reminder.locationName.isEmpty ? nil : reminder.locationName
        event.notes = reminder.notes.isEmpty ? nil : reminder.notes
        event.url = reminder.url.isEmpty ? nil : URL(string: reminder.url)
        event.recurrenceRules = Self.recurrenceRule(reminder.repeatRule).map { [$0] }
        // Bounded hourly alerts belong to SAVY. Providers can truncate multiple EKAlarms.
        if let leadTime = schedule.alert.leadTime {
            let offset = leadTime + TimeInterval(schedule.travelTimeMinutes * 60)
            event.alarms = [EKAlarm(relativeOffset: -offset)]
        } else {
            event.alarms = []
        }

        do {
            try eventStore.save(event, span: .futureEvents, commit: true)
        } catch {
            throw ScheduleIntegrationError.calendarSaveFailed(error.localizedDescription)
        }
        guard let identifier = event.eventIdentifier, !identifier.isEmpty else {
            throw ScheduleIntegrationError.calendarSaveFailed("Calendar did not return an event identifier.")
        }
        defaults.set(identifier, forKey: recoveryKey)
        // An explicit successful user save supersedes a previously failed remote update.
        var pending = pendingCalendarUpdates
        pending.removeValue(forKey: reminder.id.uuidString)
        savePendingCalendarUpdates(pending)
        return identifier
    }

    /// Called only when a person saves an explicit unlink or removes their schedule.
    /// Keep the calendar event itself; silence its alerts before SAVY starts its own.
    func disableAlertsForLinkedEvent(_ reminder: Reminder) async throws {
        let recoveryKey = "savy.schedule.event.\(reminder.id.uuidString)"
        guard let identifier = reminder.schedule?.calendarEventIdentifier ?? defaults.string(forKey: recoveryKey) else { return }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            authorized = false
            // None and Hourly never create native event alarms, so there is nothing known to cancel.
            guard reminder.schedule?.alert.leadTime != nil else { return }
            throw ScheduleIntegrationError.calendarAlertAccessDenied
        }
        guard let event = eventStore.event(withIdentifier: identifier) else {
            // The person may already have removed the event directly in Calendar.
            defaults.removeObject(forKey: recoveryKey)
            return
        }
        guard !(event.alarms ?? []).isEmpty else { return }
        guard event.calendar.allowsContentModifications else {
            throw ScheduleIntegrationError.calendarAlertCancellationFailed("The linked calendar is read-only.")
        }
        event.alarms = []
        do {
            try eventStore.save(event, span: .futureEvents, commit: true)
        } catch {
            throw ScheduleIntegrationError.calendarAlertCancellationFailed(error.localizedDescription)
        }
    }

    private static func recurrenceRule(_ rule: RepeatRule) -> EKRecurrenceRule? {
        switch rule {
        case .none: return nil
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly: return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        case .weekdays:
            let days = [EKWeekday.monday, .tuesday, .wednesday, .thursday, .friday].map { EKRecurrenceDayOfWeek($0) }
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days,
                                    daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                    daysOfTheYear: nil, setPositions: nil, end: nil)
        }
    }
}

/// The person reviews the recipients and presses Mail's Send button. Saving an entry never sends.
struct ScheduleInvitationComposer: UIViewControllerRepresentable {
    let reminder: Reminder
    let organizerEmail: String
    var onComplete: (MFMailComposeResult, Error?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(ScheduleInvitation.normalizedInvitees(for: reminder))
        controller.setPreferredSendingEmailAddress(organizerEmail.trimmingCharacters(in: .whitespacesAndNewlines))
        controller.setSubject(reminder.title)
        controller.setMessageBody("You're invited to \(reminder.title). The calendar invitation is attached.", isHTML: false)
        // The caller gates presentation with validationMessage and canSendMail().
        do {
            let data = try ScheduleInvitation.invitationData(for: reminder, organizerEmail: organizerEmail)
            controller.addAttachmentData(data, mimeType: "text/calendar; method=REQUEST", fileName: "Invitation.ics")
        } catch {
            context.coordinator.preparationError = error
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {
        if let error = context.coordinator.preparationError {
            context.coordinator.preparationError = nil
            Task { @MainActor in onComplete(.failed, error) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let onComplete: (MFMailComposeResult, Error?) -> Void
        var preparationError: Error?

        init(onComplete: @escaping (MFMailComposeResult, Error?) -> Void) { self.onComplete = onComplete }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onComplete(result, error)
        }
    }
}
#endif

enum ScheduleIntegrationError: LocalizedError {
    case calendarAccessDenied
    case calendarUnavailable
    case linkedEventUnavailable
    case calendarSaveFailed(String)
    case calendarAlertAccessDenied
    case calendarAlertCancellationFailed(String)
    case invalidSchedule(String)
    case invalidInvitation(String)

    var errorDescription: String? {
        switch self {
        case .calendarAccessDenied:
            return "Allow SAVY full Calendar access in Settings, then choose the calendar again. Or choose SAVY only."
        case .calendarUnavailable:
            return "This calendar is no longer writable. Choose another calendar or SAVY only."
        case .linkedEventUnavailable:
            return "The linked calendar event could not be found. Your SAVY entry is unchanged. Restore the event in Calendar or choose SAVY only."
        case .calendarSaveFailed(let reason):
            return "Calendar could not save this event. \(reason)"
        case .calendarAlertAccessDenied:
            return "Allow SAVY full Calendar access in Settings to stop the linked event's alerts, then save again."
        case .calendarAlertCancellationFailed(let reason):
            return "Calendar could not stop the linked event's alerts. \(reason)"
        case .invalidSchedule(let message), .invalidInvitation(let message):
            return message
        }
    }
}

/// Pure RFC 5545/5546 generation, separated from Calendar permission and the Mail composer.
enum ScheduleInvitation {
    static func normalizedInvitees(for reminder: Reminder) -> [String] {
        var seen = Set<String>()
        return (reminder.schedule?.invitees ?? []).compactMap { raw in
            let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty, seen.insert(address.lowercased()).inserted else { return nil }
            return address
        }
    }

    static func validationMessage(for reminder: Reminder, organizerEmail: String) -> String? {
        guard let schedule = reminder.schedule else { return "Choose a schedule before sending invitations." }
        if let message = schedule.validationMessage { return message }
        guard isValidEmail(organizerEmail.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return "Enter your email address as the organizer."
        }
        let recipients = normalizedInvitees(for: reminder)
        guard !recipients.isEmpty else { return "Add at least one invitee's email address." }
        guard recipients.allSatisfy(isValidEmail) else { return "Enter a valid email address for each invitee." }
        return nil
    }

    static func isValidEmail(_ value: String) -> Bool {
        // Excluding separators/control characters prevents mailto and iCalendar line injection.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+-/=?^_`{|}~@")
        guard !value.isEmpty, value.utf8.count <= 254,
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[0].utf8.count <= 64,
              !parts[0].hasPrefix("."), !parts[0].hasSuffix("."), !parts[0].contains("..") else { return false }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        let domainCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.unicodeScalars.allSatisfy { domainCharacters.contains($0) }
        }
    }

    static func invitationData(for reminder: Reminder, organizerEmail: String, now: Date = Date()) throws -> Data {
        if let message = validationMessage(for: reminder, organizerEmail: organizerEmail) {
            throw ScheduleIntegrationError.invalidInvitation(message)
        }
        guard let schedule = reminder.schedule else {
            throw ScheduleIntegrationError.invalidInvitation("Choose a schedule before sending invitations.")
        }
        let organizer = organizerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//SAVY//Schedule//EN", "CALSCALE:GREGORIAN",
                     "METHOD:REQUEST", "BEGIN:VEVENT", "UID:\(reminder.id.uuidString.lowercased())@savy",
                     "DTSTAMP:\(utcDateTime(now))", "SEQUENCE:\(max(0, Int(reminder.updatedAt.timeIntervalSince1970)))",
                     "ORGANIZER:\(mailTo(organizer))"]
        if schedule.isAllDay {
            let range = allDayRange(schedule)
            lines += ["DTSTART;VALUE=DATE:\(calendarDate(range.start, calendar: schedule.calendar))",
                      "DTEND;VALUE=DATE:\(calendarDate(range.end, calendar: schedule.calendar))"]
        } else {
            lines += ["DTSTART:\(utcDateTime(schedule.startDate))", "DTEND:\(utcDateTime(schedule.endDate))"]
        }
        lines.append("SUMMARY:\(escapedText(reminder.title))")
        if !reminder.locationName.isEmpty { lines.append("LOCATION:\(escapedText(reminder.locationName))") }
        if !reminder.notes.isEmpty { lines.append("DESCRIPTION:\(escapedText(reminder.notes))") }
        if let url = URL(string: reminder.url), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
           !reminder.url.contains(where: { $0.isNewline }) {
            lines.append("URL:\(url.absoluteString)")
        }
        if let recurrence = recurrenceLine(reminder.repeatRule) { lines.append(recurrence) }
        for address in normalizedInvitees(for: reminder) {
            lines.append("ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:\(mailTo(address))")
        }
        lines += ["STATUS:CONFIRMED", "END:VEVENT", "END:VCALENDAR"]
        return Data((lines.map(foldedLine).joined(separator: "\r\n") + "\r\n").utf8)
    }

    /// endDate is an exclusive date boundary, matching Calendar and iCalendar semantics.
    static func allDayRange(_ schedule: ReminderSchedule) -> (start: Date, end: Date) {
        let calendar = schedule.calendar
        let start = calendar.startOfDay(for: schedule.startDate)
        let selectedEnd = calendar.startOfDay(for: schedule.endDate)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, max(nextDay, selectedEnd))
    }

    private static func utcDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func calendarDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func escapedText(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    private static func mailTo(_ address: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._+-")
        return "mailto:" + (address.addingPercentEncoding(withAllowedCharacters: safe) ?? address)
    }

    /// RFC 5545 folds after at most 75 octets without splitting a UTF-8 scalar.
    private static func foldedLine(_ value: String) -> String {
        var output = ""
        var bytesOnLine = 0
        for scalar in value.unicodeScalars {
            let text = String(scalar)
            let count = text.utf8.count
            if bytesOnLine + count > 75 {
                output += "\r\n "
                bytesOnLine = 1
            }
            output += text
            bytesOnLine += count
        }
        return output
    }

    private static func recurrenceLine(_ rule: RepeatRule) -> String? {
        switch rule {
        case .none: return nil
        case .daily: return "RRULE:FREQ=DAILY"
        case .weekdays: return "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .weekly: return "RRULE:FREQ=WEEKLY"
        case .monthly: return "RRULE:FREQ=MONTHLY"
        case .yearly: return "RRULE:FREQ=YEARLY"
        }
    }
}
