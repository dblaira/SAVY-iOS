import SwiftUI

/// The shared, read-only feed projection for the Home preview and Social Media Posts page.
/// Identity, saved numbers, authored previews, and ordering come from the same records.
enum SavedPost: Identifiable {
    case entry(Reminder)
    case legacy(SocialPost)

    var id: String {
        switch self {
        case .entry(let entry): return "entry-\(entry.id.uuidString)"
        case .legacy(let post): return "legacy-\(post.id.uuidString)"
        }
    }

    var isPinned: Bool {
        switch self {
        case .entry(let entry): return entry.pinned
        case .legacy(let post): return post.pinned
        }
    }

    var postNumber: Int? {
        switch self {
        case .entry(let entry): return entry.postNumber
        case .legacy(let post): return post.postNumber
        }
    }

    var preview: NewsChannelPostPreview {
        switch self {
        case .legacy(let post):
            return NewsChannelPostPreview(text: post.trimmedText, additionalDetails: [post.connection, post.sourceLine])
        case .entry(let entry):
            let answers = entry.postAnswerTexts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = !title.isEmpty && title != "New Post" ? title : entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return NewsChannelPostPreview(
                text: answers.first ?? fallback,
                additionalDetails: Array(answers.dropFirst()) + [entry.notes, entry.outcome]
            )
        }
    }

    var numberedPreviewText: String {
        postNumber.map { "#\($0) \(preview.title)" } ?? preview.title
    }

    /// Keep the page's existing pinned/status/date order until the user rearranges it.
    @MainActor
    static func defaultOrder(store: SocialPostStore, reminderStore: ReminderStore) -> [SavedPost] {
        let entries = reminderStore.active.filter { $0.kind == .post }.sorted { $0.createdAt > $1.createdAt }
        let postedEntries = reminderStore.completed.filter { $0.kind == .post }
        let groups: [[SavedPost]] = [
            (entries + postedEntries).filter(\.pinned).map(SavedPost.entry),
            store.posts.filter(\.pinned).sorted { $0.updatedAt > $1.updatedAt }.map(SavedPost.legacy),
            entries.filter { !$0.pinned }.map(SavedPost.entry),
            store.ready.filter { !$0.pinned }.map(SavedPost.legacy),
            store.drafts.filter { !$0.pinned }.map(SavedPost.legacy),
            postedEntries.filter { !$0.pinned }.map(SavedPost.entry),
            store.posted.filter { !$0.pinned }.map(SavedPost.legacy),
        ]
        var seen = Set<String>()
        return groups.flatMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    @MainActor
    static func displayed(store: SocialPostStore, reminderStore: ReminderStore, cardOrder: PostCardOrderStore) -> [SavedPost] {
        let posts = defaultOrder(store: store, reminderStore: reminderStore)
        let byID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        return cardOrder.orderedIDs(
            defaultOrder: posts.map(\.id),
            pinnedIDs: Set(posts.filter(\.isPinned).map(\.id))
        ).compactMap { byID[$0] }
    }
}

/// Saved posts share the Reminders card layout. The inline count measures saved posts on
/// this phone against Adam's 50-post target; it does not claim anything was published.
struct NewsChannelPostsGroup: View {
    @ObservedObject var store: SocialPostStore
    /// Post entries saved through the bolt's Post door (the Reminder form's fourth face).
    @ObservedObject var reminderStore: ReminderStore
    @ObservedObject var cardOrder: PostCardOrderStore
    var scrollRevision = 0
    @State private var armedPostID: String?
    @State private var editing: SocialPost?
    @State private var editingEntry: Reminder?
    @State private var isComposing = false

    private var defaultPosts: [SavedPost] {
        SavedPost.defaultOrder(store: store, reminderStore: reminderStore)
    }

    private var displayedPosts: [SavedPost] {
        SavedPost.displayed(store: store, reminderStore: reminderStore, cardOrder: cardOrder)
    }

    var body: some View {
        let posts = displayedPosts
        VStack(alignment: .leading, spacing: 14) {
            header(count: posts.count)

            if posts.isEmpty {
                emptyRow
            } else {
                SavyCardFlow(spacing: 14) {
                    ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                        postRow(post, palette: NewsChannelPostPalette(index: index))
                    }
                }
            }
        }
        .sheet(item: $editing) { post in
            SocialPostFormView(existing: post, recentAreas: store.recentAreas) { updated in
                store.save(updated)
            }
        }
        .sheet(item: $editingEntry) { entry in
            ReminderFormView(existing: entry, existingTags: reminderStore.recentTags) { updated in
                reminderStore.save(updated)
            }
        }
        .sheet(isPresented: $isComposing) {
            ReminderFormView(initialKind: .post, existing: nil, existingTags: reminderStore.recentTags) { entry in
                reminderStore.save(entry)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newsChannelPosts")
        .onChange(of: scrollRevision) {
            withAnimation(.snappy) { armedPostID = nil }
        }
        .onChange(of: defaultPosts.map(\.id), initial: true) { _, ids in
            cardOrder.reconcile(defaultOrder: ids)
            if let armedPostID, !ids.contains(armedPostID) { self.armedPostID = nil }
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("POSTS")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(SavyTheme.crimson)
                Spacer()
                Text("\(count) / 50")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(SavyTheme.deepNavy)
                    .accessibilityIdentifier("postSavedCount")
                Button {
                    SavyHapticFeedback.primaryImpact()
                    isComposing = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, SavyTheme.crimson)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New post")
                .accessibilityIdentifier("newPost")
            }

        }
    }

