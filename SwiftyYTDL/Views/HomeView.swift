import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: PlaybackManager
    @EnvironmentObject private var importer: ImportCoordinator
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroCard

                if !library.recentlyAddedSongs.isEmpty {
                    sectionTitle("Recently Added")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(library.recentlyAddedSongs.prefix(8)) { song in
                                Button {
                                    player.play(song: song, within: library.songs)
                                } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ArtworkView(artworkPath: song.artworkPath, cornerRadius: 24, size: 152)
                                        Text(song.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(song.artist)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 152, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if !library.favoriteSongs.isEmpty {
                    sectionTitle("Liked Songs")

                    VStack(spacing: 12) {
                        ForEach(library.favoriteSongs.prefix(5)) { song in
                            Button {
                                player.play(song: song, within: library.favoriteSongs)
                            } label: {
                                SongRowView(song: song)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                if !importer.activeJobs.isEmpty {
                    sectionTitle("Imports")

                    VStack(spacing: 12) {
                        ForEach(importer.activeJobs.prefix(3)) { job in
                            ImportJobRowView(
                                job: job,
                                onRetry: { importer.retry(jobID: job.id) },
                                onCancel: { importer.cancel(jobID: job.id) }
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                if library.songs.isEmpty {
                    EmptyStateView(
                        title: "Start Building Your Library",
                        message: "Import a song or copy a playlist from the Search tab and your personal offline collection will appear here.",
                        systemImage: "music.note.house"
                    )
                }
            }
            .padding(.vertical)
        }
        .background(
            LinearGradient(
                colors: theme.subtleBackgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("Home")
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(player.currentSong == nil ? "Offline Mix" : "Now Playing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .textCase(.uppercase)

            if let song = player.currentSong {
                HStack(spacing: 16) {
                    ArtworkView(artworkPath: song.artworkPath, cornerRadius: 24, size: 112)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(song.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text(song.artist)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.82))
                        Button(player.isPlaying ? "Pause" : "Play") {
                            player.togglePlayPause()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                    }
                }
            } else {
                Text("A sideload-friendly music player built around your own imports, playlists, and offline listening.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Paste a track link, analyze a playlist export, and save audio for playback with queueing, lock screen controls, and resume progress.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: theme.strongGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
        .padding(.horizontal)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.horizontal)
    }
}
