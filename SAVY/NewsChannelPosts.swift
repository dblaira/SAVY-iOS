import SwiftUI

/// Saved posts share the Reminders card layout. The inline count measures saved posts on
/// this phone against Adam's 50-post target; it does not claim anything was published.
struct NewsChannelPostsGroup: View {
    @ObservedObject var store: SocialPostStore
    /// Post entries saved through the bolt's Post door (the Reminder form's fourth face).
    @ObservedObject var reminderStore: ReminderStore
    @State private var editing: SocialPost?
    @State private var editingEntry: Reminder?
    @State private var isComposing = false

    private var postEntries: [Reminder] {
        return reminderStore.active.filter { $0.kind == .post }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var postedEntries: [Reminder] {
        return reminderStore.completed.filter { $0.kind == .post }
    }

    private var pinnedEntries: [Reminder] {
        (postEntries + postedEntries).filter(\.pinned)
    }

    private var pinnedPosts: [SocialPost] {
        store.posts.filter(\.pinned).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Keep the existing pinned/status ordering while applying one continuous color cycle.
    /// The two stores have independent UUID namespaces, so identity includes the source.
    private var displayedPosts: [SavedPost] {
        let groups: [[SavedPost]] = [
            pinnedEntries.map(SavedPost.entry),
            pinnedPosts.map(SavedPost.legacy),
            postEntries.filter { !$0.pinned }.map(SavedPost.entry),
            store.ready.filter { !$0.pinned }.map(SavedPost.legacy),
            store.drafts.filter { !$0.pinned }.map(SavedPost.legacy),
            postedEntries.filter { !$0.pinned }.map(SavedPost.entry),
            store.posted.filter { !$0.pinned }.map(SavedPost.legacy),
        ]
        var seen = Set<String>()
        return groups.flatMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        let posts = displayedPosts
        VStack(alignment: .leading, spacing: 14) {
            header(count: posts.count)

            if posts.isEmpty {
                emptyRow
            } else {
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                    postRow(post, palette: NewsChannelPostPalette(index: index))
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
                    .foregroundStyle(SavyTheme.bottomNavTan)
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
            SavySwipeRow(
                actions: actions(for: post),
                gestureAccessibilityIdentifier: "postRow-\(post.id.uuidString)",
                onTap: { editing = post }
            ) {
                NewsChannelPostRow(post: post, palette: palette)
            }
            .overlay(alignment: .topTrailing) {
                pinButton(isPinned: post.pinned, palette: palette, identifier: "pinPost-\(post.id.uuidString)") {
                    store.togglePin(post)
                }
            }
        case .entry(let entry):
            SavySwipeRow(
                actions: actions(for: entry),
                gestureAccessibilityIdentifier: "postEntryRow-\(entry.id.uuidString)",
                onTap: { editingEntry = entry }
            ) {
                NewsChannelPostEntryRow(entry: entry, palette: palette)
            }
            .overlay(alignment: .topTrailing) {
                pinButton(isPinned: entry.pinned, palette: palette, identifier: "pinPostEntry-\(entry.id.uuidString)") {
                    guard var updated = reminderStore.reminders.first(where: { $0.id == entry.id }) else { return }
                    updated.pinned.toggle()
                    reminderStore.save(updated)
                }
            }
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

    private enum SavedPost: Identifiable {
        case entry(Reminder)
        case legacy(SocialPost)

        var id: String {
            switch self {
            case .entry(let entry): return "entry-\(entry.id.uuidString)"
            case .legacy(let post): return "legacy-\(post.id.uuidString)"
            }
        }
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
private struct NewsChannelPostPreview {
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
        let preview = NewsChannelPostPreview(
            text: post.trimmedText,
            additionalDetails: [post.connection, post.sourceLine]
        )
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
            leadingEdge: SavyTheme.crimson,
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

    private var authoredAnswers: [String] {
        entry.postAnswerTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var authoredText: String {
        if let firstAnswer = authoredAnswers.first { return firstAnswer }
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != "New Post" { return title }
        return entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let preview = NewsChannelPostPreview(
            text: authoredText,
            additionalDetails: Array(authoredAnswers.dropFirst()) + [entry.notes, entry.outcome]
        )
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
            leadingEdge: SavyTheme.crimson,
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
