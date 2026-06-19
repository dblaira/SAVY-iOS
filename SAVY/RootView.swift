import SwiftUI

enum RootHomeLayout {
    static let leverageGridColumnCount = 2
    static let leverageGridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 17),
        count: leverageGridColumnCount
    )
    static let horizontalPadding: CGFloat = 24
    static let heroTopPadding: CGFloat = 0
    static let heroHeight: CGFloat = 248
    static let heroContentTopPadding: CGFloat = 34
    static let heroWordmarkEyebrowSpacing: CGFloat = 10
    static let heroDividerHeight: CGFloat = 3
    static let heroWordmarkFontSize: CGFloat = 64
    static let heroEyebrowFontSize: CGFloat = 20
    static let carouselTopPadding: CGFloat = 20
    static let carouselHorizontalPadding: CGFloat = 2
    static let carouselCardWidth: CGFloat = 282
    static let carouselCardHeight: CGFloat = 236
    static let latestSectionBandHeight: CGFloat = 92
    static let pinnedEntryRowHeight: CGFloat = 81
    static let pinnedEntryTrailingInset: CGFloat = 17
    static let pinnedEntryFontSize: CGFloat = 32
    static let bottomNavigationHeight: CGFloat = 112
    static let bottomNavigationTopPadding: CGFloat = 24
    static let bottomNavigationIconSize: CGFloat = 28
    static let bottomNavigationLabelSize: CGFloat = 11
    static let bottomNavigationHorizontalPadding: CGFloat = 4
    static let floatingCaptureSize: CGFloat = 72
    static let floatingCaptureBackground = SavyTheme.deepNavy
    /// FAB center sits on the top edge of the bottom navigation bar.
    static var floatingCaptureCenterAboveBottom: CGFloat {
        bottomNavigationHeight
    }
    static var radialMenuBottomPadding: CGFloat {
        floatingCaptureCenterAboveBottom + (floatingCaptureSize / 2) + 10
    }
    static let radialMenuButtonSize: CGFloat = 66
    static let radialMenuIconSize: CGFloat = 29
    static let radialMenuLabelSize: CGFloat = 14
    static let accountMenuSymbolName = "line.3.horizontal"
    static let accountMenuTopPadding: CGFloat = 88
}

struct RootView: View {
    let onSignOut: (() -> Void)?
    @StateObject private var navigationState = SavyNavigationState()
    @StateObject private var leverageStore = LeverageDataStore()
    @StateObject private var metadataStore = MetadataEntryStore.live()
    @StateObject private var reminderStore = ReminderStore()

    init(onSignOut: (() -> Void)? = nil) {
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SavyTheme.paper.ignoresSafeArea()

                Group {
                    if navigationState.activeSection == .now {
                        EditorialHomeView(leverageStore: leverageStore)
                    } else if
                        let sectionID = navigationState.activeSection.leverageSectionID,
                        let section = leverageStore.section(id: sectionID)
                    {
                        LeverageSectionView(section: section)
                    } else {
                        EditorialHomeView(leverageStore: leverageStore)
                    }
                }
                .padding(.bottom, RootHomeLayout.bottomNavigationHeight + 8)

                SavyRadialFabMenu(
                    isPresented: navigationState.isRadialMenuPresented,
                    onDismiss: {
                        navigationState.dismissRadialMenu()
                    },
                    onSelect: { kind in
                        navigationState.openComposer(for: kind)
                    }
                )

                VStack(spacing: 0) {
                    Spacer()

                    ZStack(alignment: .top) {
                        SavyBottomNavigationBar(navigationState: navigationState)

                        SavyFloatingActionButton(isPresented: navigationState.isRadialMenuPresented) {
                            navigationState.toggleRadialMenu()
                        }
                        .offset(y: -RootHomeLayout.floatingCaptureSize / 2)
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                accountMenuButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $navigationState.activeComposerKind) { kind in
                reminderEntrySheet(for: kind)
            }
        }
    }

    /// Routes the radial "+" menu to the Re_Call entry forms and calendar, all backed by the
    /// shared `reminderStore`. Reminder/Action open the three-face form; Calendar opens the
    /// day-timeline calendar (which opens the form to edit an item).
    @ViewBuilder
    private func reminderEntrySheet(for kind: MetadataEntryKind) -> some View {
        switch kind {
        case .reminder:
            ReminderFormView(initialKind: .reminder, existing: nil, existingTags: reminderStore.recentTags) { reminder in
                reminderStore.save(reminder)
            }
        case .action:
            ReminderFormView(initialKind: .action, existing: nil, existingTags: reminderStore.recentTags) { reminder in
                reminderStore.save(reminder)
            }
        case .calendar:
            SavyCalendarScreen()
                .environmentObject(reminderStore)
        }
    }

