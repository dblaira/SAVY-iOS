import SwiftUI
import Combine

/// Adam, 2026-11-07: "I want to keep the way SAVY works, with forms for follow-ups and no bloated
/// conversation screen." History is a list of replies. A reply opens as the form's questions with
/// their icons. Respond is a three-box form, never a chat box.
struct AIHistoryView<Entry: AIExchangeHost>: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var jobs = SendToAIJobs.shared
    @Binding var entry: Entry
    let form: String

    private var exchanges: [AIExchange] { entry.aiExchanges ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Array(exchanges.enumerated().reversed()), id: \.element.id) { index, exchange in
                        NavigationLink {
                            AIReplyView(entry: $entry, form: form, exchangeID: exchange.id)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: AIProvider(rawValue: exchange.provider)?.symbol ?? "sparkle")
                                    .foregroundStyle(Brand.crimson)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Reply \(index + 1) · \(exchange.provider)").foregroundStyle(.black)
                                    Text(exchange.followUp.first.flatMap { $0.isEmpty ? nil : $0 } ?? "The form")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.black.opacity(0.6))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(exchange.sentAt, style: .time)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.black.opacity(0.6))
                            }
                        }
                    }
                }
                .listRowBackground(Brand.card)
            }
            .aiPageStyle(title: "History")
            // Replies finish outside any sheet; take them here too so the list grows while open.
            .onAppear { takeFinishedReplies() }
            .onReceive(jobs.$finished.receive(on: DispatchQueue.main)) { _ in takeFinishedReplies() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { SavyCloseIcon() }
                        .tint(.black)
                }
            }
        }
    }

    private func takeFinishedReplies() {
        let replies = jobs.take(for: entry.id)
        guard !replies.isEmpty else { return }
        entry.aiExchanges = (entry.aiExchanges ?? []) + replies
    }
}

/// One reply, in the form's own shape. ChatGPT, 2026-11-08: answer "Which part?" first and keep the
/// submitted form and unchanged answers behind an expandable row.
struct AIReplyView<Entry: AIExchangeHost>: View {
    @Binding var entry: Entry
    let form: String
    let exchangeID: UUID
    @State private var showsRespond = false
    @State private var showsSubmitted = false
    @State private var showsUnchanged = false

    private var exchanges: [AIExchange] { entry.aiExchanges ?? [] }
    private var exchange: AIExchange? { exchanges.first { $0.id == exchangeID } }
    private var parent: AIExchange? { exchange?.parentID.flatMap { id in exchanges.first { $0.id == id } } }
    private var number: Int { (exchanges.firstIndex { $0.id == exchangeID } ?? 0) + 1 }
    private var questions: [AIQuestion] {
        guard let exchange else { return [] }
        return exchange.questions.isEmpty ? entry.aiQuestions : exchange.questions
    }
    /// Indices whose answer differs from the reply this one responds to. All of them for a first reply.
    private var changed: [Int] {
        guard let exchange else { return [] }
        guard let parent else { return Array(exchange.answers.indices) }
        return exchange.answers.indices.filter { index in
            !parent.answers.indices.contains(index) || parent.answers[index] != exchange.answers[index]
        }
    }
    private var unchanged: [Int] { (exchange?.answers.indices).map { Array($0).filter { !changed.contains($0) } } ?? [] }

