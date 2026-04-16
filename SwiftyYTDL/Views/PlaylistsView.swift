import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: PlaybackManager

    @StateObject private var viewModel = PlaylistsViewModel()

    var body: some View {
        List {
            if library.playlists.isEmpty {
                EmptyStateView(
                    title: "No Playlists Yet",
                    message: "Create playlists manually or import one from a URL, CSV, JSON, or pasted link list.",
                    systemImage: "music.note.house.fill"
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                ForEach(library.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlistID: playlist.id)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange.opacity(0.9), .pink.opacity(0.7), .brown.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Image(systemName: "music.note.list")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 60, height: 60)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                    .font(.headline)
                                Text("\(playlist.items.count) items")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .contextMenu {
                        Button("Play Playlist") {
                            let songs = playlist.items.compactMap { library.song(withID: $0.songID) }
                            player.playPlaylist(songs)
                        }
                        Button("Duplicate") {
                            Task {
                                await library.duplicatePlaylist(playlistID: playlist.id)
                            }
                        }
                        Button("Rename") {
                            viewModel.startRenaming(playlist)
                        }
                        Button("Delete", role: .destructive) {
                            Task {
                                await library.deletePlaylist(playlistID: playlist.id)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task {
                                await library.deletePlaylist(playlistID: playlist.id)
                            }
                        }
                        Button("Rename") {
                            viewModel.startRenaming(playlist)
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.startCreate()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingCreateSheet) {
            playlistNameSheet(title: "New Playlist", actionTitle: "Create") {
                let name = viewModel.draftName.trimmedOrNil ?? "New Playlist"
                Task {
                    _ = await library.createPlaylist(named: name)
                    viewModel.isShowingCreateSheet = false
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingRenameSheet) {
            playlistNameSheet(title: "Rename Playlist", actionTitle: "Save") {
                guard let playlist = viewModel.playlistToRename else { return }
                let name = viewModel.draftName.trimmedOrNil ?? playlist.name
                Task {
                    await library.renamePlaylist(playlistID: playlist.id, name: name)
                    viewModel.isShowingRenameSheet = false
                }
            }
        }
    }

    private func playlistNameSheet(title: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        NavigationView {
            Form {
                TextField("Playlist Name", text: $viewModel.draftName)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.isShowingCreateSheet = false
                        viewModel.isShowingRenameSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle, action: action)
                }
            }
        }
    }
}