    @ViewBuilder
    private var accountMenuButton: some View {
        if let onSignOut {
            VStack {
                HStack {
                    Spacer()

                    Menu {
                        Button("Sign Out", role: .destructive) {
                            onSignOut()
                        }
                    } label: {
                        Image(systemName: RootHomeLayout.accountMenuSymbolName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.78))
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.08), in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Account menu")
                }
                .padding(.horizontal, 24)
                .padding(.top, RootHomeLayout.accountMenuTopPadding)

                Spacer()
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}

struct EditorialHomeView: View {
    @ObservedObject var leverageStore: LeverageDataStore

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(topInset: proxy.safeAreaInsets.top)

                    contentSourceBand
                        .padding(.horizontal, RootHomeLayout.horizontalPadding)
                        .padding(.top, 12)

                    leverageCarousel
                        .padding(.top, RootHomeLayout.carouselTopPadding)

                    latestSection
                }
                .padding(.bottom, 40)
            }
            .ignoresSafeArea(edges: .top)
            .refreshable {
                await leverageStore.refresh()
            }
            .task(id: "gateway-sync") {
                await leverageStore.refresh()
            }
        }
        .background(SavyTheme.paper.ignoresSafeArea())
    }

    private var contentSourceBand: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(leverageStore.isLiveContent ? Color(red: 0.16, green: 0.72, blue: 0.35) : Color(red: 0.86, green: 0.45, blue: 0.12))
                    .frame(width: 8, height: 8)

                Text(leverageStore.status)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(leverageStore.isLiveContent ? SavyTheme.ink : SavyTheme.crimson)

                if leverageStore.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SavyTheme.crimson)
                }

                Spacer()
            }

            Text(leverageStore.statusDetail)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(leverageStore.isLiveContent ? Color(red: 0.16, green: 0.72, blue: 0.35).opacity(0.12) : Color(red: 0.86, green: 0.45, blue: 0.12).opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(leverageStore.status). \(leverageStore.statusDetail)")
    }

    private func header(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RootHomeLayout.heroWordmarkEyebrowSpacing) {
            Text("SAVY")
                .font(SavyTypography.bodoniModa(RootHomeLayout.heroWordmarkFontSize))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text("The Adam Pattern")
                .font(.system(size: RootHomeLayout.heroEyebrowFontSize, weight: .semibold))
                .foregroundStyle(SavyTheme.crimson)
        }
        .padding(.horizontal, RootHomeLayout.horizontalPadding)
        .padding(.top, topInset + RootHomeLayout.heroContentTopPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: RootHomeLayout.heroHeight,
            maxHeight: RootHomeLayout.heroHeight,
            alignment: .topLeading
        )
        .background(SavyTheme.deepNavy)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SavyTheme.crimson)
                .frame(height: RootHomeLayout.heroDividerHeight)
        }
    }

    private var leverageCarousel: some View {
        let quote = leverageStore.featuredQuote

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                principleCard(quote: quote)

                ForEach(HomeLeverageCard.referenceCards) { card in
                    if let section = leverageStore.section(id: card.sectionID) {
                        NavigationLink {
                            LeverageSectionView(section: section)
                        } label: {
                            HomeLeverageCardView(card: card, count: section.items.count)
                                .frame(
                                    width: RootHomeLayout.carouselCardWidth,
                                    height: RootHomeLayout.carouselCardHeight
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        HomeLeverageCardView(card: card, count: 0)
                            .frame(
                                width: RootHomeLayout.carouselCardWidth,
                                height: RootHomeLayout.carouselCardHeight
                            )
                    }
                }
            }
            .padding(.horizontal, RootHomeLayout.carouselHorizontalPadding)
        }
    }

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GREATEST LEVERAGE")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(SavyTheme.ink)
                .frame(maxWidth: .infinity, minHeight: RootHomeLayout.latestSectionBandHeight, alignment: .leading)
                .padding(.horizontal, 18)
                .background(SavyTheme.sectionBand)

            ForEach(HomePinnedEntry.referenceRows) { entry in
                HomePinnedEntryRow(entry: entry)
            }
        }
    }

    private func principleCard(quote: LeverageItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(SavyTheme.crimson)
                    .frame(width: 4, height: 74)

                Text("“\(quote.title.shortQuote)”")
                    .font(.system(size: 21, weight: .regular, design: .serif))
                    .italic()
                    .lineSpacing(4)
                    .foregroundStyle(SavyTheme.ink)
            }

            Text("FEATURED SIGNAL")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(.black.opacity(0.32))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(
            width: RootHomeLayout.carouselCardWidth,
            height: RootHomeLayout.carouselCardHeight,
            alignment: .leading
        )
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }
}

