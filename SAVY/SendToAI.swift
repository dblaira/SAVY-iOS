import Foundation
import Combine

/// Adam, 2026-11-07: "I am forced to start every fucking conversation from a blank page."
/// The saved form is the message. One send carries the whole filled-in form and every earlier
/// exchange; the reply comes back in the form's own shape. No chat box anywhere.
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case claude = "Claude"
    case chatGPT = "ChatGPT"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .chatGPT: return "bubble.left.and.text.bubble.right"
        }
    }
}

enum SendToAI {
    static let apiKeyDefaultsKey = "sendToAI.anthropicAPIKey"
    static let providersDefaultsKey = "sendToAI.providers"
    static let model = "claude-opus-5-5"
    static let visualSymbols = ["target", "doc.text", "lightbulb", "person.2"]
    static let respondPrompts = ["What do you want next?", "Which part?", "What must stay?"]
    static let respondSymbols = ["arrow.turn.down.right", "scope", "pin"]

    /// The questions a reply answers, in form order: Decide, then Visual. Each keeps its icon.
    /// Decide questions are editable, so the frozen prompt is the first line of the saved field,
    /// the question as Adam actually asked it; the catalog only supplies the icon.
    static func questions(for entry: Reminder) -> [AIQuestion] {
        let theme = PostThemeCatalog.theme(id: entry.postThemeID)
        let catalog = theme?.questions ?? []
        let saved = entry.postAnswersContainQuestions == true ? (entry.postAnswers ?? []) : []
        let count = max(catalog.count, saved.count)
        let decide = (0..<count).map { index -> AIQuestion in
            let symbol = catalog.indices.contains(index) ? catalog[index].symbol : "text.bubble"
            let fallback = catalog.indices.contains(index) ? catalog[index].prompt : "Decide \(index + 1)"
            guard saved.indices.contains(index) else { return AIQuestion(prompt: fallback, symbol: symbol) }
            let firstLine = saved[index].split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let prompt = firstLine.trimmingCharacters(in: .whitespaces)
            return AIQuestion(prompt: prompt.isEmpty ? fallback : prompt, symbol: symbol)
        }
        let visual = (entry.visualTemplates ?? VisualTemplateDraft()).questions.enumerated().map {
            AIQuestion(prompt: $0.element, symbol: visualSymbols[$0.offset])
        }
        return decide + visual
    }

    /// The chosen providers, remembered between sends. Claude until Adam chooses otherwise.
    static var selectedProviders: Set<AIProvider> {
        get {
            let saved = SendToAIJobs.defaults.stringArray(forKey: providersDefaultsKey) ?? []
            let set = Set(saved.compactMap(AIProvider.init(rawValue:)))
            return set.isEmpty ? [.claude] : set
        }
        set { SendToAIJobs.defaults.set(newValue.map(\.rawValue).sorted(), forKey: providersDefaultsKey) }
    }

    /// Every reply from the first send down to `id`, oldest first.
    static func chain(to id: UUID?, in exchanges: [AIExchange]) -> [AIExchange] {
        var result: [AIExchange] = []
        var next = id
        while let current = next, let exchange = exchanges.first(where: { $0.id == current }) {
            result.insert(exchange, at: 0)
            next = exchange.parentID
        }
        return result
    }

    /// Form follows function: the reply has the form's shape. One line per question, nothing else.
    static func instruction(questionCount: Int, isFollowUp: Bool) -> String {
        var text = """
        This is one filled-in form from SAVY, Adam Blair's app. The questions are the ways he thinks \
        about a thing; his answers sit under each question. Reply with exactly \(questionCount) lines. \
        Line k is your answer to question k, in that order: one or two short sentences, plain words, \
        his words where they exist. No numbering, no labels, no preamble, no blank lines, no headings, \
        no bullets, nothing before line 1 or after line \(questionCount).
        """
        if isFollowUp {
            text += """
             After the form come the earlier exchanges, oldest first, then the new Respond. Every earlier \
            Respond still applies, above all every "What must stay?". Answer what "Which part?" names \
            first and fully. Repeat every answer that does not change word for word, so the unchanged \
            ones can be folded away.
            """
        }
        return text
    }

    /// The message: the form, every earlier exchange in this chain, then the new Respond.
    static func message(form: String, chain: [AIExchange], followUp: [String]) -> String {
        var parts = [form]
        for (index, exchange) in chain.enumerated() {
            if !exchange.followUp.isEmpty {
                let respond = zip(respondPrompts, exchange.followUp).map { "\($0)\n\($1)" }.joined(separator: "\n\n")
                parts.append("Respond \(index + 1)\n\n" + respond)
            }
            let prompts = exchange.questions.map(\.prompt)
            let reply = zip(prompts, exchange.answers).map { "\($0)\n\($1)" }.joined(separator: "\n\n")
            parts.append("Reply \(index + 1) (\(exchange.provider))\n\n" + reply)
        }
        if !followUp.isEmpty {
            let respond = zip(respondPrompts, followUp).map { "\($0)\n\($1)" }.joined(separator: "\n\n")
            parts.append("Respond now\n\n" + respond + "\n\nAnswer the same questions again, changed by what Respond asks for.")
        }
        return parts.joined(separator: "\n\n")
    }

