import SwiftUI

enum RootHomeLayout {
    static let leverageGridColumnCount = 2
    static let leverageGridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 17),
        count: leverageGridColumnCount
    )
    static let horizontalPadding: CGFloat = 24
    static let heroTopPadding: CGFloat = 0
    static let heroHeight: CGFloat = 204
    static let heroContentTopPadding: CGFloat = 34
    static let heroDividerHeight: CGFloat = 1
    static let heroWordmarkFontSize: CGFloat = 64
    static let carouselHorizontalPadding: CGFloat = 2
    static let carouselTopPadding: CGFloat = 24
    static let carouselBottomPadding: CGFloat = 24
    static let carouselCardWidth: CGFloat = 282
    static let carouselCardHeight: CGFloat = 140
    static let carouselCardTitleFontSize: CGFloat = 24
    static let latestSectionBandHeight: CGFloat = 80
    static let pinnedEntryRowHeight: CGFloat = 96
    static let pinnedEntryTrailingInset: CGFloat = 17
    static let pinnedEntryFontSize: CGFloat = 24
    static let homeBandCardSpacing: CGFloat = 10
    static let homeBandTopPadding: CGFloat = 14
    /// Leave the summit visible between the carousel and the destination cards.
    static let homeLandscapeRevealHeight: CGFloat = 80
    static let homeBandBottomPadding: CGFloat = 16
    static let homeBandHorizontalPadding: CGFloat = 16
    static let homeBandCardCornerRadius: CGFloat = 8
    static let bottomNavigationHeight: CGFloat = 128
    /// Navy band painted above the tan bar (FAB overflow zone); does not add layout height.
    static let bottomNavNavyRiserHeight: CGFloat = 44
    static let bottomNavigationTopPadding: CGFloat = 8
    static let bottomNavigationBottomPadding: CGFloat = 28
    static let bottomNavigationIconSize: CGFloat = 25
    static let bottomNavigationIconWeight: Font.Weight = .regular
    static let bottomNavigationLabelSize: CGFloat = 15
    static let bottomNavigationIconLabelSpacing: CGFloat = 7
    static let bottomNavigationHorizontalPadding: CGFloat = 0
    static let floatingCaptureSize: CGFloat = 64
    static let floatingCaptureSymbolOuterSize: CGFloat = 30
    static let floatingCaptureSymbolInnerSize: CGFloat = 25
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
    @StateObject private var postStore: SocialPostStore
    @StateObject private var postCardOrder = PostCardOrderStore()
    @StateObject private var connectionStore = ConnectionStore()
    @StateObject private var storyStore: StoryStore
    @State private var isPersonalAuthorityReviewPresented = false
    @State private var isPostsPresented = false
    @State private var opensPostsAfterComposer = false

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
        let loadedPostStore: SocialPostStore
        let loadedReminderStore: ReminderStore
        let numberLedgerURL: URL
        if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_UNLOCKED") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SAVYUITests", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_RESET_REMINDERS") {
                for name in ["posts.json", "stories.json", "captures.json", "outbox.json", "post-numbers.json"] {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                }
            }
            loadedPostStore = try! SocialPostStore(fileURL: directory.appendingPathComponent("posts.json"))
            _storyStore = StateObject(wrappedValue: try! StoryStore(fileURL: directory.appendingPathComponent("stories.json")))
            loadedReminderStore = ReminderStore(
                repo: LocalReminderRepository(),
                cacheURL: directory.appendingPathComponent("reminders.json"),
                technicalCaptureStore: try! TechnicalCaptureStore(fileURL: directory.appendingPathComponent("captures.json")),
                candidateOutbox: try! CowboyCandidateOutbox(fileURL: directory.appendingPathComponent("outbox.json")),
                candidateClient: IsolatedUITestCandidateClient()
            )
            if let count = Int(ProcessInfo.processInfo.environment["SAVY_UI_TEST_SEED_POST_COUNT"] ?? "") {
                loadedReminderStore.seedPostsForUITesting(count: count)
            }
            numberLedgerURL = directory.appendingPathComponent("post-numbers.json")
        } else {
            loadedPostStore = SocialPostStore.live()
            _storyStore = StateObject(wrappedValue: StoryStore.live())
            loadedReminderStore = ReminderStore(
                repo: GatewayReminderRepository(
                    accessToken: { session.accessToken },
                    userEmail: { session.user.displayEmail }
                )
            )
            numberLedgerURL = PostNumberAllocator.defaultFileURL
        }
        // Both formats participate in the initial chronological sequence. A damaged ledger
        // is left intact rather than replaced with a sequence that could reuse references.
        if let allocator = try? PostNumberAllocator(fileURL: numberLedgerURL) {
            allocator.seed(reminders: loadedReminderStore.reminders, socialPosts: loadedPostStore.posts)
            loadedReminderStore.configurePostNumbering(allocator)
            loadedPostStore.configurePostNumbering(allocator)
        }
        _postStore = StateObject(wrappedValue: loadedPostStore)
        _reminderStore = StateObject(wrappedValue: loadedReminderStore)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                (navigationState.activeSection == .now ? SavyTheme.deepNavy : SavyTheme.pageBackground)
                    .ignoresSafeArea()

                Group {
                    switch navigationState.activeSection {
                    case .now:
                        EditorialHomeView(
                            leverageStore: leverageStore,
                            reminderStore: reminderStore,
                            postStore: postStore,
                            postCardOrder: postCardOrder,
                            storyStore: storyStore,
                            connectionStore: connectionStore,
                            onSignOut: onSignOut,
                            onOpenPersonalAuthorityReview: {
                                isPersonalAuthorityReviewPresented = true
                            }
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
                .padding(.bottom, RootHomeLayout.bottomNavigationHeight)

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
            .sheet(item: $navigationState.activeComposerKind, onDismiss: {
                // Push the Posts screen only once the composer is gone, so the push is not
                // swallowed by the sheet's own dismissal.
                if opensPostsAfterComposer {
                    opensPostsAfterComposer = false
                    isPostsPresented = true
                }
            }) { kind in
                reminderEntrySheet(for: kind)
            }
            .fullScreenCover(isPresented: $isPersonalAuthorityReviewPresented) {
                PersonalAuthorityReviewView()
            }
            .navigationDestination(isPresented: $isPostsPresented) {
                // Posts live on the Social Media Posts page.
                LeverageSectionView(
                    section: leverageStore.section(id: "news-channel") ?? LeverageContent.newsChannel,
                    postStore: postStore,
                    storyStore: storyStore,
                    reminderStore: reminderStore,
                    postCardOrder: postCardOrder
                )
            }
            .task {
                await reminderStore.bootstrap()
            }
        }
        .savySolidTopScrollEdge()
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
        case .post:
            // Adam approved the Post mockup on the Reminder form path (2026-09-13: "That looks
            // good. Let's build that.") — Post is the fourth face of the same entry form.
            // Nothing posts on its own; saved entries land on the Social Media Posts page.
            ReminderFormView(initialKind: .post, existing: nil, existingTags: reminderStore.recentTags) { reminder in
                reminderStore.save(reminder)
                opensPostsAfterComposer = true
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
        VStack {
            HStack {
                Spacer()
                SavyAccountMenuButton(
                    onSignOut: onSignOut,
                    onOpenPersonalAuthorityReview: {
                        isPersonalAuthorityReviewPresented = true
                    },
                    appearance: .onDarkHero
                )
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .safeAreaPadding(.top, 10)
        .zIndex(20)
    }
}

private struct IsolatedUITestCandidateClient: CowboyCandidateSubmitting {
    func submit(_ payload: CowboyCandidateIntakePayload) async throws -> CowboyCandidateReceipt {
        throw URLError(.notConnectedToInternet)
    }
}

struct EditorialHomeView: View {
    @ObservedObject var leverageStore: LeverageDataStore
    @ObservedObject var reminderStore: ReminderStore
    @ObservedObject var postStore: SocialPostStore
    @ObservedObject var postCardOrder: PostCardOrderStore
    @ObservedObject var storyStore: StoryStore
    @ObservedObject var connectionStore: ConnectionStore
    let onSignOut: (() -> Void)?
    let onOpenPersonalAuthorityReview: () -> Void
    @State private var editingReminder: Reminder?
    @StateObject private var sectionPinStore = HomeSectionPinStore()
    @State private var armedHomeCardID: String?
    @State private var selectedHomeCard: HomeLeverageCard?

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

                    VStack(alignment: .leading, spacing: 0) {
                        homeCarousel

                        Color.clear
                            .frame(height: RootHomeLayout.homeLandscapeRevealHeight)
                            .accessibilityHidden(true)

                        homeContentSections

                        contentSourceBand
                            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.horizontal, RootHomeLayout.horizontalPadding)
                            .padding(.top, 24)
                    }
                    .padding(.bottom, 40)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(0, proxy.size.height + proxy.safeAreaInsets.top - RootHomeLayout.heroHeight),
                        alignment: .top
                    )
                    .background {
                        GeometryReader { landscape in
                            Image("HomeMountainLandscape")
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: landscape.size.width,
                                    height: proxy.size.height + proxy.safeAreaInsets.top
                                )
                                .clipped()
                                // Keep the crop independent of saved card count. Once the
                                // header scrolls away, the landscape stays behind the cards.
                                .offset(y: max(0, -landscape.frame(in: .named("homeLandscapeScroll")).minY))
                        }
                        .clipped()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
            }
            .coordinateSpace(name: "homeLandscapeScroll")
            .accessibilityIdentifier("editorialHomeScroll")
            .savyHeaderOverscrollCapture("home")
            .onScrollPhaseChange { _, phase in
                if phase == .interacting, armedHomeCardID != nil {
                    withAnimation(.snappy) { armedHomeCardID = nil }
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable {
                await leverageStore.refresh()
            }
            .task(id: "gateway-sync") {
                await leverageStore.refresh()
            }
        }
        .background(SavyTheme.deepNavy.ignoresSafeArea())
        .navigationDestination(item: $selectedHomeCard) { card in
            if let section = leverageStore.section(id: card.sectionID) {
                if section.id == "beliefs" {
                    ConnectionView(section: section, store: connectionStore)
                } else if section.id == "news-channel" {
                    LeverageSectionView(section: section, postStore: postStore, storyStore: storyStore, reminderStore: reminderStore, postCardOrder: postCardOrder)
                } else {
                    LeverageSectionView(section: section)
                }
            }
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderFormView(existing: reminder, existingTags: reminderStore.recentTags) { updated in
                reminderStore.save(updated)
            }
        }
    }

    private var contentSourceBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(leverageStore.isLiveContent ? Color(red: 0.16, green: 0.72, blue: 0.35) : Color(red: 0.86, green: 0.45, blue: 0.12))
                    .frame(width: 8, height: 8)

                Text(leverageStore.status)
                    .font(SavyTheme.readingLabel(13))
                    .foregroundStyle(leverageStore.isLiveContent ? SavyTheme.deepNavy : SavyTheme.crimson)

                if leverageStore.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SavyTheme.crimson)
                }

                Spacer()
            }

            Text(leverageStore.statusDetail)
                .font(SavyTheme.readingBody(13))
                .foregroundStyle(SavyTheme.deepNavy.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            Text("Capture: \(reminderStore.syncStatusLabel)")
                .font(SavyTheme.readingBody(13))
                .foregroundStyle(SavyTheme.deepNavy.opacity(0.72))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(leverageStore.isLiveContent ? Color(red: 0.16, green: 0.72, blue: 0.35).opacity(0.12) : Color(red: 0.86, green: 0.45, blue: 0.12).opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SavyTheme.deepNavy.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(leverageStore.status). \(leverageStore.statusDetail)")
    }

    private func header(topInset: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("SAVY")
                .font(SavyTypography.displaySerif(RootHomeLayout.heroWordmarkFontSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            if let onSignOut {
                SavyAccountMenuButton(
                    onSignOut: onSignOut,
                    onOpenPersonalAuthorityReview: onOpenPersonalAuthorityReview
                )
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

    private var homeCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(feedRows) { entry in
                    switch entry.source {
                    case let .reminder(reminder):
                        Button {
                            editingReminder = reminder
                        } label: {
                            HomeFeedRowView(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("greatestLeverageReminder")

                    case let .leverage(section, item):
                        NavigationLink {
                            LeverageDetailView(section: section, item: item)
                        } label: {
                            HomeFeedRowView(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("greatestLeverageEntry")
                    }
                }
            }
            .padding(.horizontal, RootHomeLayout.carouselHorizontalPadding)
            .padding(.top, RootHomeLayout.carouselTopPadding)
            .padding(.bottom, RootHomeLayout.carouselBottomPadding)
        }
        .accessibilityIdentifier("greatestLeverageCarousel")
    }

    private var homeContentSections: some View {
        let posts = SavedPost.displayed(store: postStore, reminderStore: reminderStore, cardOrder: postCardOrder)
        return VStack(alignment: .leading, spacing: RootHomeLayout.homeBandCardSpacing) {
            ForEach(Array(sectionPinStore.orderedCards().enumerated()), id: \.element.id) { index, card in
                let isPinned = sectionPinStore.isPinned(card.sectionID)
                let colors = Self.homeBandCardColors(for: index)
                SavyUpNextCardRow(
                    reminderId: card.sectionID,
                    armedId: $armedHomeCardID,
                    actions: [
                        SavySwipeAction(title: isPinned ? "Unpin" : "Pin", icon: "pin", bg: Brand.tileBlue) {
                            withAnimation(.snappy) { sectionPinStore.toggle(card.sectionID) }
                        },
                    ],
                    onTap: { selectedHomeCard = card },
                    onMoveUp: { withAnimation(.snappy) { sectionPinStore.move(card.sectionID, direction: .up) } },
                    onMoveDown: { withAnimation(.snappy) { sectionPinStore.move(card.sectionID, direction: .down) } },
                    gestureAccessibilityIdentifier: "homeReorder-\(card.sectionID)"
                ) {
                    HomeContentSectionView(
                        card: card,
                        section: leverageStore.section(id: card.sectionID),
                        posts: posts,
                        connections: connectionStore.entries,
                        hiddenConnectionIDs: connectionStore.hiddenSourceIDs,
                        isPinned: isPinned,
                        isReordering: armedHomeCardID == card.sectionID,
                        bg: colors.bg,
                        fg: colors.fg,
                        accent: colors.accent
                    )
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                }
                .zIndex(armedHomeCardID == card.sectionID ? 1 : 0)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("homeContentSection-\(card.sectionID)")
                .accessibilityValue(isPinned ? "Pinned" : "Unpinned")
            }
        }
        .padding(.top, RootHomeLayout.homeBandTopPadding)
        .padding(.bottom, RootHomeLayout.homeBandBottomPadding)
        .padding(.horizontal, RootHomeLayout.homeBandHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Copied from Understood `ActionsHomeView.cardColors` / `SavyReminderScreens.cardColors`.
    private static func homeBandCardColors(for index: Int) -> (bg: Color, fg: Color, accent: Color) {
        switch index {
        case 0: return (.white, SavyTheme.deepNavy, SavyTheme.crimson)
        case 1: return (Brand.darkRed, .white, .white)
        default: return (SavyTheme.bottomNavTan, SavyTheme.deepNavy, SavyTheme.crimson)
        }
    }

}

struct HomeFeedRow: Identifiable {
    enum Source {
        case reminder(Reminder)
        case leverage(section: LeverageSection, item: LeverageItem)
    }

    let id: String
    let title: String
    let subtitle: String?
    let alignment: Alignment
    let source: Source

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
                    source: .reminder(reminder)
                )
            )
        }

        if rows.count < limit {
            for (offset, item) in leverageStore.greatestLeverageItems(limit: limit - rows.count).enumerated() {
                guard let section = leverageStore.sections.first(where: { section in
                    section.items.contains(where: { $0.id == item.id })
                }) else { continue }
                let index = rows.count + offset
                rows.append(
                    HomeFeedRow(
                        id: item.id,
                        title: item.title,
                        subtitle: item.kicker,
                        alignment: index.isMultiple(of: 2) ? .leading : .center,
                        source: .leverage(section: section, item: item)
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
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("greatestLeverageDate")
            }
        }
        .padding(.horizontal, RootHomeLayout.pinnedEntryTrailingInset)
        .padding(.vertical, 16)
        .frame(
            width: RootHomeLayout.carouselCardWidth,
            height: RootHomeLayout.carouselCardHeight,
            alignment: .topLeading
        )
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
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

struct HomeLeverageCard: Identifiable, Hashable {
    let id: String
    let sectionID: String
    let eyebrow: String
    let title: String

    static let referenceCards: [HomeLeverageCard] = [
        HomeLeverageCard(id: "beliefs", sectionID: "beliefs", eyebrow: "CONNECTION", title: "Connection"),
        HomeLeverageCard(id: "ontology", sectionID: "ontology", eyebrow: "ONTOLOGY", title: "Adam's Ontology"),
        HomeLeverageCard(id: "essays", sectionID: "field-essays", eyebrow: "FIELD ESSAYS", title: "Field Essays"),
        HomeLeverageCard(id: "news", sectionID: "news-channel", eyebrow: "SOCIAL MEDIA POSTS", title: "Social Media Posts")
    ]
}

/// Home destinations pin independently and retain their order within each pin group.
@MainActor
final class HomeSectionPinStore: ObservableObject {
    /// The original single-pin key remains readable for existing installations.
    static let defaultsKey = "savy.homePinnedSectionID"
    static let pinnedIDsDefaultsKey = "savy.homePinnedSectionIDs"
    static let orderDefaultsKey = "savy.homeSectionOrder"
    static let defaultPinnedSectionID = "news-channel"

    @Published private(set) var pinnedSectionIDs: Set<String>
    @Published private(set) var sectionOrder: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? SavyCardPreferences.defaults
        self.defaults = defaults
        sectionOrder = defaults.stringArray(forKey: Self.orderDefaultsKey) ?? []
        if let saved = defaults.stringArray(forKey: Self.pinnedIDsDefaultsKey) {
            pinnedSectionIDs = Set(saved)
        } else {
            let previous = defaults.string(forKey: Self.defaultsKey)
            if let previous, HomeLeverageCard.referenceCards.contains(where: { $0.sectionID == previous }) {
                pinnedSectionIDs = [previous]
            } else {
                pinnedSectionIDs = previous == nil ? [Self.defaultPinnedSectionID] : []
            }
            defaults.set(pinnedSectionIDs.sorted(), forKey: Self.pinnedIDsDefaultsKey)
        }
    }

    func isPinned(_ sectionID: String) -> Bool {
        pinnedSectionIDs.contains(sectionID)
    }

    func pin(_ sectionID: String) {
        guard pinnedSectionIDs.insert(sectionID).inserted else { return }
        defaults.set(pinnedSectionIDs.sorted(), forKey: Self.pinnedIDsDefaultsKey)
        moveToFrontOfPinGroup(sectionID)
    }

    func unpin(_ sectionID: String) {
        guard pinnedSectionIDs.remove(sectionID) != nil else { return }
        defaults.set(pinnedSectionIDs.sorted(), forKey: Self.pinnedIDsDefaultsKey)
        moveToFrontOfPinGroup(sectionID)
    }

    func toggle(_ sectionID: String) {
        if isPinned(sectionID) {
            unpin(sectionID)
        } else {
            pin(sectionID)
        }
    }

    func orderedCards() -> [HomeLeverageCard] {
        let reference = HomeLeverageCard.referenceCards
        var seen = Set<String>()
        let cards = (sectionOrder + reference.map(\.sectionID))
            .filter { seen.insert($0).inserted }
            .compactMap { id in reference.first { $0.sectionID == id } }
        return cards.filter { isPinned($0.sectionID) } + cards.filter { !isPinned($0.sectionID) }
    }

    private func moveToFrontOfPinGroup(_ sectionID: String) {
        var order = orderedCards().map(\.sectionID)
        guard order.contains(sectionID) else { return }
        order.removeAll { $0 == sectionID }
        let insertion = isPinned(sectionID) ? 0 : order.prefix { isPinned($0) }.count
        order.insert(sectionID, at: insertion)
        let visibleIDs = Set(order)
        sectionOrder = order + sectionOrder.filter { !visibleIDs.contains($0) }
        defaults.set(sectionOrder, forKey: Self.orderDefaultsKey)
    }

    /// Move one visible position without crossing the pinned/unpinned boundary.
    func move(_ sectionID: String, direction: ReminderStore.UpNextMoveDirection) {
        var cards = orderedCards()
        guard let index = cards.firstIndex(where: { $0.sectionID == sectionID }) else { return }
        let target = direction == .up ? index - 1 : index + 1
        guard cards.indices.contains(target),
              isPinned(cards[target].sectionID) == isPinned(sectionID) else { return }
        cards.swapAt(index, target)
        sectionOrder = cards.map(\.sectionID)
        defaults.set(sectionOrder, forKey: Self.orderDefaultsKey)
    }
}

private struct HomeContentSectionView: View {
    let card: HomeLeverageCard
    let section: LeverageSection?
    let posts: [SavedPost]
    var connections: [ConnectionEntry] = []
    var hiddenConnectionIDs: Set<String> = []
    var isPinned = false
    var isReordering = false
    let bg: Color
    let fg: Color
    let accent: Color
    var body: some View {
        SavyBandCard(
            bg: bg,
            fg: fg,
            accent: accent,
            title: card.title,
            signalText: isPinned ? countText : "",
            secondaryText: isPinned ? postReferences : "",
            detailLine: previewText,
            detail: isPinned ? .full : .minimal,
            isCompact: !isPinned,
            // The existing pair of reorder buttons needs its normal touch area only
            // while selected; the resting destination row stays compact.
            minimumHeight: isReordering ? 94 : nil,
            titleAccessibilityIdentifier: "homeCardTitle-\(card.sectionID)"
        ) {
            EmptyView()
        }
    }

    private var countText: String {
        if card.sectionID == "news-channel" { return "\(posts.count) / 50 saved posts" }
        let authoredCount = card.sectionID == "beliefs" ? connections.count : 0
        return "\(visibleItems.count + authoredCount) items"
    }

    private var postReferences: String {
        guard card.sectionID == "news-channel" else { return "" }
        let numbers = posts.prefix(3).compactMap(\.postNumber).map { "#\($0)" }
        return numbers.isEmpty ? "" : "Posts " + numbers.joined(separator: " · ")
    }

    private var previewText: String? {
        if card.sectionID == "news-channel" { return posts.first?.preview.title }
        if card.sectionID == "beliefs", !connections.isEmpty {
            return connections.prefix(3).map { $0.preview.title }.joined(separator: "\n")
        }
        return visibleItems.prefix(3).map(\.title).joined(separator: "\n")
    }

    private var visibleItems: [LeverageItem] {
        let items = section?.items ?? []
        return card.sectionID == "beliefs" ? items.filter { !hiddenConnectionIDs.contains($0.id) } : items
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
    @Environment(\.dismiss) private var dismiss
    @State private var postScrollRevision = 0
    let section: LeverageSection
    var postStore: SocialPostStore? = nil
    var storyStore: StoryStore? = nil
    var reminderStore: ReminderStore? = nil
    var postCardOrder: PostCardOrderStore? = nil

    private var isBeliefs: Bool { section.id == "beliefs" }
    private var isPosts: Bool { section.id == "news-channel" }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(section.title)
                        .font(SavyTypography.displaySerif(44, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
                        .background(SavyTheme.pageBackground)
                        .overlay(alignment: .bottom) {
                            if isPosts {
                                Rectangle().fill(SavyTheme.headerDivider).frame(height: RootHomeLayout.heroDividerHeight)
                            }
                        }
                        .padding(.horizontal, -24)
                        .accessibilityIdentifier(isPosts ? "socialMediaPostsHeader" : "sectionPageHeader")

                    if let postStore, let reminderStore, let postCardOrder {
                        NewsChannelPostsGroup(store: postStore, reminderStore: reminderStore, cardOrder: postCardOrder, scrollRevision: postScrollRevision)
                    }

                    if let storyStore {
                        // Adam: "Add a plus button to the Stories area of the News Channel page and
                        // have that open to different form."
                        NewsChannelStoriesGroup(store: storyStore)
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
                .savyHeaderPageContent(minHeight: viewport.size.height)
            }
            .savyHeaderOverscrollCapture(section.id)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { postScrollRevision += 1 }
            }
        }
        .background(SavyTheme.pageBackground.ignoresSafeArea())
        .toolbarBackground(SavyTheme.pageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(SavyTheme.crimson)
        .navigationBarBackButtonHidden(isPosts)
        .toolbar {
            if isPosts {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) { postsBackButton }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { postsBackButton }
                }
            }
        }
    }

    private var postsBackButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(SavyTheme.crimson)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("socialMediaPostsBack")
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
        .background(SavyTheme.contentBackground.ignoresSafeArea())
        .savyPageTitle(section.title)
        .toolbarBackground(SavyTheme.pageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(SavyTheme.crimson)
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
            .foregroundStyle(SavyTheme.deepNavy)
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
                .foregroundStyle(SavyTheme.deepNavy)
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
                .foregroundStyle(SavyTheme.deepNavy.opacity(0.72))
        }

        if !item.body.isEmpty, item.body != item.title {
            Rectangle().fill(SavyTheme.deepNavy.opacity(0.2)).frame(height: 1)
                .padding(.vertical, 4)

            Text(item.body)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .lineSpacing(7)
                .foregroundStyle(SavyTheme.deepNavy)
        }
    }

    @ViewBuilder
    private func pathwaySection(_ result: BeliefGraphTraceResult) -> some View {
        if let trace = result.graphTrace, !trace.triplePaths.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pathway")
                    .font(SavyTheme.beliefSerif(42))
                    .foregroundStyle(SavyTheme.deepNavy)

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
    // Shared navy for page headers, their overscroll backdrops, and navigation bands.
    static let pageBackground = deepNavy
    static let contentBackground = Color.white
    static let headerDivider = Color.white
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
    static let sandyBrown = Brand.tan
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
