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
    @State private var hasTime: Bool
    @State private var hasDefer: Bool
    @State private var hasEnd: Bool
    @State private var date: Date
    @State private var time: Date
    @State private var deferDate: Date
    @State private var endTime: Date
    @State private var tagDraft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var committed = false
    @State private var cancelled = false
    @State private var showSaved = false

    private let listChoices = ["Learning", "Leverage", "Delegation", "Inspiration", "Risk", "Health"]

    init(initialKind: ReminderKind = .reminder, existing: Reminder?, existingTags: [String] = [], onSave: @escaping (Reminder) -> Void) {
        self.existing = existing
        self.existingTags = existingTags
        self.onSave = onSave
        var base = existing ?? Reminder()
        if existing == nil { base.kind = initialKind }
        _r = State(initialValue: base)
        _hasDate = State(initialValue: base.dueDate != nil)
        _hasTime = State(initialValue: base.dueTime != nil)
        _hasDefer = State(initialValue: base.deferDate != nil)
        _hasEnd = State(initialValue: base.endTime != nil)
        _date = State(initialValue: base.dueDate ?? Date())
        _time = State(initialValue: base.dueTime ?? Date())
        _deferDate = State(initialValue: base.deferDate ?? Date())
        _endTime = State(initialValue: base.endTime ?? base.dueTime ?? Date())
        _pickedImage = State(initialValue: LocalImageStore.load(base.imageLocalPath))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $r.kind) {
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
        .preferredColorScheme(.light)
    }

    /// Brief confirmation shown when the Save button is tapped (not on swipe-to-save).
    private var savedToast: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46)).foregroundStyle(Brand.crimson)
                Text("Locked In").font(Brand.serif(30)).foregroundStyle(.black)
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
            TextField("What do I want?", text: $r.title)
                .accessibilityIdentifier("Title")
            TextField("When I am...I like to", text: whenIAmBinding, axis: .vertical).lineLimit(1...3)
            TextField("Done looks like...", text: $r.outcome, axis: .vertical).lineLimit(1...3)
            subtasksEditor("Steps", addLabel: "Add Step")
        } header: { sectionHeader("Delegate") }
        .listRowBackground(Brand.card)

        patternSection

        Section {
            priorityGroup
            effortGroup
            energyGroup
        } header: { sectionHeader("Choose") }
        .listRowBackground(Brand.card)

        Section {
            dateGroup("Due", icon: "calendar", isOn: $hasDate, date: $date)
            dateGroup("Start / defer", icon: "calendar.badge.clock", isOn: $hasDefer, date: $deferDate)
            repeatGroup
            timeGroup("Nudge", icon: "bell", isOn: $hasTime, time: $time)
            timeGroup("End", icon: "clock.badge.checkmark", isOn: $hasEnd, time: $endTime)
        } header: { sectionHeader("Schedule") }
        .listRowBackground(Brand.card)

        Section {
            listGroup
            Toggle(isOn: $r.flag) { Label("Flag", systemImage: "flag") }
            tagsEditor
        } header: { sectionHeader("Organize") }
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

    private var messagingRow: some View {
        HStack {
            Image(systemName: "message").foregroundStyle(.secondary)
            TextField("When messaging a person", text: $r.whenMessagingPerson)
        }
    }

    private func dateGroup(_ title: String, icon: String, isOn: Binding<Bool>, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) { Label(title, systemImage: icon) }
            DatePicker(title, selection: date, displayedComponents: .date)
                .labelsHidden().disabled(!isOn.wrappedValue).opacity(isOn.wrappedValue ? 1 : 0.45)
        }
    }

    private func timeGroup(_ title: String, icon: String, isOn: Binding<Bool>, time: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) { Label(title, systemImage: icon) }
            DatePicker(title, selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden().disabled(!isOn.wrappedValue).opacity(isOn.wrappedValue ? 1 : 0.45)
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
    private var earlyReminderGroup: some View {
        enumMenu("Early Reminder", icon: "bell", selection: $r.earlyReminder) { $0.label }
    }
    private var priorityGroup: some View {
        enumMenu("Priority", icon: "exclamationmark.3", selection: $r.priority) { $0.label }
    }
    private var effortGroup: some View {
        enumMenu("Effort", icon: "timer", selection: $r.effort) { $0.label }
    }
    private var energyGroup: some View {
        enumMenu("Energy", icon: "bolt", selection: $r.energy) { $0.label }
    }
    /// Adam's 8-step success architecture — its own cream section, a clean dropdown.
    private var patternSection: some View {
        Section {
            enumMenu("Pattern", icon: "list.number", selection: $r.context) { $0.label }
        } header: { sectionHeader("Pattern") }
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

    private func subtasksEditor(_ title: String, addLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "checklist")
            ForEach($r.subtasks) { $sub in
                HStack {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                    TextField("Step", text: $sub.title)
                    Button { r.subtasks.removeAll { $0.id == sub.id } } label: {
                        Image(systemName: "minus.circle.fill")
                    }.foregroundStyle(.secondary)
                }
            }
            Button { r.subtasks.append(Subtask()) } label: {
                Text(addLabel).foregroundStyle(Brand.crimson)
            }
        }
    }

    // MARK: - Actions

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
        if r.subtasks.contains(where: { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }) { return true }
        if hasDate || hasTime || hasDefer || hasEnd || pickedImage != nil { return true }
        return false
    }

    private func persist() {
        addTag()
        if let pickedImage {
            r.imageLocalPath = LocalImageStore.save(pickedImage)
        }
        r.dueDate = hasDate ? date : nil
        r.dueTime = hasTime ? time : nil
        r.deferDate = hasDefer ? deferDate : nil
        r.endTime = hasEnd ? endTime : nil
        r.subtasks.removeAll { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        if r.title.trimmingCharacters(in: .whitespaces).isEmpty { r.title = "New \(r.kind.label)" }
        onSave(r)
    }
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
