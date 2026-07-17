import Foundation
import SwiftUI
import AVFoundation
import CryptoKit
import Network

struct PersonalAuthorityCandidatePayload: Decodable {
    let generatedAt: String
    let candidateCount: Int
    let candidates: [PersonalAuthorityCandidate]
}

struct PersonalAuthorityCandidate: Decodable, Identifiable, Equatable {
    let index: Int
    let id: String
    let text: String
    let source: String
    let sourceHash: String
    let signalScore: Int
    let reason: String
    let reviewStatus: String
    let authorityStatus: String

    var sourceLabel: String {
        source == "cursor-data-export" ? "Cursor" : "OpenAI"
    }

    var authoredText: String {
        PersonalAuthorityConferenceClassifier.authoredText(from: text)
    }

    var containsInjectedSystemPrefix: Bool {
        PersonalAuthorityConferenceClassifier.containsInjectedSystemPrefix(text)
    }

    var conferenceStatus: PersonalAuthorityConferenceStatus {
        PersonalAuthorityConferenceClassifier.status(for: authoredText)
    }
}

enum PersonalAuthorityConferenceStatus: String, CaseIterable, Identifiable {
    case ready
    case sourceCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: "READY"
        case .sourceCheck: "CHECK SOURCE"
        }
    }

    var explanation: String {
        switch self {
        case .ready:
            "Matched to an Adam user message with no embedded-source marker."
        case .sourceCheck:
            "May contain a quote, transcript, pasted response, or attributed words."
        }
    }
}

enum PersonalAuthorityConferenceClassifier {
    private static let systemPrefix = try! NSRegularExpression(
        pattern: #"^<system_reminder>.*?</system_reminder>\s*"#,
        options: [.dotMatchesLineSeparators]
    )
    private static let embeddedSourceMarker = try! NSRegularExpression(
        pattern: #"(summar(?:ize|y)|transcript|quoted?|pasted?|following (?:text|article|response|conversation|content)|i especially like these suggestions|the fix:|what (?:claude|chatgpt|the ai|cursor) (?:said|wrote|gave)|assistant(?:’|'| i)s response)"#,
        options: [.caseInsensitive]
    )
    private static let longQuotedBlock = try! NSRegularExpression(
        pattern: #"[“\"](.{120,}?)[”\"]"#,
        options: [.dotMatchesLineSeparators]
    )

    static func containsInjectedSystemPrefix(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return systemPrefix.firstMatch(in: text, range: range) != nil
    }

    static func authoredText(from text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return systemPrefix
            .stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func status(for authoredText: String) -> PersonalAuthorityConferenceStatus {
        let range = NSRange(authoredText.startIndex..<authoredText.endIndex, in: authoredText)
        let hasEmbeddedMarker = embeddedSourceMarker.firstMatch(in: authoredText, range: range) != nil
        let hasLongQuote = longQuotedBlock.firstMatch(in: authoredText, range: range) != nil
        return hasEmbeddedMarker || hasLongQuote ? .sourceCheck : .ready
    }
}

enum PersonalAuthorityDecision: String, Codable, CaseIterable {
    case mine
    case context
    case evidenceOnly
}

struct PersonalAuthorityTextBlock: Identifiable, Equatable {
    enum Style: Equatable {
        case heading
        case body
        case bullet
    }

    let id: Int
    let style: Style
    let text: String
}

enum PersonalAuthorityTextFormatter {
    private static let sectionLabels = [
        "What I want?",
        "How I think about it?",
        "How do I know when I'm done?",
        "How do I know when I’m done?",
        "Objective Measurements:"
    ]

    static func blocks(from text: String) -> [PersonalAuthorityTextBlock] {
        var result: [PersonalAuthorityTextBlock] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let markdownRange = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                append(.heading, String(line[markdownRange.upperBound...]), to: &result)
                continue
            }

            if let label = sectionLabels.first(where: { line.lowercased().hasPrefix($0.lowercased()) }) {
                let exactLabel = String(line.prefix(label.count))
                append(.heading, exactLabel, to: &result)

                let remainder = String(line.dropFirst(label.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    append(.body, remainder, to: &result)
                }
                continue
            }

            if let listRange = line.range(of: #"^(?:[-*•]|\d+[.)])\s+"#, options: .regularExpression) {
                append(.bullet, String(line[listRange.upperBound...]), to: &result)
                continue
            }

            if line.count <= 72, line.hasSuffix("?") || line.hasSuffix(":") {
                append(.heading, line, to: &result)
            } else {
                append(.body, line, to: &result)
            }
        }

