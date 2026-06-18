import SwiftUI

/// SAVY glue between the radial "+" menu and the Re_Call reminder system.
///
/// `ReminderFormView` (the three-face entry form) and `CalendarView` are brought over from Re_Call
/// verbatim. This file wires them to a shared `ReminderStore`: the form saves into the store, and
/// the calendar reads from it and opens the form to edit an existing item.

extension ReminderStore {
    /// Previously-used tags, most-used first — fed to the form's "recent tag" suggestions.
    var recentTags: [String] {
        let counts = Dictionary(grouping: reminders.flatMap(\.tags), by: { $0 })
            .mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }
}

/// Hosts `CalendarView` and presents the entry form when a day's event is tapped.
struct SavyCalendarScreen: View {
    @EnvironmentObject private var store: ReminderStore
    @State private var editing: Reminder?

    var body: some View {
        CalendarView { reminder in
            editing = reminder
        }
        .presentationDragIndicator(.visible)
        .sheet(item: $editing) { reminder in
            ReminderFormView(existing: reminder, existingTags: store.recentTags) { updated in
                store.save(updated)
            }
        }
    }
}
