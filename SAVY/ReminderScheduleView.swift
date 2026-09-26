import SwiftUI
import EventKit

private struct ScheduleOrganizerEmailKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var scheduleOrganizerEmail: String {
        get { self[ScheduleOrganizerEmailKey.self] }
        set { self[ScheduleOrganizerEmailKey.self] = newValue }
    }
}

/// Scheduling edits stay local until Done. Closing or cancelling this sheet never changes
/// the parent entry or requests Calendar access.
@MainActor
struct ReminderScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scheduleOrganizerEmail) private var signedInEmail

    private let onSave: (Reminder) -> Void
    private let onRemove: () -> Void
    private let canRemove: Bool

    @State private var draft: Reminder
    @State private var schedule: ReminderSchedule
    @State private var inviteeText: String
    @State private var organizerEmail: String
    @State private var calendarChoices: [CalendarChoice] = []
    @State private var showCalendars = false
    @State private var loadingCalendars = false
    @State private var calendarError: String?
    @State private var showTimeZones = false
    @State private var timeZoneSearch = ""
    @State private var errorMessage: String?

    private struct CalendarChoice: Identifiable {
        let id: String
        let title: String
    }

    init(entry: Reminder, onSave: @escaping (Reminder) -> Void, onRemove: @escaping () -> Void) {
        self.onSave = onSave
        self.onRemove = onRemove
        canRemove = entry.schedule != nil || entry.dueDate != nil || entry.dueTime != nil
        _draft = State(initialValue: entry)
        let initialSchedule = Self.initialSchedule(for: entry)
        _schedule = State(initialValue: initialSchedule)
        _inviteeText = State(initialValue: initialSchedule.invitees?.joined(separator: ", ") ?? "")
        _organizerEmail = State(initialValue: initialSchedule.organizerEmail ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                datesSection
                locationSection
                inviteesSection
                optionsSection
                detailsSection
                if canRemove {
                    Section {
                        Button("Remove Schedule", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                        .accessibilityIdentifier("scheduleRemove")
                    }
                    .listRowBackground(Brand.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white.ignoresSafeArea())
            .tint(Brand.crimson)
            .accessibilityIdentifier("scheduleForm")
            .environment(\.timeZone, schedule.calendar.timeZone)
            .savyPageTitle("Schedule", color: SavyTheme.deepNavy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("scheduleDone")
                }
            }
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .onAppear {
                if organizerEmail.isEmpty { organizerEmail = signedInEmail }
            }
            .sheet(isPresented: $showCalendars) { calendarPicker }
            .sheet(isPresented: $showTimeZones) { timeZonePicker }
            .alert("Schedule", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.light)
    }

    private var locationSection: some View {
        Section {
            TextField("Location or Video Call", text: $draft.locationName, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("scheduleLocation")
        } header: { sectionHeader("Location") }
        .listRowBackground(Brand.card)
    }

    private var datesSection: some View {
        Section {
            DatePicker("Starts", selection: startBinding,
                       displayedComponents: schedule.isAllDay ? [.date] : [.date, .hourAndMinute])
                .accessibilityIdentifier("scheduleStarts")
            DatePicker("Ends", selection: endBinding,
                       displayedComponents: schedule.isAllDay ? [.date] : [.date, .hourAndMinute])
                .accessibilityIdentifier("scheduleEnds")
            Toggle("All-day", isOn: Binding(get: { schedule.isAllDay }, set: setAllDay))
                .accessibilityIdentifier("scheduleAllDay")
            if !schedule.isAllDay {
                Button { showTimeZones = true } label: {
                    valueRow("Time Zone", value: timeZoneLabel)
                }
                .accessibilityIdentifier("scheduleTimeZone")
            }
            Picker("Repeat", selection: $draft.repeatRule) {
                ForEach(RepeatRule.allCases) { rule in
                    Text(rule.label).tag(rule)
                }
            }
            .accessibilityIdentifier("scheduleRepeat")
        }
        .listRowBackground(Brand.card)
    }

    private var inviteesSection: some View {
        Section {
            TextField("Email addresses", text: $inviteeText, axis: .vertical)
                .lineLimit(1...4)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("scheduleInvitees")
            if !invitees.isEmpty {
                TextField("Your email", text: $organizerEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("scheduleOrganizer")
            }
        } header: {
            sectionHeader("Invitees")
        } footer: {
            if !invitees.isEmpty {
                Text("Use Save & Send Invitations to review them in Mail.")
            }
        }
        .listRowBackground(Brand.card)
    }

    private var optionsSection: some View {
        Section {
            Button(action: openCalendars) {
                valueRow("Calendar", value: calendarLabel)
            }
            .accessibilityIdentifier("scheduleCalendar")
            Picker("Alert", selection: Binding(get: { schedule.alert }, set: setAlert)) {
                ForEach(ReminderAlert.allCases) { alert in
                    Text(alert.label).tag(alert)
                }
            }
            .accessibilityIdentifier("scheduleAlert")
            if schedule.alert == .hourly {
                Text("Every hour until \(hourlyEndLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scheduleHourlySummary")
            }
            Picker("Travel Time", selection: $schedule.travelTimeMinutes) {
                ForEach(travelTimeChoices, id: \.self) { minutes in
                    Text(travelLabel(minutes)).tag(minutes)
                }
            }
            .accessibilityIdentifier("scheduleTravelTime")
        }
        .listRowBackground(Brand.card)
    }

    private var detailsSection: some View {
        Section {
            TextField("URL", text: $draft.url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("scheduleURL")
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityIdentifier("scheduleNotes")
        }
        .listRowBackground(Brand.card)
    }

    private var startBinding: Binding<Date> {
        Binding(get: { schedule.startDate }, set: { value in
            let start = schedule.isAllDay ? schedule.calendar.startOfDay(for: value) : value
            let previousStart = schedule.startDate
            schedule.startDate = start
            if schedule.isAllDay {
                let days = schedule.calendar.dateComponents([.day], from: previousStart, to: start).day ?? 0
                schedule.endDate = schedule.calendar.date(byAdding: .day, value: days, to: schedule.endDate) ?? schedule.endDate
                schedule.endDate = schedule.calendar.startOfDay(for: schedule.endDate)
                if schedule.endDate <= start {
                    schedule.endDate = schedule.calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
                }
            } else {
                schedule.endDate = schedule.endDate.addingTimeInterval(start.timeIntervalSince(previousStart))
            }
        })
    }

    private var endBinding: Binding<Date> {
        Binding(get: {
            guard schedule.isAllDay else { return schedule.endDate }
            return schedule.calendar.date(byAdding: .day, value: -1, to: schedule.endDate) ?? schedule.startDate
        }, set: { value in
            guard schedule.isAllDay else {
                schedule.endDate = value
                return
            }
            let lastDay = schedule.calendar.startOfDay(for: value)
            schedule.endDate = schedule.calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(86_400)
        })
    }

    private func setAllDay(_ value: Bool) {
        guard value != schedule.isAllDay else { return }
        let calendar = schedule.calendar
        if value {
            let start = calendar.startOfDay(for: schedule.startDate)
            let endDay = calendar.startOfDay(for: schedule.endDate)
            let exclusiveEnd = schedule.endDate == endDay ? endDay
                : calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay.addingTimeInterval(86_400)
            schedule.startDate = start
            schedule.endDate = max(exclusiveEnd, calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
            if schedule.alert == .hourly { schedule.alert = .atStart }
        } else {
            let finalDay = calendar.date(byAdding: .day, value: -1, to: schedule.endDate) ?? schedule.startDate
            schedule.startDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: schedule.startDate) ?? schedule.startDate
            schedule.endDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: finalDay) ?? schedule.startDate.addingTimeInterval(3_600)
        }
        schedule.isAllDay = value
    }

    private func setAlert(_ value: ReminderAlert) {
        if value == .hourly {
            setAllDay(false)
            if schedule.endDate.timeIntervalSince(schedule.startDate) > ReminderSchedule.maximumHourlyDuration {
                schedule.endDate = schedule.startDate.addingTimeInterval(3 * 3_600)
            }
        }
        schedule.alert = value
    }

    private var invitees: [String] {
        var seen = Set<String>()
        return inviteeText.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private var hourlyEndLabel: String {
        let formatter = DateFormatter()
        formatter.timeZone = schedule.calendar.timeZone
        formatter.dateStyle = schedule.calendar.isDate(schedule.startDate, inSameDayAs: schedule.endDate) ? .none : .medium
        formatter.timeStyle = .short
        return formatter.string(from: schedule.endDate)
    }

    private var timeZoneLabel: String {
        schedule.timeZoneIdentifier.replacingOccurrences(of: "_", with: " ")
    }

    private var travelTimeChoices: [Int] {
        Array(Set([0, 5, 10, 15, 30, 45, 60, 90, 120, schedule.travelTimeMinutes])).sorted()
    }

    private func travelLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "None" }
        if minutes % 60 == 0 { return minutes == 60 ? "1 hour" : "\(minutes / 60) hours" }
        return "\(minutes) minutes"
    }

    private func save() {
        if let message = schedule.validationMessage {
            errorMessage = message
            return
        }
        if let invalid = invitees.first(where: { !ScheduleInvitation.isValidEmail($0) }) {
            errorMessage = "Enter an email address for \(invalid)."
            return
        }
        schedule.invitees = invitees.isEmpty ? nil : invitees
        let organizer = organizerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.organizerEmail = organizer.isEmpty ? nil : organizer
        draft.schedule = schedule
        draft.dueDate = schedule.calendar.startOfDay(for: schedule.startDate)
        draft.dueTime = schedule.isAllDay ? nil : schedule.startDate
        draft.endTime = schedule.isAllDay ? nil : schedule.endDate
        onSave(draft)
        dismiss()
    }

    private static func initialSchedule(for entry: Reminder) -> ReminderSchedule {
        if let schedule = entry.schedule { return schedule }
        let calendar = Calendar.current
        let now = Date()
        let nextHour = calendar.nextDate(after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3_600)
        let start = entry.fireDate ?? nextHour
        var end = start.addingTimeInterval(3_600)
        if let legacyEnd = entry.endTime {
            let clock = calendar.dateComponents([.hour, .minute], from: legacyEnd)
            end = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: start) ?? end
            if end <= start { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(86_400) }
        }
        return ReminderSchedule(startDate: start, endDate: end)
    }

    private var calendarLabel: String {
        guard let id = schedule.calendarIdentifier else { return "SAVY" }
        return calendarChoices.first { $0.id == id }?.title ?? CalendarScheduleBridge.shared.calendarLabel(id: id)
    }

    private func openCalendars() {
        showCalendars = true
        loadingCalendars = true
        calendarError = nil
        Task {
            do {
                try await CalendarScheduleBridge.shared.loadCalendars()
                calendarChoices = CalendarScheduleBridge.shared.availableCalendars.map {
                    CalendarChoice(id: $0.calendarIdentifier, title: $0.title)
                }
            } catch {
                calendarChoices = []
                calendarError = error.localizedDescription
            }
            loadingCalendars = false
        }
    }

    private var calendarPicker: some View {
        NavigationStack {
            List {
                Section {
                    calendarChoice("SAVY", identifier: nil)
                }
                .listRowBackground(Brand.card)
                Section {
                    if loadingCalendars {
                        ProgressView()
                    } else if let calendarError {
                        Text(calendarError).foregroundStyle(.secondary)
                    } else {
                        ForEach(calendarChoices) { choice in
                            calendarChoice(choice.title, identifier: choice.id)
                        }
                    }
                }
                .listRowBackground(Brand.card)
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .savyPageTitle("Calendar", color: SavyTheme.deepNavy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCalendars = false }
                }
            }
            .tint(Brand.crimson)
        }
    }

    private func calendarChoice(_ title: String, identifier: String?) -> some View {
        Button {
            schedule.calendarIdentifier = identifier
            showCalendars = false
        } label: {
            HStack {
                Text(title).foregroundStyle(SavyTheme.deepNavy)
                Spacer()
                if schedule.calendarIdentifier == identifier {
                    Image(systemName: "checkmark").foregroundStyle(Brand.crimson)
                }
            }
        }
    }

    private var timeZonePicker: some View {
        NavigationStack {
            List {
                ForEach(TimeZone.knownTimeZoneIdentifiers.filter {
                    timeZoneSearch.isEmpty || $0.localizedCaseInsensitiveContains(timeZoneSearch.replacingOccurrences(of: " ", with: "_"))
                }, id: \.self) { identifier in
                    Button {
                        schedule.timeZoneIdentifier = identifier
                        showTimeZones = false
                    } label: {
                        HStack {
                            Text(identifier.replacingOccurrences(of: "_", with: " "))
                                .foregroundStyle(SavyTheme.deepNavy)
                            Spacer()
                            if schedule.timeZoneIdentifier == identifier {
                                Image(systemName: "checkmark").foregroundStyle(Brand.crimson)
                            }
                        }
                    }
                    .listRowBackground(Brand.card)
                }
            }
            .searchable(text: $timeZoneSearch, prompt: "City or time zone")
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .savyPageTitle("Time Zone", color: SavyTheme.deepNavy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTimeZones = false }
                }
            }
            .tint(Brand.crimson)
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(SavyTheme.deepNavy)
            Spacer()
            Text(value).foregroundStyle(Brand.crimson)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.crimson)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SavyTheme.deepNavy.opacity(0.72))
            .textCase(nil)
    }
}