        return result
    }

    private static func append(
        _ style: PersonalAuthorityTextBlock.Style,
        _ text: String,
        to result: inout [PersonalAuthorityTextBlock]
    ) {
        result.append(PersonalAuthorityTextBlock(id: result.count, style: style, text: text))
    }
}

@MainActor
final class PersonalAuthoritySpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    struct VoiceOption: Identifiable, Equatable {
        let id: String
        let name: String
        let qualityLabel: String
        let qualityRank: Int
        let language: String

        var displayName: String { "\(name) · \(qualityLabel)" }
    }

    enum Mode {
        case idle
        case speaking
        case paused
    }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var selectedVoiceID: String
    let voiceOptions: [VoiceOption]

    private let synthesizer = AVSpeechSynthesizer()
    private static let selectedVoiceDefaultsKey = "savy.personal-authority-voice.v2"

    override init() {
        let options = Self.availableEnglishVoices()
        voiceOptions = options

        let saved = UserDefaults.standard.string(forKey: Self.selectedVoiceDefaultsKey)
        if let saved, options.contains(where: { $0.id == saved }) {
            selectedVoiceID = saved
        } else {
            selectedVoiceID = options.first?.id ?? AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? ""
        }

        super.init()
        synthesizer.delegate = self
    }

    var selectedVoiceLabel: String {
        voiceOptions.first(where: { $0.id == selectedVoiceID })?.displayName ?? "Apple voice"
    }

    var bestVoiceOptions: [VoiceOption] {
        voiceOptions.filter { $0.qualityRank >= 2 }
    }

    var standardVoiceOptions: [VoiceOption] {
        voiceOptions.filter { $0.qualityRank == 1 }
    }

    var buttonTitle: String {
        switch mode {
        case .idle: "Listen"
        case .speaking: "Pause"
        case .paused: "Continue"
        }
    }

    var buttonSymbol: String {
        switch mode {
        case .idle: "speaker.wave.2.fill"
        case .speaking: "pause.fill"
        case .paused: "play.fill"
        }
    }

    func toggle(text: String) {
        switch mode {
        case .idle:
            start(text: text)
        case .speaking:
            guard synthesizer.pauseSpeaking(at: .word) else { return }
            mode = .paused
        case .paused:
            guard synthesizer.continueSpeaking() else { return }
            mode = .speaking
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        mode = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func selectVoice(_ option: VoiceOption, preview: Bool = true) {
        stop()
        selectedVoiceID = option.id
        UserDefaults.standard.set(option.id, forKey: Self.selectedVoiceDefaultsKey)

        if preview {
            start(text: "This is \(option.name). I can read your Cowboy AI candidates in this voice.")
        }
    }

    private func start(text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: selectedVoiceID)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.25
        synthesizer.speak(utterance)
        mode = .speaking
    }

    private static func availableEnglishVoices() -> [VoiceOption] {
        let preferredNames = ["Ava", "Zoe", "Evan", "Tom", "Samantha", "Nathan", "Allison", "Susan"]

        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .map { voice in
                let rank: Int
                let quality: String
                switch voice.quality {
                case .premium:
                    rank = 3
                    quality = "Premium"
                case .enhanced:
                    rank = 2
                    quality = "Enhanced"
                default:
                    rank = 1
                    quality = "Standard"
                }

                return VoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    qualityLabel: quality,
                    qualityRank: rank,
                    language: voice.language
                )
            }
            .sorted { lhs, rhs in
                if lhs.qualityRank != rhs.qualityRank { return lhs.qualityRank > rhs.qualityRank }
                let lhsUS = lhs.language.lowercased().hasPrefix("en-us")
                let rhsUS = rhs.language.lowercased().hasPrefix("en-us")
                if lhsUS != rhsUS { return lhsUS }
                let lhsPreference = preferredNames.firstIndex(of: lhs.name) ?? preferredNames.count
                let rhsPreference = preferredNames.firstIndex(of: rhs.name) ?? preferredNames.count
                if lhsPreference != rhsPreference { return lhsPreference < rhsPreference }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.mode = .idle
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.mode = .idle
        }
    }
}