    @ViewBuilder
    private func postRow(_ savedPost: SavedPost, palette: NewsChannelPostPalette) -> some View {
        switch savedPost {
        case .legacy(let post):
            SavyUpNextCardRow(
                reminderId: savedPost.id,
                armedId: $armedPostID,
                actions: actions(for: post),
                onTap: { editing = post },
                onMoveUp: { move(savedPost, direction: -1) },
                onMoveDown: { move(savedPost, direction: 1) },
                gestureAccessibilityIdentifier: "postRow-\(post.id.uuidString)"
            ) {
                NewsChannelPostRow(post: post, palette: palette)
            }
            .overlay(alignment: .topTrailing) {
                pinButton(isPinned: post.pinned, palette: palette, identifier: "pinPost-\(post.id.uuidString)") {
                    store.togglePin(post)
                }
                .padding(.trailing, armedPostID == savedPost.id ? 52 : 0)
            }
            .zIndex(armedPostID == savedPost.id ? 10 : 0)
        case .entry(let entry):
            SavyUpNextCardRow(
                reminderId: savedPost.id,
                armedId: $armedPostID,
                actions: actions(for: entry),
                onTap: { editingEntry = entry },
                onMoveUp: { move(savedPost, direction: -1) },
                onMoveDown: { move(savedPost, direction: 1) },
                gestureAccessibilityIdentifier: "postEntryRow-\(entry.id.uuidString)"
            ) {
                NewsChannelPostEntryRow(entry: entry, palette: palette)
            }
            .overlay(alignment: .topTrailing) {
                pinButton(isPinned: entry.pinned, palette: palette, identifier: "pinPostEntry-\(entry.id.uuidString)") {
                    guard var updated = reminderStore.reminders.first(where: { $0.id == entry.id }) else { return }
                    updated.pinned.toggle()
                    reminderStore.save(updated)
                }
                .padding(.trailing, armedPostID == savedPost.id ? 52 : 0)
            }
            .zIndex(armedPostID == savedPost.id ? 10 : 0)
        }
    }

    private func move(_ post: SavedPost, direction: Int) {
        let posts = defaultPosts
        withAnimation(.snappy) {
            cardOrder.move(
                post.id,
                direction: direction,
                defaultOrder: posts.map(\.id),
                pinnedIDs: Set(posts.filter(\.isPinned).map(\.id))
            )
        }
    }

    private func pinButton(isPinned: Bool, palette: NewsChannelPostPalette, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isPinned ? palette.pin : palette.fg.opacity(0.6))
                .offset(y: isPinned ? 0 : -4)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .accessibilityLabel(isPinned ? "Unpin post" : "Pin post")
        .accessibilityIdentifier(identifier)
    }

    private func actions(for entry: Reminder) -> [SavySwipeAction] {
        var list: [SavySwipeAction] = []
        if entry.status != .completed {
            list.append(SavySwipeAction(title: "Posted", icon: "checkmark", bg: SavyTheme.crimson) {
                reminderStore.complete(entry)
            })
        }
        list.append(SavySwipeAction(title: "Delete", icon: "trash", bg: Color(hex: 0xB00124)) {
            reminderStore.delete(entry)
        })
        return list
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing yet.")
                .font(SavyTheme.beliefSerif(22))
                .foregroundStyle(SavyTheme.ink)
            Text("Tap + to choose a theme and begin.")
                .font(.system(size: 15))
                .foregroundStyle(.black.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }

    private func actions(for post: SocialPost) -> [SavySwipeAction] {
        var list: [SavySwipeAction] = []
        if post.status != .posted {
            list.append(SavySwipeAction(title: "Posted", icon: "checkmark", bg: SavyTheme.crimson) {
                store.markPosted(post)
            })
        }
        list.append(SavySwipeAction(title: "Delete", icon: "trash", bg: Color(hex: 0xB00124)) {
            store.delete(post)
        })
        return list
    }
}

/// Palette position belongs to the combined displayed list, including both kinds of post.
struct NewsChannelPostPalette {
    let bg: Color
    let fg: Color
    let accent: Color
    let border: Color
    let pin: Color

