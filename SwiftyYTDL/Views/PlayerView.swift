import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var player: PlaybackManager
    @EnvironmentObject private var theme: ThemeManager
    let onClose: () -> Void

    var body: some View {
        NavigationView {
            Group {
                if let song = player.currentSong {
                    ScrollView {
                        VStack(spacing: 28) {
                            ArtworkView(artworkPath: song.artworkPath, artworkSourceURL: song.effectiveArtworkSourceURL, cornerRadius: 34, size: 300)
                                .padding(.top, 8)

                            VStack(spacing: 8) {
                                Text(song.title)
                                    .font(.largeTitle.weight(.bold))
                                    .multilineTextAlignment(.center)
                                Text(song.artist)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(spacing: 12) {
                                Slider(
                                    value: Binding(
                                        get: { player.currentTime },
                                        set: { player.seek(to: $0) }
                                    ),
                                    in: 0...max(player.duration, 1)
                                )

                                HStack {
                                    Text(player.currentTime.asDurationText)
                                    Spacer()
                                    Text(player.duration.asDurationText)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 24) {
                                Button {
                                    player.toggleShuffle()
                                } label: {
                                    Image(systemName: player.shuffleEnabled ? "shuffle.circle.fill" : "shuffle.circle")
                                        .font(.system(size: 28))
                                }

                                Button {
                                    player.skipToPrevious()
                                } label: {
                                    Image(systemName: "backward.fill")
                                        .font(.system(size: 28))
                                }

                                Button {
                                    player.togglePlayPause()
                                } label: {
                                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 62))
                                }

                                Button {
                                    player.skipToNext()
                                } label: {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 28))
                                }

                                Button {
                                    player.cycleRepeatMode()
                                } label: {
                                    Image(systemName: repeatIcon)
                                        .font(.system(size: 28))
                                }
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 14) {
                                Text("Up Next")
                                    .font(.title3.weight(.semibold))

                                ForEach(queueEntries) { entry in
                                    QueueEntryRow(entry: entry, isCurrent: entry.index == player.currentIndex)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                    .background(
                        LinearGradient(
                            colors: theme.subtleBackgroundGradientColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                } else {
                    EmptyStateView(
                        title: "Nothing Playing",
                        message: "Choose a song from Home, Library, or Playlists to start listening.",
                        systemImage: "play.circle"
                    )
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onClose()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off:
            return "repeat.circle"
        case .all:
            return "repeat.circle.fill"
        case .one:
            return "repeat.1.circle.fill"
        }
    }

    private var queueEntries: [QueueEntry] {
        player.queue.enumerated().map { index, song in
            QueueEntry(index: index, song: song)
        }
    }
}

private struct QueueEntry: Identifiable {
    let index: Int
    let song: Song

    var id: UUID { song.id }
}

private struct QueueEntryRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let entry: QueueEntry
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(artworkPath: entry.song.artworkPath, artworkSourceURL: entry.song.effectiveArtworkSourceURL, cornerRadius: 12, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.song.title)
                    .font(.headline)
                Text(entry.song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(theme.accentColor)
            }
        }
        .padding(12)
        .background(
            isCurrent ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}