@MainActor
final class CowboyNaturalVoiceController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    enum Mode: Equatable {
        case idle
        case findingMac
        case generating
        case playing
        case paused
        case failed(String)
    }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var isDiscovered = false
    @Published var playbackRate: Double {
        didSet {
            let clamped = min(max(playbackRate, Self.minimumPlaybackRate), Self.maximumPlaybackRate)
            if playbackRate != clamped {
                playbackRate = clamped
                return
            }
            UserDefaults.standard.set(playbackRate, forKey: Self.playbackRateDefaultsKey)
            player?.rate = Float(playbackRate)
        }
    }

    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var player: AVAudioPlayer?
    private var requestID = UUID()
    private let transport = CowboyNaturalVoiceTransport()
    private static let cacheVersion = "qwen3-tts-voice-design-v1"
    private static let playbackRateDefaultsKey = "savy.cowboy-natural-voice.playback-rate.v1"
    static let minimumPlaybackRate = 0.75
    static let maximumPlaybackRate = 1.50

    override init() {
        let savedRate = UserDefaults.standard.double(forKey: Self.playbackRateDefaultsKey)
        playbackRate = savedRate == 0
            ? 1.0
            : min(max(savedRate, Self.minimumPlaybackRate), Self.maximumPlaybackRate)
        super.init()
        startDiscovery()
    }

    var statusLabel: String {
        switch mode {
        case .findingMac: "Finding Cowboy AI on this Mac"
        case .generating: "Cowboy AI is creating the voice"
        case .playing, .paused: "Qwen natural voice · local Mac"
        case .failed: "Natural voice needs the Mac"
        case .idle: isDiscovered ? "Qwen natural voice · local Mac" : "Finding Cowboy AI on this Mac"
        }
    }

    var buttonTitle: String {
        switch mode {
        case .idle, .failed: "Listen"
        case .findingMac: "Finding Mac"
        case .generating: "Creating voice"
        case .playing: "Pause"
        case .paused: "Continue"
        }
    }

    var buttonSymbol: String {
        switch mode {
        case .playing: "pause.fill"
        case .paused: "play.fill"
        case .findingMac, .generating: "waveform.badge.magnifyingglass"
        case .idle, .failed: "waveform"
        }
    }

    var isWorking: Bool {
        mode == .findingMac || mode == .generating
    }

    var canStop: Bool {
        mode == .playing || mode == .paused
    }

    var errorMessage: String? {
        guard case .failed(let message) = mode else { return nil }
        return message
    }

    func toggle(text: String) {
        switch mode {
        case .playing:
            player?.pause()
            mode = .paused
        case .paused:
            player?.rate = Float(playbackRate)
            player?.play()
            mode = .playing
        case .findingMac, .generating:
            break
        case .idle, .failed:
            let currentRequest = UUID()
            requestID = currentRequest
            Task { await generateAndPlay(text: text, requestID: currentRequest) }
        }
    }

    func stop() {
        requestID = UUID()
        player?.stop()
        player = nil
        mode = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startDiscovery() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_cowboyai._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoint = results.first?.endpoint
            Task { @MainActor [weak self] in
                self?.endpoint = endpoint
                self?.isDiscovered = endpoint != nil
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor [weak self] in self?.isDiscovered = false }
            }
        }
        self.browser = browser
        browser.start(queue: DispatchQueue(label: "savy.cowboyai.natural-voice"))
    }

    private func generateAndPlay(text: String, requestID: UUID) async {
        if let cached = try? Data(contentsOf: cacheURL(for: text)) {
            play(cached, requestID: requestID)
            return
        }

        mode = .findingMac
        for _ in 0..<40 where endpoint == nil {
            try? await Task.sleep(for: .milliseconds(100))
            guard self.requestID == requestID else { return }
        }
        guard let endpoint else {
            mode = .failed("Cowboy AI could not find the Mac on this network.")
            return
        }

        mode = .generating
        do {
            let audio = try await transport.synthesize(text: text, endpoint: endpoint)
            guard self.requestID == requestID else { return }
            try? FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            try? audio.write(to: cacheURL(for: text), options: .atomic)
            play(audio, requestID: requestID)
        } catch {
            guard self.requestID == requestID else { return }
            mode = .failed(error.localizedDescription)
        }
    }

    private func play(_ data: Data, requestID: UUID) {
        guard self.requestID == requestID else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.enableRate = true
            player.rate = Float(playbackRate)
            player.prepareToPlay()
            player.play()
            self.player = player
            mode = .playing
        } catch {
            mode = .failed("SAVY could not play the natural voice.")
        }
    }

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CowboyNaturalVoice", isDirectory: true)
    }

    private func cacheURL(for text: String) -> URL {
        let digest = SHA256.hash(data: Data("\(Self.cacheVersion)|\(text)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appendingPathComponent("\(digest).wav")
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.player = nil
            self?.mode = .idle
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

struct CowboyVoiceRateControl: View {
    @ObservedObject var controller: CowboyNaturalVoiceController
    var labelColor: Color = SavyTheme.deepNavy
    var accentColor: Color = SavyTheme.crimson

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("SLOWER")
                Spacer()
                Text(String(format: "%.2f×", controller.playbackRate))
                    .accessibilityIdentifier("cowboyVoicePlaybackRate")
                Spacer()
                Text("FASTER")
            }
            .font(SavyTheme.readingLabel(11))
            .tracking(1.2)
            .foregroundStyle(labelColor)

            Slider(
                value: $controller.playbackRate,
                in: CowboyNaturalVoiceController.minimumPlaybackRate...CowboyNaturalVoiceController.maximumPlaybackRate,
                step: 0.05
            )
            .tint(accentColor)
            .accessibilityLabel("Voice speed")
            .accessibilityValue(String(format: "%.2f times", controller.playbackRate))
        }
    }
}

