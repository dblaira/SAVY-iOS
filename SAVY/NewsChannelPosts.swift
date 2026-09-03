import SwiftUI

/// Posts live on the News Channel page. Adam, 2026-09-02: "wants posts to be found in the News
/// Channel page. We may change the name or intent of the News Channel page, but for now, add
/// the results of the form there." Same paper page, same white cards as the stories below.
struct NewsChannelPostsGroup: View {
    @ObservedObject var store: SocialPostStore
    @State private var editing: SocialPost?
    @State private var isComposing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if store.posts.isEmpty {
                emptyRow
            } else {
                group(store.ready)
                group(store.drafts)
                group(store.posted)
            }
        }
        .sheet(item: $editing) { post in
            SocialPostFormView(existing: post, recentAreas: store.recentAreas) { updated in
                store.save(updated)
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

            // The tally underneath: News, Advertising, Clear Signs, and when the last one went out.
            Text(tallyLine)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.black.opacity(0.42))
                .accessibilityIdentifier("postsTally")
        }
    }

    private var tallyLine: String {
        [
            "NEWS \(store.postedNewsCount)",
            "ADVERTISING \(store.postedAdvertisingCount)",
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
