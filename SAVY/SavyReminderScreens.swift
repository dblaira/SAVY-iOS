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
    @State private var armedReorderId: String?
    @State private var isCompletedExpanded = false

    private var activeItems: [Reminder] {
        store.active.filter { $0.kind == kind }
    }

    private var completedItems: [Reminder] {
        store.completed.filter { $0.kind == kind }
    }

    private var hasPhotoBackground: Bool {
        kind == .reminder || kind == .action
    }

    private var title: String {
        switch kind {
        case .reminder: return "Reminders"
        case .action: return "Actions"
        case .event: return "Calendar"
        case .post: return "Posts"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                pageContent(viewportHeight: proxy.size.height)
            }
            .coordinateSpace(name: "remindersLandscapeScroll")
            .savyHeaderOverscrollCapture(kind == .action ? "actions" : "reminders")
            .background(SavyTheme.pageBackground)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting, armedReorderId != nil {
                    withAnimation(.snappy) { armedReorderId = nil }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityIdentifier(kind == .action ? "actionsHome" : "remindersHome")
        .sheet(item: $editing) { reminder in
            ReminderFormView(existing: reminder, existingTags: store.recentTags) { updated in
                store.save(updated)
            }
        }
    }

    @ViewBuilder private func pageContent(viewportHeight: CGFloat) -> some View {
        if hasPhotoBackground {
            VStack(spacing: 0) {
                hero
                Rectangle().fill(SavyTheme.headerDivider).frame(height: RootHomeLayout.heroDividerHeight)

                VStack(spacing: 0) {
                    activeBand
                    completedBottomSection
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background {
                    GeometryReader { landscape in
                        if kind == .action {
                            actionsLandscape(
                                width: landscape.size.width,
                                contentTop: landscape.frame(in: .named("remindersLandscapeScroll")).minY,
                                viewportHeight: viewportHeight
                            )
                        } else {
                            Image("RemindersBeachLandscape")
                                .resizable()
                                .scaledToFill()
                                // Bias this 4:3 photo toward the cliff without losing the ocean.
                                .offset(x: -max(0, viewportHeight * 4 / 3 - landscape.size.width) * 0.15)
                                .frame(
                                    width: landscape.size.width,
                                    height: viewportHeight
                                )
                                .clipped()
                                // Preserve the cliff in a portrait crop, independent of card count.
                                // Like Home, keep the scene behind cards once the hero scrolls away.
                                .offset(y: max(0, -landscape.frame(in: .named("remindersLandscapeScroll")).minY))
                        }
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
        } else {
            VStack(spacing: 0) {
                hero
                Rectangle().fill(SavyTheme.headerDivider).frame(height: RootHomeLayout.heroDividerHeight)
                activeBand
                completedBottomSection
            }
            .savyHeaderPageContent(minHeight: viewportHeight)
        }
    }

    private func actionsLandscape(width: CGFloat, contentTop: CGFloat, viewportHeight: CGFloat) -> some View {
        let sky = Color(red: 0.52, green: 0.70, blue: 0.83)
        let visibleHeight = max(0, viewportHeight - max(0, contentTop))

        return ZStack(alignment: .bottom) {
            sky
            Image("ActionsCarLandscape")
                .resizable()
                .scaledToFit()
                .frame(width: width, height: width * 480 / 959)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [sky, sky.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 44)
                }
                // Keep the complete photograph above the existing navy navigation band.
                .padding(.bottom, RootHomeLayout.bottomNavNavyRiserHeight + 8)
        }
        .frame(width: width, height: visibleHeight)
        // Keep the photo in the visible viewport even when the Actions list is long.
        .offset(y: max(0, -contentTop))
    }

    private var hero: some View {
        Text(title)
            .font(SavyTypography.displaySerif(48, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 60)
            .padding(.bottom, 18)
            .padding(.horizontal, 16)
            .background(SavyTheme.pageBackground)
    }

    private var activeBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Spacer()
                Text("\(activeItems.count)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(SavyTheme.deepNavy.opacity(kind == .reminder ? 1 : 0.65))
            }

            if activeItems.isEmpty {
                emptyState
            } else {
                SavyCardFlow(spacing: 10) {
                    ForEach(Array(activeItems.enumerated()), id: \.element.id) { index, reminder in
                        SavyUpNextCardRow(
                            reminderId: reminder.id.uuidString,
                            armedId: $armedReorderId,
                            actions: cardActions(reminder),
                            onTap: { editing = reminder },
                            onMoveUp: { store.moveUpNext(reminder, direction: .up) },
                            onMoveDown: { store.moveUpNext(reminder, direction: .down) },
                            gestureAccessibilityIdentifier: "reminderReorderGesture-\(reminder.id.uuidString)"
                        ) {
                            SavyReminderBandCard(
                                reminder: reminder,
                                bg: cardColors(for: index).bg,
                                fg: cardColors(for: index).fg,
                                accent: cardColors(for: index).accent,
                                detail: reminder.pinned ? .full : .minimal
                            )
                            .accessibilityIdentifier(cardIdentifier(for: index))
                        }
                        .zIndex(armedReorderId == reminder.id.uuidString ? 1 : 0)
                    }
                }
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hasPhotoBackground ? Color.clear : SavyTheme.contentBackground)
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
                            .foregroundStyle(SavyTheme.deepNavy)
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
        .background(hasPhotoBackground ? Color.clear : SavyTheme.contentBackground)
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
        SavyReminderCardAppearance.colors(for: index)
    }

    private func cardIdentifier(for index: Int) -> String {
        switch (kind, index) {
        case (.reminder, 0): return "upNextCard0"
        case (.reminder, _): return "upNextCard"
        case (.action, 0): return "topActionCard"
        case (.action, _): return "actionCard"
        case (.event, _): return "eventCard"
        case (.post, _): return "postCard"
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
    let reminderId: String
    @Binding var armedId: String?
    let actions: [SavySwipeAction]
    var onTap: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var gestureAccessibilityIdentifier: String? = nil
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
            .opacity(swipeOffset > 0 ? 1 : 0)
            .allowsHitTesting(swipeOffset > 0)
            .accessibilityHidden(swipeOffset <= 0)
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
                    onMoveDown: onMoveDown,
                    gestureAccessibilityIdentifier: gestureAccessibilityIdentifier
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
                    .allowsHitTesting(false)
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
        #if targetEnvironment(macCatalyst)
        .contextMenu { macContextMenu }
        #endif
    }

    #if targetEnvironment(macCatalyst)
    /// A right click offers the same actions the swipe and long press reveal on iPhone.
    @ViewBuilder private var macContextMenu: some View {
        ForEach(actions) { action in
            Button(action.title, systemImage: action.icon) { withAnimation(.snappy) { action.run() } }
        }
        Divider()
        Button("Move Up", systemImage: "chevron.up") { withAnimation(.snappy) { onMoveUp() } }
        Button("Move Down", systemImage: "chevron.down") { withAnimation(.snappy) { onMoveDown() } }
    }
    #endif

    private var reorderControls: some View {
        VStack(spacing: 2) {
            reorderButton("chevron.up", action: onMoveUp)
            reorderButton("chevron.down", action: onMoveDown)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(SavyTheme.crimson.opacity(0.55))
                .allowsHitTesting(false)
        }
    }

    private func reorderButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(SavyTheme.crimson)
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "chevron.up" ? "Move up" : "Move down")
        .accessibilityIdentifier(icon == "chevron.up" ? "reorderUp" : "reorderDown")
    }
}

private struct SavyUpNextGestureHost: UIViewRepresentable {
    @Binding var armedId: String?
    let reminderId: String
    let actionsWidth: CGFloat
    @Binding var swipeOffset: CGFloat
    var onTap: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var gestureAccessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> SavyUpNextGestureView {
        let view = SavyUpNextGestureView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        view.pan.delegate = context.coordinator
        view.longPress.delegate = context.coordinator
        view.tap.delegate = context.coordinator
        view.isAccessibilityElement = gestureAccessibilityIdentifier != nil
        view.accessibilityIdentifier = gestureAccessibilityIdentifier
        return view
    }

    func updateUIView(_ uiView: SavyUpNextGestureView, context: Context) {
        context.coordinator.parent = self
        uiView.isAccessibilityElement = gestureAccessibilityIdentifier != nil
        uiView.accessibilityIdentifier = gestureAccessibilityIdentifier
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
                    self.parent.swipeOffset = 0
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

        func move(up: Bool) {
            withAnimation(.snappy) {
                if up { parent.onMoveUp() }
                else { parent.onMoveDown() }
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
                if parent.actionsWidth == 0 || view.reorderArmed || isArmed() { return false }
                let velocity = view.pan.velocity(in: view)
                let isHorizontal = abs(velocity.x) > abs(velocity.y) * 1.15
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
        // A two-finger trackpad swipe reveals the actions the way a finger swipe does on iPhone.
        pan.allowedScrollTypesMask = .continuous
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
        case .ended:
            let dy = longPress.location(in: self).y - longPressStartY
            if abs(dy) > 20 {
                coordinator?.move(up: dy < 0)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                coordinator?.disarm()
            }
            reorderArmed = false
        case .cancelled, .failed:
            let wasReordering = reorderArmed
            reorderArmed = false
            if wasReordering { coordinator?.disarm() }
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

/// Reminders and the Home carousel use the same card presentation.
enum SavyReminderCardAppearance {
    static func colors(for index: Int) -> (bg: Color, fg: Color, accent: Color) {
        switch index {
        case 0: return (.white, SavyTheme.deepNavy, SavyTheme.crimson)
        case 1: return (Brand.darkRed, .white, .white)
        default: return (SavyTheme.bottomNavTan, SavyTheme.deepNavy, SavyTheme.crimson)
        }
    }

}

/// Cards begin with their title. Reference numbers and saved metadata sit below it;
/// type labels, pin markers, and delegation badges do not occupy the card face.
struct SavyBandCard: View {
    let bg: Color
    let fg: Color
    let accent: Color
    let title: String
    let signalText: String
    let secondaryText: String
    var detailLine: String? = nil
    var detail: SavyCardDetail = .minimal
    var isCompact: Bool = false
    var minimumHeight: CGFloat? = nil
    var border: Color = .white.opacity(0.08)
    var secondaryLineLimit: Int = 1
    var titleAccessibilityIdentifier: String? = nil
    var referenceText: String? = nil
    var referenceAccessibilityIdentifier: String? = nil
    var expandsContent: Bool = false
    var previewHeight: CGFloat? = nil
    var metadataColor: Color? = nil
    var metadataWeight: Font.Weight? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
            titleText

            Rectangle().fill(accent).frame(width: 36, height: 2)

            if !isCompact, let referenceText, !referenceText.isEmpty {
                Text(referenceText)
                    .font(.system(size: 11, weight: metadataWeight ?? .heavy))
                    .tracking(1.5)
                    .foregroundStyle(metadataColor ?? fg.opacity(0.7))
                    .accessibilityIdentifier(referenceAccessibilityIdentifier ?? "cardReference")
            }

            if !isCompact, !signalText.isEmpty {
                Text(signalText)
                    .font(.system(size: 13, weight: metadataWeight ?? .bold))
                    .foregroundStyle(metadataColor ?? fg.opacity(0.8))
                    .lineLimit(expandsContent && previewHeight == nil ? nil : (isCompact ? 1 : 2))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isCompact, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.system(size: 12, weight: metadataWeight ?? .medium))
                    .foregroundStyle(metadataColor ?? fg.opacity(0.55))
                    .lineLimit(expandsContent && previewHeight == nil ? nil : (isCompact ? 1 : secondaryLineLimit))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isCompact, (expandsContent || detail != .minimal),
               previewHeight == nil || (signalText.isEmpty && secondaryText.isEmpty),
               let note = detailLine {
                Text(note)
                    .font(.system(size: 14, weight: metadataWeight ?? .regular))
                    .foregroundStyle(metadataColor ?? fg.opacity(0.78))
                    .lineLimit(expandsContent && previewHeight == nil ? nil : (detail == .full ? 3 : 1))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompact ? 8 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minimumHeight, alignment: .topLeading)
        .frame(height: previewHeight, alignment: .topLeading)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(border))
    }

    @ViewBuilder
    private var titleText: some View {
        let text = Text(title)
            .font(SavyTypography.displaySerif(26, weight: .regular))
            .foregroundStyle(fg)
            .lineLimit(isCompact ? 1 : (previewHeight != nil ? 2 : nil))
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
        if let titleAccessibilityIdentifier {
            text.accessibilityIdentifier(titleAccessibilityIdentifier)
        } else {
            text
        }
    }
}

struct SavyReminderBandCard: View {
    let reminder: Reminder
    let bg: Color
    let fg: Color
    let accent: Color
    var detail: SavyCardDetail = .minimal
    var showsSchedule: Bool = true
    var showsCompleteMetadata: Bool = false
    var previewHeight: CGFloat? = nil
    var metadataColor: Color? = nil
    var metadataWeight: Font.Weight? = nil

    var body: some View {
        SavyBandCard(
            bg: bg,
            fg: fg,
            accent: accent,
            title: reminder.title.isEmpty ? "Untitled" : reminder.title,
            signalText: signalText,
            secondaryText: secondaryText,
            detailLine: detailLine,
            detail: detail,
            isCompact: !reminder.pinned,
            minimumHeight: reminder.pinned && previewHeight == nil ? 186 : nil,
            expandsContent: showsCompleteMetadata,
            previewHeight: reminder.pinned ? previewHeight : nil,
            metadataColor: metadataColor,
            metadataWeight: metadataWeight
        )
    }

    private var detailLine: String? {
        if showsCompleteMetadata {
            var parts: [String] = []
            if let when = reminder.whenIAm, !when.isEmpty { parts.append("When I am: \(when)") }
            if !reminder.outcome.isEmpty { parts.append(reminder.outcome) }
            if !reminder.notes.isEmpty { parts.append(reminder.notes) }
            if !reminder.url.isEmpty { parts.append(reminder.url) }
            if !reminder.waitingOn.isEmpty { parts.append("Waiting on / delegate to: \(reminder.waitingOn)") }
            if let theme = reminder.postThemeName, !theme.isEmpty { parts.append(theme) }
            parts.append(contentsOf: reminder.postQuestionAndAnswers.filter { !$0.isEmpty })
            parts.append(contentsOf: reminder.subtasks.map { "\($0.done ? "☑" : "☐") \($0.title)" })
            if let image = reminder.imageLocalPath, !image.isEmpty { parts.append("Image attached") }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }
        if !reminder.notes.isEmpty { return reminder.notes }
        if !reminder.outcome.isEmpty { return reminder.outcome }
        return nil
    }

    private var signalText: String {
        var parts: [String] = []
        if reminder.context != .none { parts.append(reminder.context.label) }
        if showsCompleteMetadata {
            if reminder.marksClearSignOfSuccess == true, reminder.context != .clearSign {
                parts.append("Clear Signs of Success")
            }
            if reminder.marksCompounding == true, reminder.context != .compound {
                parts.append("Compounding")
            }
        } else if reminder.priority != .none {
            parts.append(reminder.priority.marks)
        }
        parts.append(contentsOf: reminder.tags.map { "#\($0)" })
        return parts.joined(separator: "   ·   ")
    }

    private var secondaryText: String {
        var parts: [String] = []
        if showsSchedule, let when = reminder.whenLabel { parts.append(when) }
        if !reminder.listName.isEmpty {
            parts.append(showsCompleteMetadata ? "Lift: \(reminder.listName)" : reminder.listName)
        }
        if !reminder.locationName.isEmpty { parts.append(reminder.locationName) }
        if showsCompleteMetadata {
            if reminder.priority != .none {
                parts.append(previewHeight == nil ? "Priority: \(reminder.priority.label)" : reminder.priority.marks)
            }
            if reminder.energy != .none {
                parts.append(previewHeight == nil ? "Energy: \(reminder.energy.label)" : "\(reminder.energy.label) energy")
            }
            if reminder.effort != .none { parts.append("Effort: \(reminder.effort.label)") }
            if reminder.repeatRule != .none {
                parts.append(previewHeight == nil ? "Repeat: \(reminder.repeatRule.label)" : reminder.repeatRule.label)
            }
            if reminder.flag { parts.append("Flagged") }
            if reminder.urgent { parts.append("Urgent") }
        }
        return parts.joined(separator: previewHeight == nil ? "   ·   " : " · ")
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
                        .lineLimit(reminder.pinned ? 3 : 1)
                    if reminder.pinned, let when = reminder.whenLabel {
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
        .accessibilityLabel(reminder.title.isEmpty ? "Untitled" : reminder.title)
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
            .opacity(offset > 0 ? 1 : 0)
            .allowsHitTesting(offset > 0)
            .accessibilityHidden(offset <= 0)
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
        #if targetEnvironment(macCatalyst)
        .contextMenu {
            ForEach(actions) { action in
                Button(action.title, systemImage: action.icon) { withAnimation(.snappy) { action.run() } }
            }
        }
        #endif
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
