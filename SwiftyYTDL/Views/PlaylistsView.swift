import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: PlaybackManager
    @EnvironmentObject private var searchCoordinator: SearchCoordinator
    @EnvironmentObject private var theme: ThemeManager

    @StateObject private var viewModel = PlaylistsViewModel()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    private let chromeAnimation = Animation.spring(response: 0.35, dampingFraction: 0.9)

    var body: some View {
        List {
            let playlists = filteredPlaylists

            if playlists.isEmpty {
                EmptyStateView(
                    title: "No Playlists Yet",
                    message: searchText.isEmpty
                        ? "Create playlists manually or import one from a URL, CSV, JSON, or pasted link list."
                        : "No playlists match your search.",
                    systemImage: "music.note.house.fill"
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                ForEach(playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlistID: playlist.id)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: theme.placeholderGradientColors,
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
                        .tint(theme.accentColor)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .applyHiddenNavBarBackgroundIfAvailable()
        .safeAreaInset(edge: .top, spacing: 0) {
            if searchCoordinator.isPlaylistsSearchPresented {
                playlistsSearchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(chromeAnimation, value: searchCoordinator.isPlaylistsSearchPresented)
        .onChange(of: searchCoordinator.isPlaylistsSearchPresented) { isPresented in
            if isPresented {
                isSearchFocused = true
            } else {
                isSearchFocused = false
            }
        }
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

    private var playlistsSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search playlists", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Cancel") {
                searchText = ""
                withAnimation(chromeAnimation) {
                    searchCoordinator.isPlaylistsSearchPresented = false
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(false), in: Capsule())
            } else {
                Capsule()
                    .fill(.thinMaterial)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var filteredPlaylists: [PlaylistModel] {
        guard let query = searchText.trimmedOrNil else { return library.playlists }
        let normalizedQuery = query.normalizedForMatching
        return library.playlists.filter { playlist in
            playlist.name.normalizedForMatching.contains(normalizedQuery)
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