/// Reusable SAVY control for reading meaningful app content through Cowboy AI on Adam's Mac.
struct CowboyNaturalVoicePanel: View {
    let text: String
    var accessibilityIdentifier = "cowboyNaturalVoicePanel"

    @StateObject private var voice = CowboyNaturalVoiceController()

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label("LISTEN WITH COWBOY AI", systemImage: "waveform")
                    .font(SavyTheme.readingLabel(12))
                    .tracking(1.3)
                    .foregroundStyle(SavyTheme.crimson)

                Spacer(minLength: 8)

                Text(voice.statusLabel)
                    .font(SavyTheme.readingBody(11))
                    .foregroundStyle(SavyTheme.deepNavy.opacity(0.62))
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 10) {
                Button {
                    SavyHapticFeedback.selection()
                    voice.toggle(text: text)
                } label: {
                    Label(voice.buttonTitle, systemImage: voice.buttonSymbol)
                        .font(SavyTheme.readingTitle(17))
                        .foregroundStyle(Brand.card)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(SavyTheme.deepNavy, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(voice.isWorking || !hasText)
                .accessibilityIdentifier("\(accessibilityIdentifier)Listen")

                if voice.canStop {
                    Button {
                        voice.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Brand.card)
                            .frame(width: 54, height: 54)
                            .background(Brand.darkRed, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop reading")
                }
            }

            CowboyVoiceRateControl(controller: voice)

            if let error = voice.errorMessage {
                Text(error)
                    .font(SavyTheme.readingBody(12))
                    .foregroundStyle(Brand.darkRed)
            }
        }
        .padding(16)
        .background(Brand.tan.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(SavyTheme.crimson.opacity(0.22), lineWidth: 1)
        }
        .onDisappear { voice.stop() }
    }
}

private enum CowboyNaturalVoiceError: LocalizedError {
    case invalidResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Cowboy AI returned unreadable audio."
        case .server(_, let message): message
        }
    }
}

private final class CowboyNaturalVoiceTransport: @unchecked Sendable {
    func synthesize(text: String, endpoint: NWEndpoint) async throws -> Data {
        let body = try JSONEncoder().encode(["text": text])
        return try await withCheckedThrowingContinuation { continuation in
            let header = [
                "POST /v1/voice/synthesize HTTP/1.1",
                "Host: cowboyai.local",
                "Accept: audio/wav",
                "Content-Type: application/json",
                "Content-Length: \(body.count)",
                "Connection: close",
                "",
                "",
            ].joined(separator: "\r\n")
            var request = Data(header.utf8)
            request.append(body)
            CowboyNaturalVoiceHTTPExchange(
                endpoint: endpoint,
                request: request,
                continuation: continuation
            ).start()
        }
    }
}

private final class CowboyNaturalVoiceHTTPExchange: @unchecked Sendable {
    private let connection: NWConnection
    private let request: Data
    private let continuation: CheckedContinuation<Data, Error>
    private let state = CowboyNaturalVoiceExchangeState()
    private let queue = DispatchQueue(label: "savy.cowboyai.natural-voice.http")

