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
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

struct SavyBottomNavigationBar: View {
    @ObservedObject var navigationState: SavyNavigationState
    private let barBackground = Color(red: 0.80, green: 0.70, blue: 0.58)
    private let inactiveColor = Color(red: 0.34, green: 0.27, blue: 0.21).opacity(0.68)

    private var leadingSections: [SavyNavigationSection] {
        Array(SavyNavigationSection.allCases.prefix(2))
    }

    private var trailingSections: [SavyNavigationSection] {
        Array(SavyNavigationSection.allCases.suffix(2))
    }

    var body: some View {
        ZStack(alignment: .top) {
            barBackground

            HStack(alignment: .top, spacing: 0) {
                ForEach(leadingSections) { section in
                    navigationButton(for: section)
                }

                Spacer()
                    .frame(maxWidth: .infinity)

                ForEach(trailingSections) { section in
                    navigationButton(for: section)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(height: 1)
        }
        .frame(height: RootHomeLayout.bottomNavigationHeight)
        .background(barBackground.ignoresSafeArea(edges: .bottom))
    }

    private func navigationButton(for section: SavyNavigationSection) -> some View {
        Button {
            SavyHapticFeedback.selection()
            navigationState.activeSection = section
            navigationState.dismissRadialMenu()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: section.symbolName)
                    .font(.system(
                        size: RootHomeLayout.bottomNavigationIconSize,
                        weight: navigationState.activeSection == section ? .heavy : .bold
                    ))

                Text(section.title)
                    .font(.system(size: RootHomeLayout.bottomNavigationLabelSize, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: RootHomeLayout.bottomNavigationHeight - 18)
            .foregroundStyle(navigationState.activeSection == section ? SavyTheme.crimson : inactiveColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
    }
}

struct SavyRadialFabMenu: View {
    let isPresented: Bool
    let onDismiss: () -> Void
    let onSelect: (MetadataEntryKind) -> Void

    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }
                    .transition(.opacity)

                ZStack {
                    radialButton(kind: .reminder, x: -122, y: -94)
                    radialButton(kind: .action, x: 0, y: -148)
                    radialButton(kind: .calendar, x: 122, y: -94)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 118)
                .transition(.scale(scale: 0.78, anchor: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: isPresented)
    }

    private func radialButton(kind: MetadataEntryKind, x: CGFloat, y: CGFloat) -> some View {
        Button {
            SavyHapticFeedback.primaryImpact()
            onSelect(kind)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: RootHomeLayout.radialMenuIconSize, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(
                        width: RootHomeLayout.radialMenuButtonSize,
                        height: RootHomeLayout.radialMenuButtonSize
                    )
                    .background(SavyTheme.deepNavy, in: Circle())
                    .shadow(color: SavyTheme.deepNavy.opacity(0.24), radius: 12, y: 8)

                Text(kind.menuTitle)
                    .font(.system(size: RootHomeLayout.radialMenuLabelSize, weight: .heavy))
                    .foregroundStyle(SavyTheme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.94), in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .offset(x: x, y: y)
        .accessibilityLabel(kind.menuTitle)
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

struct SavyFloatingActionButton: View {
    let isPresented: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SavyHapticFeedback.primaryImpact()
            action()
        } label: {
            Image(systemName: isPresented ? "xmark" : "plus")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.white)
                .frame(
                    width: RootHomeLayout.floatingCaptureSize,
                    height: RootHomeLayout.floatingCaptureSize
                )
                .background(RootHomeLayout.floatingCaptureBackground, in: Circle())
                .shadow(color: SavyTheme.deepNavy.opacity(0.26), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPresented ? "Close quick entry menu" : "Open quick entry menu")
    }
}