    var body: some View {
        Form {
            if let exchange, !exchange.followUp.isEmpty {
                Section {
                    Button { withAnimation { showsSubmitted.toggle() } } label: {
                        HStack(spacing: 12) {
                            Label("Respond", systemImage: "list.bullet.rectangle").foregroundStyle(.black)
                            Spacer()
                            Text(exchange.followUp[1].isEmpty ? exchange.followUp[0] : exchange.followUp[1])
                                .foregroundStyle(Brand.crimson).lineLimit(1)
                            Image(systemName: showsSubmitted ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.crimson)
                        }
                    }
                    if showsSubmitted {
                        ForEach(exchange.followUp.indices, id: \.self) { index in
                            AIQuestionRow(prompt: SendToAI.respondPrompts[index],
                                          symbol: SendToAI.respondSymbols[index],
                                          answer: exchange.followUp[index])
                        }
                    }
                }
                .listRowBackground(Brand.card)
            }
            Section {
                ForEach(changed, id: \.self) { index in row(index) }
                if !unchanged.isEmpty {
                    Button { withAnimation { showsUnchanged.toggle() } } label: {
                        HStack(spacing: 12) {
                            Label("Unchanged", systemImage: "equal.circle").foregroundStyle(.black)
                            Spacer()
                            Text(unchanged.count == 1 ? "1 answer" : "\(unchanged.count) answers")
                                .foregroundStyle(Brand.crimson)
                            Image(systemName: showsUnchanged ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.crimson)
                        }
                    }
                    if showsUnchanged {
                        ForEach(unchanged, id: \.self) { index in row(index) }
                    }
                }
            } header: { AIPage.header("Reply \(number) · \(exchange?.provider ?? "")") }
            .listRowBackground(Brand.card)
            // Room under the last row so the Respond button never covers writing.
            Section { Color.clear.frame(height: 56) }
                .listRowBackground(Color.clear)
        }
        .aiPageStyle(title: "Reply \(number)")
        .safeAreaInset(edge: .bottom) {
            Button { showsRespond = true } label: {
                Label("Respond", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.crimson, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("Respond")
        }
        .sheet(isPresented: $showsRespond) {
            AIRespondView(entry: $entry, form: form, previousID: exchangeID)
        }
    }

    private func row(_ index: Int) -> some View {
        let question = questions.indices.contains(index) ? questions[index] : AIQuestion(prompt: "Answer", symbol: "sparkles")
        return AIQuestionRow(prompt: question.prompt, symbol: question.symbol, answer: exchange?.answers[index] ?? "")
    }
}

/// The follow-up form. Three boxes, who to send to, and Send; the reply lands as the next exchange.
struct AIRespondView<Entry: AIExchangeHost>: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var jobs = SendToAIJobs.shared
    @Binding var entry: Entry
    let form: String
    let previousID: UUID
    @State private var followUp: [String]
    @State private var providers = SendToAI.selectedProviders
    @FocusState private var focused: Int?

    init(entry: Binding<Entry>, form: String, previousID: UUID) {
        _entry = entry
        self.form = form
        self.previousID = previousID
        _followUp = State(initialValue: SendToAIJobs.respondDraft(entryID: entry.wrappedValue.id, parentID: previousID))
    }

    private var canSend: Bool {
        !providers.isEmpty && !followUp.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(0..<3, id: \.self) { index in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: SendToAI.respondSymbols[index])
                                .font(.system(size: 16))
                                .foregroundStyle(Brand.crimson)
                                .frame(width: 24, height: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(SendToAI.respondPrompts[index]).foregroundStyle(.black)
                                TextField("", text: $followUp[index], axis: .vertical)
                                    .lineLimit(1...)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(.black)
                                    .frame(minHeight: 44, alignment: .topLeading)
                                    .focused($focused, equals: index)
                                    .accessibilityIdentifier("Respond\(index)")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { focused = index }
                        .padding(.top, 8)
                    }
                } header: { AIPage.header("Respond") }
                .listRowBackground(Brand.card)
                Section {
                    AIProviderChooser(selection: $providers)
                } header: { AIPage.header("Send to") }
                .listRowBackground(Brand.card)
            }
            .aiPageStyle(title: "Respond")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { SavyCloseIcon() }
                        .tint(.black)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { send() } label: { Image(systemName: "paperplane.fill").font(.system(size: 20)) }
                        .tint(Brand.crimson)
                        .disabled(!canSend)
                        .accessibilityLabel("Send")
                        .accessibilityIdentifier("RespondSend")
                }
            }
            .onAppear { focused = 0 }
            .onChange(of: followUp) { _, draft in
                SendToAIJobs.saveRespondDraft(draft, entryID: entry.id, parentID: previousID)
            }
            .onChange(of: providers) { _, chosen in SendToAI.selectedProviders = chosen }
        }
    }

    private func send() {
        let exchanges = entry.aiExchanges ?? []
        guard let previous = exchanges.first(where: { $0.id == previousID }) else { return }
        let questions = previous.questions.isEmpty ? entry.aiQuestions : previous.questions
        let chain = SendToAI.chain(to: previousID, in: exchanges)
        let message = SendToAI.message(form: form, chain: chain, followUp: followUp)
        jobs.send(entryID: entry.id, providers: providers, parentID: previousID,
                  questions: questions, followUp: followUp, message: message)
        // The draft stays until the reply arrives, so a failed send can be sent again untyped.
        dismiss()
    }
}

