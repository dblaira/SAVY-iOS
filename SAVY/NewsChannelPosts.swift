import SwiftUI

/// Posts live on the Social Media Posts page. Adam, 2026-09-19: "Let's call news channel
/// social media posts." Same paper page, same white cards as the stories below.
///
/// No tally line under POSTS. Adam, 2026-09-03, after his first quote post went out through Grok
/// Bot: "the small news, advertising and clean signs numbers below the posts label don't make
/// sense. When I post through Grok Bot that doesn't tie to the app, so the numbers aren't honest."

struct NewsChannelPostsGroup: View {
    @ObservedObject var store: SocialPostStore
    /// Post entries saved through the bolt's Post door (the Reminder form's fourth face).
    var reminderStore: ReminderStore? = nil
    @State private var editing: SocialPost?
    @State private var editingEntry: Reminder?
    @State private var isComposing = false

    private var postEntries: [Reminder] {
        guard let reminderStore else { return [] }
        return reminderStore.active.filter { $0.kind == .post }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var postedEntries: [Reminder] {
        guard let reminderStore else { return [] }
        return reminderStore.completed.filter { $0.kind == .post }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if store.posts.isEmpty && postEntries.isEmpty && postedEntries.isEmpty {
                emptyRow
            } else {
                entryGroup(postEntries)
                group(store.ready)
                group(store.drafts)
                entryGroup(postedEntries)
                group(store.posted)
            }
        }
        .sheet(item: $editing) { post in
            SocialPostFormView(existing: post, recentAreas: store.recentAreas) { updated in
                store.save(updated)
            }
        }
        .sheet(item: $editingEntry) { entry in
            if let reminderStore {
                ReminderFormView(existing: entry, existingTags: reminderStore.recentTags) { updated in
                    reminderStore.save(updated)
                }
            }
        }
        .sheet(isPresented: $isComposing) {
            SocialPostFormView(existing: nil, recentAreas: store.recentAreas) { post in
                store.save(post)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newsChannelPosts")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("POSTS")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(SavyTheme.crimson)
                Spacer()
                Button {
                    SavyHapticFeedback.primaryImpact()
                    isComposing = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(SavyTheme.crimson)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New post")
                .accessibilityIdentifier("newPost")
            }

        }
    }

    private func group(_ items: [SocialPost]) -> some View {
        ForEach(items) { post in
            SavySwipeRow(
                actions: actions(for: post),
                gestureAccessibilityIdentifier: "postRow-\(post.id.uuidString)",
                onTap: { editing = post }
            ) {
                NewsChannelPostRow(post: post)
            }
        }
    }

    private func entryGroup(_ items: [Reminder]) -> some View {
        ForEach(items) { entry in
            SavySwipeRow(
                actions: actions(for: entry),
                gestureAccessibilityIdentifier: "postEntryRow-\(entry.id.uuidString)",
                onTap: { editingEntry = entry }
            ) {
                NewsChannelPostEntryRow(entry: entry)
            }
        }
    }

    private func actions(for entry: Reminder) -> [SavySwipeAction] {
        guard let reminderStore else { return [] }
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
            Text("Tap the bolt and choose Post.")
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

/// One post as a story-style card: status dot, kicker, his words, then where it came from.
struct NewsChannelPostRow: View {
    let post: SocialPost

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)

                Text(kickerText)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.black.opacity(0.4))
                    .lineLimit(1)

                if post.clearSign {
                    Spacer(minLength: 4)
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(SavyTheme.crimson)
                        .accessibilityLabel("Clear Sign")
                }
            }

            Text(post.trimmedText.isEmpty ? "Untitled" : post.trimmedText)
                .font(SavyTheme.beliefSerif(24, weight: .regular))
                .lineSpacing(3)
                .foregroundStyle(SavyTheme.ink)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)

            if !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(.black.opacity(0.55))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }

    private var statusColor: Color {
        switch post.status {
        case .draft: return SavyTheme.bottomNavTan
        case .ready: return SavyTheme.green
        case .posted: return SavyTheme.crimson
        }
    }

    private var kickerText: String {
        [post.status.label, post.platform.label, post.move.label, post.door.label]
            .map { $0.uppercased() }
            .joined(separator: " · ")
    }

    private var secondaryText: String {
        var parts: [String] = []
        if !post.sourceName.isEmpty { parts.append(post.sourceName) }
        if let when = post.whenLabel { parts.append(when) }
        if post.status == .posted, post.likes + post.replies + post.profileTaps > 0 {
            parts.append("\(post.replies) replies · \(post.likes) likes · \(post.profileTaps) taps")
        }
        parts.append(contentsOf: post.areas.map { "#\($0)" })
        return parts.joined(separator: "   ·   ")
    }
}

/// A Post entry from the bolt's Post door — same white card as the SocialPost rows, with the
/// theme name in the kicker and the first answered Decide line as the preview.
struct NewsChannelPostEntryRow: View {
    let entry: Reminder

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(entry.status == .completed ? SavyTheme.crimson : SavyTheme.bottomNavTan)
                    .frame(width: 9, height: 9)

                Text(kickerText)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.black.opacity(0.4))
                    .lineLimit(1)
            }

            Text(headlineText)
                .font(SavyTheme.beliefSerif(24, weight: .regular))
                .lineSpacing(3)
                .foregroundStyle(SavyTheme.ink)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)

            if !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(.black.opacity(0.55))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }

    private var kickerText: String {
        var parts = [entry.status == .completed ? "Posted" : "Post"]
        if let theme = entry.postThemeName, !theme.isEmpty { parts.append(theme) }
        return parts.map { $0.uppercased() }.joined(separator: " · ")
    }

    private var headlineText: String {
        let title = entry.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty, title != "New Post" { return title }
        let firstAnswer = (entry.postAnswers ?? [])
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return firstAnswer ?? "Untitled"
    }

    private var secondaryText: String {
        var parts: [String] = []
        let answered = (entry.postAnswers ?? [])
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        if answered > 0 { parts.append("\(answered) answered") }
        if let when = entry.whenLabel { parts.append(when) }
        parts.append(contentsOf: entry.tags.map { "#\($0)" })
        return parts.joined(separator: "   ·   ")
    }
}
