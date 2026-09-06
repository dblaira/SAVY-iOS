import EventKit
import Foundation
import SwiftUI

/// One event as SAVY reads it off the phone's own Calendar database — Adam's iCloud calendars
/// included, because iCloud calendars live in that database once the account is on the phone.
struct AppleCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date?
    let isAllDay: Bool
    let calendarName: String
    let accountName: String        // the account the calendar comes from: "iCloud", "Gmail", …

    /// True when this event touches `day` at all — a two-day event shows on both days. The end is
    /// exclusive, the way Apple writes it, so an all-day event does not bleed into tomorrow.
    func covers(_ day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        let finish = end ?? start
        guard finish > start else { return start >= dayStart && start < dayEnd }
        return start < dayEnd && finish > dayStart
    }

    /// All-day events, and any event that started on an earlier day, sit in the all-day row.
    func sitsInAllDayRow(on day: Date, calendar: Calendar = .current) -> Bool {
        isAllDay || !calendar.isDate(start, inSameDayAs: day)
    }
}

/// One account on the phone and the event calendars under it.
struct AppleCalendarAccount: Identifiable, Equatable {
    let id: String
    let name: String               // EKSource title — "iCloud" for an iCloud account
    let isICloud: Bool
    let calendarNames: [String]
}

/// What SAVY can say about the connection, in Adam's words on the Calendar screen.
struct AppleCalendarConnection: Equatable {
    var status: EKAuthorizationStatus
    var accounts: [AppleCalendarAccount]

    static let unknown = AppleCalendarConnection(status: .notDetermined, accounts: [])

    var iCloudAccounts: [AppleCalendarAccount] { accounts.filter(\.isICloud) }
    var iCloudCalendarNames: [String] { iCloudAccounts.flatMap(\.calendarNames) }
    var isReading: Bool { status == .fullAccess }
    var isICloudConnected: Bool { isReading && !iCloudCalendarNames.isEmpty }

    /// The one line the Calendar screen shows.
    var headline: String {
        switch status {
        case .fullAccess:
            if isICloudConnected {
                let count = iCloudCalendarNames.count
                return "iCloud Calendar connected · \(count) calendar\(count == 1 ? "" : "s")"
            }
            if accounts.isEmpty {
                return "Apple Calendar connected · no calendars on this phone yet"
            }
            return "Apple Calendar connected · no iCloud calendar on this phone"
        case .writeOnly:
            return "Apple Calendar can only be written to — turn on Full Access to read it"
        case .denied:
            return "Apple Calendar is off for SAVY"
        case .restricted:
            return "Apple Calendar is restricted on this phone"
        case .notDetermined:
            return "Connect your iCloud Apple Calendar"
        @unknown default:
            return "Connect your iCloud Apple Calendar"
        }
    }

    /// The calendars behind the headline, so Adam can see which ones came across.
    var detail: String? {
        guard isReading, !accounts.isEmpty else { return nil }
        return accounts
            .map { "\($0.name): \($0.calendarNames.joined(separator: ", "))" }
            .joined(separator: " · ")
    }

    /// True when the only thing left is a trip to Settings.
    var needsSettings: Bool {
        status == .denied || status == .restricted || status == .writeOnly
    }
}

/// The seam SAVY codes against so the Calendar can be tested without a real phone database.
@MainActor
protocol AppleCalendarSource {
    var status: EKAuthorizationStatus { get }
    func requestAccess() async -> Bool
    func accounts() -> [AppleCalendarAccount]
    func events(from start: Date, to end: Date) -> [AppleCalendarEvent]
}

/// The real thing: EventKit against the phone's Calendar database.
@MainActor
final class EventKitCalendarSource: AppleCalendarSource {
    private let store = EKEventStore()

