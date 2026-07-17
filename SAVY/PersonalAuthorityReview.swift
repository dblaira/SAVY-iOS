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

    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var player: AVAudioPlayer?
    private var requestID = UUID()
    private let transport = CowboyNaturalVoiceTransport()
    private static let cacheVersion = "qwen3-tts-voice-design-v1"

    override init() {
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

                    Text("709 signals\nwaiting for you")
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
        .accessibilityLabel("Open Cowboy AI candidate review. 709 signals waiting.")
        .accessibilityIdentifier("personalAuthorityLaunchCard")
    }
}

struct PersonalAuthorityReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = PersonalAuthorityReviewStore()
    @StateObject private var speech = PersonalAuthoritySpeechController()
    @StateObject private var naturalSpeech = CowboyNaturalVoiceController()
    @State private var position = 0

    private var current: PersonalAuthorityCandidate? {
        guard store.candidates.indices.contains(position) else { return nil }
        return store.candidates[position]
    }

    var body: some View {
        ZStack {
            SavyTheme.deepNavy.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                    statusBand
                    reviewSurface
                }
                .padding(.bottom, 42)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.light)
        .onDisappear {
            naturalSpeech.stop()
            speech.stop()
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

                    Text("Teach the model\nwhat is yours.")
                        .font(SavyTypography.displaySerif(49, weight: .bold))
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
                .accessibilityLabel("Close Cowboy AI review")
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
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 24)
    }

    private var statusBand: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: -8) {
                    Text("\(store.candidates.count)")
                        .font(SavyTypography.displaySerif(70, weight: .bold))
                        .foregroundStyle(SavyTheme.crimson)
                    Text("signals that might be you")
                        .font(SavyTypography.displaySerif(26, weight: .bold))
                        .foregroundStyle(SavyTheme.deepNavy)
                }

                Spacer()

                Text("\(Int((store.progress * 100).rounded()))%")
                    .font(SavyTheme.readingLabel(23))
                    .foregroundStyle(SavyTheme.crimson)
            }

            ProgressView(value: store.progress)
                .tint(SavyTheme.crimson)
                .scaleEffect(x: 1, y: 1.8, anchor: .center)

            Text("\(store.reviewedCount) decided  ·  \(store.waitingCount) waiting")
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

    @ViewBuilder
    private var reviewSurface: some View {
        if let error = store.loadError {
            Text(error)
                .font(SavyTheme.readingTitle(20))
                .foregroundStyle(Brand.card)
                .padding(28)
        } else if let candidate = current {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("DOES THIS BELONG TO YOU?")
                        .font(SavyTheme.readingLabel(13))
                        .tracking(1.5)
                        .foregroundStyle(Brand.tan)
                    Spacer()
                    Text(candidate.sourceLabel)
                        .font(SavyTheme.readingLabel(15))
                        .foregroundStyle(SavyTheme.crimson)
                }

                candidateCard(candidate)

                DisclosureGroup("Why Cowboy AI surfaced this") {
                    Text("\(candidate.reason). This is still a candidate, not accepted authority.")
                        .font(SavyTheme.readingBody(14))
                        .foregroundStyle(Brand.card.opacity(0.78))
                        .padding(.top, 8)
                }
                .font(SavyTheme.readingBody(13))
                .tint(Brand.tan)
                .foregroundStyle(Brand.tan)

                listenControls(candidate)
                decisionButtons(candidate)
                candidateNavigation
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 26)
        }
    }

    private func listenControls(_ candidate: PersonalAuthorityCandidate) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("LOCAL NATURAL VOICE")
                    .font(SavyTheme.readingLabel(12))
                    .tracking(1.5)
                    .foregroundStyle(Brand.tan)

                Spacer()
                Text(naturalSpeech.statusLabel)
                    .font(SavyTheme.readingBody(12))
                    .foregroundStyle(Brand.card)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 10) {
                Button {
                    SavyHapticFeedback.selection()
                    naturalSpeech.toggle(text: candidate.text)
                } label: {
                    Label(naturalSpeech.buttonTitle, systemImage: naturalSpeech.buttonSymbol)
                        .font(SavyTheme.readingTitle(18))
                        .foregroundStyle(SavyTheme.deepNavy)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Brand.tan, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(naturalSpeech.isWorking)
                .accessibilityIdentifier("personalAuthorityListen")

                if naturalSpeech.canStop {
                    Button {
                        naturalSpeech.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Brand.card)
                            .frame(width: 58, height: 58)
                            .background(Brand.darkRed, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop reading")
                }
            }

            if let error = naturalSpeech.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(SavyTheme.readingBody(12))
                        .foregroundStyle(Brand.card.opacity(0.78))

                    HStack {
                        Button("Use iPhone voice instead") {
                            speech.toggle(text: candidate.text)
                        }
                        .font(SavyTheme.readingBody(12))
                        .foregroundStyle(Brand.tan)

                        Spacer()

                        Menu("Choose iPhone voice") {
                            ForEach(speech.voiceOptions) { voice in
                                voiceMenuButton(voice)
                            }
                        }
                        .font(SavyTheme.readingBody(12))
                        .foregroundStyle(Brand.tan)
                    }
                }
            }
        }
    }

    private func voiceMenuButton(_ voice: PersonalAuthoritySpeechController.VoiceOption) -> some View {
        Button {
            speech.selectVoice(voice)
        } label: {
            Label(
                voice.displayName,
                systemImage: voice.id == speech.selectedVoiceID
                    ? "checkmark.circle.fill"
                    : "waveform"
            )
        }
    }

    private func candidateCard(_ candidate: PersonalAuthorityCandidate) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("CANDIDATE", systemImage: "sparkles")
                .font(SavyTheme.readingLabel(13))
                .tracking(1.8)
                .foregroundStyle(SavyTheme.crimson)

            ForEach(PersonalAuthorityTextFormatter.blocks(from: candidate.text)) { block in
                switch block.style {
                case .heading:
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(SavyTheme.crimson)
                            .frame(width: 4, height: 42)
                        Text(block.text)
                            .font(SavyTypography.displaySerif(29, weight: .bold))
                            .foregroundStyle(SavyTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
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
                            .lineSpacing(4)
                    }
                }
            }
        }
        .padding(23)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    }

    private func decisionButtons(_ candidate: PersonalAuthorityCandidate) -> some View {
        VStack(spacing: 11) {
            decisionButton(
                title: "Yes, this is mine",
                detail: "Mark it for validated promotion",
                symbol: "checkmark",
                color: SavyTheme.crimson,
                decision: .mine,
                candidate: candidate
            )

            HStack(spacing: 11) {
                decisionButton(
                    title: "Sometimes",
                    detail: "It needs context",
                    symbol: "minus",
                    color: Brand.primaryYellow,
                    decision: .context,
                    candidate: candidate
                )
                decisionButton(
                    title: "No",
                    detail: "Evidence only",
                    symbol: "xmark",
                    color: Color(hex: 0x7D16D8),
                    decision: .evidenceOnly,
                    candidate: candidate
                )
            }
        }
    }

    private func decisionButton(
        title: String,
        detail: String,
        symbol: String,
        color: Color,
        decision: PersonalAuthorityDecision,
        candidate: PersonalAuthorityCandidate
    ) -> some View {
        let isSelected = store.decision(for: candidate) == decision

        return Button {
            SavyHapticFeedback.primaryImpact()
            naturalSpeech.stop()
            speech.stop()
            store.decide(decision, candidate: candidate)
            withAnimation(.easeInOut(duration: 0.2)) {
                position = min(position + 1, max(store.candidates.count - 1, 0))
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : symbol)
                    .font(.system(size: 20, weight: .bold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SavyTheme.readingTitle(16))
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.72)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(decision == .context ? SavyTheme.deepNavy : .white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white, lineWidth: 3)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var candidateNavigation: some View {
        HStack {
            Button {
                naturalSpeech.stop()
                speech.stop()
                position = max(position - 1, 0)
            } label: {
                Label("Previous", systemImage: "arrow.left")
            }
            .disabled(position == 0)

            Spacer()

            Text("\(position + 1) of \(store.candidates.count)")
                .font(SavyTheme.readingBody(12))

            Spacer()

            Button {
                naturalSpeech.stop()
                speech.stop()
                position = min(position + 1, max(store.candidates.count - 1, 0))
            } label: {
                Label("Next", systemImage: "arrow.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(position >= store.candidates.count - 1)
        }
        .font(SavyTheme.readingBody(13))
        .foregroundStyle(Brand.tan)
    }
}

#Preview("Personal Authority Review") {
    PersonalAuthorityReviewView()
}
