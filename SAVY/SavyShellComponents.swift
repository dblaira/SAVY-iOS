import SwiftUI
import UIKit

enum SavyHapticFeedback {
    static let primaryImpactIntensity: CGFloat = 1.0

    @MainActor
    static func primaryImpact() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred(intensity: primaryImpactIntensity)
    }

    @MainActor
    static func menuOpen() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.92)
    }

    @MainActor
    static func menuClose() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.78)
    }

    @MainActor
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

enum SavyFabMenuMotion {
    static let open = Animation.spring(response: 0.34, dampingFraction: 0.72)
    static let close = Animation.spring(response: 0.3, dampingFraction: 0.8)
}

struct SavyAccountMenuButton: View {
    let onSignOut: () -> Void
    var lightForeground = true

    var body: some View {
        Menu {
            Button("Sign Out", role: .destructive) {
                onSignOut()
            }
        } label: {
            Image(systemName: RootHomeLayout.accountMenuSymbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(
                    lightForeground
                        ? .white.opacity(0.78)
                        : SavyTheme.ink
                )
                .frame(
                    width: RootHomeLayout.accountMenuButtonSize,
                    height: RootHomeLayout.accountMenuButtonSize
                )
                .background(
                    lightForeground
                        ? .white.opacity(0.08)
                        : Color.black.opacity(0.06),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(
                            lightForeground
                                ? .white.opacity(0.12)
                                : Color.black.opacity(0.12),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account menu")
    }
}

struct SavyBottomNavigationBar: View {
    @ObservedObject var navigationState: SavyNavigationState
    let onSelectCaptureKind: (MetadataEntryKind) -> Void

    @State private var draggingFab = false
    @State private var menuWasOpenAtStart = false

    private let barBackground = Color(red: 0.80, green: 0.70, blue: 0.58)
    private let inactiveColor = Color(red: 0.34, green: 0.27, blue: 0.21).opacity(0.68)

    var body: some View {
        ZStack(alignment: .top) {
            barBackground

            HStack(alignment: .center, spacing: 0) {
                ForEach(SavyNavigationSection.leadingSections) { section in
                    navigationButton(for: section)
                }

                Spacer()
                    .frame(maxWidth: .infinity)

                ForEach(SavyNavigationSection.trailingSections) { section in
                    navigationButton(for: section)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, RootHomeLayout.bottomNavigationTopPadding)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(height: 1)

            ZStack {
                if navigationState.isRadialMenuPresented {
                    fabOption(.reminder).offset(x: -76, y: -40)
                    fabOption(.action).offset(x: 0, y: -116)
                    fabOption(.calendar).offset(x: 76, y: -40)
                }

                captureFab
                    .offset(y: -22)
            }
        }
        .frame(height: RootHomeLayout.bottomNavigationHeight)
        .background(alignment: .top) {
            SavyTheme.deepNavy
                .frame(height: RootHomeLayout.bottomNavNavyRiserHeight)
                .offset(y: -RootHomeLayout.bottomNavNavyRiserHeight)
        }
        .background(barBackground.ignoresSafeArea(edges: .bottom))
        .animation(SavyFabMenuMotion.open, value: navigationState.isRadialMenuPresented)
    }

    private var captureFab: some View {
        borderedSymbol(navigationState.isRadialMenuPresented ? "xmark" : "bolt.fill")
            .frame(
                width: RootHomeLayout.floatingCaptureSize,
                height: RootHomeLayout.floatingCaptureSize
            )
            .background(RootHomeLayout.floatingCaptureBackground, in: Circle())
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !draggingFab {
                            draggingFab = true
                            menuWasOpenAtStart = navigationState.isRadialMenuPresented
                            if !navigationState.isRadialMenuPresented {
                                SavyHapticFeedback.menuOpen()
                                withAnimation(SavyFabMenuMotion.open) {
                                    navigationState.isRadialMenuPresented = true
                                }
                            }
                        }

                        let target = targetKind(for: value.translation)
                        if target != navigationState.highlightedCaptureKind {
                            navigationState.highlightedCaptureKind = target
                            if target != nil {
                                SavyHapticFeedback.selection()
                            }
                        }
                    }
                    .onEnded { _ in
                        if let selected = navigationState.highlightedCaptureKind {
                            SavyHapticFeedback.primaryImpact()
                            withAnimation(SavyFabMenuMotion.close) {
                                onSelectCaptureKind(selected)
                            }
                        } else if menuWasOpenAtStart {
                            SavyHapticFeedback.menuClose()
                            withAnimation(SavyFabMenuMotion.close) {
                                navigationState.dismissRadialMenu()
                            }
                        }

                        draggingFab = false
                        navigationState.highlightedCaptureKind = nil
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                navigationState.isRadialMenuPresented
                    ? "Close quick entry menu"
                    : "Open quick entry menu"
            )
    }

    private func fabOption(_ kind: MetadataEntryKind) -> some View {
        let isHighlighted = navigationState.highlightedCaptureKind == kind

        return Button {
            SavyHapticFeedback.primaryImpact()
            withAnimation(SavyFabMenuMotion.close) {
                onSelectCaptureKind(kind)
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: kind.fabMenuSymbolName)
                    .font(.system(size: RootHomeLayout.radialMenuIconSize, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(
                        width: RootHomeLayout.radialMenuButtonSize,
                        height: RootHomeLayout.radialMenuButtonSize
                    )
                    .background(
                        isHighlighted ? SavyTheme.crimson : Brand.nearBlack,
                        in: Circle()
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                .white.opacity(isHighlighted ? 0.9 : 0.15),
                                lineWidth: 1.5
                            )
                    )
                    .scaleEffect(isHighlighted ? 1.15 : 1)

                Text(kind.menuTitle)
                    .font(.system(size: RootHomeLayout.radialMenuLabelSize, weight: .heavy))
                    .foregroundStyle(SavyTheme.crimson)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.menuTitle)
    }

    private func borderedSymbol(_ name: String) -> some View {
        ZStack {
            Image(systemName: name)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.black)
            Image(systemName: name)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func targetKind(for translation: CGSize) -> MetadataEntryKind? {
        guard hypot(translation.width, translation.height) > 30 else { return nil }
        let angle = atan2(-translation.height, translation.width) * 180 / .pi
        if angle >= 45 && angle < 135 { return .action }
        if angle >= -45 && angle < 45 { return .calendar }
        if angle >= 135 || angle < -135 { return .reminder }
        return nil
    }

    private func navigationButton(for section: SavyNavigationSection) -> some View {
        let isActive = navigationState.activeSection == section

        return Button {
            SavyHapticFeedback.selection()
            navigationState.activeSection = section
            withAnimation(SavyFabMenuMotion.close) {
                navigationState.dismissRadialMenu()
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 22, weight: isActive ? .semibold : .regular))

                Text(section.title)
                    .font(.system(size: RootHomeLayout.bottomNavigationLabelSize, weight: isActive ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(height: RootHomeLayout.bottomNavigationHeight - RootHomeLayout.bottomNavigationTopPadding)
            .foregroundStyle(isActive ? SavyTheme.crimson : inactiveColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
    }
}

struct MetadataComposerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: MetadataEntryKind
    let onSave: (MetadataEntry) throws -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var scheduledAt = Date()
    @State private var usesSchedule = true
    @State private var tagText = ""
    @State private var context = ""
    @State private var priority: MetadataEntryPriority = .medium
    @State private var cadence = ""
    @State private var notificationEnabled = false
    @State private var isShowingMoreMetadata = false
    @State private var validationMessage: String?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SavyTheme.deepNavy.ignoresSafeArea()

                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 96, height: 6)
                        .padding(.top, 12)
                        .padding(.bottom, 24)

                    header

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            capturePanel
                            schedulePanel
                            metadataPanel

                            if let message = validationMessage ?? saveError {
                                Text(message)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(SavyTheme.crimson)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button("Cancel") { dismiss() }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(panelBackground, in: Capsule())

            Text(kind.menuTitle)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Button("Save", action: save)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(SavyTheme.crimson, in: Capsule())
        }
        .padding(.horizontal, 20)
    }

    private var capturePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Capture")

            VStack(alignment: .leading, spacing: 14) {
                TextField(titlePlaceholder, text: $title, axis: .vertical)
                    .lineLimit(3, reservesSpace: false)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .tint(SavyTheme.crimson)

                Rectangle()
                    .fill(panelLine)
                    .frame(height: 1)

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .tint(SavyTheme.crimson)
            }
            .padding(22)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    @ViewBuilder
    private var schedulePanel: some View {
        if kind != .action {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(kind == .calendar ? "Calendar" : "Reminder")

                VStack(alignment: .leading, spacing: 18) {
                    Toggle("Schedule this entry", isOn: $usesSchedule)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .tint(SavyTheme.crimson)

                    if usesSchedule {
                        DatePicker("When", selection: $scheduledAt)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .tint(SavyTheme.crimson)
                    }
                }
                .padding(22)
                .background(panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var metadataPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Metadata")

            VStack(alignment: .leading, spacing: 18) {
                TextField("Tags or context labels", text: $tagText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .tint(SavyTheme.crimson)
                    .textInputAutocapitalization(.never)

                Rectangle()
                    .fill(panelLine)
                    .frame(height: 1)

                DisclosureGroup("More Metadata", isExpanded: $isShowingMoreMetadata) {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Behavioral context", text: $context)
                        Picker("Energy / Priority", selection: $priority) {
                            ForEach(MetadataEntryPriority.allCases) { priority in
                                Text(priority.title).tag(priority)
                            }
                        }
                        TextField("Cadence or recurrence intent", text: $cadence)
                        if kind != .action {
                            Toggle("Request notification scheduling", isOn: $notificationEnabled)
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .tint(SavyTheme.crimson)
                    .padding(.top, 14)
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .tint(SavyTheme.crimson)
            }
            .padding(22)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var panelBackground: Color {
        Color.white.opacity(0.10)
    }

    private var panelLine: Color {
        Color.white.opacity(0.12)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 30, weight: .heavy))
            .foregroundStyle(.white.opacity(0.54))
            .padding(.horizontal, 4)
    }

    private var titlePlaceholder: String {
        switch kind {
        case .reminder:
            "What should future you remember?"
        case .action:
            "What is the next move?"
        case .calendar:
            "What belongs on the calendar?"
        }
    }

    private func save() {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            validationMessage = "Add a title before saving."
            return
        }

        let entry = MetadataEntry(
            kind: kind,
            title: normalizedTitle,
            notes: notes,
            scheduledAt: usesSchedule && kind != .action ? scheduledAt : nil,
            tags: tagText
                .split(separator: ",")
                .map(String.init),
            context: context,
            priority: priority,
            cadence: cadence,
            syncState: .pendingSync
        )

        do {
            try onSave(entry)
            dismiss()
        } catch {
            saveError = "SAVY could not save locally. The sheet stayed open so this is not lost."
        }
    }
}