/// The Send to AI rows and the Answer section for the forms that are not the shared entry form.
/// Adam, 2026-11-08: "i want it on all forms." Same chooser, same Send, same reply shape, same History.
struct AISendToAISection<Entry: AIExchangeHost>: View {
    @ObservedObject private var jobs = SendToAIJobs.shared
    @Binding var entry: Entry
    let form: String
    /// Section header color: navy on the white forms, white on the navy Story form.
    var headerColor: Color = SavyTheme.deepNavy.opacity(0.72)
    @State private var providers = SendToAI.selectedProviders
    @State private var showsHistory = false

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(headerColor)
    }

    private var isSending: Bool { jobs.isSending(entry.id) }
    private var failure: String? { jobs.failures[entry.id] }

    var body: some View {
        Section {
            AIProviderChooser(selection: $providers)
                .onChange(of: providers) { _, chosen in SendToAI.selectedProviders = chosen }
            Button { send() } label: {
                HStack(spacing: 10) {
                    if isSending {
                        ProgressView().tint(Brand.crimson).frame(width: 24)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Brand.crimson)
                            .frame(width: 24)
                    }
                    Text("Send to AI").foregroundStyle(Brand.crimson)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .disabled(isSending || providers.isEmpty)
            .accessibilityIdentifier("SendToAI")
            if failure != nil, jobs.hasPending(entry.id), !isSending {
                Button { jobs.retry(entry.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                            .foregroundStyle(Brand.crimson)
                            .frame(width: 24)
                        Text("Try again").foregroundStyle(Brand.crimson)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("SendToAIRetry")
            }
        } header: { header("Send to AI") }
        .listRowBackground(Brand.card)
        .onAppear { takeFinishedReplies() }
        .onReceive(jobs.$finished.receive(on: DispatchQueue.main)) { _ in takeFinishedReplies() }
        .sheet(isPresented: $showsHistory) { AIHistoryView(entry: $entry, form: form) }

        if let latest = entry.aiExchanges?.last {
            Section {
                if let failure {
                    Text(failure).foregroundStyle(Brand.crimson).fixedSize(horizontal: false, vertical: true)
                }
                let questions = latest.questions.isEmpty ? entry.aiQuestions : latest.questions
                ForEach(Array(latest.answers.indices), id: \.self) { (index: Int) in
                    let question = questions.indices.contains(index) ? questions[index] : AIQuestion(prompt: "Answer", symbol: "sparkles")
                    AIAnswerField(prompt: question.prompt, symbol: question.symbol, text: answerBinding(index))
                        .accessibilityIdentifier("Answer\(index)")
                }
                Button { showsHistory = true } label: {
                    HStack(spacing: 12) {
                        Label("History", systemImage: "clock").foregroundStyle(.black)
                        Spacer()
                        let count = entry.aiExchanges?.count ?? 0
                        Text(count == 1 ? "1 exchange" : "\(count) exchanges").foregroundStyle(Brand.crimson)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.crimson)
                    }
                }
                .accessibilityIdentifier("AIHistory")
            } header: { header("Answer · \(latest.provider)") }
            .listRowBackground(Brand.card)
        } else if let failure {
            Section {
                Text(failure).foregroundStyle(Brand.crimson).fixedSize(horizontal: false, vertical: true)
            } header: { header("Answer") }
            .listRowBackground(Brand.card)
        }
    }

    private func send() {
        let message = SendToAI.message(form: form, chain: [], followUp: [])
        jobs.send(entryID: entry.id, providers: providers, parentID: nil,
                  questions: entry.aiQuestions, followUp: [], message: message)
    }

    private func takeFinishedReplies() {
        let replies = jobs.take(for: entry.id)
        guard !replies.isEmpty else { return }
        entry.aiExchanges = (entry.aiExchanges ?? []) + replies
    }

    private func answerBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { entry.aiExchanges?.last?.answers[index] ?? "" },
            set: { text in
                guard var exchanges = entry.aiExchanges, var last = exchanges.popLast(),
                      last.answers.indices.contains(index) else { return }
                last.answers[index] = text
                entry.aiExchanges = exchanges + [last]
            }
        )
    }
}