    init(endpoint: NWEndpoint, request: Data, continuation: CheckedContinuation<Data, Error>) {
        connection = NWConnection(to: endpoint, using: .tcp)
        self.request = request
        self.continuation = continuation
    }

    func start() {
        connection.stateUpdateHandler = { [self] connectionState in
            switch connectionState {
            case .ready:
                connection.send(content: request, completion: .contentProcessed { [self] error in
                    if let error { finish(.failure(error)) }
                    else { receiveNext() }
                })
            case .failed(let error):
                finish(.failure(error))
            case .cancelled:
                finish(.failure(CowboyNaturalVoiceError.invalidResponse))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [self] data, _, complete, error in
            if let data { state.append(data) }
            if let error {
                finish(.failure(error))
            } else if complete {
                do { finish(.success(try Self.parseHTTPResponse(state.data))) }
                catch { finish(.failure(error)) }
            } else {
                receiveNext()
            }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard state.markFinished() else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(with: result)
    }

    private static func parseHTTPResponse(_ data: Data) throws -> Data {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator),
              let header = String(data: data[..<range.lowerBound], encoding: .utf8),
              let statusLine = header.components(separatedBy: "\r\n").first,
              let status = Int(statusLine.split(separator: " ").dropFirst().first ?? "") else {
            throw CowboyNaturalVoiceError.invalidResponse
        }
        let body = Data(data[range.upperBound...])
        guard (200..<300).contains(status) else {
            let detail = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["detail"] as? String
                ?? "Cowboy AI could not create the natural voice."
            throw CowboyNaturalVoiceError.server(status, detail)
        }
        guard body.starts(with: Data("RIFF".utf8)) else {
            throw CowboyNaturalVoiceError.invalidResponse
        }
        return body
    }
}

private nonisolated final class CowboyNaturalVoiceExchangeState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var received = Data()

    var data: Data { lock.withLock { received } }

    func append(_ data: Data) {
        lock.withLock { received.append(data) }
    }

    func markFinished() -> Bool {
        lock.withLock {
            guard !finished else { return false }
            finished = true
            return true
        }
    }
}

@MainActor
final class PersonalAuthorityReviewStore: ObservableObject {
    static let reviewDefaultsKey = "savy.personal-authority-review.20260717.v1"

    @Published private(set) var candidates: [PersonalAuthorityCandidate] = []
    @Published private(set) var decisions: [String: PersonalAuthorityDecision] = [:]
    @Published private(set) var loadError: String?

    private let defaults: UserDefaults

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadDecisions()
        loadCandidates(from: bundle)
    }

    var reviewedCount: Int { decisions.count }
    var waitingCount: Int { max(candidates.count - reviewedCount, 0) }
    var progress: Double {
        guard !candidates.isEmpty else { return 0 }
        return Double(reviewedCount) / Double(candidates.count)
    }

    func decision(for candidate: PersonalAuthorityCandidate) -> PersonalAuthorityDecision? {
        decisions[candidate.id]
    }

    func decide(_ decision: PersonalAuthorityDecision, candidate: PersonalAuthorityCandidate) {
        decisions[candidate.id] = decision
        persistDecisions()
    }

    nonisolated static func decodeCandidates(from data: Data) throws -> PersonalAuthorityCandidatePayload {
        try JSONDecoder().decode(PersonalAuthorityCandidatePayload.self, from: data)
    }

    private func loadCandidates(from bundle: Bundle) {
        guard let url = bundle.url(forResource: "PersonalAuthorityCandidates", withExtension: "json") else {
            loadError = "The 709-candidate review file is missing from SAVY."
            return
        }

        do {
            let payload = try Self.decodeCandidates(from: Data(contentsOf: url))
            candidates = payload.candidates
            guard payload.candidateCount == payload.candidates.count else {
                loadError = "The candidate count does not match the bundled review file."
                return
            }
        } catch {
            loadError = "SAVY could not read the candidate review file."
        }
    }

    private func loadDecisions() {
        guard let data = defaults.data(forKey: Self.reviewDefaultsKey),
              let saved = try? JSONDecoder().decode([String: PersonalAuthorityDecision].self, from: data) else {
            return
        }
        decisions = saved
    }

    private func persistDecisions() {
        guard let data = try? JSONEncoder().encode(decisions) else { return }
        defaults.set(data, forKey: Self.reviewDefaultsKey)
    }
}

