import XCTest
@testable import SAVY

final class SavyCalendarSeedTests: XCTestCase {
    private func pacificCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    /// A throwaway cache file and defaults suite per test, cleaned up when the test ends.
    private func freshStoreContext() throws -> (cacheURL: URL, defaults: UserDefaults) {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("savy-calendar-seed-\(UUID().uuidString).json")
        let suiteName = "savy.calendarSeed.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: cacheURL)
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return (cacheURL, defaults)
    }

    func testAppleEventIsWednesdaySeptember9At10Pacific() throws {
        let calendar = pacificCalendar()
        let reminder = try XCTUnwrap(SavyCalendarSeed.appleSeptember2026.reminder(calendar: calendar))

        let day = calendar.dateComponents(
            [.year, .month, .day, .weekday],
            from: try XCTUnwrap(reminder.dueDate)
        )
        XCTAssertEqual(day.year, 2026)
        XCTAssertEqual(day.month, 9)
        XCTAssertEqual(day.day, 9)
        XCTAssertEqual(day.weekday, 4, "September 9, 2026 is a Wednesday, not a Tuesday")

        let time = calendar.dateComponents([.hour, .minute], from: try XCTUnwrap(reminder.dueTime))
        XCTAssertEqual(time.hour, 10)
        XCTAssertEqual(time.minute, 0)
        XCTAssertEqual(reminder.kind, .event, "It belongs on the Calendar, not in the reminder list")
    }

    func testTenPacificLandsAtTheRightLocalHourElsewhere() throws {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let reminder = try XCTUnwrap(SavyCalendarSeed.appleSeptember2026.reminder(calendar: eastern))

        let parts = eastern.dateComponents([.day, .hour], from: try XCTUnwrap(reminder.dueTime))
        XCTAssertEqual(parts.day, 9)
        XCTAssertEqual(parts.hour, 13, "10:00 Pacific is 1:00 p.m. Eastern")
    }

    @MainActor
    func testTheEventLandsOnTheCalendarOnce() throws {
        let context = try freshStoreContext()
        let first = ReminderStore(cacheURL: context.cacheURL, calendarSeedDefaults: context.defaults)
        XCTAssertEqual(
            first.reminders.filter { $0.id == SavyCalendarSeed.appleSeptember2026.id }.count,
            1,
            "The Apple event should be on the calendar exactly once"
        )

        let second = ReminderStore(cacheURL: context.cacheURL, calendarSeedDefaults: context.defaults)
        XCTAssertEqual(
            second.reminders.filter { $0.id == SavyCalendarSeed.appleSeptember2026.id }.count,
            1,
            "A second launch should not duplicate the event"
        )
    }

    @MainActor
    func testDeletingTheEventKeepsItGone() throws {
        let context = try freshStoreContext()
        let store = ReminderStore(cacheURL: context.cacheURL, calendarSeedDefaults: context.defaults)
        let seeded = try XCTUnwrap(
            store.reminders.first { $0.id == SavyCalendarSeed.appleSeptember2026.id }
        )
        store.delete(seeded)

        let relaunched = ReminderStore(cacheURL: context.cacheURL, calendarSeedDefaults: context.defaults)
        let onCalendar = relaunched.reminders.filter {
            $0.id == SavyCalendarSeed.appleSeptember2026.id && $0.status != .deleted
        }
        XCTAssertTrue(onCalendar.isEmpty, "Delete it once and it stays deleted")
    }
}
