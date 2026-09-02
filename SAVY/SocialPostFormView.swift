import SwiftUI
import UIKit

/// The post form. Same shell as the Reminder / Action / Event form — white page, cream
/// sections, crimson accent, floppy-disk Save — so entry feels identical.
///
/// Field order follows how a post is made: the post itself in Adam's words, then the
/// source it came from, then the connection, then the choices, then what happened
/// after he pressed Post over on X.
struct SocialPostFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let existing: SocialPost?
    let recentAreas: [String]
    var onSave: (SocialPost) -> Void

    @State private var post: SocialPost
    @State private var postedDate: Date
    @State private var areaDraft = ""
    @State private var committed = false
    @State private var cancelled = false
    @State private var showSaved = false
    @State private var showCopied = false

    init(existing: SocialPost?, recentAreas: [String] = [], onSave: @escaping (SocialPost) -> Void) {
        self.existing = existing
        self.recentAreas = recentAreas
        self.onSave = onSave
        let base = existing ?? SocialPost()
        _post = State(initialValue: base)
        _postedDate = State(initialValue: base.postedAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                postSection

                if hasText {
                    sendSection
                }

                sourceSection
                connectionSection
                chooseSection
                statusSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.white.ignoresSafeArea())
            .tint(Brand.crimson)
            .navigationTitle(post.headline)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { cancelled = true; dismiss() } label: {
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
            .onChange(of: post.status) { _, status in
                if status == .posted, post.postedAt == nil {
                    postedDate = Date()
                    post.postedAt = postedDate
                }
            }
            // Swiped away with content, not cancelled: keep it.
            .onDisappear { autosaveIfNeeded() }
        }
        .overlay { if showSaved { toast("Saved") } }
        .overlay { if showCopied { toast("Copied") } }
        .preferredColorScheme(.light)
    }

    // MARK: - Sections

    private var postSection: some View {
        Section {
            TextField(PostFormCopy.postPrompt, text: $post.text, axis: .vertical)
                .lineLimit(3...)
                .textFieldStyle(.plain)
                .font(SavyTypography.displaySerif(22, weight: .regular))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("PostText")

            HStack {
                Text("\(post.characterCount) / \(SocialPost.xCharacterLine)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(post.characterCount > SocialPost.xCharacterLine ? Brand.crimson : .black.opacity(0.45))
                    .accessibilityIdentifier("PostCharacterCount")
                Spacer()
                if post.characterCount > SocialPost.xCharacterLine {
                    Text("Over X's line without Premium")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.crimson)
                }
            }
        } header: { sectionHeader(PostFormCopy.postHeader) }
        .listRowBackground(Brand.card)
    }

    /// Nothing posts on its own. These hand the words to X; Adam presses Post there.
    private var sendSection: some View {
        Section {
            Button {
                copyPost()
            } label: {
                Label("Copy the post", systemImage: "doc.on.doc")
                    .foregroundStyle(Brand.crimson)
            }
            .accessibilityIdentifier("CopyPost")

            if post.platform == .x, let url = post.xComposeURL {
                Button {
                    copyPost(showToast: false)
                    openURL(url)
                } label: {
                    Label("Open X with this post — you press Post", systemImage: "arrow.up.right.square")
                        .foregroundStyle(Brand.crimson)
                }
                .accessibilityIdentifier("OpenX")
            }
        } header: { sectionHeader("Send") }
        .listRowBackground(Brand.card)
    }

    private var sourceSection: some View {
        Section {
            HStack {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("Link", text: $post.sourceLink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("SourceLink")
            }
            HStack {
                Image(systemName: "person").foregroundStyle(.secondary)
                TextField("Who made it", text: $post.sourceName)
                    .accessibilityIdentifier("SourceName")
            }
            TextField(PostFormCopy.linePrompt, text: $post.sourceLine, axis: .vertical)
                .lineLimit(1...)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("SourceLine")
        } header: { sectionHeader(PostFormCopy.sourceHeader) }
        .listRowBackground(Brand.card)
    }

    private var connectionSection: some View {
        Section {
            TextField(PostFormCopy.connectionPrompt, text: $post.connection, axis: .vertical)
                .lineLimit(1...)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("Connection")

            areasEditor
        } header: { sectionHeader(PostFormCopy.connectionHeader) }
        .listRowBackground(Brand.card)
    }

    private var chooseSection: some View {
        Section {
            Picker(selection: $post.move) {
                ForEach(PostMove.allCases) { Text($0.label).tag($0) }
            } label: {
                Label("Jab or Hook", systemImage: "hand.raised")
            }
            .pickerStyle(.segmented)

            enumMenu("Door", icon: "door.left.hand.open", selection: $post.door) { $0.label }
            enumMenu("Platform", icon: "paperplane", selection: $post.platform) { $0.label }
            enumMenu("Pattern", icon: "list.number", selection: $post.pattern) { $0.label }
        } header: { sectionHeader(PostFormCopy.chooseHeader) }
        .listRowBackground(Brand.card)
    }

    private var statusSection: some View {
        Section {
            Picker("Status", selection: $post.status) {
                ForEach(PostStatus.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("PostStatus")

            if post.status == .posted {
                DatePicker("Posted", selection: $postedDate, displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: postedDate) { _, value in post.postedAt = value }

                HStack {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    TextField("Link to the post", text: $post.postLink)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Toggle(isOn: $post.clearSign) {
                    Label("Clear Sign — a creator I respect replied", systemImage: "star")
                }

                Stepper("Replies: \(post.replies)", value: $post.replies, in: 0...1_000_000)
                Stepper("Likes: \(post.likes)", value: $post.likes, in: 0...1_000_000)
                Stepper("Profile taps: \(post.profileTaps)", value: $post.profileTaps, in: 0...1_000_000)
            }
        } header: { sectionHeader(PostFormCopy.statusHeader) }
        .listRowBackground(Brand.card)
    }

    // MARK: - Pieces

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.black.opacity(0.5))
    }

    private func enumMenu<T: CaseIterable & Identifiable & Hashable>(
        _ title: String, icon: String, selection: Binding<T>, label: @escaping (T) -> String
    ) -> some View where T.AllCases: RandomAccessCollection {
        Picker(selection: selection) {
            ForEach(T.allCases) { Text(label($0)).tag($0) }
        } label: {
            Label(title, systemImage: icon)
        }
        .pickerStyle(.menu)
        .tint(Brand.crimson)
    }

    /// Areas the post touches — tap a standing one, or type a new one.
    private var areasEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Areas", systemImage: "tag")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recentAreas, id: \.self) { area in
                        let isOn = post.areas.contains(area)
                        Button {
                            SavyHapticFeedback.selection()
                            if isOn { post.areas.removeAll { $0 == area } } else { post.areas.append(area) }
                        } label: {
                            Text(area)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isOn ? .white : .black)
                                .padding(.vertical, 6).padding(.horizontal, 12)
                                .background(isOn ? Brand.crimson : Color(white: 0.92))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(area)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }

            HStack {
                TextField("Add an area", text: $areaDraft)
                    .onSubmit(addArea)
                    .onChange(of: areaDraft) { _, value in if value.contains(",") { addArea() } }
                Button("Add", action: addArea)
                    .foregroundStyle(Brand.crimson)
                    .disabled(areaDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            let extras = post.areas.filter { !recentAreas.contains($0) }
            if !extras.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(extras, id: \.self) { area in
                            HStack(spacing: 4) {
                                Text(area).font(.system(size: 15, weight: .semibold))
                                Button { post.areas.removeAll { $0 == area } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }.foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5).padding(.horizontal, 10)
                            .background(Color(white: 0.92)).clipShape(Capsule())
                        }
                    }
                }
            }
        }
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

    private var hasText: Bool {
        !post.trimmedText.isEmpty
    }

    private func addArea() {
        let a = areaDraft
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty && !post.areas.contains(a) { post.areas.append(a) }
        areaDraft = ""
    }

    private func copyPost(showToast: Bool = true) {
        UIPasteboard.general.string = post.trimmedText
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard showToast else { return }
        withAnimation(.spring(response: 0.3)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation { showCopied = false }
        }
    }

    private func commit() {
        committed = true
        persist()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.3)) { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { dismiss() }
    }

    private func autosaveIfNeeded() {
        guard !committed, !cancelled, post.hasContent else { return }
        persist()
    }

    private func persist() {
        addArea()
        if post.status == .posted {
            post.postedAt = postedDate
        }
        onSave(post)
    }
}

private enum PostFormCopy {
    static let postHeader = "Post"
    static let postPrompt = "My point of view, word for word"
    static let sourceHeader = "Source"
    static let linePrompt = "The line, the number, the name — exactly as it was"
    static let connectionHeader = "Connection"
    static let connectionPrompt = "Where this touches something else"
    static let chooseHeader = "Choose"
    static let statusHeader = "Status"
}
