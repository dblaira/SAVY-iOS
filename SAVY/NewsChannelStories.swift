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
                    .foregroundStyle(SavyTheme.deepNavy)
                Spacer()
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
                .accessibilityLabel("New story")
                .accessibilityIdentifier("newStory")
            }
            .padding(.top, 6)

            if !store.ordered.isEmpty {
                SavyCardFlow(spacing: 14) {
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

/// Stories have no pin state, so every list card uses the shared compact presentation.
/// The full subtitle, body, and publication metadata remain in the story editor.
struct NewsChannelStoryRow: View {
    let story: Story

    var body: some View {
        SavyBandCard(
            bg: .white,
            fg: SavyTheme.ink,
            accent: SavyTheme.crimson,
            title: story.trimmedTitle.isEmpty ? "Untitled" : story.trimmedTitle,
            signalText: "",
            secondaryText: "",
            isCompact: true,
            titleAccessibilityIdentifier: "storyHeadline-\(story.id.uuidString)"
        )
    }
}
