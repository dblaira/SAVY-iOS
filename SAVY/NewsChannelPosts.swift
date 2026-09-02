import SwiftUI

/// Posts live on the News Channel page. Adam, 2026-09-02: "wants posts to be found in the News
/// Channel page. We may change the name or intent of the News Channel page, but for now, add
/// the results of the form there." A post is an entry from his form; it opens in that form.
struct NewsChannelPostsGroup: View {
    @ObservedObject var store: SocialPostStore
    @ObservedObject var reminderStore: ReminderStore
    @State private var editing: Reminder?
    @State private var isComposing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if store.posts.isEmpty {
                emptyRow
            } else {
                group(store.drafts)
                group(store.posted)
            }
        }
        .sheet(item: $editing) { post in
            ReminderFormView(existing: post, existingTags: store.recentTags + reminderStore.recentTags) { updated in
                route(updated, previous: post)
            }
        }
        .sheet(isPresented: $isComposing) {
            ReminderFormView(initialKind: .post, existing: nil, existingTags: store.recentTags + reminderStore.recentTags) { entry in
                route(entry, previous: nil)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newsChannelPosts")
    }

    /// The destination picker on the form decides where a saved entry lands.
    private func route(_ entry: Reminder, previous: Reminder?) {
        if entry.kind == .post {
            store.save(entry)
        } else {
            if let previous { store.delete(previous) }
            reminderStore.save(entry)
        }
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

            Text(tallyLine)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.black.opacity(0.42))
                .accessibilityIdentifier("postsTally")
        }
    }

    private var tallyLine: String {
        [
            "CLEAR SIGNS \(store.clearSignCount)",
            "LAST POST \(lastPostLabel.uppercased())",
        ].joined(separator: "  ·  ")
    }

    private var lastPostLabel: String {
        guard let date = store.lastPostedAt else { return "none yet" }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    private func group(_ items: [Reminder]) -> some View {
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

    /// Same swipe set as his tabs: Done means Posted here.
    private func actions(for post: Reminder) -> [SavySwipeAction] {
        var list: [SavySwipeAction] = []
        if post.status == .completed {
            list.append(SavySwipeAction(title: "Reopen", icon: "arrow.uturn.backward", bg: SavyTheme.crimson) {
                store.unpost(post)
            })
        } else {
            list.append(SavySwipeAction(title: "Posted", icon: "checkmark", bg: SavyTheme.crimson) {
                store.markPosted(post)
            })
            list.append(SavySwipeAction(title: post.pinned ? "Unpin" : "Pin", icon: "pin", bg: Brand.tileBlue) {
                store.togglePin(post)
            })
        }
        list.append(SavySwipeAction(title: "Delete", icon: "trash", bg: Color(hex: 0xB00124)) {
            store.delete(post)
        })
        return list
    }
}

/// One post as a story-style card: status dot, his signals, his words, then when.
struct NewsChannelPostRow: View {
    let post: Reminder

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(post.status == .completed ? SavyTheme.crimson : SavyTheme.bottomNavTan)
                    .frame(width: 9, height: 9)

                Text(kickerText)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.black.opacity(0.4))
                    .lineLimit(1)

                if post.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.4))
                }

                if post.isClearSignOfSuccess {
                    Spacer(minLength: 4)
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(SavyTheme.crimson)
                        .accessibilityLabel("Clear Sign of Success")
                }
            }

            Text(post.title.isEmpty ? "Untitled" : post.title)
                .font(SavyTheme.beliefSerif(24, weight: .regular))
                .lineSpacing(3)
                .foregroundStyle(SavyTheme.ink)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)

            if !signalText.isEmpty {
                Text(signalText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black.opacity(0.6))
                    .lineLimit(2)
            }

            if !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.system(size: 14))
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
        post.status == .completed ? "POSTED" : "DRAFT"
    }

    /// The same signals his tab cards show: Pattern step, priority marks, tags.
    private var signalText: String {
        var parts: [String] = []
        if post.context != .none { parts.append(post.context.label) }
        if post.isCompounding { parts.append("Compounding") }
        if post.priority != .none { parts.append(post.priority.marks) }
        parts.append(contentsOf: post.tags.map { "#\($0)" })
        return parts.joined(separator: "   ·   ")
    }

    private var secondaryText: String {
        var parts: [String] = []
        if post.status == .completed, let date = post.completedAt {
            let fmt = DateFormatter(); fmt.dateFormat = "MMM d h:mm a"
            parts.append("Posted \(fmt.string(from: date))")
        } else if let when = post.whenLabel {
            parts.append(when)
        }
        if !post.listName.isEmpty { parts.append(post.listName) }
        if !post.locationName.isEmpty { parts.append(post.locationName) }
        return parts.joined(separator: "   ·   ")
    }
}
