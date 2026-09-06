import EventKit
import XCTest
@testable import SAVY

@MainActor
private final class FakeAppleCalendarSource: AppleCalendarSource {
    var status: EKAuthorizationStatus
    var accountsOnPhone: [AppleCalendarAccount]
    var eventsOnPhone: [AppleCalendarEvent]
    var grantsAccess: Bool
    private(set) var requestCount = 0
    private(set) var lastRange: DateInterval?

    init(
        status: EKAuthorizationStatus = .notDetermined,
        accounts: [AppleCalendarAccount] = [],
        events: [AppleCalendarEvent] = [],
        grantsAccess: Bool = true
    ) {
        self.status = status
        self.accountsOnPhone = accounts
        self.eventsOnPhone = events
        self.grantsAccess = grantsAccess
    }

    func requestAccess() async -> Bool {
        requestCount += 1
        if grantsAccess { status = .fullAccess }
        return grantsAccess
    }

    func accounts() -> [AppleCalendarAccount] { accountsOnPhone }

    func events(from start: Date, to end: Date) -> [AppleCalendarEvent] {
        lastRange = DateInterval(start: start, end: end)
        return eventsOnPhone.filter { $0.start >= start && $0.start < end }
    }
}

@MainActor
final class AppleCalendarBridgeTests: XCTestCase {
    private func pacific() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        pacific().date(
            from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    private let iCloud = AppleCalendarAccount(
        id: "icloud-source",
        name: "iCloud",
        isICloud: true,
        calendarNames: ["Home", "Work"]
    )

    func testConnectingReadsTheICloudCalendars() async {
        let source = FakeAppleCalendarSource(accounts: [iCloud])
        let store = AppleCalendarStore(source: source, calendar: pacific())

        await store.connect(around: date(9, 9))

        XCTAssertEqual(source.requestCount, 1, "SAVY should ask for calendar access once")
        XCTAssertTrue(store.connection.isICloudConnected)
        XCTAssertEqual(store.connection.iCloudCalendarNames, ["Home", "Work"])
        XCTAssertEqual(store.connection.headline, "iCloud Calendar connected · 2 calendars")
        XCTAssertEqual(store.connection.detail, "iCloud: Home, Work")
        XCTAssertFalse(store.connection.needsSettings)
    }

    func testAlreadyGrantedAccessIsNotAskedForAgain() async {
        let source = FakeAppleCalendarSource(status: .fullAccess, accounts: [iCloud])
        let store = AppleCalendarStore(source: source, calendar: pacific())

        await store.connect(around: date(9, 9))

        XCTAssertEqual(source.requestCount, 0)
        XCTAssertTrue(store.connection.isReading)
    }

    func testTurnedOffCalendarSaysSoAndPointsAtSettings() async {
        let source = FakeAppleCalendarSource(status: .denied, accounts: [iCloud], grantsAccess: false)
        let store = AppleCalendarStore(source: source, calendar: pacific())

        await store.connect(around: date(9, 9))

        XCTAssertEqual(source.requestCount, 0, "A denied phone should not be re-prompted from here")
        XCTAssertFalse(store.connection.isICloudConnected)
        XCTAssertTrue(store.connection.needsSettings)
        XCTAssertEqual(store.connection.headline, "Apple Calendar is off for SAVY")
        XCTAssertTrue(store.events.isEmpty)
    }

    func testWriteOnlyAccessIsNotAConnection() async {
        let source = FakeAppleCalendarSource(status: .writeOnly, accounts: [iCloud], grantsAccess: false)
        let store = AppleCalendarStore(source: source, calendar: pacific())

        await store.connect(around: date(9, 9))

        XCTAssertFalse(store.connection.isReading)
        XCTAssertTrue(store.connection.needsSettings)
        XCTAssertTrue(store.connection.headline.contains("Full Access"))
    }

    func testEventsLandOnTheDayTheyBelongTo() async {
        let timed = AppleCalendarEvent(
            id: "timed",
            title: "Apple Event",
            start: date(9, 9, 10),
            end: date(9, 9, 11),
            isAllDay: false,
            calendarName: "Work",
            accountName: "iCloud"
        )
        let allDay = AppleCalendarEvent(
            id: "all-day",
            title: "Anniversary",
            start: date(9, 9),
            end: date(9, 10),
            isAllDay: true,
            calendarName: "Home",
            accountName: "iCloud"
        )
        let twoDay = AppleCalendarEvent(
            id: "two-day",
            title: "Trip",
            start: date(9, 8, 18),
            end: date(9, 9, 12),
            isAllDay: false,
            calendarName: "Home",
            accountName: "iCloud"
        )
        let source = FakeAppleCalendarSource(accounts: [iCloud], events: [timed, allDay, twoDay])
        let store = AppleCalendarStore(source: source, calendar: pacific())

        await store.connect(around: date(9, 9))

        let onTheNinth = store.events(on: date(9, 9)).map(\.id)
        XCTAssertEqual(Set(onTheNinth), ["timed", "all-day", "two-day"])
        XCTAssertEqual(store.events(on: date(9, 8)).map(\.id), ["two-day"])
        XCTAssertTrue(
            store.events(on: date(9, 10)).isEmpty,
            "An all-day event ends where Apple ends it — it does not bleed into the next day"
        )
        XCTAssertTrue(store.events(on: date(9, 12)).isEmpty)

        let calendar = pacific()
        XCTAssertFalse(timed.sitsInAllDayRow(on: date(9, 9), calendar: calendar))
        XCTAssertTrue(allDay.sitsInAllDayRow(on: date(9, 9), calendar: calendar))
        XCTAssertTrue(
            twoDay.sitsInAllDayRow(on: date(9, 9), calendar: calendar),
            "An event that started yesterday belongs in the all-day row, not at an hour"
        )
        XCTAssertFalse(twoDay.sitsInAllDayRow(on: date(9, 8), calendar: calendar))
    }

    func testTheMonthOnScreenIsReadWithAMonthEitherSide() async {
        let source = FakeAppleCalendarSource(accounts: [iCloud])
        let store = AppleCalendarStore(source: source, calendar: pacific())

        await store.connect(around: date(9, 9))

        XCTAssertEqual(source.lastRange?.start, date(8, 1))
        XCTAssertEqual(source.lastRange?.end, date(11, 1))
    }

    func testMovingWithinTheLoadedWindowDoesNotReRead() async {
        let source = FakeAppleCalendarSource(accounts: [iCloud])
        let store = AppleCalendarStore(source: source, calendar: pacific())

        await store.connect(around: date(9, 9))
        let firstRange = source.lastRange
        store.loadIfNeeded(around: date(10, 1))
        XCTAssertEqual(source.lastRange, firstRange, "October was already loaded with September")

        store.loadIfNeeded(around: date(12, 1))
        XCTAssertNotEqual(source.lastRange, firstRange, "December is outside the window; re-read it")
    }
}
