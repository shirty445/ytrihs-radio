import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlaybackManager
    let onOpen: () -> Void

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        ArtworkView(artworkPath: song.artworkPath, artworkSourceURL: song.effectiveArtworkSourceURL, cornerRadius: 8, size: 40)
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    player.skipToNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FloatingMiniPlayerGlass())
        }
    }
}

private struct FloatingMiniPlayerGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(false), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.22))
                        .allowsHitTesting(false)
                }
                .shadow(color: .white.opacity(0.25), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        } else {
            content
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.72))
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(0.42))
                        )
                )
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.24), .clear, .white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }
                .shadow(color: .white.opacity(0.18), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
    }
}