    var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func accounts() -> [AppleCalendarAccount] {
        let calendars = store.calendars(for: .event)
        let grouped = Dictionary(grouping: calendars) { $0.source.sourceIdentifier }
        return grouped.values.compactMap { calendars -> AppleCalendarAccount? in
            guard let source = calendars.first?.source else { return nil }
            return AppleCalendarAccount(
                id: source.sourceIdentifier,
                name: source.title,
                isICloud: Self.isICloud(source),
                calendarNames: calendars.map(\.title).sorted()
            )
        }
        .sorted { lhs, rhs in
            if lhs.isICloud != rhs.isICloud { return lhs.isICloud }
            return lhs.name < rhs.name
        }
    }

    func events(from start: Date, to end: Date) -> [AppleCalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            AppleCalendarEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Untitled",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarName: event.calendar?.title ?? "",
                accountName: event.calendar?.source?.title ?? ""
            )
        }
        .sorted { $0.start < $1.start }
    }

    /// iCloud arrives as a CalDAV source titled "iCloud"; a local phone calendar does not.
    private static func isICloud(_ source: EKSource) -> Bool {
        source.sourceType == .calDAV && source.title.compare("iCloud", options: .caseInsensitive) == .orderedSame
    }
}

/// Holds the connection and the events the Calendar screen draws. Read-only on purpose: SAVY shows
/// Adam's Apple Calendar, it does not write to it.
@MainActor
final class AppleCalendarStore: ObservableObject {
    @Published private(set) var connection: AppleCalendarConnection = .unknown
    @Published private(set) var events: [AppleCalendarEvent] = []

    private let source: any AppleCalendarSource
    private let calendar: Calendar
    private var loadedRange: DateInterval?
    private var eventsByDay: [Date: [AppleCalendarEvent]] = [:]

    init(source: any AppleCalendarSource = EventKitCalendarSource(), calendar: Calendar = .current) {
        self.source = source
        self.calendar = calendar
        connection = AppleCalendarConnection(status: source.status, accounts: [])
    }

    /// Ask once, then read. Called when the Calendar screen appears, because Adam asked for the
    /// connection to be there without hunting for a switch.
    func connect(around date: Date = Date()) async {
        if source.status == .notDetermined {
            _ = await source.requestAccess()
        }
        reload(around: date)
    }

    /// Re-read the phone for the month on screen.
    func reload(around date: Date) {
        let status = source.status
        guard status == .fullAccess else {
            connection = AppleCalendarConnection(status: status, accounts: [])
            events = []
            eventsByDay = [:]
            loadedRange = nil
            return
        }
        let range = Self.window(around: date, calendar: calendar)
        connection = AppleCalendarConnection(status: status, accounts: source.accounts())
        events = source.events(from: range.start, to: range.end)
        eventsByDay = Self.index(events, calendar: calendar)
        loadedRange = range
    }

    /// Reload only when the month on screen falls outside what is already loaded.
    func loadIfNeeded(around date: Date) {
        guard source.status == .fullAccess else { return }
        guard let loaded = loadedRange else {
            reload(around: date)
            return
        }
        let month = calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 1)
        if !loaded.contains(month.start) || !loaded.contains(month.end.addingTimeInterval(-1)) {
            reload(around: date)
        }
    }

    func events(on day: Date) -> [AppleCalendarEvent] {
        eventsByDay[calendar.startOfDay(for: day)] ?? []
    }

    /// Events filed under every day they touch, so the month grid does not re-scan the list once
    /// per cell while Adam scrolls.
    private static func index(
        _ events: [AppleCalendarEvent],
        calendar: Calendar
    ) -> [Date: [AppleCalendarEvent]] {
        var byDay: [Date: [AppleCalendarEvent]] = [:]
        for event in events {
            var day = calendar.startOfDay(for: event.start)
            let lastDay = calendar.startOfDay(for: event.end ?? event.start)
            while day <= lastDay {
                if event.covers(day, calendar: calendar) {
                    byDay[day, default: []].append(event)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return byDay
    }

    /// The month on screen plus a month either side, so a swipe forward or back has its events.
    private static func window(around date: Date, calendar: Calendar) -> DateInterval {
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let end = calendar.date(byAdding: .month, value: 2, to: monthStart) ?? monthStart
        return DateInterval(start: start, end: end)
    }
}