    /// Splits the reply into one answer per question. A reply with the wrong shape still lands
    /// in the first box instead of being lost.
    static func answers(from reply: String, questionCount: Int) -> [String] {
        var lines = reply.split(whereSeparator: \.isNewline).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        lines = lines.map { line in
            // Only a marker followed by a space is a list marker; "3.5 hours" and "-5 degrees" stay whole.
            line.replacingOccurrences(of: "^(\\d+[.)]|[-*•])\\s+", with: "", options: .regularExpression)
        }
        if lines.count == questionCount { return lines }
        if lines.count > questionCount {
            return Array(lines.prefix(questionCount - 1)) + [lines.dropFirst(questionCount - 1).joined(separator: " ")]
        }
        return lines + Array(repeating: "", count: questionCount - lines.count)
    }

    /// The Claude key lives in the device keychain. Adam pastes it once per device.
    static var apiKey: String? {
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty { return key }
        return ClaudeKeyStore.read()
    }

    /// Where the helper lives. The simulator and the Mac app talk to this Mac directly. The phone
    /// reaches the same helper over Adam's Tailscale network: the Mac Studio first, because it
    /// never sleeps, then the laptop. No key ever sits on the phone.
    static var helperURLs: [URL] {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        return [URL(string: "http://127.0.0.1:8787/ask")!]
        #else
        return [URL(string: "http://100.102.153.54:8787/ask")!, URL(string: "http://100.111.154.126:8787/ask")!]
        #endif
    }

    /// Every build can reach both providers through the helper; a Claude key on the device
    /// is used first when one is there.
    static func canReach(_ provider: AIProvider) -> Bool { true }

    static func ask(provider: AIProvider, message: String, questionCount: Int, isFollowUp: Bool) async throws -> [String] {
        let instruction = instruction(questionCount: questionCount, isFollowUp: isFollowUp)
        let reply: String
        if provider == .claude, let key = apiKey {
            reply = try await askAnthropic(form: message, instruction: instruction, key: key)
        } else {
            reply = try await askLocalHelper(provider: provider, prompt: instruction + "\n\n---\n\n" + message)
        }
        return answers(from: reply, questionCount: questionCount)
    }

    /// Anthropic Messages API, called directly from the app with the stored key.
    private static func askAnthropic(form: String, instruction: String, key: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": instruction,
            "messages": [["role": "user", "content": form]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SendToAIError.server(String(data: data, encoding: .utf8) ?? "")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]] ?? []
        let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard !text.isEmpty else { throw SendToAIError.server("empty reply") }
        return text
    }

    /// `script/send-to-ai-helper.py` on Adam's Mac answers through the Claude Code login or the
    /// Codex (ChatGPT) login already on the machine.
    private static func askLocalHelper(provider: AIProvider, prompt: String) async throws -> String {
        var lastError: Error = SendToAIError.server("")
        for url in helperURLs {
            do {
                return try await ask(url: url, provider: provider, prompt: prompt)
            } catch {
                // A Mac that is off, unreachable or not signed in hands the question to the next one.
                lastError = error
            }
        }
        throw lastError
    }

    private static func ask(url: URL, provider: AIProvider, prompt: String) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["provider": provider.rawValue, "prompt": prompt])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw SendToAIError.server(String(data: data, encoding: .utf8) ?? "")
        }
        return text
    }
}

enum SendToAIError: LocalizedError {
    case noKey(AIProvider)
    case server(String)
    var errorDescription: String? {
        switch self {
        case .noKey(let provider): return "No \(provider.rawValue) connection on this device yet."
        case .server(let detail):
            if detail.isEmpty { return "No reply came back." }
            if detail.contains("Could not connect") || detail.contains("timed out") || detail.contains("network connection was lost") {
                return "The Mac did not answer. It has to be awake and on Tailscale."
            }
            return detail
        }
    }
}

/// Keeps every send alive outside any sheet, so closing Respond, leaving the form or relaunching
/// never loses a reply that is on its way. Every request is saved before it is sent and retried
/// after a relaunch; finished replies wait here until the entry takes them.
@MainActor
final class SendToAIJobs: ObservableObject {
    static let shared = SendToAIJobs()
    private static let pendingKey = "sendToAI.pendingRequests"
    private static let finishedKey = "sendToAI.finishedReplies"
    nonisolated private static let draftPrefix = "sendToAI.respondDraft."