struct PersonalAuthorityLaunchCard: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomLeading) {
                Image("RetroSignals")
                    .resizable()
                    .scaledToFill()
                    .frame(width: RootHomeLayout.carouselCardWidth, height: RootHomeLayout.carouselCardHeight)
                    .clipped()

                LinearGradient(
                    colors: [.clear, SavyTheme.deepNavy.opacity(0.94)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("COWBOY AI")
                        .font(SavyTheme.readingLabel(12))
                        .tracking(1.8)
                        .foregroundStyle(SavyTheme.crimson)

                    Text("709 statements\nready to scan")
                        .font(SavyTypography.displaySerif(28, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(-2)
                }
                .padding(20)
            }
            .frame(width: RootHomeLayout.carouselCardWidth, height: RootHomeLayout.carouselCardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Cowboy AI confirmation list. 709 statements ready to scan.")
        .accessibilityIdentifier("personalAuthorityLaunchCard")
    }
}

private enum PersonalAuthorityConferenceFilter: String, CaseIterable, Identifiable {
    case all
    case ready
    case sourceCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "ALL"
        case .ready: "READY"
        case .sourceCheck: "CHECK SOURCE"
        }
    }
}

struct PersonalAuthorityReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = PersonalAuthorityReviewStore()
    @State private var filter: PersonalAuthorityConferenceFilter = .all
    @State private var searchText = ""
    @State private var selectedCandidate: PersonalAuthorityCandidate?

    private var readyCount: Int {
        store.candidates.filter { $0.conferenceStatus == .ready }.count
    }

    private var sourceCheckCount: Int {
        store.candidates.filter { $0.conferenceStatus == .sourceCheck }.count
    }

    private var cleanedPrefixCount: Int {
        store.candidates.filter(\.containsInjectedSystemPrefix).count
    }

    private var visibleCandidates: [PersonalAuthorityCandidate] {
        store.candidates.filter { candidate in
            let isInFilter: Bool
            switch filter {
            case .all: isInFilter = true
            case .ready: isInFilter = candidate.conferenceStatus == .ready
            case .sourceCheck: isInFilter = candidate.conferenceStatus == .sourceCheck
            }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || candidate.authoredText.localizedCaseInsensitiveContains(query)
                || candidate.sourceLabel.localizedCaseInsensitiveContains(query)
                || String(candidate.index).contains(query)
            return isInFilter && matchesSearch
        }
    }

    var body: some View {
        ZStack {
            SavyTheme.deepNavy.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                    statusBand
                    conferenceSurface
                }
                .padding(.bottom, 88)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.light)
        .safeAreaInset(edge: .bottom) {
            conferenceBoundary
        }
        .sheet(item: $selectedCandidate) { candidate in
            PersonalAuthorityConferenceDetail(candidate: candidate)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("personalAuthorityReview")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COWBOY AI")
                        .font(SavyTheme.readingLabel(13))
                        .tracking(2.2)
                        .foregroundStyle(SavyTheme.crimson)

                    Text("Confirm what\nyou said.")
                        .font(SavyTypography.displaySerif(52, weight: .bold))
                        .foregroundStyle(Brand.card)
                        .lineSpacing(-6)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 12)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(SavyTheme.deepNavy)
                        .frame(width: 48, height: 48)
                        .background(Brand.card, in: Circle())
                }
                .accessibilityLabel("Close Cowboy AI confirmation list")
            }

            ZStack(alignment: .bottomTrailing) {
                Image("RetroSignals")
                    .resizable()
                    .scaledToFit()
                    .background(Color(hex: 0xECEBE2))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Image("HarnessedHat")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 66, height: 66)
                    .padding(5)
                    .background(Brand.card, in: Circle())
                    .overlay(Circle().stroke(SavyTheme.deepNavy, lineWidth: 5))
                    .padding(12)
            }

            Text("“If I’ve said it, then it is approved.”")
                .font(SavyTypography.displaySerif(27, weight: .bold))
                .foregroundStyle(Brand.card)
                .fixedSize(horizontal: false, vertical: true)

            Text("CONFIRMATION, NOT BELIEF REVIEW")
                .font(SavyTheme.readingLabel(12))
                .tracking(1.6)
                .foregroundStyle(Brand.tan)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 24)
    }

    private var statusBand: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                conferenceMetric(
                    count: readyCount,
                    label: "DIRECT\nMESSAGES",
                    color: SavyTheme.crimson,
                    scale: 1
                )

                conferenceMetric(
                    count: sourceCheckCount,
                    label: "CHECK\nSOURCE",
                    color: Color(hex: 0xE66F24),
                    scale: 0.78
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "scissors")
                    .foregroundStyle(SavyTheme.deepNavy)
                Text("\(cleanedPrefixCount) Cursor system prefixes removed")
                    .font(SavyTheme.readingTitle(15))
                    .foregroundStyle(SavyTheme.deepNavy)
            }

            Text("The cleanup count overlaps the two groups above. Your words after each injected prefix remain intact.")
                .font(SavyTheme.readingBody(13))
                .foregroundStyle(SavyTheme.secondaryText)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .background(Brand.tan)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SavyTheme.crimson).frame(height: 5)
        }
    }

    private func conferenceMetric(
        count: Int,
        label: String,
        color: Color,
        scale: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: -4) {
            Text("\(count)")
                .font(SavyTypography.displaySerif(68 * scale, weight: .bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(SavyTheme.readingLabel(12))
                .tracking(1.2)
                .foregroundStyle(SavyTheme.deepNavy)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .bottomLeading)
    }

    @ViewBuilder
    private var conferenceSurface: some View {
        if let error = store.loadError {
            Text(error)
                .font(SavyTheme.readingTitle(20))
                .foregroundStyle(Brand.card)
                .padding(28)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("SCAN THE EXACT WORDS")
                        .font(SavyTheme.readingLabel(13))
                        .tracking(1.7)
                        .foregroundStyle(Brand.tan)

                    Text("Nothing below is promoted by this screen. You are confirming authorship before Cowboy AI changes the graph.")
                        .font(SavyTheme.readingBody(15))
                        .foregroundStyle(Brand.card.opacity(0.82))
                }

                TextField("Search your words, source, or number", text: $searchText)
                    .font(SavyTheme.readingBody(16))
                    .foregroundStyle(SavyTheme.deepNavy)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(Brand.card, in: RoundedRectangle(cornerRadius: 12))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(PersonalAuthorityConferenceFilter.allCases) { option in
                            conferenceFilterButton(option)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                HStack {
                    Text("\(visibleCandidates.count) shown")
                        .font(SavyTheme.readingLabel(12))
                        .foregroundStyle(Brand.tan)
                    Spacer()
                    Text("Tap any statement to read or listen")
                        .font(SavyTheme.readingBody(12))
                        .foregroundStyle(Brand.card.opacity(0.68))
                }

                LazyVStack(spacing: 12) {
                    ForEach(visibleCandidates) { candidate in
                        conferenceRow(candidate)
                    }
                }
                .accessibilityIdentifier("personalAuthorityConferenceList")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    private func conferenceFilterButton(_ option: PersonalAuthorityConferenceFilter) -> some View {
        return Button {
            SavyHapticFeedback.selection()
            withAnimation(.easeInOut(duration: 0.18)) { filter = option }
        } label: {
            Text(option.title)
                .font(SavyTheme.readingLabel(12))
                .tracking(1.1)
                .foregroundStyle(filter == option ? SavyTheme.deepNavy : Brand.card)
                .padding(.horizontal, 15)
                .frame(minHeight: 42)
                .background(filter == option ? Brand.tan : SavyTheme.deepNavy.opacity(0.18))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Brand.tan.opacity(0.48), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func conferenceRow(_ candidate: PersonalAuthorityCandidate) -> some View {
        let needsCheck = candidate.conferenceStatus == .sourceCheck

        return Button {
            selectedCandidate = candidate
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Text("#\(candidate.index)")
                        .font(SavyTheme.readingLabel(12))
                        .foregroundStyle(SavyTheme.deepNavy)

                    Text(candidate.sourceLabel.uppercased())
                        .font(SavyTheme.readingLabel(11))
                        .foregroundStyle(SavyTheme.secondaryText)

                    Spacer()

                    if candidate.containsInjectedSystemPrefix {
                        Label("PREFIX CLEANED", systemImage: "scissors")
                            .font(SavyTheme.readingLabel(10))
                            .foregroundStyle(SavyTheme.deepNavy)
                    }
                }

                Text(candidate.authoredText)
                    .font(SavyTypography.displaySerif(21, weight: .bold))
                    .foregroundStyle(SavyTheme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    Circle()
                        .fill(needsCheck ? Color(hex: 0xE66F24) : SavyTheme.crimson)
                        .frame(width: 8, height: 8)
                    Text(candidate.conferenceStatus.title)
                        .font(SavyTheme.readingLabel(11))
                        .foregroundStyle(needsCheck ? Color(hex: 0xA44314) : SavyTheme.crimson)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SavyTheme.deepNavy)
                }
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(needsCheck ? Color(hex: 0xE66F24) : SavyTheme.crimson)
                    .frame(width: needsCheck ? 7 : 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("personalAuthorityCandidateRow\(candidate.index)")
    }

    private var conferenceBoundary: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 1) {
                Text("0% PROMOTED")
                    .font(SavyTheme.readingLabel(12))
                    .tracking(1.2)
                Text("This is the list before approval.")
                    .font(SavyTheme.readingBody(12))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .heavy))
                    .frame(width: 40, height: 40)
                    .background(SavyTheme.deepNavy.opacity(0.1), in: Circle())
            }
        }
        .foregroundStyle(SavyTheme.deepNavy)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Brand.tan)
        .overlay(alignment: .top) {
            Rectangle().fill(SavyTheme.crimson).frame(height: 4)
        }
    }
}

