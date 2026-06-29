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
    static let carouselCardTitleFontSize: CGFloat = 24
    static let latestSectionBandHeight: CGFloat = 92
    static let pinnedEntryRowHeight: CGFloat = 96
    static let pinnedEntryTrailingInset: CGFloat = 17
    static let pinnedEntryFontSize: CGFloat = 24
    static let bottomNavigationHeight: CGFloat = 96
    /// Navy band painted above the tan bar (FAB overflow zone); does not add layout height.
    static let bottomNavNavyRiserHeight: CGFloat = 32
    static let bottomNavigationTopPadding: CGFloat = 14
    static let bottomNavigationIconSize: CGFloat = 36
    static let bottomNavigationLabelSize: CGFloat = 11
    static let bottomNavigationHorizontalPadding: CGFloat = 4
    static let floatingCaptureSize: CGFloat = 64
    static var floatingCaptureBackground: Color { SavyTheme.crimson }
    /// FAB center sits on the top edge of the bottom navigation bar.
    static var floatingCaptureCenterAboveBottom: CGFloat {
        bottomNavigationHeight
    }
    static var radialMenuBottomPadding: CGFloat {
        floatingCaptureCenterAboveBottom + (floatingCaptureSize / 2) + 10
    }
    static let radialMenuButtonSize: CGFloat = 56
    static let radialMenuIconSize: CGFloat = 20
    static let radialMenuLabelSize: CGFloat = 12
    static let accountMenuSymbolName = "line.3.horizontal"
    static let accountMenuButtonSize: CGFloat = 42
    static let accountMenuTopPadding: CGFloat = 88

    /// Nudges the menu down to the optical center of the SAVY wordmark cap height.
    static var accountMenuHeroWordmarkOffset: CGFloat {
        ((heroWordmarkFontSize - accountMenuButtonSize) * 0.42) + 5
    }
}

struct RootView: View {
    let session: AuthSession
    let onSignOut: (() -> Void)?
    @StateObject private var navigationState: SavyNavigationState
    @StateObject private var leverageStore = LeverageDataStore()
    @StateObject private var metadataStore = MetadataEntryStore.live()
    @StateObject private var reminderStore: ReminderStore