    init(index: Int) {
        switch index % 4 {
        case 0:
            bg = .white
            fg = SavyTheme.deepNavy
            accent = SavyTheme.crimson
            border = .white.opacity(0.08)
            pin = SavyTheme.crimson
        case 1:
            bg = Brand.darkRed
            fg = .white
            accent = .white
            border = .white.opacity(0.08)
            pin = .white
        case 2:
            bg = SavyTheme.bottomNavTan
            fg = SavyTheme.deepNavy
            accent = SavyTheme.crimson
            border = .white.opacity(0.08)
            pin = SavyTheme.crimson
        default:
            bg = SavyTheme.deepNavy
            fg = .white
            accent = SavyTheme.crimson
            border = SavyTheme.bottomNavTan.opacity(0.75)
            pin = SavyTheme.bottomNavTan
        }
    }
}

/// Extract only a display preview; the source post and full saved answers remain untouched.
struct NewsChannelPostPreview {
    let title: String
    let detail: String?

    init(text: String, additionalDetails: [String] = []) {
        let authoredText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var firstSentence = authoredText
        var remainder = ""
        if !authoredText.isEmpty {
            authoredText.enumerateSubstrings(
                in: authoredText.startIndex..<authoredText.endIndex,
                options: .bySentences
            ) { sentence, range, _, stop in
                firstSentence = (sentence ?? authoredText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                remainder = String(authoredText[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                stop = true
            }
        }
        title = firstSentence.isEmpty ? "Untitled" : firstSentence
        detail = ([remainder] + additionalDetails)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != firstSentence && $0 != authoredText }
    }
}

/// Legacy posts retain their original editor and share the same card renderer as Reminders.
struct NewsChannelPostRow: View {
    let post: SocialPost
    let palette: NewsChannelPostPalette

    var body: some View {
        let preview = SavedPost.legacy(post).preview
        SavyBandCard(
            bg: palette.bg,
            fg: palette.fg,
            accent: palette.accent,
            title: preview.title,
            signalText: signalText,
            secondaryText: secondaryText,
            detailLine: preview.detail,
            detail: post.pinned ? .full : .minimal,
            isCompact: !post.pinned,
            minimumHeight: post.pinned ? 186 : nil,
            border: palette.border,
            secondaryLineLimit: 2,
            titleAccessibilityIdentifier: "postHeadline-\(post.id.uuidString)"
        ) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11, weight: .bold))
                Text(post.postNumber.map { "POST #\($0)" } ?? "POST")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .accessibilityIdentifier("postNumber-\(post.id.uuidString)")
                if post.clearSign {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.pin)
                        .accessibilityLabel("Clear Sign")
                }
            }
            .padding(.trailing, 36)
        }
    }

    private var signalText: String {
        var parts = [post.platform.label, post.move.label]
        if post.pattern != .none { parts.append(post.pattern.label) }
        parts.append(contentsOf: post.areas.map { "#\($0)" })
        return parts.joined(separator: "   ·   ")
    }

    private var secondaryText: String {
        var parts = [post.status.label, post.door.label]
        if !post.sourceName.isEmpty { parts.append(post.sourceName) }
        parts.append(post.whenLabel ?? post.createdAt.formatted(date: .abbreviated, time: .omitted))
        if post.status == .posted, post.likes + post.replies + post.profileTaps > 0 {
            parts.append("\(post.replies) replies · \(post.likes) likes · \(post.profileTaps) taps")
        }
        return parts.joined(separator: "   ·   ")
    }
}

/// The first authored answer leads; its prefilled question stays in the saved entry.
struct NewsChannelPostEntryRow: View {
    let entry: Reminder
    let palette: NewsChannelPostPalette

    var body: some View {
        let preview = SavedPost.entry(entry).preview
        SavyBandCard(
            bg: palette.bg,
            fg: palette.fg,
            accent: palette.accent,
            title: preview.title,
            signalText: signalText,
            secondaryText: secondaryText,
            detailLine: preview.detail,
            detail: entry.pinned ? .full : .minimal,
            isCompact: !entry.pinned,
            minimumHeight: entry.pinned ? 186 : nil,
            border: palette.border,
            secondaryLineLimit: 2,
            titleAccessibilityIdentifier: "postEntryHeadline-\(entry.id.uuidString)"
        ) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11, weight: .bold))
                Text(entry.postNumber.map { "POST #\($0)" } ?? "POST")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .accessibilityIdentifier("postEntryNumber-\(entry.id.uuidString)")
            }
            .padding(.trailing, 36)
        }
    }

    private var signalText: String {
        var parts: [String] = []
        if let theme = entry.postThemeName, !theme.isEmpty { parts.append(theme) }
        if entry.priority != .none { parts.append(entry.priority.marks) }
        if entry.context != .none { parts.append(entry.context.label) }
        parts.append(contentsOf: entry.tags.map { "#\($0)" })
        return parts.joined(separator: "   ·   ")
    }

    private var secondaryText: String {
        var parts = ["\(entry.postAnsweredCount) answered"]
        if !entry.listName.isEmpty { parts.append(entry.listName) }
        if !entry.locationName.isEmpty { parts.append(entry.locationName) }
        parts.append(entry.whenLabel ?? entry.createdAt.formatted(date: .abbreviated, time: .omitted))
        parts.append(entry.status == .completed ? "Posted" : "Draft")
        return parts.joined(separator: "   ·   ")
    }
}
