import SwiftUI

// Watch capture kit: the same in every app that uses it.

/// Screen one: one door per kind of entry. Tapping a door
/// opens the Watch's own dictation. The words are saved the moment dictation finishes.
struct CaptureHomeView: View {
    @EnvironmentObject private var store: WatchCaptureStore
    @State private var route: ProofRoute?

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(WatchCaptureKind.allCases) { kind in
                            CaptureDoor(kind: kind) { words in
                                if let capture = store.capture(kind, words: words, source: .wrist) {
                                    route = ProofRoute(captureID: capture.id, returnsHome: true)
                                }
                            }
                        }
                    }
                    if store.problem != nil, store.waitingCount > 0 {
                        Label("\(store.waitingCount) waiting to send", systemImage: "icloud.slash")
                            .font(.footnote)
                            .foregroundStyle(WatchTheme.text)
                    }
                    if !store.items.isEmpty {
                        recent
                    }
                }
                .padding(.horizontal, 2)
            }
            .background(WatchTheme.background.ignoresSafeArea())
            .navigationTitle(WatchCaptureConfig.appName)
            .navigationDestination(item: $route) { route in
                CaptureProofView(route: route)
            }
            #if DEBUG
            .task { openDemoScreen() }
            #endif
        }
    }

    #if DEBUG
    private func openDemoScreen() {
        guard let screen = WatchCaptureDemo.screen, route == nil, let newest = store.seedDemo() else { return }
        switch screen {
        case "proof":
            route = ProofRoute(captureID: newest.id, returnsHome: false)
        case "calendar":
            if let timed = store.items.first(where: { $0.capture.proposedWindow != nil }) {
                route = ProofRoute(captureID: timed.id, returnsHome: false)
            }
        default:
            break
        }
    }
    #endif

    private var recent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchTheme.text.opacity(0.8))
            ForEach(store.items.prefix(6)) { item in
                Button {
                    route = ProofRoute(captureID: item.id, returnsHome: false)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.capture.kind.symbol)
                            .foregroundStyle(WatchTheme.accent)
                        Text(item.capture.words)
                            .lineLimit(1)
                            .foregroundStyle(WatchTheme.text)
                        Spacer(minLength: 2)
                        Image(systemName: item.sentAt == nil ? "icloud.and.arrow.up" : "checkmark.icloud")
                            .foregroundStyle(WatchTheme.text.opacity(0.7))
                    }
                    .font(.footnote)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ProofRoute: Hashable {
    var captureID: UUID
    /// True right after a capture: the proof shows for four seconds, then the app returns home.
    var returnsHome: Bool
}

private struct CaptureDoor: View {
    let kind: WatchCaptureKind
    let onWords: (String) -> Void

    var body: some View {
        TextFieldLink(prompt: Text(kind.label)) {
            VStack(spacing: 4) {
                Image(systemName: kind.symbol)
                    .font(.title3)
                    .foregroundStyle(WatchTheme.accent)
                Text(kind.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchTheme.doorText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(WatchTheme.door, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } onSubmit: { words in
            onWords(words)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.label)
        .accessibilityIdentifier("WatchDoor-\(kind.rawValue)")
    }
}

/// Screen three: proof the Watch heard the words right. The exact words, the entry type, any
/// day or hour it heard, and whether iCloud has them yet. One tap re-records.
struct CaptureProofView: View {
    let route: ProofRoute
    @EnvironmentObject private var store: WatchCaptureStore
    @Environment(\.dismiss) private var dismiss
    @State private var keepsOpen = false
    @State private var timerRun = 0

    var body: some View {
        Group {
            if let item = store.item(id: route.captureID) {
                proof(item)
            } else {
                Text("This capture is no longer on the Watch.")
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.text)
            }
        }
        .background(WatchTheme.background.ignoresSafeArea())
        .simultaneousGesture(TapGesture().onEnded { keepsOpen = true })
        .task(id: timerRun) {
            guard route.returnsHome else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !keepsOpen else { return }
            dismiss()
        }
    }

    private func proof(_ item: WatchCaptureStore.Item) -> some View {
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

                Text(item.capture.words)
                    .font(.body)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("WatchProofWords")

                if let window = item.capture.proposedWindow {
                    Label(Self.describe(window, timeZoneIdentifier: item.capture.timeZoneIdentifier),
                          systemImage: "calendar")
                        .font(.footnote)
                        .foregroundStyle(WatchTheme.text)
                }

                status(item)

                TextFieldLink(prompt: Text(item.capture.kind.label)) {
                    Label("Re-record", systemImage: "mic")
                        .frame(maxWidth: .infinity)
                } onSubmit: { words in
                    if store.replaceWords(of: item.id, with: words) != nil {
                        keepsOpen = false
                        timerRun += 1
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { keepsOpen = true })
                .accessibilityIdentifier("WatchReRecord")

                Button("Done") { dismiss() }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func status(_ item: WatchCaptureStore.Item) -> some View {
        if item.sentAt != nil {
            Label("Saved on Watch · in iCloud", systemImage: "checkmark.icloud")
                .font(.footnote)
                .foregroundStyle(WatchTheme.text)
        } else if store.problem == .noICloudAccount {
            Label("Saved on Watch · sign in to iCloud to send", systemImage: "icloud.slash")
                .font(.footnote)
                .foregroundStyle(WatchTheme.text)
        } else if store.problem == .couldNotSend {
            Label("Saved on Watch · sends when online", systemImage: "icloud.slash")
                .font(.footnote)
                .foregroundStyle(WatchTheme.text)
        } else {
            Label("Saved on Watch · sending", systemImage: "icloud.and.arrow.up")
                .font(.footnote)
                .foregroundStyle(WatchTheme.text)
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
