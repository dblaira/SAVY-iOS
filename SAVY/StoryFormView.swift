import SwiftUI
import UIKit

/// The Story form — the long form. Title, Subtitle, and a body that takes pasted writing as it
/// is: bullets, numbered lines, quotes, blank lines. Same shell as the post form.
struct StoryFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let existing: Story?
    var onSave: (Story) -> Bool
    private let recoveryID: String

    @State private var story: Story
    @State private var postedDate: Date
    @State private var committed = false
    @State private var cancelled = false
    @State private var showSaved = false
    @State private var showCopied = false
    @State private var saveFailed = false

    init(existing: Story?, recoveryDraft: EntryRecoveryDraft? = nil, onSave: @escaping (Story) -> Bool) {
        self.existing = existing
        self.onSave = onSave
        recoveryID = recoveryDraft?.id ?? EntryRecoveryDraft.storyKey(existing)
        if case .story(let writing) = (recoveryDraft ?? EntryDraftStore.shared.draft(for: recoveryID))?.contents {
            _story = State(initialValue: writing.story)
            _postedDate = State(initialValue: writing.postedDate)
            return
        }
        let base = existing ?? Story()
        _story = State(initialValue: base)
        _postedDate = State(initialValue: base.postedAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                bodySection
                if story.hasContent {
                    sendSection
                }
                statusSection
            }
            .scrollContentBackground(.hidden)
            .background(SavyTheme.pageBackground.ignoresSafeArea())
            .tint(Brand.crimson)
            .savyPageTitle(story.headline, color: SavyTheme.deepNavy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { cancel() } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 22))
                    }
                    .tint(.black)
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { commit() } label: {
                        SaveDiskIcon(size: 24)
                    }
                    .accessibilityLabel("Save")
                }
            }
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .onChange(of: story.status) { _, status in
                if status == .posted, story.postedAt == nil {
                    postedDate = Date()
                    story.postedAt = postedDate
                }
            }
            .onDisappear { autosaveIfNeeded() }
            .onChange(of: recoveryContents) { _, _ in saveRecoveryDraft() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { saveRecoveryDraft() } }
            .alert("Couldn't save Story", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Keep this form open. Your latest changes could not be saved to this device.")
            }
        }
        .overlay { if showSaved { toast("Saved") } }
        .overlay { if showCopied { toast("Copied") } }
        .preferredColorScheme(.light)
        .savyMacFormSheet()
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField("Title", text: $story.title, axis: .vertical)
                .lineLimit(1...)
                .textFieldStyle(.plain)
                .font(SavyTypography.displaySerif(26, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("StoryTitle")

            TextField("Subtitle", text: $story.subtitle, axis: .vertical)
                .lineLimit(1...)
                .textFieldStyle(.plain)
                .font(SavyTypography.displaySerif(20, weight: .regular))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("StorySubtitle")
        } header: { sectionHeader("Story") }
        .listRowBackground(Brand.card)
    }

    /// The body keeps pasted writing exactly as it arrives. Grows with the text; nothing is cut off.
    private var bodySection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if story.body.isEmpty {
                    Text("Paste or write the body — bullets, numbered lists, and quotes stay as written")
                        .font(.system(size: 17))
                        .foregroundStyle(.black.opacity(0.3))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: $story.body)
                    .font(.system(size: 17))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 320)
                    .accessibilityIdentifier("StoryBody")
            }

            HStack {
                Text("\(story.wordCount) words")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.45))
                    .accessibilityIdentifier("StoryWordCount")
                Spacer()
            }
        } header: { sectionHeader("Body") }
        .listRowBackground(Brand.card)
    }

    /// Nothing posts on its own. Copy hands the words to X, YouTube, or wherever he writes.
    private var sendSection: some View {
        Section {
            Button {
                copy(story.trimmedBody)
            } label: {
                Label("Copy the body", systemImage: "doc.on.doc").foregroundStyle(Brand.crimson)
            }
            .disabled(story.trimmedBody.isEmpty)
            .accessibilityIdentifier("CopyStoryBody")

            Button {
                let parts = [story.trimmedTitle, story.trimmedSubtitle].filter { !$0.isEmpty }
                copy(parts.joined(separator: "\n"))
            } label: {
                Label("Copy the title and subtitle", systemImage: "doc.on.doc").foregroundStyle(Brand.crimson)
            }
            .disabled(story.trimmedTitle.isEmpty && story.trimmedSubtitle.isEmpty)
        } header: { sectionHeader("Send") }
        .listRowBackground(Brand.card)
    }

    private var statusSection: some View {
        Section {
            Picker("Status", selection: $story.status) {
                ForEach(PostStatus.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("StoryStatus")

            if story.status == .posted {
                DatePicker("Posted", selection: $postedDate, displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: postedDate) { _, value in story.postedAt = value }
            }
        } header: { sectionHeader("Status") }
        .listRowBackground(Brand.card)
    }

    // MARK: - Pieces

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
    }

    private func toast(_ title: String) -> some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46)).foregroundStyle(Brand.crimson)
                Text(title).font(Brand.serif(30)).foregroundStyle(.black)
            }
            .padding(.horizontal, 40).padding(.vertical, 30)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.2), radius: 28, y: 12)
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.3)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation { showCopied = false }
        }
    }

    private func commit() {
        guard persist() else { saveFailed = true; return }
        committed = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.3)) { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { dismiss() }
    }

    private func autosaveIfNeeded() {
        guard !committed, !cancelled, story.hasContent else { return }
        if persist() { committed = true } else { saveFailed = true }
    }

    private var recoveryContents: EntryRecoveryDraft.Contents {
        .story(.init(original: existing, story: story, postedDate: postedDate))
    }

    private func saveRecoveryDraft() {
        guard !committed, !cancelled else { return }
        if !EntryDraftStore.shared.save(id: recoveryID, contents: recoveryContents) { saveFailed = true }
    }

    private func cancel() {
        guard EntryDraftStore.shared.remove(recoveryID) else { saveFailed = true; return }
        cancelled = true
        dismiss()
    }

    private func persist() -> Bool {
        if story.status == .posted {
            story.postedAt = postedDate
        }
        guard onSave(story) else { return false }
        return EntryDraftStore.shared.remove(recoveryID)
    }
}