/// A question with its icon and an editable answer under it. Same look as the form rows.
struct AIAnswerField: View {
    let prompt: String
    let symbol: String
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Brand.crimson)
                .frame(width: 24, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(prompt).foregroundStyle(.black)
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(1...)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(prompt)
            }
        }
        .padding(.top, 8)
    }
}

/// Claude and ChatGPT, either or both. Crimson check for chosen, same row look as the form.
struct AIProviderChooser: View {
    @Binding var selection: Set<AIProvider>

    var body: some View {
        HStack(spacing: 20) {
            ForEach(AIProvider.allCases) { provider in
                let chosen = selection.contains(provider)
                Button {
                    if chosen { selection.remove(provider) } else { selection.insert(provider) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(Brand.crimson)
                        Text(provider.rawValue)
                            .foregroundStyle(chosen ? Brand.crimson : .black)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("SendTo\(provider.rawValue)")
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
            Spacer()
        }
    }
}

/// A question with its icon and the answer under it, read-only. Same look as the form rows.
struct AIQuestionRow: View {
    let prompt: String
    let symbol: String
    let answer: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Brand.crimson)
                .frame(width: 24, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(prompt).foregroundStyle(.black)
                Text(answer).foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 8)
    }
}

enum AIPage {
    static func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SavyTheme.deepNavy.opacity(0.72))
    }
}

extension View {
    func aiPageStyle(title: String) -> some View {
        self
            #if !targetEnvironment(macCatalyst)
            .font(.system(size: 17, weight: .regular))
            .dynamicTypeSize(.large)
            .environment(\.legibilityWeight, .regular)
            #endif
            .scrollContentBackground(.hidden)
            .background(SavyTheme.contentBackground.ignoresSafeArea())
            .tint(Brand.crimson)
            .savyPageTitle(title, color: SavyTheme.deepNavy)
    }
}


/// Where the Claude key goes on the phone. One box, Save. The key is kept in the keychain.
struct ClaudeKeyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ClaudeKeyStore.read() ?? ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "key")
                            .font(.system(size: 16))
                            .foregroundStyle(Brand.crimson)
                            .frame(width: 24, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Paste the Claude key").foregroundStyle(.black)
                            SecureField("", text: $key)
                                .textFieldStyle(.plain)
                                .foregroundStyle(.black)
                                .frame(minHeight: 44, alignment: .topLeading)
                                .accessibilityIdentifier("ClaudeKey")
                        }
                    }
                    .padding(.top, 8)
                    if saved {
                        Text("Saved on this device.").foregroundStyle(Brand.crimson)
                    }
                } header: { AIPage.header("Claude key") }
                .listRowBackground(Brand.card)
            }
            .aiPageStyle(title: "Claude key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { SavyCloseIcon() }
                        .tint(.black)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saved = ClaudeKeyStore.save(key)
                    } label: { SaveDiskIcon(size: 24) }
                    .accessibilityLabel("Save")
                }
            }
        }
    }
}
