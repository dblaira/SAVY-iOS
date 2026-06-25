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

/// Hosts `CalendarView` in the bottom-nav Calendar tab.
struct SavyCalendarTabScreen: View {
    @EnvironmentObject private var store: ReminderStore
    @State private var editing: Reminder?

    var body: some View {
        CalendarView { reminder in
            editing = reminder
        }
        .sheet(item: $editing) { reminder in
            ReminderFormView(existing: reminder, existingTags: store.recentTags) { updated in
                store.save(updated)
            }
        }
    }
}

/// Lightweight Reminders / Actions tab surfaces until the full Re_Call feeds ship here.
struct SavyReminderKindTabScreen: View {
    let kind: ReminderKind

    @EnvironmentObject private var store: ReminderStore
    @State private var editing: Reminder?

    private var items: [Reminder] {
        store.active.filter { $0.kind == kind }
    }

    private var title: String {
        switch kind {
        case .reminder:
            "Reminders"
        case .action:
            "Actions"
        case .event:
            "Calendar"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(SavyTheme.readingTitle(34))
                    .foregroundStyle(SavyTheme.ink)
                    .padding(.top, 52)
                    .padding(.horizontal, 24)

                if items.isEmpty {
                    Text("Nothing here yet. Use the bolt to capture one.")
                        .font(SavyTheme.readingBody(16))
                        .foregroundStyle(SavyTheme.secondaryText)
                        .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 10) {
                        ForEach(items) { reminder in
                            Button {
                                editing = reminder
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(reminder.title.isEmpty ? reminder.kind.label : reminder.title)
                                        .font(SavyTheme.readingTitle(22))
                                        .foregroundStyle(SavyTheme.ink)
                                        .multilineTextAlignment(.leading)

                                    if let when = reminder.whenLabel, !when.isEmpty {
                                        Text(when.uppercased())
                                            .font(SavyTheme.readingLabel(12))
                                            .tracking(1.2)
                                            .foregroundStyle(SavyTheme.crimson)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .background(Brand.card, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color.white.ignoresSafeArea())
        .sheet(item: $editing) { reminder in
            ReminderFormView(existing: reminder, existingTags: store.recentTags) { updated in
                store.save(updated)
            }
        }
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
