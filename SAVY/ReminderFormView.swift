import SwiftUI
import PhotosUI
import UIKit

/// The entry form. One shared Action-style capture flow for Reminder, Action, and Event entries:
/// the top selector changes where the saved item lands, while the field order stays identical.
struct ReminderFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = LocationProvider()

    let existing: Reminder?
    let existingTags: [String]
    var onSave: (Reminder) -> Void

    @State private var r: Reminder
    @State private var hasDate: Bool
    @State private var hasDefer: Bool
    @State private var date: Date
    @State private var deferDate: Date
    @State private var tagDraft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var committed = false
    @State private var cancelled = false
    @State private var showSaved = false
    @State private var showCowboyAnswer = false
    @StateObject private var cowboyAI = SavyCowboyAIController()
    @FocusState private var focusedSubtaskID: UUID?
    @State private var subtasks: [Subtask]

    private let listChoices = ["Learning", "Leverage", "Delegation", "Inspiration", "Risk", "Health"]

    private static func dueDateTime(on date: Date, at time: Date? = nil) -> Date {
        let calendar = Calendar.current
        let defaultTime = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time ?? defaultTime)
        return calendar.date(bySettingHour: timeComponents.hour ?? 12, minute: timeComponents.minute ?? 0, second: 0, of: date) ?? date
    }

    init(initialKind: ReminderKind = .reminder, existing: Reminder?, existingTags: [String] = [], onSave: @escaping (Reminder) -> Void) {
        self.existing = existing
        self.existingTags = existingTags
        self.onSave = onSave
        var base = existing ?? Reminder()
        if existing == nil {
            base.kind = initialKind
            if initialKind == .event { base.dueDate = Date() }
        }
        _r = State(initialValue: base)
        _subtasks = State(initialValue: base.subtasks)
        _hasDate = State(initialValue: base.dueDate != nil)
        _hasDefer = State(initialValue: base.deferDate != nil)
        _date = State(initialValue: Self.dueDateTime(on: base.dueDate ?? Date(), at: base.dueTime))
        _deferDate = State(initialValue: base.deferDate ?? Date())
        _pickedImage = State(initialValue: LocalImageStore.load(base.imageLocalPath))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(EntryFormCopy.destinationPickerTitle, selection: $r.kind) {
                        ForEach(ReminderKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Brand.card)

                unifiedEntrySections
            }
            .scrollContentBackground(.hidden)
            .background(Color.white.ignoresSafeArea())
            .tint(Brand.crimson)
            // Header mirrors the Title as you type — the type name until the first character, then
            // the live title at full size. Compact icon buttons leave it more room.
            .navigationTitle(r.title.trimmingCharacters(in: .whitespaces).isEmpty ? r.kind.label : r.title)
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
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            // Auto-save: if the form is swiped away (not via Cancel) and has content, keep it.
            .onDisappear { autosaveIfNeeded() }
        }
        .overlay { if showSaved { savedToast } }
        .sheet(isPresented: $showCowboyAnswer, onDismiss: cowboyAI.clearAnswer) {
            if let answer = cowboyAI.answer {
                SavyCowboyAIAnswerView(answer: answer) {
                    keepCowboyAIAnswerInNotes(answer)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    /// Brief confirmation shown when the Save button is tapped (not on swipe-to-save).
    private var savedToast: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46)).foregroundStyle(Brand.crimson)
                Text("Harnessed!").font(Brand.serif(30)).foregroundStyle(.black)
            }
            .padding(.horizontal, 40).padding(.vertical, 30)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.2), radius: 28, y: 12)
        }
        .transition(.opacity)
    }

    // MARK: - Shared entry flow

    @ViewBuilder private var unifiedEntrySections: some View {
        Section {
            // Grow with content so every character stays visible — no mid-word "..." cutoff.
            TextField(EntryFormCopy.wantPrompt, text: $r.title, axis: .vertical)
                .lineLimit(1...)
                .textFieldStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("Title")
            TextField(EntryFormCopy.whenPrompt, text: whenIAmBinding, axis: .vertical)
                .lineLimit(1...)
                .textFieldStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("WhenIAm")
            TextField(EntryFormCopy.donePrompt, text: $r.outcome, axis: .vertical)
                .lineLimit(1...)
                .textFieldStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("DoneLooksLike")
        } header: { sectionHeader(EntryFormCopy.delegateHeader) }
        .listRowBackground(Brand.card)

        Section {
            Button {
                Task {
                    await cowboyAI.ask(rawWords: cowboyAIRawWords)
                    showCowboyAnswer = cowboyAI.answer != nil
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                    Text(cowboyAI.isAsking ? "Asking CowboyAI…" : "Ask CowboyAI")
                    Spacer()
                    if cowboyAI.isAsking { ProgressView() }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Brand.card)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 4)
                .background(SavyTheme.deepNavy, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(cowboyAI.isAsking || !hasSpeakableEntryText)
            .accessibilityIdentifier("askCowboyAI")

            if let error = cowboyAI.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.darkRed)
                    .accessibilityIdentifier("cowboyAIError")
            }
        } header: {
            sectionHeader("Use it")
        }
        .listRowBackground(Brand.card)

        if hasSpeakableEntryText {
            Section {
                CowboyNaturalVoicePanel(
                    text: speakableEntryText,
                    accessibilityIdentifier: "entryFormNaturalVoice"
                )
                .listRowInsets(EdgeInsets())
            } header: {
                sectionHeader("Hear it back")
            }
            .listRowBackground(Color.clear)
        }

        stepsSection

        organizationSection

        Section {
            priorityGroup
            energyGroup
        } header: { sectionHeader(EntryFormCopy.chooseHeader) }
        .listRowBackground(Brand.card)

        Section {
            dateGroup("Start", icon: "calendar.badge.clock", isOn: $hasDefer, date: $deferDate)
            dueDateTimeGroup
            repeatGroup
        } header: { sectionHeader(EntryFormCopy.scheduleHeader) }
        .listRowBackground(Brand.card)

        Section {
            TextField("Notes", text: $r.notes, axis: .vertical).lineLimit(1...5)
            urlField("Link")
            imageRow
        } header: { sectionHeader("Details") }
        .listRowBackground(Brand.card)

        Section {
            locationRow
            HStack {
                Image(systemName: "person").foregroundStyle(.secondary)
                TextField("Waiting on / delegate to", text: $r.waitingOn)
            }
        } header: { sectionHeader("Place / People") }
        .listRowBackground(Brand.card)
    }

    // MARK: - Reusable field groups

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.black.opacity(0.5))
    }

    private func urlField(_ placeholder: String) -> some View {
        TextField(placeholder, text: $r.url)
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
    }

    private var whenIAmBinding: Binding<String> {
        Binding(
            get: { r.whenIAm ?? "" },
            set: { r.whenIAm = $0 }
        )
    }

    private var speakableEntryText: String {
        [
            r.title,
            r.whenIAm ?? "",
            r.outcome,
            r.notes,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private var hasSpeakableEntryText: Bool {
        !speakableEntryText.isEmpty
    }

    private var cowboyAIRawWords: String {
        [
            (EntryFormCopy.wantPrompt, r.title),
            (EntryFormCopy.whenPrompt, r.whenIAm ?? ""),
            (EntryFormCopy.donePrompt, r.outcome),
            ("Notes", r.notes),
        ]
        .compactMap { label, words in
            let exactWords = words.trimmingCharacters(in: .whitespacesAndNewlines)
            return exactWords.isEmpty ? nil : "\(label)\n\(exactWords)"
        }
        .joined(separator: "\n\n")
    }

    private func keepCowboyAIAnswerInNotes(_ answer: SavyCowboyAIAnswer) {
        let block = "CowboyAI\n\(answer.noteText)"
        if r.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            r.notes = block
        } else if !r.notes.contains(block) {
            r.notes += "\n\n\(block)"
        }
    }

    private var imageRow: some View {
        let hasPickedImage = pickedImage != nil

        return HStack {
            Label("Image", systemImage: "photo")
            Spacer()
            if let img = pickedImage {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(hasPickedImage ? "Change" : "Add").foregroundStyle(Brand.crimson)
            }
        }
    }

    private var locationRow: some View {
        HStack {
            Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
            TextField("Location", text: $r.locationName)
            Button {
                Task { if let name = await location.currentPlaceName() { r.locationName = name } }
            } label: {
                if location.isResolving { ProgressView() } else { Image(systemName: "location") }
            }.foregroundStyle(Brand.crimson)
        }
    }

    private func dateGroup(_ title: String, icon: String, isOn: Binding<Bool>, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) { Label(title, systemImage: icon) }
            DatePicker(title, selection: date, displayedComponents: .date)
                .labelsHidden().disabled(!isOn.wrappedValue).opacity(isOn.wrappedValue ? 1 : 0.45)
        }
    }

    private var dueDateTimeGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $hasDate) { Label("Due", systemImage: "calendar") }
            DatePicker("Due", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden().disabled(!hasDate).opacity(hasDate ? 1 : 0.45)
        }
        .onChange(of: hasDate) { _, isEnabled in
            if isEnabled { date = Self.dueDateTime(on: date) }
        }
    }

    /// A single clean dropdown row for a CaseIterable enum selector.
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

    private var repeatGroup: some View {
        enumMenu("Repeat", icon: "repeat", selection: $r.repeatRule) { $0.label }
    }
    private var priorityGroup: some View {
        enumMenu("Priority", icon: "exclamationmark.3", selection: $r.priority) { $0.label }
    }
    private var energyGroup: some View {
        enumMenu("Energy", icon: "bolt", selection: $r.energy) { $0.label }
    }
    /// One organizing area: Pattern first, then Lift and Tags at the same hierarchy level.
    private var organizationSection: some View {
        Section {
            enumMenu(EntryFormCopy.patternTitle, icon: "list.number", selection: $r.context) { $0.label }
            listGroup
            tagsEditor
        } header: { sectionHeader(EntryFormCopy.patternHeader) }
        .listRowBackground(Brand.card)
    }
    private var listGroup: some View {
        Picker(selection: $r.listName) {
            Text("None").tag("")
            ForEach(listChoices, id: \.self) { Text($0).tag($0) }
        } label: {
            Label("Lift", systemImage: "sparkles")
        }
        .pickerStyle(.menu)
        .tint(Brand.crimson)
    }

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tags", systemImage: "tag")
            HStack {
                TextField("Add a tag", text: $tagDraft)
                    .onSubmit(addTag)
                    .onChange(of: tagDraft) { _, value in if value.contains(",") { addTag() } }
                Button("Add", action: addTag)
                    .foregroundStyle(Brand.crimson)
                    .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !suggestedTags.isEmpty {
                Menu {
                    ForEach(suggestedTags, id: \.self) { tag in
                        Button(tag) { addExistingTag(tag) }
                    }
                } label: {
                    HStack {
                        Label("Add a recent tag", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .tint(Brand.crimson)
            }
            if !r.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(r.tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag).font(.system(size: 15, weight: .semibold))
                                Button { r.tags.removeAll { $0 == tag } } label: {
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

    private var stepsSection: some View {
        Section {
            ForEach($subtasks) { $sub in
                HStack {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                    TextField("Step", text: $sub.title)
                        .focused($focusedSubtaskID, equals: sub.id)
                    Button { subtasks.removeAll { $0.id == sub.id } } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("removeStep")
                }
            }

            Button(action: addSubtask) {
                Text(EntryFormCopy.addStepTitle).foregroundStyle(Brand.crimson)
            }
        } header: {
            sectionHeader(EntryFormCopy.stepsTitle)
        }
        .listRowBackground(Brand.card)
    }

    // MARK: - Actions

    private func addSubtask() {
        let subtask = Subtask()
        subtasks.append(subtask)
        DispatchQueue.main.async { focusedSubtaskID = subtask.id }
    }

    private func addTag() {
        let t = tagDraft
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        if !t.isEmpty && !r.tags.contains(t) { r.tags.append(t) }
        tagDraft = ""
    }

    /// Previously-used tags not already on this item (most-used first, supplied by the caller).
    private var suggestedTags: [String] { existingTags.filter { !r.tags.contains($0) } }

    private func addExistingTag(_ tag: String) {
        if !r.tags.contains(tag) { r.tags.append(tag) }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                pickedImage = img
            }
        }
    }

    private func commit() {
        committed = true
        persist()
        // Adam's list #7: every saved entry rides home to the Harness
        // Delegation queue through the shared iCloud pocket -- his
        // three sentences (want / when I am / done), verbatim. No new
        // menu options; the toast says where it went: "Harnessed!"
        HarnessDelegationWriter.write(
            want: r.title,
            think: r.whenIAm ?? "",
            done: r.outcome
        )
        HarnessedRegistry.mark(r)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.3)) { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { dismiss() }
    }

    /// Save when the sheet is dismissed by swiping (not Cancel) and the user actually entered something.
    private func autosaveIfNeeded() {
        guard !committed, !cancelled, hasContent else { return }
        persist()
    }

    private var hasContent: Bool {
        if !r.title.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if !r.notes.isEmpty || !r.outcome.isEmpty || !(r.whenIAm ?? "").isEmpty || !r.url.isEmpty { return true }
        if !r.locationName.isEmpty || !r.waitingOn.isEmpty { return true }
        if !r.tags.isEmpty { return true }
        if subtasks.contains(where: { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }) { return true }
        if hasDate || hasDefer || pickedImage != nil { return true }
        return false
    }

    private func persist() {
        addTag()
        if let pickedImage {
            r.imageLocalPath = LocalImageStore.save(pickedImage)
        }
        r.dueDate = hasDate ? date : nil
        r.dueTime = hasDate ? date : nil
        r.deferDate = hasDefer ? deferDate : nil
        r.endTime = nil
        r.subtasks = subtasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        if r.title.trimmingCharacters(in: .whitespaces).isEmpty { r.title = "New \(r.kind.label)" }
        onSave(r)
    }
}

private enum EntryFormCopy {
    static let destinationPickerTitle = "Destination"
    static let delegateHeader = "Delegate"
    static let patternHeader = "Pattern"
    static let chooseHeader = "Choose"
    static let scheduleHeader = "Schedule"
    static let wantPrompt = "What do I want?"
    static let whenPrompt = "When I am...I like to"
    static let donePrompt = "Done looks like..."
    static let stepsTitle = "Steps"
    static let addStepTitle = "Add Step"
    static let patternTitle = "Pattern"
}

// MARK: - Save (floppy disk) icon

/// A classic floppy-disk "save" glyph drawn as line art — iOS has no built-in floppy symbol.
/// Body with a beveled top-right corner, a shutter window up top, and a label at the bottom.
struct FloppyDisk: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.midX - s / 2, oy = rect.midY - s / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x / 24 * s, y: oy + y / 24 * s) }
        var p = Path()
        // Body outline (rounded corners, beveled top-right)
        p.move(to: pt(3, 2))
        p.addLine(to: pt(16, 2))
        p.addLine(to: pt(22, 8))
        p.addLine(to: pt(22, 21))
        p.addQuadCurve(to: pt(21, 22), control: pt(22, 22))
        p.addLine(to: pt(3, 22))
        p.addQuadCurve(to: pt(2, 21), control: pt(2, 22))
        p.addLine(to: pt(2, 3))
        p.addQuadCurve(to: pt(3, 2), control: pt(2, 2))
        p.closeSubpath()
        // Shutter window (open at the top edge)
        p.move(to: pt(8, 2))
        p.addLine(to: pt(8, 9))
        p.addLine(to: pt(15, 9))
        p.addLine(to: pt(15, 2))
        // Label (rounded top, open at the bottom edge)
        p.move(to: pt(6, 22))
        p.addLine(to: pt(6, 15))
        p.addQuadCurve(to: pt(7, 14), control: pt(6, 14))
        p.addLine(to: pt(17, 14))
        p.addQuadCurve(to: pt(18, 15), control: pt(18, 14))
        p.addLine(to: pt(18, 22))
        return p
    }
}

struct SaveDiskIcon: View {
    var size: CGFloat = 24
    var body: some View {
        FloppyDisk()
            .stroke(Color.black, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