    init(
        session: AuthSession,
        onSignOut: (() -> Void)? = nil,
        initialSection: SavyNavigationSection = .now
    ) {
        self.session = session
        self.onSignOut = onSignOut
        let navigationState = SavyNavigationState()
        navigationState.activeSection = initialSection
        _navigationState = StateObject(wrappedValue: navigationState)
        _reminderStore = StateObject(
            wrappedValue: ReminderStore(
                repo: GatewayReminderRepository(
                    accessToken: { session.accessToken },
                    userEmail: { session.user.displayEmail }
                )
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SavyTheme.paper.ignoresSafeArea()

                Group {
                    switch navigationState.activeSection {
                    case .now:
                        EditorialHomeView(
                            leverageStore: leverageStore,
                            reminderStore: reminderStore,
                            onSignOut: onSignOut
                        )
                    case .reminders:
                        SavyReminderKindTabScreen(kind: .reminder)
                            .environmentObject(reminderStore)
                    case .actions:
                        SavyReminderKindTabScreen(kind: .action)
                            .environmentObject(reminderStore)
                    case .calendar:
                        SavyCalendarTabScreen()
                            .environmentObject(reminderStore)
                    }
                }
                .padding(.bottom, RootHomeLayout.bottomNavigationHeight + 8)

                if navigationState.isRadialMenuPresented {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            SavyHapticFeedback.menuClose()
                            withAnimation(SavyFabMenuMotion.close) {
                                navigationState.dismissRadialMenu()
                            }
                        }
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    Spacer()

                    SavyBottomNavigationBar(
                        navigationState: navigationState,
                        onSelectCaptureKind: { kind in
                            navigationState.openComposer(for: kind)
                        }
                    )
                }
                .ignoresSafeArea(edges: .bottom)

                if navigationState.activeSection != .now {
                    accountMenuButton
                }
            }
            .animation(SavyFabMenuMotion.open, value: navigationState.isRadialMenuPresented)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $navigationState.activeComposerKind) { kind in
                reminderEntrySheet(for: kind)
            }
            .task {
                await reminderStore.bootstrap()
            }
        }
    }

    /// Routes the radial "+" menu to the shared Re_Call-style entry form, backed by the
    /// shared `reminderStore`. The output tabs stay separate; entry stays identical.
    @ViewBuilder
    private func reminderEntrySheet(for kind: MetadataEntryKind) -> some View {
        switch kind {
        case .reminder:
            ReminderFormView(initialKind: .reminder, existing: nil, existingTags: reminderStore.recentTags) { reminder in
                reminderStore.save(reminder)
                navigationState.activeSection = .reminders
            }
        case .action:
            ReminderFormView(initialKind: .action, existing: nil, existingTags: reminderStore.recentTags) { reminder in
                reminderStore.save(reminder)
                navigationState.activeSection = .actions
            }
        case .calendar:
            ReminderFormView(initialKind: .event, existing: nil, existingTags: reminderStore.recentTags) { reminder in
                reminderStore.save(reminder)
                navigationState.activeSection = .calendar
            }
        }
    }

    @ViewBuilder
    private var accountMenuButton: some View {
        if let onSignOut {
            VStack {
                HStack {
                    Spacer()
                    SavyAccountMenuButton(onSignOut: onSignOut, lightForeground: false)
                }
                .padding(.horizontal, 24)
                Spacer()
            }
            .safeAreaPadding(.top, 12)
        }
    }
}

struct EditorialHomeView: View {
    @ObservedObject var leverageStore: LeverageDataStore
    @ObservedObject var reminderStore: ReminderStore
    let onSignOut: (() -> Void)?

    private var feedRows: [HomeFeedRow] {
        HomeFeedRow.rows(
            reminderStore: reminderStore,
            leverageStore: leverageStore,
            limit: 4
        )
    }
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(topInset: proxy.safeAreaInsets.top)

                    leverageCarousel
                        .padding(.top, RootHomeLayout.carouselTopPadding)

                    latestSection

