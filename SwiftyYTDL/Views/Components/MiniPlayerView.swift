import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlaybackManager
    let onOpen: () -> Void
    @State private var bubbleAmount: CGFloat = 0.0

    var body: some View {
        if let song = player.currentSong {
            ZStack {
                bubbleOverlay

                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ArtworkView(artworkPath: song.artworkPath, cornerRadius: 9, size: 46)
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
                    .onTapGesture {
                        triggerBubbleAndOpen()
                    }

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.skipToNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .modifier(FloatingMiniPlayerGlass())
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    private var bubbleOverlay: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 26 + bubbleAmount * 64, height: 26 + bubbleAmount * 64)
                .scaleEffect(1 + bubbleAmount * 0.45)
                .opacity(0.22 - bubbleAmount * 0.18)

            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 1.2)
                .frame(width: 34 + bubbleAmount * 92, height: 34 + bubbleAmount * 92)
                .scaleEffect(1 + bubbleAmount * 0.35)
                .opacity(0.24 - bubbleAmount * 0.20)
        }
        .allowsHitTesting(false)
    }

    private func triggerBubbleAndOpen() {
        withAnimation(.easeOut(duration: 0.22)) {
            bubbleAmount = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            onOpen()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeOut(duration: 0.16)) {
                bubbleAmount = 0
            }
        }
    }
}

private struct FloatingMiniPlayerGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.white.opacity(0.12)), in: .rect(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.22))
                )
                .shadow(color: .white.opacity(0.25), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(.white.opacity(0.42))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.24), .clear, .white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                )
                .shadow(color: .white.opacity(0.18), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
    }
}