struct HomePinnedEntry: Identifiable {
    let id: String
    let title: String
    let alignment: Alignment

    static let referenceRows: [HomePinnedEntry] = [
        HomePinnedEntry(id: "top-pinned-entry", title: "Top Pinned entry", alignment: .leading),
        HomePinnedEntry(id: "second-top-pinned-entry", title: "2nd top Pinned entry", alignment: .center)
    ]
}

private struct HomePinnedEntryRow: View {
    let entry: HomePinnedEntry

    var body: some View {
        Text(entry.title)
            .font(.system(
                size: RootHomeLayout.pinnedEntryFontSize,
                weight: .regular,
                design: .serif
            ))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .frame(
                maxWidth: .infinity,
                minHeight: RootHomeLayout.pinnedEntryRowHeight,
                alignment: entry.alignment
            )
            .padding(.leading, entry.alignment == .leading ? 11 : 0)
            .background(SavyTheme.pinnedEntry)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.72))
                    .frame(height: 1)
            }
            .padding(.trailing, RootHomeLayout.pinnedEntryTrailingInset)
    }
}

struct HomeLeverageCard: Identifiable {
    let id: String
    let sectionID: String
    let eyebrow: String
    let title: String

    static let referenceCards: [HomeLeverageCard] = [
        HomeLeverageCard(id: "news", sectionID: "news-channel", eyebrow: "NEWS CHANNEL", title: "News\nChannel"),
        HomeLeverageCard(id: "essays", sectionID: "field-essays", eyebrow: "FIELD ESSAYS", title: "Field\nEssays"),
        HomeLeverageCard(id: "ontology", sectionID: "ontology", eyebrow: "ONTOLOGY", title: "Adam's\nOntology"),
        HomeLeverageCard(id: "beliefs", sectionID: "beliefs", eyebrow: "BELIEFS", title: "Belief\nLibrary")
    ]
}

private struct HomeLeverageCardView: View {
    let card: HomeLeverageCard
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack(spacing: 10) {
                Circle()
                    .fill(SavyTheme.green)
                    .frame(width: 10, height: 10)

                Text(card.eyebrow)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(.black.opacity(0.36))
            }

            Text(card.title)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .lineSpacing(-1)
                .foregroundStyle(SavyTheme.ink)

            Spacer(minLength: 0)

            Text("\(count) ITEMS")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.black.opacity(0.28))
        }
        .padding(.top, 28)
        .padding(.horizontal, 30)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

