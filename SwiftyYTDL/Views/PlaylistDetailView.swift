import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: PlaybackManager
    @EnvironmentObject private var importer: ImportCoordinator

    let playlistID: UUID

    @State private var isShowingSongPicker = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        Group {
            if let playlist = library.playlist(withID: playlistID) {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(playlist.name)
                                .font(.title.weight(.bold))

                            Text("\(playlist.items.count) items • \(resolvedSongs(in: playlist).count) playable")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Play") {
                                    player.playPlaylist(resolvedSongs(in: playlist))
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Shuffle") {
                                    player.playPlaylist(resolvedSongs(in: playlist).shuffled())
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 10)
                    }

                    if playlist.items.contains(where: { $0.pendingItem != nil }) {
                        Section {
                            Text("Unresolved tracks stay in the playlist so order is preserved. Import them later and they’ll relink automatically when the metadata matches.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Items") {
                        ForEach(playlist.items) { item in
                            if let song = library.song(withID: item.songID) {
                                Button {
                                    player.play(song: song, within: resolvedSongs(in: playlist))
                                } label: {
                                    SongRowView(song: song)
                                }
                                .buttonStyle(.plain)
                            } else if let pending = item.pendingItem {
                                pendingRow(pending)
                            }
                        }
                        .onDelete { indexSet in
                            let itemIDs = indexSet.compactMap { playlist.items[safe: $0]?.id }
                            Task {
                                await library.removePlaylistItems(itemIDs, from: playlist.id)
                            }
                        }
                        .onMove { fromOffsets, toOffset in
                            Task {
                                await library.movePlaylistItems(from: fromOffsets, to: toOffset, in: playlist.id)
                            }
                        }
                    }
                }
                .environment(\.editMode, $editMode)
                .navigationTitle(playlist.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Add Songs") {
                                isShowingSongPicker = true
                            }
                            Button(editMode == .active ? "Done Editing" : "Edit Order") {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $isShowingSongPicker) {
                    PlaylistSongPickerView(playlistID: playlist.id)
                }
            } else {
                EmptyStateView(
                    title: "Playlist Not Found",
                    message: "This playlist was removed from the local library.",
                    systemImage: "music.note.list"
                )
            }
        }
    }

    private func resolvedSongs(in playlist: PlaylistModel) -> [Song] {
        playlist.items.compactMap { library.song(withID: $0.songID) }
    }

    private func pendingRow(_ pending: PlaylistPendingItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pending.title)
                        .font(.headline)
                    Text("\(pending.artist) • \(pending.albumTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(pending.status.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.12), in: Capsule())
                    .foregroundStyle(.orange)
            }

            if let note = pending.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let sourceURL = pending.sourceURL, let url = URL(string: sourceURL) {
                Button("Import Track") {
                    let candidate = ImportCandidate(
                        requestURL: url,
                        displayURL: url,
                        playlistIndex: pending.playlistIndex,
                        sourceID: pending.sourceID,
                        title: pending.title,
                        artist: pending.artist,
                        albumTitle: pending.albumTitle,
                        duration: 0,
                        artworkURL: nil,
                        playlistName: nil
                    )
                    importer.enqueue([candidate], quality: library.database.preferences.audioQuality)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PlaylistSongPickerView: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID

    @State private var searchText = ""
    @State private var selection = Set<UUID>()

    var body: some View {
        NavigationView {
            List(filteredSongs, selection: $selection) { song in
                SongRowView(song: song)
            }
            .searchable(text: $searchText)
            .navigationTitle("Add Songs")
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await library.addSongs(Array(selection), to: playlistID)
                            dismiss()
                        }
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var filteredSongs: [Song] {
        guard !searchText.isEmpty else { return library.songs }

        return library.songs.filter { song in
            song.title.normalizedForMatching.contains(searchText.normalizedForMatching)
                || song.artist.normalizedForMatching.contains(searchText.normalizedForMatching)
        }
    }
}