    /// Physical-device UI tests write synthetic replies; they never reach the live store.
    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard !SavyRuntime.isTesting else {
            let suite = "com.adamblair.savy.ui-test.send-to-ai"
            let defaults = UserDefaults(suiteName: suite)!
            if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_RESET_REMINDERS") {
                defaults.removePersistentDomain(forName: suite)
            }
            return defaults
        }
        return .standard
    }()

    /// One request as sent: everything needed to ask again after a relaunch or a failure.
    struct Request: Identifiable, Codable, Equatable {
        var id = UUID()
        var entryID: UUID
        var provider: AIProvider
        var parentID: UUID?
        var questions: [AIQuestion]
        var followUp: [String]
        var message: String
    }

    @Published private(set) var inFlight: [UUID] = []
    @Published private(set) var pending: [Request] = []
    @Published private(set) var finished: [UUID: [AIExchange]] = [:]
    @Published private(set) var failures: [UUID: String] = [:]

    private init() {
        let defaults = Self.defaults
        if let data = defaults.data(forKey: Self.finishedKey),
           let saved = try? JSONDecoder().decode([UUID: [AIExchange]].self, from: data) {
            finished = saved
        }
        if let data = defaults.data(forKey: Self.pendingKey),
           let saved = try? JSONDecoder().decode([Request].self, from: data) {
            pending = saved
        }
        // Requests that were on their way when SAVY last closed are asked again.
        for request in pending { dispatch(request) }
    }

    func isSending(_ entryID: UUID) -> Bool {
        pending.contains { $0.entryID == entryID && inFlight.contains($0.id) }
    }

    func hasPending(_ entryID: UUID) -> Bool { pending.contains { $0.entryID == entryID } }

    func send(entryID: UUID, providers: Set<AIProvider>, parentID: UUID?, questions: [AIQuestion],
              followUp: [String], message: String) {
        failures[entryID] = nil
        // A new send replaces whatever was still waiting for this entry.
        pending.removeAll { $0.entryID == entryID && !inFlight.contains($0.id) }
        for provider in providers.sorted(by: { $0.rawValue < $1.rawValue }) {
            let request = Request(entryID: entryID, provider: provider, parentID: parentID,
                                  questions: questions, followUp: followUp, message: message)
            pending.append(request)
            persistPending()
            dispatch(request)
        }
    }

    /// Asks again for everything still waiting on this entry.
    func retry(_ entryID: UUID) {
        failures[entryID] = nil
        for request in pending where request.entryID == entryID && !inFlight.contains(request.id) {
            dispatch(request)
        }
    }

    private func dispatch(_ request: Request) {
        guard !inFlight.contains(request.id) else { return }
        inFlight.append(request.id)
        Task {
            do {
                let replies = try await SendToAI.ask(provider: request.provider, message: request.message,
                                                     questionCount: request.questions.count,
                                                     isFollowUp: request.parentID != nil)
                let exchange = AIExchange(provider: request.provider.rawValue, parentID: request.parentID,
                                          questions: request.questions, followUp: request.followUp, answers: replies)
                finished[request.entryID, default: []].append(exchange)
                persistFinished()
                pending.removeAll { $0.id == request.id }
                persistPending()
                if let parentID = request.parentID {
                    // The Respond writing has arrived safely; only now does its draft go.
                    Self.saveRespondDraft(["", "", ""], entryID: request.entryID, parentID: parentID)
                }
            } catch {
                // The request stays saved; Try again or the next launch asks once more.
                failures[request.entryID] = "\(request.provider.rawValue): \(error.localizedDescription)"
            }
            inFlight.removeAll { $0 == request.id }
        }
    }

    /// Hands finished replies to their entry and forgets them here.
    func take(for entryID: UUID) -> [AIExchange] {
        // Read before mutating: touching the published dictionary with nothing to take would
        // announce a change, and the form listens for changes.
        guard let replies = finished[entryID], !replies.isEmpty else { return [] }
        finished.removeValue(forKey: entryID)
        persistFinished()
        return replies
    }

    func clearFailure(_ entryID: UUID) { failures[entryID] = nil }

    private func persistFinished() {
        if let data = try? JSONEncoder().encode(finished) {
            Self.defaults.set(data, forKey: Self.finishedKey)
        }
    }

    private func persistPending() {
        if let data = try? JSONEncoder().encode(pending) {
            Self.defaults.set(data, forKey: Self.pendingKey)
        }
    }

    // Unsent Respond writing, kept per entry and reply until the reply it asked for arrives.
    nonisolated static func respondDraft(entryID: UUID, parentID: UUID) -> [String] {
        defaults.stringArray(forKey: draftPrefix + "\(entryID).\(parentID)") ?? ["", "", ""]
    }
    nonisolated static func saveRespondDraft(_ draft: [String], entryID: UUID, parentID: UUID) {
        let key = draftPrefix + "\(entryID).\(parentID)"
        if draft.allSatisfy({ $0.isEmpty }) { defaults.removeObject(forKey: key) }
        else { defaults.set(draft, forKey: key) }
    }
}


/// One keychain item for the Claude key. Never leaves the device, never syncs.
enum ClaudeKeyStore {
    private static let service = "com.adamblair.savy.sendToAI"
    private static let account = "anthropic_api_key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(query as CFDictionary)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return true }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
