import SwiftUI

enum ConnectionLayout {
    static let fullCardHeight: CGFloat = 186
    static let horizontalPadding: CGFloat = 24
    static let cardSpacing: CGFloat = 14
    static let cardCornerRadius: CGFloat = 8
    static let headerHorizontalPadding: CGFloat = 24
}

/// Combining local writing and source-backed beliefs here changes presentation only;
/// it does not add locally authored connections to the validated graph.
private enum SavedConnectionCard: Identifiable {
    case entry(ConnectionEntry)
    case source(LeverageItem)

    var id: String {
        switch self {
        case .entry(let entry): "entry-\(entry.id.uuidString)"
        case .source(let item): "source-\(item.id)"
        }
    }
}

struct ConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ConnectionStore
    @StateObject private var cardOrder = PostCardOrderStore(key: PostCardOrderStore.connectionsDefaultsKey)
    @State private var armedConnectionID: String?
    @State private var editingEntry: ConnectionEntry?
    @State private var isComposing = false
    @State private var selectedSource: LeverageItem?
    @State private var showsSourceDetail = false
    @State private var showsStoreError = false

    let section: LeverageSection
    var onSignOut: (() -> Void)?

    init(section: LeverageSection, store: ConnectionStore, onSignOut: (() -> Void)? = nil) {
        self.section = section
        self.store = store
        self.onSignOut = onSignOut
    }

    private var defaultCards: [SavedConnectionCard] {
        store.entries.map(SavedConnectionCard.entry)
            + section.items.filter { !store.hiddenSourceIDs.contains($0.id) }.map(SavedConnectionCard.source)
    }

    private var pinnedIDs: Set<String> {
        Set(defaultCards.filter(isPinned).map(\.id))
    }

    private var displayedCards: [SavedConnectionCard] {
        let cards = defaultCards
        let byID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        return cardOrder.orderedIDs(defaultOrder: cards.map(\.id), pinnedIDs: pinnedIDs)
            .compactMap { byID[$0] }
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    connectionHeader
                    connectionList
                }
                .padding(.horizontal, ConnectionLayout.horizontalPadding)
                .padding(.bottom, 48)
                .savyHeaderPageContent(minHeight: viewport.size.height)
            }
            .savyHeaderOverscrollCapture("connection")
            .onScrollPhaseChange { _, phase in
                if phase == .interacting {
                    withAnimation(.snappy) { armedConnectionID = nil }
                }
            }
        }
        .background(SavyTheme.pageBackground.ignoresSafeArea())
        #if !targetEnvironment(macCatalyst)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .toolbarBackground(SavyTheme.pageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(SavyTheme.crimson)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) { backButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { backButton }
            }
        }
        .savyMacNavigationBar()
        .navigationDestination(isPresented: $showsSourceDetail) {
            if let selectedSource {
                LeverageDetailView(section: section, item: selectedSource)
            }
        }
        .sheet(item: $editingEntry) { entry in
            ReminderFormView(
                connectionMode: true,
                existing: entry.metadata,
                existingTags: store.recentTags,
                onSaveAttempt: { store.save($0) },
                onSave: { _ in }
            )
        }
        .sheet(isPresented: $isComposing) {
            ReminderFormView(
                connectionMode: true,
                existing: nil,
                existingTags: store.recentTags,
                onSaveAttempt: { store.save($0) },
                onSave: { _ in }
            )
        }
        .alert("Couldn't save connection", isPresented: $showsStoreError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "Your changes could not be saved. Please try again.")
        }
        .onChange(of: defaultCards.map(\.id), initial: true) { _, ids in
            cardOrder.reconcile(defaultOrder: ids)
            if let armedConnectionID, !ids.contains(armedConnectionID) {
                self.armedConnectionID = nil
            }
        }
        .accessibilityIdentifier("connectionScreen")
    }

    private var connectionHeader: some View {
        Text(section.title)
            .font(SavyTypography.displaySerif(44, weight: .bold))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ConnectionLayout.headerHorizontalPadding)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .background(SavyTheme.pageBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(SavyTheme.headerDivider).frame(height: RootHomeLayout.heroDividerHeight)
            }
            .padding(.horizontal, -ConnectionLayout.horizontalPadding)
            .accessibilityIdentifier("connectionPageHeader")
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(SavyTheme.crimson)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("[", modifiers: .command)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("connectionBack")
    }

    private var connectionList: some View {
        let cards = displayedCards
        return VStack(alignment: .leading, spacing: ConnectionLayout.cardSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("CONNECTIONS")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(SavyTheme.crimson)
                Spacer()
                Text("\(cards.count)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(SavyTheme.deepNavy)
                    .accessibilityIdentifier("connectionSavedCount")
                Button {
                    SavyHapticFeedback.primaryImpact()
                    isComposing = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, SavyTheme.crimson)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New connection")
                .accessibilityIdentifier("newConnection")
            }

            if cards.isEmpty {
                Text("Tap + to add a connection.")
                    .font(.system(size: 15))
                    .foregroundStyle(SavyTheme.deepNavy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
            } else {
                SavyCardFlow(spacing: ConnectionLayout.cardSpacing) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        connectionRow(card, palette: NewsChannelPostPalette(index: index))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("connectionCard-\(index)")
                            .accessibilityValue(isPinned(card) ? "Pinned" : "Unpinned")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connectionCards")
    }

    private func connectionRow(_ card: SavedConnectionCard, palette: NewsChannelPostPalette) -> some View {
        SavyUpNextCardRow(
            reminderId: card.id,
            armedId: $armedConnectionID,
            actions: actions(for: card),
            onTap: { open(card) },
            onMoveUp: { move(card, direction: -1) },
            onMoveDown: { move(card, direction: 1) },
            gestureAccessibilityIdentifier: rowIdentifier(card)
        ) {
            connectionCard(card, palette: palette)
        }
        .zIndex(armedConnectionID == card.id ? 10 : 0)
    }

    private func connectionCard(_ card: SavedConnectionCard, palette: NewsChannelPostPalette) -> some View {
        let pinned = isPinned(card)
        let preview: NewsChannelPostPreview
        let signal: String
        let secondary: String
        let titleIdentifier: String
        switch card {
        case .entry(let entry):
            preview = entry.preview
            signal = entry.metadataSummary
            secondary = entry.metadata.whenLabel ?? entry.metadata.createdAt.formatted(date: .abbreviated, time: .omitted)
            titleIdentifier = "connectionEntryHeadline-\(entry.id.uuidString)"
        case .source(let item):
            preview = NewsChannelPostPreview(text: item.title, additionalDetails: [item.summary, item.body])
            signal = item.kicker == "PINNED" ? "" : item.kicker
            secondary = item.category ?? ""
            titleIdentifier = "connectionSourceHeadline-\(item.id)"
        }

        return SavyBandCard(
            bg: palette.bg,
            fg: palette.fg,
            accent: palette.accent,
            title: preview.title,
            signalText: signal,
            secondaryText: secondary,
            detailLine: preview.detail,
            detail: pinned ? .full : .minimal,
            isCompact: !pinned,
            minimumHeight: pinned ? ConnectionLayout.fullCardHeight : nil,
            border: palette.border,
            secondaryLineLimit: 2,
            titleAccessibilityIdentifier: titleIdentifier
        ) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .bold))
                Text("CONNECTION")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
            }
        }
    }

    private func isPinned(_ card: SavedConnectionCard) -> Bool {
        switch card {
        case .entry(let entry):
            entry.metadata.pinned
        case .source(let item):
            store.sourcePinned(id: item.id, defaultValue: section.items.prefix(2).contains { $0.id == item.id })
        }
    }

    private func open(_ card: SavedConnectionCard) {
        switch card {
        case .entry(let entry):
            editingEntry = entry
        case .source(let item):
            selectedSource = item
            showsSourceDetail = true
        }
    }

    private func move(_ card: SavedConnectionCard, direction: Int) {
        withAnimation(.snappy) {
            cardOrder.move(card.id, direction: direction, defaultOrder: defaultCards.map(\.id), pinnedIDs: pinnedIDs)
        }
    }

    private func togglePin(_ card: SavedConnectionCard) {
        let saved: Bool
        switch card {
        case .entry(let entry): saved = store.togglePin(entry)
        case .source(let item): saved = store.setSourcePinned(id: item.id, isPinned: !isPinned(card))
        }
        if saved {
            cardOrder.moveToFrontOfPinGroup(card.id, defaultOrder: defaultCards.map(\.id), pinnedIDs: pinnedIDs)
        } else {
            showsStoreError = true
        }
    }

    private func rowIdentifier(_ card: SavedConnectionCard) -> String {
        switch card {
        case .entry(let entry): "connectionEntryRow-\(entry.id.uuidString)"
        case .source(let item): "connectionSourceRow-\(item.id)"
        }
    }

    private func actions(for card: SavedConnectionCard) -> [SavySwipeAction] {
        [
            SavySwipeAction(title: isPinned(card) ? "Unpin" : "Pin", icon: "pin", bg: Brand.tileBlue) {
                togglePin(card)
            },
            SavySwipeAction(title: "Delete", icon: "trash", bg: Color(hex: 0xB00124)) {
                let saved: Bool
                switch card {
                case .entry(let entry): saved = store.delete(entry)
                case .source(let item): saved = store.deleteSource(id: item.id)
                }
                if !saved { showsStoreError = true }
            },
        ]
    }
}
