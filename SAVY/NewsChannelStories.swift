import SwiftUI

/// The Stories area of the News Channel page: the STORIES label, a + for a new story, and
/// Adam's stories as cards. The seeded stories from the site follow below.
struct NewsChannelStoriesGroup: View {
    @ObservedObject var store: StoryStore
    @State private var editing: Story?
    @State private var isComposing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("STORIES")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(.black.opacity(0.42))
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
                .accessibilityLabel("New story")
                .accessibilityIdentifier("newStory")
            }
            .padding(.top, 6)

            ForEach(store.ordered) { story in
                SavySwipeRow(
                    actions: actions(for: story),
                    gestureAccessibilityIdentifier: "storyRow-\(story.id.uuidString)",
                    onTap: { editing = story }
                ) {
                    NewsChannelStoryRow(story: story)
                }
            }
        }
        .sheet(item: $editing) { story in
            StoryFormView(existing: story) { updated in
                store.save(updated)
            }
        }
        .sheet(isPresented: $isComposing) {
            StoryFormView(existing: nil) { story in
                store.save(story)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newsChannelStories")
    }

    private func actions(for story: Story) -> [SavySwipeAction] {
        var list: [SavySwipeAction] = []
        if story.status != .posted {
            list.append(SavySwipeAction(title: "Posted", icon: "checkmark", bg: SavyTheme.crimson) {
                store.markPosted(story)
            })
        }
        list.append(SavySwipeAction(title: "Delete", icon: "trash", bg: Color(hex: 0xB00124)) {
            store.delete(story)
        })
        return list
    }
}

/// One story as a card in the same style as the site's stories: status, title, subtitle, a taste of the body.
struct NewsChannelStoryRow: View {
    let story: Story

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
            }

            Text(story.trimmedTitle.isEmpty ? "Untitled" : story.trimmedTitle)
                .font(SavyTheme.beliefSerif(25))
                .foregroundStyle(SavyTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !story.trimmedSubtitle.isEmpty {
                Text(story.trimmedSubtitle)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .lineSpacing(3)
                    .foregroundStyle(.black.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !story.trimmedBody.isEmpty {
                Text(story.trimmedBody)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(.black.opacity(0.55))
                    .lineLimit(4)
            }

            Text(secondaryText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.black.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }

    private var statusColor: Color {
        switch story.status {
        case .draft: return SavyTheme.bottomNavTan
        case .ready: return SavyTheme.green
        case .posted: return SavyTheme.crimson
        }
    }

    private var kickerText: String {
        "STORY · \(story.status.label.uppercased())"
    }

    private var secondaryText: String {
        var parts: [String] = ["\(story.wordCount) words"]
        if let when = story.whenLabel { parts.append("Posted \(when)") }
        return parts.joined(separator: "   ·   ")
    }
}