                    contentSourceBand
                        .padding(.horizontal, RootHomeLayout.horizontalPadding)
                        .padding(.top, 24)
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
        .background(Color.white.ignoresSafeArea())
    }

    private var contentSourceBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(leverageStore.isLiveContent ? Color(red: 0.16, green: 0.72, blue: 0.35) : Color(red: 0.86, green: 0.45, blue: 0.12))
                    .frame(width: 8, height: 8)

                Text(leverageStore.status)
                    .font(SavyTheme.readingLabel(13))
                    .foregroundStyle(leverageStore.isLiveContent ? SavyTheme.ink : SavyTheme.crimson)

                if leverageStore.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SavyTheme.crimson)
                }

                Spacer()
            }

            Text(leverageStore.statusDetail)
                .font(SavyTheme.readingBody(13))
                .foregroundStyle(SavyTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Capture: \(reminderStore.syncStatusLabel)")
                .font(SavyTheme.readingBody(13))
                .foregroundStyle(SavyTheme.secondaryText)
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
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: RootHomeLayout.heroWordmarkEyebrowSpacing) {
                Text("SAVY")
                    .font(SavyTypography.displaySerif(RootHomeLayout.heroWordmarkFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text("The Adam Pattern")
                    .font(SavyTheme.readingLabel(RootHomeLayout.heroEyebrowFontSize))
                    .foregroundStyle(SavyTheme.bottomNavTan)
            }

            Spacer(minLength: 0)

            if let onSignOut {
                SavyAccountMenuButton(onSignOut: onSignOut)
                    .padding(.top, RootHomeLayout.accountMenuHeroWordmarkOffset)
            }
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
                .font(SavyTheme.readingLabel(20))
                .foregroundStyle(SavyTheme.ink)
                .frame(maxWidth: .infinity, minHeight: RootHomeLayout.latestSectionBandHeight, alignment: .leading)
                .padding(.horizontal, 18)
                .background(Color.white)

            ForEach(feedRows) { entry in
                HomeFeedRowView(entry: entry)
            }
        }
    }

    private func principleCard(quote: LeverageItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(SavyTheme.crimson)
                    .frame(width: 4, height: 74)

                Text("“\(quote.title)”")
                    .font(SavyTheme.carouselCardTitle(22))
                    .lineSpacing(3)
                    .foregroundStyle(SavyTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("FEATURED SIGNAL")
                .font(SavyTheme.readingLabel(12))
                .tracking(1.8)
                .foregroundStyle(SavyTheme.tertiaryText)
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

struct HomeFeedRow: Identifiable {
    enum Kind {
        case pinnedReminder
        case leverageBelief
    }

    let id: String
    let title: String
    let subtitle: String?
    let alignment: Alignment
    let kind: Kind

    @MainActor
    static func rows(
        reminderStore: ReminderStore,
        leverageStore: LeverageDataStore,
        limit: Int = 4
    ) -> [HomeFeedRow] {
        var rows: [HomeFeedRow] = []

        for (index, reminder) in reminderStore.pinnedFeed.prefix(limit).enumerated() {
            rows.append(
                HomeFeedRow(
                    id: reminder.id.uuidString,
                    title: reminder.title.isEmpty ? reminder.kind.label : reminder.title,
                    subtitle: reminder.whenLabel,
                    alignment: index.isMultiple(of: 2) ? .leading : .center,
                    kind: .pinnedReminder
                )
            )
        }

        if rows.count < limit {
            for (offset, item) in leverageStore.greatestLeverageItems(limit: limit - rows.count).enumerated() {
                let index = rows.count + offset
                rows.append(
                    HomeFeedRow(
                        id: item.id,
                        title: item.title,
                        subtitle: item.kicker,
                        alignment: index.isMultiple(of: 2) ? .leading : .center,
                        kind: .leverageBelief
                    )
                )
            }
        }

        return rows
    }
}

private struct HomeFeedRowView: View {
    let entry: HomeFeedRow

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 8) {
            Text(entry.title)
                .font(SavyTheme.carouselCardTitle(RootHomeLayout.pinnedEntryFontSize))
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .foregroundStyle(SavyTheme.ink)
                .frame(maxWidth: .infinity, alignment: entry.alignment)

            if let subtitle = entry.subtitle, !subtitle.isEmpty {
                Text(subtitle.uppercased())
                    .font(SavyTheme.readingLabel(12))
                    .tracking(1.4)
                    .foregroundStyle(SavyTheme.crimson)
                    .frame(maxWidth: .infinity, alignment: entry.alignment)
            }
        }
        .padding(.horizontal, RootHomeLayout.pinnedEntryTrailingInset)
        .padding(.vertical, 16)
        .frame(
            maxWidth: .infinity,
            minHeight: RootHomeLayout.pinnedEntryRowHeight,
            alignment: .top
        )
        .background(Brand.card)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch entry.alignment {
        case .center:
            return .center
        case .trailing:
            return .trailing
        default:
            return .leading
        }
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
        HomeLeverageCard(id: "news", sectionID: "news-channel", eyebrow: "NEWS CHANNEL", title: "News Channel"),
        HomeLeverageCard(id: "essays", sectionID: "field-essays", eyebrow: "FIELD ESSAYS", title: "Field Essays"),
        HomeLeverageCard(id: "ontology", sectionID: "ontology", eyebrow: "ONTOLOGY", title: "Adam's Ontology"),
        HomeLeverageCard(id: "beliefs", sectionID: "beliefs", eyebrow: "CONNECTION", title: "Connection")
    ]
}

