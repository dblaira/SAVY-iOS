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
            .onAppear { scrollToNow(proxy, animated: false) }
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
        return Button {
            selected = day
            if !inMonth { month = day }
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isToday ? .white : (inMonth ? .black : .black.opacity(0.3)))
                    .frame(width: 30, height: 30)
                    .background {
                        if isToday { Circle().fill(Brand.crimson) }
                        else if isSelected { Circle().fill(Brand.crimson.opacity(0.12)) }
                    }
                Circle().fill(dotColor(events)).frame(width: 5, height: 5).opacity(events.isEmpty ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
        }
        .buttonStyle(.plain)
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
                    ForEach(items) { eventBlock($0, compact: true) }
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
                Button { onOpen(r) } label: { eventBlock(r, compact: false) }
                    .buttonStyle(.plain)
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

    // MARK: Data & helpers

    private func reminders(on day: Date) -> [Reminder] {
        store.reminders
            .filter { $0.status != .deleted }
            .filter { if let d = $0.dueDate { return cal.isDate(d, inSameDayAs: day) } else { return false } }
            .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }

    private func dotColor(_ events: [Reminder]) -> Color {
        events.contains { $0.urgent || $0.flag || $0.priority == .high } ? Brand.crimson : .black
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