private struct LeverageSectionView: View {
    let section: LeverageSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.eyebrow)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2.4)
                        .foregroundStyle(SavyTheme.crimson)

                    Text(section.title)
                        .font(.system(size: 44, weight: .regular, design: .serif))
                        .italic(section.id == "beliefs" || section.id == "ontology")
                        .lineSpacing(2)
                        .foregroundStyle(SavyTheme.ink)

                    Text(section.summary)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(.black.opacity(0.58))
                        .padding(.top, 4)
                }
                .padding(.top, 34)

                VStack(alignment: .leading, spacing: 14) {
                    Text(section.headline)
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(SavyTheme.ink)

                    ForEach(section.items) { item in
                        NavigationLink {
                            LeverageDetailView(section: section, item: item)
                        } label: {
                            LeverageItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(SavyTheme.paper.ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LeverageItemRow: View {
    let item: LeverageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(SavyTheme.green)
                    .frame(width: 9, height: 9)

                Text(item.kicker)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.black.opacity(0.4))
            }

            Text(item.title)
                .font(SavyTheme.beliefSerif(25))
                .foregroundStyle(SavyTheme.ink)

            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(.black.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

private struct LeverageDetailView: View {
    let section: LeverageSection
    let item: LeverageItem

    @State private var graphTrace: BeliefGraphTraceResult?

    private var showsGraphTrace: Bool {
        section.id == "beliefs"
    }

    private var beliefHeroText: String {
        let body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            return body
        }
        return item.title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsGraphTrace {
                    beliefDetailContent
                } else {
                    genericDetailContent
                }
            }
            .padding(.horizontal, 25)
            .padding(.top, 34)
            .padding(.bottom, 54)
        }
        .background(SavyTheme.paper.ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) {
            guard showsGraphTrace else {
                graphTrace = nil
                return
            }
            graphTrace = await AWSGraphClient.beliefGraphTraceOrNil(entryId: item.id)
        }
    }

    @ViewBuilder
    private var beliefDetailContent: some View {
        Text(beliefHeroText)
            .font(SavyTheme.beliefSerif(30))
            .lineSpacing(8)
            .foregroundStyle(SavyTheme.ink)
            .fixedSize(horizontal: false, vertical: true)

        if let graphTrace {
            Rectangle()
                .fill(SavyTheme.crimson)
                .frame(height: 2)
                .padding(.top, 32)
                .padding(.bottom, 28)

            pathwaySection(graphTrace)
        }
    }

    @ViewBuilder
    private var genericDetailContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(item.kicker)
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .foregroundStyle(SavyTheme.crimson)

            Text(beliefHeroText)
                .font(SavyTheme.beliefSerif(30))
                .lineSpacing(8)
                .foregroundStyle(SavyTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            legacyDetailBody
        }
    }

    @ViewBuilder
    private var legacyDetailBody: some View {
        if !item.summary.isEmpty {
            Text(item.summary)
                .font(.system(size: 19, weight: .regular, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(.black.opacity(0.58))
        }

        if !item.body.isEmpty, item.body != item.title {
            Divider()
                .padding(.vertical, 4)

            Text(item.body)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .lineSpacing(7)
                .foregroundStyle(SavyTheme.ink)
        }
    }

    @ViewBuilder
    private func pathwaySection(_ result: BeliefGraphTraceResult) -> some View {
        if let trace = result.graphTrace, !trace.triplePaths.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pathway")
                    .font(SavyTheme.beliefSerif(42))
                    .foregroundStyle(SavyTheme.ink)

                ForEach(trace.triplePaths, id: \.axiomIri) { path in
                    pathwayCard(path)
                }
            }
        }
    }

    private func pathwayCard(_ path: BeliefGraphTraceTriplePath) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(pathwayKicker(path.relationshipType))
                .font(SavyTheme.beliefSerif(22))
                .foregroundStyle(SavyTheme.ink.opacity(0.62))

            Text(pathwayEffect(path))
                .font(SavyTheme.beliefSerif(28))
                .lineSpacing(7)
                .foregroundStyle(SavyTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(SavyTheme.pinnedEntry, in: RoundedRectangle(cornerRadius: 10))
    }

    private func pathwayKicker(_ relationshipType: String?) -> String {
        let normalized = relationshipType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ") ?? ""

        if normalized.isEmpty {
            return "Causes"
        }

        return normalized.prefix(1).uppercased() + normalized.dropFirst().lowercased()
    }

    private func pathwayEffect(_ path: BeliefGraphTraceTriplePath) -> String {
        let consequent = path.consequentLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !consequent.isEmpty {
            return consequent
        }

        return path.antecedentLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown pathway"
    }
}

struct NativeCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    var onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    TextField("What is worth preserving?", text: $title)
                    TextField("Why does it matter?", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Native by default") {
                    Label("Photos, location, notifications, widgets, and intents come next.", systemImage: "iphone")
                }
            }
            .navigationTitle("Capture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, note)
                        dismiss()
                    }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct NativeCapabilityRow: View {
    let capability: NativeCapability

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: capability.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SavyTheme.crimson)
                .frame(width: 34, height: 34)
                .background(SavyTheme.crimson.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(capability.title)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .foregroundStyle(SavyTheme.ink)

                Text(capability.description)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .foregroundStyle(.black.opacity(0.5))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct NativeCapability: Identifiable {
    let id: String
    let title: String
    let description: String
    let symbol: String

    static let initial: [NativeCapability] = [
        NativeCapability(
            id: "capture",
            title: "Native Capture",
            description: "SwiftUI form, keyboard, sheet, and state.",
            symbol: "square.and.pencil"
        ),
        NativeCapability(
            id: "notifications",
            title: "Notifications",
            description: "Local notifications and actions.",
            symbol: "bell.badge"
        ),
        NativeCapability(
            id: "context",
            title: "Context",
            description: "Photos, location, widgets, intents, and device-first features.",
            symbol: "sparkles"
        )
    ]
}

enum SavyTheme {
    static let deepNavy = Color(red: 8 / 255, green: 23 / 255, blue: 45 / 255)
    static let crimson = Color(red: 230 / 255, green: 14 / 255, blue: 68 / 255)
    static let green = Color(red: 42 / 255, green: 184 / 255, blue: 96 / 255)
    static let paper = Color(red: 248 / 255, green: 244 / 255, blue: 237 / 255)
    static let paperAccent = Color(red: 239 / 255, green: 235 / 255, blue: 228 / 255)
    static let sectionBand = Color(red: 244 / 255, green: 239 / 255, blue: 231 / 255)
    static let pinnedEntry = Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255)
    static let ink = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)

    static func beliefSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

private extension String {
    var shortQuote: String {
        let maxLength = 78
        guard count > maxLength else { return self }
        let index = self.index(startIndex, offsetBy: maxLength)
        return "\(self[..<index])..."
    }
}

#Preview {
    RootView()
}