private struct HomeLeverageCardView: View {
    let card: HomeLeverageCard
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            Text(card.eyebrow)
                .font(SavyTheme.readingLabel(12))
                .tracking(1.8)
                .foregroundStyle(SavyTheme.secondaryText)

            Text(card.title)
                .font(SavyTheme.carouselCardTitle())
                .lineSpacing(3)
                .foregroundStyle(SavyTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text("\(count) ITEMS")
                .font(SavyTheme.readingLabel(12))
                .tracking(1.4)
                .foregroundStyle(SavyTheme.tertiaryText)
        }
        .padding(.top, 28)
        .padding(.horizontal, 30)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

private enum NewsChannelLayout {
    static let horizontalPadding: CGFloat = 24
    static let carouselCardWidth: CGFloat = 220
    static let carouselImageHeight: CGFloat = 148
    static let sectionLabelTracking: CGFloat = 1.8
}

private struct NewsChannelView: View {
    let section: LeverageSection

    private var pinnedItem: LeverageItem? {
        section.items.first
    }

    private var carouselItems: [LeverageItem] {
        guard section.items.count > 1 else { return [] }
        let endIndex = min(section.items.count, 5)
        return Array(section.items[1..<endIndex])
    }

    private var moreStories: [LeverageItem] {
        guard section.items.count > 5 else { return [] }
        return Array(section.items.dropFirst(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(section.title)
                    .font(.system(size: 44, weight: .regular, design: .serif))
                    .lineSpacing(2)
                    .foregroundStyle(SavyTheme.ink)
                    .padding(.top, 34)

                if let pinnedItem {
                    NavigationLink {
                        LeverageDetailView(section: section, item: pinnedItem)
                    } label: {
                        NewsPinnedStoryCard(item: pinnedItem)
                    }
                    .buttonStyle(.plain)
                }

                if !carouselItems.isEmpty {
                    newsSectionLabel("Latest Stories")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(carouselItems) { item in
                                NavigationLink {
                                    LeverageDetailView(section: section, item: item)
                                } label: {
                                    NewsCarouselCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, NewsChannelLayout.horizontalPadding)
                    }
                    .padding(.horizontal, -NewsChannelLayout.horizontalPadding)
                }

                if !moreStories.isEmpty {
                    newsSectionLabel("More Stories")

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(moreStories) { item in
                            NavigationLink {
                                LeverageDetailView(section: section, item: item)
                            } label: {
                                NewsMoreStoryRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, NewsChannelLayout.horizontalPadding)
            .padding(.bottom, 48)
        }
        .background(Color.white.ignoresSafeArea())
    }

    private func newsSectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(NewsChannelLayout.sectionLabelTracking)
            .foregroundStyle(.black.opacity(0.42))
    }
}

private struct NewsPinnedStoryCard: View {
    let item: LeverageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title)
                .font(SavyTheme.beliefSerif(25))
                .foregroundStyle(SavyTheme.ink)

            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(SavyTheme.readingBody(15))
                    .lineSpacing(3)
                    .foregroundStyle(SavyTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NewsCarouselCard: View {
    let item: LeverageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            newsImage

            if let category = item.category, !category.isEmpty {
                Text(category.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(SavyTheme.crimson)
            }

            Text(item.title)
                .font(SavyTheme.beliefSerif(20))
                .foregroundStyle(SavyTheme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !item.kicker.isEmpty {
                Text(item.kicker)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.black.opacity(0.42))
            }
        }
        .frame(width: NewsChannelLayout.carouselCardWidth, alignment: .leading)
        .padding(12)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var newsImage: some View {
        Group {
            if let imageName = item.imageName, !imageName.isEmpty {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SavyTheme.paperAccent)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.black.opacity(0.18))
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: NewsChannelLayout.carouselImageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct NewsMoreStoryRow: View {
    let item: LeverageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let category = item.category, !category.isEmpty {
                Text(category.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(SavyTheme.crimson)
            }

            Text(item.title)
                .font(SavyTheme.beliefSerif(22))
                .foregroundStyle(SavyTheme.ink)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct LeverageSectionView: View {
    let section: LeverageSection

    private var isBeliefs: Bool { section.id == "beliefs" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isBeliefs {
                    Text(section.title)
                        .font(SavyTypography.bodoniModa(44, weight: 400, opticalSize: 48))
                        .lineSpacing(2)
                        .foregroundStyle(SavyTheme.ink)
                        .padding(.top, 34)

                    Text(section.headline)
                        .font(SavyTypography.bodoniModa(24, weight: 400, opticalSize: 24))
                        .foregroundStyle(SavyTheme.ink)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.eyebrow)
                            .font(.system(size: 12, weight: .bold))
                            .tracking(2.4)
                            .foregroundStyle(SavyTheme.crimson)

                        Text(section.title)
                            .font(.system(size: 44, weight: .regular, design: .serif))
                            .italic(section.id == "ontology")
                            .lineSpacing(2)
                            .foregroundStyle(SavyTheme.ink)

                        Text(section.summary)
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .lineSpacing(5)
                            .foregroundStyle(.black.opacity(0.58))
                            .padding(.top, 4)
                    }
                    .padding(.top, 34)

                    Text(section.headline)
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(SavyTheme.ink)
                }

                VStack(alignment: .leading, spacing: isBeliefs ? 10 : 14) {
                    ForEach(section.items) { item in
                        NavigationLink {
                            LeverageDetailView(section: section, item: item)
                        } label: {
                            LeverageItemRow(item: item, isBeliefs: isBeliefs)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background((isBeliefs ? Color.white : SavyTheme.paper).ignoresSafeArea())
    }
}

private struct LeverageItemRow: View {
    let item: LeverageItem
    var isBeliefs = false

    var body: some View {
        Group {
            if isBeliefs {
                Text(item.title)
                    .font(SavyTypography.robotoMedium(22))
                    .lineSpacing(2)
                    .foregroundStyle(SavyTheme.crimson)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            } else {
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
            }
        }
        .background(
            isBeliefs ? SavyTheme.beliefCard : .white,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .shadow(color: .black.opacity(isBeliefs ? 0 : 0.04), radius: 10, y: 4)
    }
}

struct LeverageDetailView: View {
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
    static let beliefCard = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let connectionBand = Color(red: 0.93, green: 0.90, blue: 0.85)
    static let sectionBand = Color(red: 244 / 255, green: 239 / 255, blue: 231 / 255)
    static let pinnedEntry = Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255)
    static let ink = Color.black
    static let bottomNavTan = Color(red: 0.80, green: 0.70, blue: 0.58)
    static let secondaryText = Color.black.opacity(0.62)
    static let tertiaryText = Color.black.opacity(0.45)

    /// Editorial serif — bold by default, matching Notorious Recall's `Brand.serif`.
    static func displaySerif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        SavyTypography.displaySerif(size, weight: weight)
    }

    /// Primary titles on light surfaces — semibold sans; section headers use `readingLabel`.
    static func readingTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func readingBody(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func readingLabel(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy)
    }

    /// Home leverage carousel cards — Times New Roman at the same optical size as reading titles.
    static func carouselCardTitle(_ size: CGFloat = RootHomeLayout.carouselCardTitleFontSize) -> Font {
        SavyTypography.timesNewRoman(size)
    }

    static func beliefSerif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        displaySerif(size, weight: weight)
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
    RootView(
        session: AuthSession(
            accessToken: "preview",
            refreshToken: "preview",
            tokenType: "bearer",
            expiresIn: 3600,
            user: AuthUser(id: "preview-user", email: "adam@example.com")
        )
    )
}
