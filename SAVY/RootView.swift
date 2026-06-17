import SwiftUI

enum RootHomeLayout {
    static let leverageGridColumnCount = 2
    static let leverageGridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 17),
        count: leverageGridColumnCount
    )
    static let horizontalPadding: CGFloat = 24
    static let heroTopPadding: CGFloat = 0
    static let heroHeight: CGFloat = 230
    static let heroContentTopPadding: CGFloat = 34
    static let heroWordmarkEyebrowSpacing: CGFloat = 12
    static let heroDividerHeight: CGFloat = 3
    static let heroWordmarkFontName = "BodoniSvtyTwoOSITCTT-Book"
    static let heroWordmarkFontSize: CGFloat = 48
    static let carouselTopPadding: CGFloat = 20
    static let carouselHorizontalPadding: CGFloat = 2
    static let carouselCardWidth: CGFloat = 282
    static let carouselCardHeight: CGFloat = 236
    static let latestSectionBandHeight: CGFloat = 92
    static let pinnedEntryRowHeight: CGFloat = 81
    static let pinnedEntryTrailingInset: CGFloat = 17
    static let pinnedEntryFontName = "Crushed-Regular"
    static let pinnedEntryFontSize: CGFloat = 32
    static let bottomNavigationHeight: CGFloat = 112
    static let bottomNavigationTopPadding: CGFloat = 28
    static let bottomNavigationIconSize: CGFloat = 34
    static let bottomNavigationLabelSize: CGFloat = 14
    static let floatingCaptureAlignment: Alignment = .bottom
    static let floatingCaptureBottomPadding: CGFloat = 90
    static let floatingCaptureSize: CGFloat = 72
    static let floatingCaptureBackground = SavyTheme.deepNavy
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

    init(onSignOut: (() -> Void)? = nil) {
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: RootHomeLayout.floatingCaptureAlignment) {
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

                    SavyBottomNavigationBar(navigationState: navigationState)
                }
                .ignoresSafeArea(edges: .bottom)

                SavyFloatingActionButton(isPresented: navigationState.isRadialMenuPresented) {
                    navigationState.toggleRadialMenu()
                }
                .padding(.bottom, RootHomeLayout.floatingCaptureBottomPadding)

                accountMenuButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await leverageStore.refresh()
            }
            .sheet(item: $navigationState.activeComposerKind) { kind in
                MetadataComposerSheet(kind: kind) { entry in
                    try metadataStore.save(entry)
                }
            }
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

                    leverageCarousel
                        .padding(.top, RootHomeLayout.carouselTopPadding)

                    latestSection
                }
                .padding(.bottom, 40)
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(SavyTheme.paper.ignoresSafeArea())
    }

    private func header(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RootHomeLayout.heroWordmarkEyebrowSpacing) {
            Text("SAVY")
                .font(.custom(
                    RootHomeLayout.heroWordmarkFontName,
                    fixedSize: RootHomeLayout.heroWordmarkFontSize
                ))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("The Adam Pattern")
                .font(.system(size: 12, weight: .heavy))
                .tracking(3)
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
            .font(.custom(
                RootHomeLayout.pinnedEntryFontName,
                fixedSize: RootHomeLayout.pinnedEntryFontSize
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
                .font(.system(size: 25, weight: .regular, design: .serif))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(item.kicker)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(SavyTheme.crimson)

                Text(item.title)
                    .font(.system(size: 39, weight: .regular, design: .serif))
                    .lineSpacing(2)
                    .foregroundStyle(SavyTheme.ink)

                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(.black.opacity(0.58))
                }

                Divider()
                    .padding(.vertical, 4)

                Text(item.body)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .lineSpacing(7)
                    .foregroundStyle(SavyTheme.ink)
            }
            .padding(.horizontal, 25)
            .padding(.top, 34)
            .padding(.bottom, 54)
        }
        .background(SavyTheme.paper.ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
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
