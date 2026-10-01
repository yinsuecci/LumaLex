import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerService
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.title).lineLimit(1).font(.headline)
                    Text("\(player.isPlaying ? "Playing" : "Paused") · \(time(player.currentTime)) / \(time(player.duration))")
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                    ProgressView(value: min(max(player.currentTime, 0), max(player.duration, 1)),
                                 total: max(player.duration, 1))
                        .accessibilityLabel("Playback progress")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                player.togglePlayback()
            }
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = seconds.isFinite ? Int(max(0, seconds)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

