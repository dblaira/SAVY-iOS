import AVFoundation
import SwiftUI

// Watch capture kit: the same in every app that uses it. iPhone and Mac only.

/// The Watch recording beside the written words, so a misheard word (“Kodak” for “Codex”) can be
/// checked against what was actually said. Shown only when this device holds a recording for the
/// entry. It takes the form's own font and tint.
struct WatchRecordingRow: View {
    let entryID: UUID
    @StateObject private var player = WatchRecordingRowPlayer()

    var body: some View {
        if let url = WatchRecordingFiles.url(for: entryID) {
            Button { player.toggle(url) } label: {
                HStack(spacing: 12) {
                    Label {
                        Text("Watch recording")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: player.isPlaying ? "stop.circle" : "play.circle")
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    Text(player.durationLabel(for: url))
                        .foregroundStyle(.tint)
                        .monospacedDigit()
                }
            }
            .accessibilityIdentifier("watchRecordingPlay")
            .onDisappear { player.stop() }
        }
    }
}

@MainActor
final class WatchRecordingRowPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if isPlaying {
            stop()
            return
        }
        do {
            #if !os(macOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            self.player = player
            isPlaying = player.play()
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    func durationLabel(for url: URL) -> String {
        let seconds = Int((try? AVAudioPlayer(contentsOf: url).duration) ?? 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
