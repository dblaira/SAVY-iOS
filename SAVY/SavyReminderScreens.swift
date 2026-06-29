import SwiftUI
import UIKit

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

/// Reminder and Action tabs: Re_Call-style ranked cards without the Re_Call masonry template area.
struct SavyReminderKindTabScreen: View {
    let kind: ReminderKind

    @EnvironmentObject private var store: ReminderStore
    @State private var editing: Reminder?
    @State private var armedReorderId: UUID?
    @State private var isCompletedExpanded = false

    private var activeItems: [Reminder] {
        store.active.filter { $0.kind == kind }
    }

    private var completedItems: [Reminder] {
        store.completed.filter { $0.kind == kind }
    }

    private var title: String {
        switch kind {
        case .reminder: return "Reminders"
        case .action: return "Actions"
        case .event: return "Calendar"
        }
    }

    private var subtitle: String {
        switch kind {
        case .reminder: return "What matters next."
        case .action: return "Choose the move that matters."
        case .event: return "Time blocks live on the calendar."
        }
    }

    private var bandTitle: String {
        kind == .action ? "PRIORITY" : "UP NEXT"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    Rectangle().fill(SavyTheme.crimson).frame(height: 2)
                    activeBand
                    completedBottomSection
                }
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .background(SavyTheme.deepNavy)
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityIdentifier(kind == .action ? "actionsHome" : "remindersHome")
        .sheet(item: $editing) { reminder in
            ReminderFormView(existing: reminder, existingTags: store.recentTags) { updated in
                store.save(updated)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SavyTypography.displaySerif(48, weight: .bold))
                .foregroundStyle(SavyTheme.deepNavy)
            Text(subtitle)
                .font(SavyTheme.readingLabel(18))
                .foregroundStyle(SavyTheme.crimson)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 60)
        .padding(.bottom, 18)
        .padding(.horizontal, 16)
        .background(Color.white)
    }

    private var activeBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text(bandTitle)
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(2.5)
                    .foregroundStyle(SavyTheme.bottomNavTan)
                Spacer()
                Text("\(activeItems.count)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.45))
            }

            if activeItems.isEmpty {
                emptyState
            } else {
                ForEach(Array(activeItems.enumerated()), id: \.element.id) { index, reminder in
                    SavyUpNextCardRow(
                        reminderId: reminder.id,
                        armedId: $armedReorderId,
                        actions: cardActions(reminder),
                        onTap: { editing = reminder },
                        onMoveUp: { store.moveUpNext(reminder, direction: .up) },
                        onMoveDown: { store.moveUpNext(reminder, direction: .down) }
                    ) {
                        SavyReminderBandCard(
                            reminder: reminder,
                            bg: cardColors(for: index).bg,
                            fg: cardColors(for: index).fg,
                            accent: cardColors(for: index).accent,
                            detail: cardDetail(for: index)
                        )
                        .scaleEffect(x: 1, y: kind == .action ? cardScale(for: index) : 1, anchor: .top)
                        .accessibilityIdentifier(cardIdentifier(for: index))
                    }
                }
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SavyTheme.deepNavy)
    }

    @ViewBuilder private var completedBottomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !completedItems.isEmpty {
                Button {
                    SavyHapticFeedback.selection()
                    withAnimation(.snappy) { isCompletedExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Text("Completed")
                            .font(.system(size: 13, weight: .heavy))
                            .textCase(.uppercase)
                            .tracking(1.5)
                            .foregroundStyle(SavyTheme.bottomNavTan)
                        Text("\(completedItems.count)")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(SavyTheme.crimson)
                        Image(systemName: isCompletedExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(SavyTheme.crimson)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCompletedExpanded ? "Hide completed items" : "Show completed items")
                .accessibilityIdentifier(
                    kind == .action ? "completedActionsToggle" : "completedRemindersToggle"
                )

                if isCompletedExpanded {
                    ForEach(completedItems.prefix(12)) { reminder in
                        SavyCompletedReminderRow(
                            reminder: reminder,
                            onToggle: { store.uncomplete(reminder) },
                            onTap: { editing = reminder },
                            onDelete: { store.delete(reminder) }
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, completedItems.isEmpty ? 0 : 18)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SavyTheme.deepNavy)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(kind == .action ? "completedActionsSection" : "completedRemindersSection")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind == .action ? "No actions yet." : "Nothing yet.")
                .font(SavyTypography.displaySerif(26, weight: .bold))
                .foregroundStyle(.white)
            Text(kind == .action ? "Tap the bolt and choose Action." : "Tap the bolt and choose Reminder.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.nearBlack)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cardActions(_ reminder: Reminder) -> [SavySwipeAction] {
        [
            SavySwipeAction(title: "Done", icon: "checkmark", bg: SavyTheme.crimson) { store.complete(reminder) },
            SavySwipeAction(title: reminder.pinned ? "Unpin" : "Pin", icon: "pin", bg: Brand.tileBlue) { store.togglePin(reminder) },
            SavySwipeAction(title: "Delete", icon: "trash", bg: Color(hex: 0xB00124)) { store.delete(reminder) },
        ]
    }

    private func cardColors(for index: Int) -> (bg: Color, fg: Color, accent: Color) {
        switch index {
        case 0: return (.white, SavyTheme.deepNavy, SavyTheme.crimson)
        case 1: return (Brand.darkRed, .white, .white)
        default: return (SavyTheme.bottomNavTan, SavyTheme.deepNavy, SavyTheme.crimson)
        }
    }

    private func cardDetail(for index: Int) -> SavyCardDetail {
        index == 0 ? .full : (index == 1 ? .medium : .minimal)
    }

    private func cardScale(for index: Int) -> CGFloat {
        switch index {
        case 0: return 1.08
        case 1: return 1.02
        default: return 1
        }
    }

    private func cardIdentifier(for index: Int) -> String {
        switch (kind, index) {
        case (.reminder, 0): return "upNextCard0"
        case (.reminder, _): return "upNextCard"
        case (.action, 0): return "topActionCard"
        case (.action, _): return "actionCard"
        case (.event, _): return "eventCard"
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

struct SavySwipeAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let bg: Color
    let run: () -> Void
}

/// UIKit-backed swipe/reorder row so vertical scrolling remains responsive inside SwiftUI ScrollViews.
struct SavyUpNextCardRow<Content: View>: View {
    let reminderId: UUID
    @Binding var armedId: UUID?
    let actions: [SavySwipeAction]
    var onTap: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    @ViewBuilder var content: Content

    @State private var swipeOffset: CGFloat = 0
    private var actionsWidth: CGFloat { CGFloat(actions.count) * 64 }
    private var isArmed: Bool { armedId == reminderId }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(actions) { action in
                    Button {
                        withAnimation(.snappy) { swipeOffset = 0 }
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
            .zIndex(swipeOffset > 0 ? 3 : 0)

            ZStack(alignment: .topTrailing) {
                content
                    .allowsHitTesting(false)

                SavyUpNextGestureHost(
                    armedId: $armedId,
                    reminderId: reminderId,
                    actionsWidth: actionsWidth,
                    swipeOffset: $swipeOffset,
                    onTap: onTap,
                    onMoveUp: onMoveUp,
                    onMoveDown: onMoveDown
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())

                if isArmed {
                    reorderControls
                        .padding(8)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .overlay {
                if isArmed {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(SavyTheme.crimson.opacity(0.45), lineWidth: 8)
                            .padding(-4)
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(SavyTheme.crimson, lineWidth: 4)
                    }
                }
            }
            .offset(x: swipeOffset)
            .zIndex(1)
            .scaleEffect(isArmed ? 1.04 : 1)
            .shadow(color: isArmed ? SavyTheme.crimson.opacity(0.55) : .clear, radius: 22, y: 0)
            .shadow(color: isArmed ? SavyTheme.crimson.opacity(0.3) : .clear, radius: 6, y: 2)
            .animation(.snappy, value: isArmed)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear {
            if isArmed { armedId = nil }
        }
    }

    private var reorderControls: some View {
        VStack(spacing: 2) {
            reorderButton("chevron.up", action: onMoveUp)
            reorderButton("chevron.down", action: onMoveDown)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SavyTheme.crimson.opacity(0.55)))
    }

    private func reorderButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(SavyTheme.crimson)
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(icon == "chevron.up" ? "reorderUp" : "reorderDown")
    }
}

private struct SavyUpNextGestureHost: UIViewRepresentable {
    @Binding var armedId: UUID?
    let reminderId: UUID
    let actionsWidth: CGFloat
    @Binding var swipeOffset: CGFloat
    var onTap: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> SavyUpNextGestureView {
        let view = SavyUpNextGestureView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        view.pan.delegate = context.coordinator
        view.longPress.delegate = context.coordinator
        view.tap.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: SavyUpNextGestureView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SavyUpNextGestureHost
        weak var view: SavyUpNextGestureView?

        init(parent: SavyUpNextGestureHost) { self.parent = parent }

        func isArmed() -> Bool { parent.armedId == parent.reminderId }

        func arm() {
            guard parent.armedId != parent.reminderId else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
                    self.parent.armedId = self.parent.reminderId
                }
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        func disarm() {
            guard parent.armedId == parent.reminderId else { return }
            DispatchQueue.main.async {
                withAnimation(.snappy) { self.parent.armedId = nil }
            }
        }

        func setSwipeOffset(_ x: CGFloat) {
            DispatchQueue.main.async { self.parent.swipeOffset = x }
        }

        func settleSwipe(open: Bool) {
            DispatchQueue.main.async {
                withAnimation(.snappy) {
                    self.parent.swipeOffset = open ? self.parent.actionsWidth : 0
                }
            }
        }

        func tap() {
            DispatchQueue.main.async {
                if self.isArmed() {
                    self.disarm()
                } else if self.parent.swipeOffset != 0 {
                    withAnimation(.snappy) { self.parent.swipeOffset = 0 }
                } else {
                    self.parent.onTap()
                }
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view else { return true }
            if gestureRecognizer === view.pan {
                if view.reorderArmed || isArmed() { return false }
                let velocity = view.pan.velocity(in: view)
                let isHorizontal = abs(velocity.x) > abs(velocity.y) * 0.5
                return isHorizontal && (velocity.x > 0 || parent.swipeOffset > 0)
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private final class SavyUpNextGestureView: UIView {
    weak var coordinator: SavyUpNextGestureHost.Coordinator?

    fileprivate let pan = UIPanGestureRecognizer()
    fileprivate let longPress = UILongPressGestureRecognizer()
    fileprivate let tap = UITapGestureRecognizer()
    fileprivate var reorderArmed = false
    private var longPressStartY: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        pan.cancelsTouchesInView = false
        pan.addTarget(self, action: #selector(handlePan))
        addGestureRecognizer(pan)

        longPress.cancelsTouchesInView = false
        longPress.minimumPressDuration = 0.35
        longPress.addTarget(self, action: #selector(handleLongPress))
        addGestureRecognizer(longPress)

        tap.cancelsTouchesInView = false
        tap.addTarget(self, action: #selector(handleTap))
        tap.require(toFail: longPress)
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func handleTap() {
        coordinator?.tap()
    }

    @objc private func handleLongPress() {
        switch longPress.state {
        case .began:
            reorderArmed = true
            longPressStartY = longPress.location(in: self).y
            coordinator?.arm()
        case .ended, .cancelled, .failed:
            let dy = longPress.location(in: self).y - longPressStartY
            if abs(dy) > 20 {
                if dy < 0 { coordinator?.parent.onMoveUp() }
                else { coordinator?.parent.onMoveDown() }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                coordinator?.disarm()
            }
            reorderArmed = false
        default:
            break
        }
    }

    @objc private func handlePan() {
        guard let coordinator else { return }
        guard !reorderArmed, !coordinator.isArmed() else { return }
        switch pan.state {
        case .changed:
            let translation = pan.translation(in: self)
            guard abs(translation.x) > abs(translation.y) else { return }
            coordinator.setSwipeOffset(min(max(translation.x, 0), coordinator.parent.actionsWidth))
        case .ended, .cancelled, .failed:
            let translation = pan.translation(in: self)
            pan.setTranslation(.zero, in: self)
            coordinator.settleSwipe(open: translation.x > coordinator.parent.actionsWidth / 2)
        default:
            break
        }
    }
}

enum SavyCardDetail { case minimal, medium, full }

struct SavyReminderBandCard: View {
    let reminder: Reminder
    let bg: Color
    let fg: Color
    let accent: Color
    var detail: SavyCardDetail = .minimal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: kindIcon)
                    .font(.system(size: 11, weight: .bold))
                Text(reminder.kind.label.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                if reminder.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .heavy))
                }
            }
            .foregroundStyle(fg.opacity(0.7))

            Text(reminder.title.isEmpty ? "Untitled" : reminder.title)
                .font(SavyTypography.displaySerif(26, weight: .regular))
                .foregroundStyle(fg)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(accent).frame(width: 36, height: 2)

            if !signalText.isEmpty {
                Text(signalText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(fg.opacity(0.8))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(fg.opacity(0.55))
                    .lineLimit(1)
            }

            if detail != .minimal, let note = detailLine {
                Text(note)
                    .font(.system(size: 14))
                    .foregroundStyle(fg.opacity(0.78))
                    .lineLimit(detail == .full ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
    }

    private var kindIcon: String {
        switch reminder.kind {
        case .reminder: return "bell"
        case .action: return "bolt"
        case .event: return "calendar"
        }
    }

    private var detailLine: String? {
        if !reminder.notes.isEmpty { return reminder.notes }
        if !reminder.outcome.isEmpty { return reminder.outcome }
        return nil
    }

    private var signalText: String {
        var parts: [String] = []
        if reminder.context != .none { parts.append(reminder.context.label) }
        if reminder.priority != .none { parts.append(reminder.priority.marks) }
        parts.append(contentsOf: reminder.tags.map { "#\($0)" })
        return parts.joined(separator: "   ·   ")
    }

    private var secondaryText: String {
        var parts: [String] = []
        if let when = reminder.whenLabel { parts.append(when) }
        if !reminder.listName.isEmpty { parts.append(reminder.listName) }
        if !reminder.locationName.isEmpty { parts.append(reminder.locationName) }
        return parts.joined(separator: "   ·   ")
    }
}

struct SavyCompletedReminderRow: View {
    let reminder: Reminder
    var onToggle: () -> Void
    var onTap: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(SavyTheme.crimson)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reopen")

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title.isEmpty ? "Untitled" : reminder.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SavyTheme.secondaryText)
                        .strikethrough()
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    if let when = reminder.whenLabel {
                        Text(when)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SavyTheme.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SavyTheme.deepNavy.opacity(0.08)))
        .contextMenu {
            Button("Reopen") { onToggle() }
            Button("Delete", role: .destructive) { onDelete() }
        }
        .accessibilityIdentifier("completedReminderRow")
    }
}

struct SavySwipeRow<Content: View>: View {
    let actions: [SavySwipeAction]
    var gestureAccessibilityIdentifier: String?
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
            .zIndex(offset > 0 ? 3 : 0)

            ZStack {
                content
                    .allowsHitTesting(false)

                SavySwipeGestureHost(
                    accessibilityIdentifier: gestureAccessibilityIdentifier,
                    actionsWidth: actionsWidth,
                    swipeOffset: $offset,
                    onTap: onTap
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .offset(x: offset)
            .zIndex(1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SavySwipeGestureHost: UIViewRepresentable {
    var accessibilityIdentifier: String?
    let actionsWidth: CGFloat
    @Binding var swipeOffset: CGFloat
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> SavySwipeGestureView {
        let view = SavySwipeGestureView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        view.pan.delegate = context.coordinator
        view.tap.delegate = context.coordinator
        view.accessibilityIdentifier = accessibilityIdentifier
        view.isAccessibilityElement = accessibilityIdentifier != nil
        return view
    }

    func updateUIView(_ uiView: SavySwipeGestureView, context: Context) {
        context.coordinator.parent = self
        uiView.accessibilityIdentifier = accessibilityIdentifier
        uiView.isAccessibilityElement = accessibilityIdentifier != nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SavySwipeGestureHost
        weak var view: SavySwipeGestureView?

        init(parent: SavySwipeGestureHost) { self.parent = parent }

        func setSwipeOffset(_ x: CGFloat) {
            DispatchQueue.main.async { self.parent.swipeOffset = x }
        }

        func settleSwipe(open: Bool) {
            DispatchQueue.main.async {
                withAnimation(.snappy) {
                    self.parent.swipeOffset = open ? self.parent.actionsWidth : 0
                }
            }
        }

        func tap() {
            DispatchQueue.main.async {
                if self.parent.swipeOffset != 0 {
                    withAnimation(.snappy) { self.parent.swipeOffset = 0 }
                } else {
                    self.parent.onTap()
                }
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view else { return true }
            if gestureRecognizer === view.pan {
                return true
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private final class SavySwipeGestureView: UIView {
    weak var coordinator: SavySwipeGestureHost.Coordinator?

    fileprivate let pan = UIPanGestureRecognizer()
    fileprivate let tap = UITapGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        pan.cancelsTouchesInView = false
        pan.addTarget(self, action: #selector(handlePan))
        addGestureRecognizer(pan)

        tap.cancelsTouchesInView = false
        tap.addTarget(self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func handleTap() {
        coordinator?.tap()
    }

    @objc private func handlePan() {
        guard let coordinator else { return }
        switch pan.state {
        case .changed:
            let translation = pan.translation(in: self)
            guard abs(translation.x) > abs(translation.y) else { return }
            coordinator.setSwipeOffset(min(max(translation.x, 0), coordinator.parent.actionsWidth))
        case .ended, .cancelled, .failed:
            let translation = pan.translation(in: self)
            pan.setTranslation(.zero, in: self)
            coordinator.settleSwipe(open: translation.x > coordinator.parent.actionsWidth / 2)
        default:
            break
        }
    }
}
