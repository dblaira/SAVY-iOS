import SwiftUI

/// The Calendar tab: a black "Calendar" hero (Today button + month chevrons), a white month grid,
/// and a full day timeline — 24 hour rows with reminders placed at their actual times, a crimson
/// "now" line, and an all-day row. Backed by the real store.
struct CalendarView: View {
    @EnvironmentObject var store: ReminderStore
    var onOpen: (Reminder) -> Void = { _ in }

    @State private var month: Date = Date()      // any date inside the displayed month
    @State private var selected: Date = Date()

    private let cal = Calendar.current
    private let hourHeight: CGFloat = 56
    private let gutter: CGFloat = 60
    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm"; return f }()
    private static let hourFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h a"; return f }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero(proxy)
                    Rectangle().fill(Brand.crimson).frame(height: 2)
                    VStack(spacing: 18) {
                        monthCard
                        dayHeader
                        allDayRow
                        timeline
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 150)
                }
            }
            .background(Color.white)
            .ignoresSafeArea(edges: .top)
            .onAppear {
                if shouldScrollToNow {
                    scrollToNow(proxy, animated: false)
                }
            }
        }
    }

    // MARK: Hero

    private func hero(_ proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Calendar").font(Brand.serif(40)).foregroundStyle(.white)
            Spacer(minLength: 0)
            Button { goToToday(proxy) } label: {
                Text("Today")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            chevron("chevron.left") { shiftMonth(-1) }
            chevron("chevron.right") { shiftMonth(1) }
        }
        .padding(.top, 60)
        .padding(.bottom, 18)
        .padding(.horizontal, 16)
        .background(Brand.nearBlack)
    }

    private func chevron(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Month grid

    private var monthCard: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(["S", "M", "T", "W", "T", "F", "S"][i])
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            ForEach(weeks.indices, id: \.self) { w in
                HStack(spacing: 0) {
                    ForEach(weeks[w], id: \.self) { day in dayCell(day) }
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let events = reminders(on: day)
        let importance = dayImportance(events)
        let weight = dayWeight(importance)
        let markSize = dayMarkSize(weight)
        return Button {
            selected = day
            if !inMonth { month = day }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: dayFontSize(weight), weight: .heavy))
                    .foregroundStyle(dayTextColor(inMonth: inMonth, isToday: isToday, weight: weight))
                    .frame(width: markSize, height: markSize)
                    .background { dayBackground(isToday: isToday, isSelected: isSelected, weight: weight) }
                    .overlay { dayBorder(isToday: isToday, isSelected: isSelected, weight: weight) }
                daySignal(events, importance: importance, weight: weight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendarDay-\(cal.component(.day, from: day))")
        .accessibilityLabel(dayAccessibilityLabel(day: day, events: events, importance: importance))
    }

    @ViewBuilder private func daySignal(_ events: [Reminder], importance: Int, weight: Int) -> some View {
        if events.isEmpty {
            Circle().fill(Color.clear).frame(width: 5, height: 5)
        } else if weight >= 3 {
            HStack(spacing: 2) {
                ForEach(0..<min(weight, 4), id: \.self) { _ in
                    Capsule()
                        .fill(Brand.crimson)
                        .frame(width: 7, height: 3)
                }
            }
            .frame(height: 9)
        } else if events.count == 1 {
            Circle()
                .fill(dotColor(events))
                .frame(width: weight >= 2 ? 7 : 5, height: weight >= 2 ? 7 : 5)
        } else {
            Text("\(events.count)")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(importance >= 3 ? Brand.crimson : .black.opacity(0.55))
                .frame(height: 9)
        }
    }

    @ViewBuilder private func dayBackground(isToday: Bool, isSelected: Bool, weight: Int) -> some View {
        if isToday {
            Circle().fill(Brand.crimson)
        } else if weight >= 4 {
            Circle().fill(Brand.crimson.opacity(0.28))
        } else if weight == 3 {
            Circle().fill(Brand.crimson.opacity(0.18))
        } else if weight == 2 {
            Circle().fill(Brand.tan)
        } else if weight == 1 {
            Circle().fill(Color.black.opacity(0.06))
        } else if isSelected {
            Circle().fill(Brand.crimson.opacity(0.10))
        }
    }

    @ViewBuilder private func dayBorder(isToday: Bool, isSelected: Bool, weight: Int) -> some View {
        if isSelected && !isToday {
            Circle().stroke(Brand.crimson, lineWidth: weight >= 3 ? 2 : 1.5)
        } else if weight >= 2 && !isToday {
            Circle().stroke(Brand.crimson.opacity(weight >= 3 ? 0.55 : 0.25), lineWidth: weight >= 4 ? 1.5 : 1)
        }
    }

    // MARK: Day header + all-day

    private var dayHeader: some View {
        HStack {
            Text(cal.isDateInToday(selected) ? "Today" : selected.formatted(.dateTime.weekday(.wide)))
                .font(.system(size: 22, weight: .heavy)).foregroundStyle(.black)
            Spacer()
            Text(selected.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 16, weight: .heavy)).foregroundStyle(Brand.crimson)
        }
    }

    @ViewBuilder private var allDayRow: some View {
        let items = reminders(on: selected).filter { $0.dueTime == nil }
        if !items.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text("all-day")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.35))
                    .frame(width: 52, alignment: .trailing)
                VStack(spacing: 6) {
                    ForEach(items) { reminder in
                        calendarEventRow(reminder, compact: true)
                    }
                }
            }
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        let timed = reminders(on: selected).filter { $0.dueTime != nil }
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { h in
                    HStack(alignment: .top, spacing: 8) {
                        Text(Self.hourFmt.string(from: dateAtHour(h)))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.35))
                            .frame(width: 52, alignment: .trailing)
                            .offset(y: -6)
                        VStack(spacing: 0) { Divider(); Spacer(minLength: 0) }
                    }
                    .frame(height: hourHeight, alignment: .top)
                    .id("hour-\(h)")
                }
            }
            ForEach(timed) { r in
                calendarEventRow(r, compact: false)
                    .accessibilityIdentifier("calendarEvent-\(r.id.uuidString)")
                    .padding(.leading, gutter)
                    .padding(.trailing, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: yOffset(r))
            }
            if cal.isDateInToday(selected) { nowLine }
        }
        .frame(height: hourHeight * 24)
    }

    private var nowLine: some View {
        let now = Date()
        let y = (CGFloat(cal.component(.hour, from: now)) + CGFloat(cal.component(.minute, from: now)) / 60) * hourHeight
        return HStack(spacing: 0) {
            Circle().fill(Brand.crimson).frame(width: 8, height: 8)
            Rectangle().fill(Brand.crimson).frame(height: 2)
        }
        .padding(.leading, gutter - 4)
        .offset(y: y - 1)
    }

    private func eventBlock(_ r: Reminder, compact: Bool) -> some View {
        let hot = r.urgent || r.flag || r.priority == .high
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(hot ? Brand.crimson : Color.black.opacity(0.5)).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title.isEmpty ? "Untitled" : r.title)
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                    .strikethrough(r.status == .completed).lineLimit(1)
                if let sub = compact ? subtitle(r) : (r.dueTime.map { Self.timeFmt.string(from: $0) }) {
                    Text(sub).font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .frame(height: compact ? 46 : hourHeight - 8, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((hot ? Brand.crimson : Color.black).opacity(hot ? 0.12 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke((hot ? Brand.crimson : Color.black).opacity(0.15)))
    }

    private func calendarEventRow(_ reminder: Reminder, compact: Bool) -> some View {
        SavyCalendarSwipeRow(
            actions: calendarActions(reminder),
            onTap: { onOpen(reminder) }
        ) {
            eventBlock(reminder, compact: compact)
        }
        .accessibilityIdentifier("calendarEvent-\(reminder.id.uuidString)")
    }

    private func calendarActions(_ reminder: Reminder) -> [SavySwipeAction] {
        [
            SavySwipeAction(
                title: reminder.status == .completed ? "Reopen" : "Done",
                icon: reminder.status == .completed ? "arrow.uturn.left" : "checkmark",
                bg: Brand.crimson
            ) {
                if reminder.status == .completed {
                    store.uncomplete(reminder)
                } else {
                    store.complete(reminder)
                }
            },
            SavySwipeAction(
                title: reminder.pinned ? "Unpin" : "Pin",
                icon: "pin",
                bg: Brand.tileBlue
            ) {
                store.togglePin(reminder)
            },
            SavySwipeAction(title: "Delete", icon: "trash", bg: Color(hex: 0xB00124)) {
                store.delete(reminder)
            },
        ]
    }

    // MARK: Data & helpers

    private func reminders(on day: Date) -> [Reminder] {
        store.reminders
            .filter { $0.status != .deleted }
            .filter { if let d = $0.dueDate { return cal.isDate(d, inSameDayAs: day) } else { return false } }
            .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }

    private var shouldScrollToNow: Bool {
        reminders(on: selected).allSatisfy { $0.dueTime != nil }
    }

    private func dotColor(_ events: [Reminder]) -> Color {
        events.contains { $0.urgent || $0.flag || $0.priority == .high } ? Brand.crimson : .black
    }

    private func dayImportance(_ events: [Reminder]) -> Int {
        events.reduce(0) { $0 + eventWeight($1) }
    }

    private func dayWeight(_ importance: Int) -> Int {
        switch importance {
        case 9...: return 4
        case 5...8: return 3
        case 3...4: return 2
        case 1...2: return 1
        default: return 0
        }
    }

    private func eventWeight(_ reminder: Reminder) -> Int {
        var score = 1
        if reminder.kind == .action { score += 1 }
        if reminder.kind == .event { score += 1 }
        if reminder.pinned { score += 2 }
        if reminder.flag { score += 2 }
        if reminder.urgent { score += 3 }
        switch reminder.priority {
        case .high: score += 4
        case .medium: score += 2
        case .low: score += 1
        case .none: break
        }
        return score
    }

    private func dayMarkSize(_ weight: Int) -> CGFloat {
        switch weight {
        case 4...: return 50
        case 3: return 44
        case 2: return 38
        case 1: return 32
        default: return 28
        }
    }

    private func dayFontSize(_ weight: Int) -> CGFloat {
        switch weight {
        case 4...: return 22
        case 3: return 21
        case 2: return 19
        default: return 18
        }
    }

    private func dayTextColor(inMonth: Bool, isToday: Bool, weight: Int) -> Color {
        if isToday { return .white }
        if !inMonth { return .black.opacity(0.28) }
        return weight >= 3 ? Brand.crimson : .black
    }

    private func dayAccessibilityLabel(day: Date, events: [Reminder], importance: Int) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard !events.isEmpty else { return "\(date), no scheduled items" }
        return "\(date), \(events.count) scheduled items, importance \(importance)"
    }

    private func subtitle(_ r: Reminder) -> String? {
        if !r.notes.isEmpty { return r.notes }
        return r.listName.isEmpty || r.listName == "Reminders" ? nil : r.listName
    }

    private func dateAtHour(_ h: Int) -> Date { cal.date(from: DateComponents(hour: h)) ?? Date() }

    private func yOffset(_ r: Reminder) -> CGFloat {
        guard let t = r.dueTime else { return 0 }
        let c = cal.dateComponents([.hour, .minute], from: t)
        return (CGFloat(c.hour ?? 0) + CGFloat(c.minute ?? 0) / 60) * hourHeight
    }

    private func shiftMonth(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: month) { month = m }
    }

    private func goToToday(_ proxy: ScrollViewProxy) {
        let today = Date()
        selected = today
        month = today
        scrollToNow(proxy, animated: true)
    }

    private func scrollToNow(_ proxy: ScrollViewProxy, animated: Bool) {
        let h = max(0, cal.component(.hour, from: Date()) - 1)
        if animated { withAnimation { proxy.scrollTo("hour-\(h)", anchor: .center) } }
        else { proxy.scrollTo("hour-\(h)", anchor: .center) }
    }

    /// Six weeks of days (Sunday-first) covering the displayed month plus leading/trailing spill.
    private var weeks: [[Date]] {
        guard let monthStart = cal.dateInterval(of: .month, for: month)?.start else { return [] }
        let weekdayOfFirst = cal.component(.weekday, from: monthStart) // 1 = Sunday
        guard let start = cal.date(byAdding: .day, value: -(weekdayOfFirst - 1), to: monthStart) else { return [] }
        let days = (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }
}

private struct SavyCalendarSwipeRow<Content: View>: View {
    let actions: [SavySwipeAction]
    var onTap: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    private var actionsWidth: CGFloat { CGFloat(actions.count) * 64 }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(actions) { action in
                    Button {
                        withAnimation(.snappy) { offset = 0 }
                        action.run()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: action.icon)
                                .font(.system(size: 16, weight: .bold))
                            Text(action.title)
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 64)
                        .frame(maxHeight: .infinity)
                        .background(action.bg)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("swipe\(action.title)")
                }
            }
            .frame(width: actionsWidth)
            .frame(maxHeight: .infinity)

            Button {
                if offset != 0 {
                    withAnimation(.snappy) { offset = 0 }
                } else {
                    onTap()
                }
            } label: {
                content
            }
            .buttonStyle(.plain)
            .offset(x: offset)
            .highPriorityGesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(max(value.translation.width, 0), actionsWidth)
            }
            .onEnded { _ in
                withAnimation(.snappy) {
                    offset = offset > actionsWidth / 2 ? actionsWidth : 0
                }
            }
    }
}
