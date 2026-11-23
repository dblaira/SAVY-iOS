import SwiftUI
import WatchKit

// Watch capture kit: the same in every app that uses it.
//
// Adam, Nov 20, 2026: “one large button that I can press. The idea here is to reduce friction,
// so if I'm reducing friction, I just need one button to press. I pressed the button, I record
// it, and then after it's recorded, then there can be some selections.”

enum CaptureRoute: Hashable {
    /// Right after a recording stops: play it, then Save or pick a type.
    case review(UUID)
    /// A saved capture from the recent list.
    case proof(UUID)
}

/// Screen one: one big button. Press to record, press again to stop.
struct CaptureHomeView: View {
    @EnvironmentObject private var store: WatchCaptureStore
    @ObservedObject private var recorder = WatchRecorder.shared
    @ObservedObject private var launch = WatchCaptureLaunch.shared
    @State private var route: CaptureRoute?

    var body: some View {
        NavigationStack {
            Group {
                if recorder.isRecording {
                    RecordingView(recorder: recorder, onStop: stopRecording)
                } else {
                    home
                }
            }
            .background { WatchBackground() }
            .modifier(WatchTitleBar(hidden: recorder.isRecording))
            .navigationDestination(item: $route) { route in
                switch route {
                case .review(let id):
                    ReviewView(captureID: id) { reRecord(replacing: id) }
                case .proof(let id):
                    CaptureProofView(captureID: id)
                }
            }
            .onAppear {
                if launch.takeRecordingRequest() { startRecording() }
            }
            .onChange(of: launch.recordingRequested) { _, requested in
                if requested, launch.takeRecordingRequest() { startRecording() }
            }
            #if DEBUG
            .task { openDemoScreen() }
            #endif
        }
    }