private struct PersonalAuthorityConferenceDetail: View {
    @Environment(\.dismiss) private var dismiss
    let candidate: PersonalAuthorityCandidate

    var body: some View {
        ZStack {
            SavyTheme.deepNavy.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("STATEMENT #\(candidate.index)")
                                .font(SavyTheme.readingLabel(13))
                                .tracking(1.5)
                                .foregroundStyle(SavyTheme.crimson)
                            Text(candidate.sourceLabel)
                                .font(SavyTheme.readingBody(13))
                                .foregroundStyle(Brand.tan)
                        }

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(SavyTheme.deepNavy)
                                .frame(width: 44, height: 44)
                                .background(Brand.card, in: Circle())
                        }
                        .accessibilityLabel("Close statement")
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(candidate.conferenceStatus == .ready ? SavyTheme.crimson : Color(hex: 0xE66F24))
                            .frame(width: 11, height: 11)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.conferenceStatus.title)
                                .font(SavyTheme.readingLabel(13))
                                .foregroundStyle(Brand.card)
                            Text(candidate.conferenceStatus.explanation)
                                .font(SavyTheme.readingBody(13))
                                .foregroundStyle(Brand.card.opacity(0.74))
                        }
                    }

                    if candidate.containsInjectedSystemPrefix {
                        Label(
                            "Cursor's injected system reminder is hidden here. The words below begin after that closing tag.",
                            systemImage: "scissors"
                        )
                        .font(SavyTheme.readingBody(13))
                        .foregroundStyle(SavyTheme.deepNavy)
                        .padding(14)
                        .background(Brand.tan, in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 17) {
                        ForEach(PersonalAuthorityTextFormatter.blocks(from: candidate.authoredText)) { block in
                            formattedBlock(block)
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.card, in: RoundedRectangle(cornerRadius: 18))

                    CowboyNaturalVoicePanel(
                        text: candidate.authoredText,
                        accessibilityIdentifier: "personalAuthority"
                    )

                    Text("No approval action exists on this screen. This statement remains candidate-only.")
                        .font(SavyTheme.readingBody(13))
                        .foregroundStyle(Brand.tan)
                        .padding(.bottom, 30)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.light)
        .accessibilityIdentifier("personalAuthorityCandidateDetail")
    }

    @ViewBuilder
    private func formattedBlock(_ block: PersonalAuthorityTextBlock) -> some View {
        switch block.style {
        case .heading:
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(SavyTheme.crimson)
                    .frame(width: 4, height: 38)
                Text(block.text)
                    .font(SavyTypography.displaySerif(27, weight: .bold))
                    .foregroundStyle(SavyTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .body:
            Text(block.text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(SavyTheme.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(Color(hex: 0xE66F24))
                    .frame(width: 8, height: 8)
                Text(block.text)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(SavyTheme.ink)
                    .lineSpacing(4)
            }
        }
    }
}

#Preview("Personal Authority Review") {
    PersonalAuthorityReviewView()
}
