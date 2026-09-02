import SwiftUI

/// Posts screen — Ready, Drafts, Posted — on the same navy field and white hero as the
/// Reminders and Actions tabs. Reached from the Posts card on Now, or right after a
/// post is saved from the bolt.
struct SocialPostsView: View {
    @ObservedObject var store: SocialPostStore
    @State private var editing: SocialPost?
    @State private var isComposing = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    Rectangle().fill(SavyTheme.crimson).frame(height: 2)
                    signalBand
                    band("READY", items: store.ready, identifier: "readyPosts")
                    band("DRAFTS", items: store.drafts, identifier: "draftPosts")
                    band("POSTED", items: store.posted, identifier: "postedPosts")
                    Spacer(minLength: 24)
                }
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .background(SavyTheme.deepNavy)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("postsHome")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    SavyHapticFeedback.primaryImpact()
                    isComposing = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(SavyTheme.crimson)
                }
                .accessibilityLabel("New post")
                .accessibilityIdentifier("newPost")
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
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Posts")
                .font(SavyTypography.displaySerif(48, weight: .bold))
                .foregroundStyle(SavyTheme.deepNavy)
            // Adam: "it's not building products as much as it is building meaning in public."
            Text("Building meaning in public.")
                .font(SavyTheme.readingLabel(18))
                .foregroundStyle(SavyTheme.crimson)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .padding(.horizontal, 16)
        .background(Color.white)
    }

    /// The tally underneath: jabs to hooks, Clear Signs, and when the last one went out.
    private var signalBand: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            signal("JABS", value: "\(store.postedJabCount)")
            signal("HOOKS", value: "\(store.postedHookCount)")
            signal("CLEAR SIGNS", value: "\(store.clearSignCount)")
            Spacer(minLength: 0)
            signal("LAST POST", value: lastPostLabel)
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("postsSignalBand")
    }

    private func signal(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(SavyTheme.bottomNavTan)
            Text(value)
                .font(SavyTypography.displaySerif(22, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var lastPostLabel: String {
        guard let date = store.lastPostedAt else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    private func band(_ title: String, items: [SocialPost], identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(2.5)
                    .foregroundStyle(SavyTheme.bottomNavTan)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.45))
            }

            if items.isEmpty {
                if identifier == "draftPosts", store.posts.isEmpty {
                    emptyState
                }
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, post in
                    SavySwipeRow(
                        actions: actions(for: post),
                        gestureAccessibilityIdentifier: "postRow-\(post.id.uuidString)",
                        onTap: { editing = post }
                    ) {
                        SocialPostCard(
                            post: post,
                            bg: cardColors(for: post, index: index).bg,
                            fg: cardColors(for: post, index: index).fg,
                            accent: cardColors(for: post, index: index).accent
                        )
                    }
                }
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SavyTheme.deepNavy)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing yet.")
                .font(SavyTypography.displaySerif(26, weight: .bold))
                .foregroundStyle(.white)
            Text("Tap the bolt and choose Post.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.nearBlack)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func cardColors(for post: SocialPost, index: Int) -> (bg: Color, fg: Color, accent: Color) {
        switch post.status {
        case .ready:
            return (.white, SavyTheme.deepNavy, SavyTheme.crimson)
        case .draft:
            return index == 0
                ? (Brand.darkRed, .white, .white)
                : (SavyTheme.bottomNavTan, SavyTheme.deepNavy, SavyTheme.crimson)
        case .posted:
            return (Brand.nearBlack, .white, SavyTheme.bottomNavTan)
        }
    }
}

struct SocialPostCard: View {
    let post: SocialPost
    let bg: Color
    let fg: Color
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11, weight: .bold))
                Text(kickerText)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .lineLimit(1)
                if post.clearSign {
                    Spacer(minLength: 4)
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(accent)
                        .accessibilityLabel("Clear Sign")
                }
            }
            .foregroundStyle(fg.opacity(0.7))

            Text(post.trimmedText.isEmpty ? "Untitled" : post.trimmedText)
                .font(SavyTypography.displaySerif(22, weight: .regular))
                .foregroundStyle(fg)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(accent).frame(width: 36, height: 2)

            if !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(fg.opacity(0.6))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
    }

    private var kickerText: String {
        [post.platform.label, post.move.label, post.door.label]
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

/// The Posts card on Now — first in the content sections, same shape as the others.
struct SocialPostsHomeCard: View {
    @ObservedObject var store: SocialPostStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("POSTS")
                .font(SavyTheme.readingLabel(12))
                .tracking(1.8)
                .foregroundStyle(SavyTheme.crimson)

            Text("Posts")
                .font(SavyTheme.carouselCardTitle(34))
                .lineSpacing(3)
                .foregroundStyle(SavyTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(headline)
                .font(SavyTheme.readingBody(17))
                .lineSpacing(4)
                .foregroundStyle(SavyTheme.secondaryText)
                .lineLimit(3)

            HStack {
                Text("\(store.posts.count) ITEMS")
                    .font(SavyTheme.readingLabel(12))
                    .tracking(1.4)
                    .foregroundStyle(SavyTheme.tertiaryText)
            }
        }
        .padding(.horizontal, RootHomeLayout.horizontalPadding)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, minHeight: RootHomeLayout.contentSectionMinHeight, alignment: .topLeading)
        .background(Color.white)
    }

    private var headline: String {
        if store.posts.isEmpty {
            return "Building meaning in public."
        }
        var parts: [String] = []
        if !store.ready.isEmpty { parts.append("\(store.ready.count) ready") }
        if !store.drafts.isEmpty {
            parts.append(store.drafts.count == 1 ? "1 draft" : "\(store.drafts.count) drafts")
        }
        parts.append("\(store.posted.count) posted")
        parts.append("jabs \(store.postedJabCount) · hooks \(store.postedHookCount)")
        return parts.joined(separator: " · ")
    }
}