    private var home: some View {
        ScrollView {
            VStack(spacing: 10) {
                RecordButton { startRecording() }
                if let problem = recorder.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(WatchTheme.text)
                        .multilineTextAlignment(.center)
                }
                if store.problem != nil, store.waitingCount > 0 {
// [route icloud]
                    Label("\(store.waitingCount) waiting to send", systemImage: "icloud.slash")
// [route iphone]
                    Label("\(store.waitingCount) waiting for your iPhone", systemImage: "iphone.slash")
// [route end]
                        .font(.footnote)
                        .foregroundStyle(WatchTheme.text)
                }
                if !store.items.isEmpty {
                    recent
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchTheme.text.opacity(0.8))
            ForEach(store.items.prefix(6)) { item in
                Button {
                    route = item.isDraft ? .review(item.id) : .proof(item.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.capture.kind.symbol)
                            .foregroundStyle(WatchTheme.accent)
                        Text(item.capture.summary)
                            .lineLimit(1)
                            .foregroundStyle(WatchTheme.text)
                        Spacer(minLength: 2)
                        Image(systemName: item.statusSymbol)
                            .foregroundStyle(WatchTheme.text.opacity(0.7))
                    }
                    .font(.footnote)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startRecording() {
        guard !recorder.isRecording else { return }
        route = nil
        Task { await recorder.start(into: store.newRecordingURL()) }
    }

    private func stopRecording() {
        guard let result = recorder.stop(),
              let capture = store.keepRecording(at: result.url, duration: result.duration) else { return }
        route = .review(capture.id)
        WatchPhoneLink.shared.askPhoneForWords(capture, audioURL: result.url)
    }

    private func reRecord(replacing id: UUID) {
        store.discardDraft(id)
        route = nil
        startRecording()
    }

    #if DEBUG
    private func openDemoScreen() {
        guard let screen = WatchCaptureDemo.screen, route == nil, !recorder.isRecording,
              let recording = store.seedDemo() else { return }
        switch screen {
        case "recording":
            recorder.showDemoRecording()
        case "review":
            // As if the nearby iPhone had already sent back the words.
            store.applyWordsFromPhone(WatchCaptureKind.saveDefault.demoWords, to: recording.id)
            route = .review(recording.id)
        case "saved":
            store.save(recording.id, as: WatchCaptureKind.saveDefault)
            route = .proof(recording.id)
        default:
            break
        }
    }
    #endif
}

/// The big button. The accent color inside a ring, like a record button.
struct RecordButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(WatchTheme.ring, lineWidth: 5)
                Circle().fill(WatchTheme.accent).padding(11)
                Image(systemName: "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(WatchTheme.door)
            }
            .frame(width: 128, height: 128)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record")
        .accessibilityIdentifier("WatchRecordButton")
    }
}

/// Screen two: the time, the moving level, and the stop button.
struct RecordingView: View {
    @ObservedObject var recorder: WatchRecorder
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(recordingClock(recorder.elapsed))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchTheme.strongText)
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(WatchTheme.accent)
                        .frame(width: 4, height: max(4, level * 44))
                }
            }
            .frame(height: 44)
            Button(action: onStop) {
                ZStack {
                    Circle().strokeBorder(WatchTheme.ring, lineWidth: 5)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WatchTheme.accent)
                        .frame(width: 38, height: 38)
                }
                .frame(width: 84, height: 84)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
            .accessibilityIdentifier("WatchStopButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Screen three: hear it, then one tap saves. Save uses the default type; the smaller buttons
/// save as another type in the same one tap. Leaving the screen saves it too, so a recording
/// is never lost; only Delete throws it away.
struct ReviewView: View {
    let captureID: UUID
    let onReRecord: () -> Void
    @EnvironmentObject private var store: WatchCaptureStore
    @StateObject private var player = WatchRecordingPlayer()
    @ObservedObject private var link = WatchPhoneLink.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var deleted = false

    var body: some View {
        Group {
            if let item = store.item(id: captureID) {
                if item.isDraft {
                    review(item)
                } else {
                    CaptureProofContent(item: item, player: player)
                        .task {
                            guard !isDemo else { return }
                            try? await Task.sleep(for: .seconds(3))
                            dismiss()
                        }
                }
            } else {
                Text("This recording is no longer on the Watch.")
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.text)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { WatchBackground() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { saveIfDraft() }
        }
        .onDisappear {
            player.stop()
            saveIfDraft()
        }
    }

    private func review(_ item: WatchCaptureStore.Item) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        if let url = store.audioURL(for: item.capture) { player.toggle(url) }
                    } label: {
                        Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(WatchTheme.doorText)
                            .frame(width: 44, height: 44)
                            .background(WatchTheme.door, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Stop playing" : "Play")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(recordingClock(item.capture.audioDuration ?? 0))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(WatchTheme.strongText)
                        Text("Recorded")
                            .font(.footnote)
                            .foregroundStyle(WatchTheme.text.opacity(0.8))
                    }
                }

                WrittenWords(item: item, isWaiting: link.waiting.contains(item.id))

                Button { save(as: WatchCaptureKind.saveDefault) } label: {
                    VStack(spacing: 0) {
                        Label("Save", systemImage: "checkmark")
                            .font(.headline)
                        Text(WatchCaptureKind.saveDefault.label)
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
                .accessibilityIdentifier("WatchSave")

                HStack(spacing: 4) {
                    ForEach(WatchCaptureKind.allCases.filter { $0 != WatchCaptureKind.saveDefault }) { kind in
                        Button { save(as: kind) } label: {
                            VStack(spacing: 2) {
                                Image(systemName: kind.symbol)
                                    .foregroundStyle(WatchTheme.accent)
                                Text(kind.label)
                                    .font(.caption2)
                                    .foregroundStyle(WatchTheme.doorText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(WatchTheme.door, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Save as \(kind.label)")
                    }
                }

                HStack {
                    Button(role: .destructive) {
                        deleted = true
                        store.discardDraft(captureID)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { onReRecord() } label: {
                        Label("Again", systemImage: "arrow.counterclockwise")
                    }
                }
                .font(.footnote)
            }
            .padding(.horizontal, 2)
        }
    }

    private func save(as kind: WatchCaptureKind) {
        player.stop()
        store.save(captureID, as: kind)
    }

    private func saveIfDraft() {
        guard !deleted, let item = store.item(id: captureID), item.isDraft else { return }
        store.save(captureID, as: item.capture.kind)
    }

    private var isDemo: Bool {
        #if DEBUG
        WatchCaptureDemo.screen != nil
        #else
        false
        #endif
    }
}

// [route icloud]
/// A saved capture from the recent list: what it is, whether iCloud has it, and playback.
// [route iphone]
/// A saved capture from the recent list: what it is, whether the iPhone has it, and playback.
// [route end]
struct CaptureProofView: View {
    let captureID: UUID
    @EnvironmentObject private var store: WatchCaptureStore
    @StateObject private var player = WatchRecordingPlayer()

    var body: some View {
        Group {
            if let item = store.item(id: captureID) {
                CaptureProofContent(item: item, player: player)
            } else {
                Text("This capture is no longer on the Watch.")
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.text)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { WatchBackground() }
        .onDisappear { player.stop() }
    }
}

// [route icloud]
/// Proof that it saved: the check, the type, the words or the recording, and the iCloud status.
// [route iphone]
/// Proof that it saved: the check, the type, the words or the recording, and whether the iPhone
/// has made its entry.
// [route end]
struct CaptureProofContent: View {
    let item: WatchCaptureStore.Item
    @ObservedObject var player: WatchRecordingPlayer
    @ObservedObject private var link = WatchPhoneLink.shared
    @EnvironmentObject private var store: WatchCaptureStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(WatchTheme.accent)
                    Label(item.capture.kind.label, systemImage: item.capture.kind.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WatchTheme.doorText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WatchTheme.door, in: Capsule())
                }
                if item.capture.hasRecording {
                    Button {
                        if let url = store.audioURL(for: item.capture) { player.toggle(url) }
                    } label: {
                        Label("Recording · \(recordingClock(item.capture.audioDuration ?? 0))",
                              systemImage: player.isPlaying ? "stop.circle" : "play.circle")
                            .foregroundStyle(WatchTheme.strongText)
                    }
                    .buttonStyle(.plain)
                }
                WrittenWords(item: item, isWaiting: link.waiting.contains(item.id))
                Label(item.statusText(problem: store.problem), systemImage: item.statusSymbol)
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
    }

    static func describe(_ window: WatchProposedWindow, timeZoneIdentifier: String) -> String {
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        var day = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        day.timeZone = zone
        if window.isAllDay { return window.start.formatted(day) + " · All day" }
        var time = Date.FormatStyle().hour().minute()
        time.timeZone = zone
        return window.start.formatted(day) + " · " + window.start.formatted(time)
    }
}

/// The words, so a misheard one (“Kodak” for “Codex”) shows before it reaches the entry. They come
/// from Siri, or from the nearby iPhone a few seconds after a recording stops.
struct WrittenWords: View {
    let item: WatchCaptureStore.Item
    let isWaiting: Bool

    var body: some View {
        if !item.capture.words.isEmpty {
            Text(item.capture.words)
                .font(.body)
                .foregroundStyle(WatchTheme.strongText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("WatchWrittenWords")
            if let window = item.capture.proposedWindow {
                Label(CaptureProofContent.describe(window, timeZoneIdentifier: item.capture.timeZoneIdentifier),
                      systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.text)
            }
        } else if isWaiting {
            HStack(spacing: 6) {
                ProgressView()
                    .tint(WatchTheme.strongText)
                    .frame(width: 18, height: 18)
                Text("Your iPhone is writing out the words…")
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.text)
            }
        } else if item.capture.hasRecording {
            Text("Your iPhone writes out the words.")
                .font(.footnote)
                .foregroundStyle(WatchTheme.text.opacity(0.8))
        }
    }
}

/// Behind every Watch screen: the app's color, a bit darker and rougher toward the edges, like
/// the paper in the app icon. Without `WatchTheme.edge` it is the flat color.
struct WatchBackground: View {
    var body: some View {
        ZStack {
            WatchTheme.background
            if let edge = WatchTheme.edge {
                EllipticalGradient(
                    stops: [
                        .init(color: edge.opacity(0), location: 0),
                        .init(color: edge.opacity(0), location: 0.5),
                        .init(color: edge.opacity(0.22), location: 0.78),
                        .init(color: edge.opacity(0.5), location: 1),
                    ],
                    center: .center, startRadiusFraction: 0, endRadiusFraction: 0.74)
                WatchEdgeGrain(dark: edge, light: WatchTheme.door)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Paper grain: small specks, thicker toward the edges and none in the middle. The same specks
/// on every draw, so nothing shimmers when the screen redraws.
struct WatchEdgeGrain: View {
    let dark: Color
    let light: Color

    var body: some View {
        Canvas { context, size in
            let halfWidth = size.width / 2, halfHeight = size.height / 2
            guard halfWidth > 0, halfHeight > 0 else { return }
            var random = WatchGrainRandom(seed: 0x5A56_5921)
            for _ in 0..<3200 {
                let x = random.unit() * size.width
                let y = random.unit() * size.height
                let chance = random.unit(), shade = random.unit(), sizeRoll = random.unit()
                let dx = (x - halfWidth) / halfWidth, dy = (y - halfHeight) / halfHeight
                let strength = min(1, max(0, ((dx * dx + dy * dy).squareRoot() - 0.55) / 0.7))
                guard chance < strength else { continue }
                let side = 0.5 + sizeRoll * 0.9
                let color = shade < 0.75
                    ? dark.opacity(0.10 + strength * 0.30)
                    : light.opacity(0.10 + strength * 0.18)
                context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}

/// A small fixed-seed generator, so the grain is identical every time it is drawn.
struct WatchGrainRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// The next number from 0 up to, not including, 1.
    mutating func unit() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat((state >> 33) & 0xFF_FFFF) / CGFloat(0x100_0000)
    }
}

/// The app's name at the top left of the first screen, on the clock's line. An app with its own
/// lettering gives it in `WatchTheme.titleStrokes` and gets it drawn: pen strokes, or with
/// `titleFilled` the outlines of a typeset name. An app without gets its name in plain lettering
/// in the same place.
struct WatchTitleBar: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if WatchTheme.titleStrokes.isEmpty || WatchTheme.titleFilled {
            content.toolbar {
                if !hidden {
                    ToolbarItem(placement: .topBarLeading) {
                        if WatchTheme.titleStrokes.isEmpty { WatchPlainTitle() } else { WatchTitle() }
                    }
                }
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    WatchTitle().opacity(hidden ? 0 : 1)
                }
            }
        }
    }
}

/// The app's name in plain lettering, for an app with no lettering of its own.
struct WatchPlainTitle: View {
    var body: some View {
        Text(WatchCaptureConfig.appName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(WatchTheme.strongText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("WatchTitle")
    }
}

/// The app's name in its own lettering: hand-drawn pen strokes, or, with `WatchTheme.titleFilled`,
/// the filled outlines of a typeset name.
struct WatchTitle: View {
    var body: some View {
        lettering
            .accessibilityElement()
            .accessibilityLabel(WatchCaptureConfig.appName)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("WatchTitle")
    }

    @ViewBuilder private var lettering: some View {
        let mark = WatchTitleMark(strokes: WatchTheme.titleStrokes)
        let shape = WatchTitleMark.aspectRatio(of: WatchTheme.titleStrokes)
        if WatchTheme.titleFilled {
            // A typeset name is wide: it takes the room beside the clock and no more.
            let width = WKInterfaceDevice.current().screenBounds.width * 0.58
            mark.fill(WatchTheme.strongText)
                .frame(width: width, height: width / max(shape, 1))
        } else {
            mark.stroke(WatchTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .aspectRatio(shape, contentMode: .fit)
                .padding(1.5)
                .frame(height: 28)
        }
    }
}

/// Hand-drawn lettering as straight lines, scaled to fit the space it is given.
struct WatchTitleMark: Shape {
    let strokes: [[CGPoint]]

    static func bounds(of strokes: [[CGPoint]]) -> CGRect {
        let points = strokes.flatMap { $0 }
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func aspectRatio(of strokes: [[CGPoint]]) -> CGFloat {
        let box = bounds(of: strokes)
        return box.height > 0 ? box.width / box.height : 1
    }

    func path(in rect: CGRect) -> Path {
        let box = Self.bounds(of: strokes)
        guard box.width > 0, box.height > 0 else { return Path() }
        let scale = min(rect.width / box.width, rect.height / box.height)
        let shiftX = rect.midX - box.midX * scale
        let shiftY = rect.midY - box.midY * scale
        var path = Path()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: CGPoint(x: first.x * scale + shiftX, y: first.y * scale + shiftY))
            for point in stroke.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * scale + shiftX, y: point.y * scale + shiftY))
            }
        }
        return path
    }
}

/// Minutes and seconds, as Voice Memos shows them.
func recordingClock(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", total / 60, total % 60)
}

extension WatchCapture {
    /// One line for the recent list.
    var summary: String {
        words.isEmpty ? "Recording \(recordingClock(audioDuration ?? 0))" : words
    }
}

extension WatchCaptureStore.Item {
// [route icloud]
    var statusSymbol: String {
        if isDemo { return "icloud.slash" }
        if isDraft { return "pencil.circle" }
        return sentAt == nil ? "icloud.and.arrow.up" : "checkmark.icloud"
    }

    func statusText(problem: WatchCaptureStore.Problem?) -> String {
        if isDemo { return "Demo · not sent" }
        if sentAt != nil { return "Saved on Watch · in iCloud" }
        switch problem {
        case .noICloudAccount: return "Saved on Watch · sign in to iCloud to send"
        case .couldNotSend: return "Saved on Watch · sends when online"
        case .iCloudStorageFull: return "Saved on Watch · iCloud storage is full"
        case .iCloudRefused(let code): return "Saved on Watch · iCloud refused it (code \(code))"
        default: return "Saved on Watch · sending"
        }
    }
// [route iphone]
    var statusSymbol: String {
        if isDemo { return "iphone.slash" }
        if isDraft { return "pencil.circle" }
        return sentAt == nil ? "arrow.up.circle" : "checkmark.circle"
    }

    func statusText(problem: WatchCaptureStore.Problem?) -> String {
        if isDemo { return "Demo · not sent" }
        if sentAt != nil { return "Saved on Watch · on your iPhone" }
        switch problem {
        case .phoneOutOfReach: return "Saved on Watch · waits until your iPhone is close"
        case .phoneCouldNotSave: return "Saved on Watch · your iPhone could not save it yet"
        default: return "Saved on Watch · sending to your iPhone"
        }
    }
// [route end]

    private var isDemo: Bool {
        #if DEBUG
        WatchCaptureDemo.screen != nil
        #else
        false
        #endif
    }
}
