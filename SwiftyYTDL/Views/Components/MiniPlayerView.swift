import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlaybackManager
    let onOpen: () -> Void
    @State private var bubbleAmount: CGFloat = 0.0
    @State private var didStartPress = false
    private let bubbleDisabledOnIOS26 = true

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    ArtworkView(artworkPath: song.artworkPath, cornerRadius: 8, size: 40)
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
                .gesture(openGesture)

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
            .overlay {
                if #available(iOS 26.0, *) {
                    EmptyView()
                } else {
                    bubbleOverlay
                }
            }
            .modifier(FloatingMiniPlayerGlass())
        }
    }

    private var openGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !didStartPress else { return }
                didStartPress = true
                if #available(iOS 26.0, *), bubbleDisabledOnIOS26 {
                    // no-op (bubble effect not used on iOS 26)
                } else {
                    triggerHoldBubble()
                }
            }
            .onEnded { value in
                didStartPress = false
                if #available(iOS 26.0, *), bubbleDisabledOnIOS26 {
                    // no-op (bubble effect not used on iOS 26)
                } else {
                    endHoldBubble()
                }

                // Treat a press as an "open" unless it turned into a swipe/drag.
                let moved = max(abs(value.translation.width), abs(value.translation.height))
                if moved < 40 {
                    onOpen()
                }
            }
    }

    private var bubbleOverlay: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.white.opacity(0.10 * bubbleAmount))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.34 * bubbleAmount), lineWidth: 1.0)
            )
            .scaleEffect(1 + bubbleAmount * 0.035)
            .blur(radius: 0.2 + bubbleAmount * 0.9)
            .shadow(color: .white.opacity(0.22 * bubbleAmount), radius: 10, y: 3)
            .shadow(color: .black.opacity(0.08 * bubbleAmount), radius: 16, y: 10)
            .allowsHitTesting(false)
    }

    private func triggerHoldBubble() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
            bubbleAmount = 1
        }
    }

    private func endHoldBubble() {
        withAnimation(.easeOut(duration: 0.18)) {
            bubbleAmount = 0
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
                .pressableScaleEffect(pressedScale: 1.03)
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
