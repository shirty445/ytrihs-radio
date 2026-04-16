import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: PlaybackManager
    @EnvironmentObject private var searchCoordinator: SearchCoordinator
    @EnvironmentObject private var theme: ThemeManager

    @StateObject private var viewModel = LibraryViewModel()
    @FocusState private var isSearchFocused: Bool
    private let chromeAnimation = Animation.spring(response: 0.35, dampingFraction: 0.9)

    var body: some View {
        List {
            switch viewModel.selectedSection {
            case .songs:
                songsSection(library.songs(matching: viewModel.searchText))
            case .albums:
                albumsSection(library.albums(matching: viewModel.searchText))
            case .artists:
                artistsSection(library.artists(matching: viewModel.searchText))
            case .favorites:
                songsSection(filteredFavorites)
            case .recent:
                songsSection(filteredRecent)
            case .downloads:
                songsSection(filteredOffline)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .applyHiddenNavBarBackgroundIfAvailable()
        .safeAreaInset(edge: .top, spacing: 0) {
            topChrome
        }
        .animation(chromeAnimation, value: searchCoordinator.isLibrarySearchPresented)
        .onChange(of: searchCoordinator.isLibrarySearchPresented) { isPresented in
            if isPresented {
                isSearchFocused = true
            } else {
                isSearchFocused = false
            }
        }
        .sheet(item: $viewModel.editedSong) { song in
            EditSongMetadataView(song: song)
        }
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
            sectionPicker

            if searchCoordinator.isLibrarySearchPresented {
                librarySearchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(LibraryViewModel.Section.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedSection = section
                        }
                    } label: {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(viewModel.selectedSection == section ? Color.white : Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .background {
                        if viewModel.selectedSection == section {
                            Capsule(style: .continuous)
                                .fill(theme.accentColor)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var librarySearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search your library", text: $viewModel.searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Cancel") {
                viewModel.searchText = ""
                withAnimation(chromeAnimation) {
                    searchCoordinator.isLibrarySearchPresented = false
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

    private var filteredFavorites: [Song] {
        let favorites = library.favoriteSongs
        guard !viewModel.searchText.isEmpty else { return favorites }
        return favorites.filter { song in
            song.title.normalizedForMatching.contains(viewModel.searchText.normalizedForMatching)
                || song.artist.normalizedForMatching.contains(viewModel.searchText.normalizedForMatching)
        }
    }

    private var filteredRecent: [Song] {
        let recent = library.recentlyAddedSongs
        guard !viewModel.searchText.isEmpty else { return recent }
        return recent.filter { song in
            song.title.normalizedForMatching.contains(viewModel.searchText.normalizedForMatching)
                || song.artist.normalizedForMatching.contains(viewModel.searchText.normalizedForMatching)
        }
    }

    private var filteredOffline: [Song] {
        let offline = library.offlineSongs
        guard !viewModel.searchText.isEmpty else { return offline }
        return offline.filter { song in
            song.title.normalizedForMatching.contains(viewModel.searchText.normalizedForMatching)
                || song.artist.normalizedForMatching.contains(viewModel.searchText.normalizedForMatching)
        }
    }

    @ViewBuilder
    private func songsSection(_ songs: [Song]) -> some View {
        if songs.isEmpty {
            EmptyStateView(
                title: "Nothing Here Yet",
                message: "Import music or change the filter to see tracks in this part of your library.",
                systemImage: "music.note.list"
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } else {
            ForEach(songs) { song in
                Button {
                    player.play(song: song, within: songs)
                } label: {
                    SongRowView(song: song)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(song.isFavorite ? "Remove Like" : "Like") {
                        Task {
                            await library.toggleFavorite(songID: song.id)
                        }
                    }
                    Button("Play Next") {
                        player.queueNext(song)
                    }
                    Button("Edit Metadata") {
                        viewModel.editedSong = song
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(song.isFavorite ? "Unlike" : "Like") {
                        Task {
                            await library.toggleFavorite(songID: song.id)
                        }
                    }
                    .tint(theme.accentColor)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        Task {
                            await library.removeSong(songID: song.id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func albumsSection(_ albums: [AlbumSummary]) -> some View {
        if albums.isEmpty {
            EmptyStateView(
                title: "No Albums Yet",
                message: "Imported tracks with album metadata will be grouped here automatically.",
                systemImage: "square.stack"
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } else {
            ForEach(albums) { album in
                NavigationLink {
                    AlbumDetailView(album: album)
                } label: {
                    HStack(spacing: 14) {
                        ArtworkView(artworkPath: album.artworkPath, cornerRadius: 14, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.title)
                                .font(.headline)
                            Text("\(album.artist) • \(album.songCount) songs")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func artistsSection(_ artists: [ArtistSummary]) -> some View {
        if artists.isEmpty {
            EmptyStateView(
                title: "No Artists Yet",
                message: "Artists are built from your imported tracks and metadata edits.",
                systemImage: "music.mic"
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } else {
            ForEach(artists) { artist in
                NavigationLink {
                    ArtistDetailView(artist: artist)
                } label: {
                    HStack(spacing: 14) {
                        ArtworkView(artworkPath: artist.artworkPath, cornerRadius: 18, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(artist.name)
                                .font(.headline)
                            Text("\(artist.songCount) tracks")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct AlbumDetailView: View {
    @EnvironmentObject private var player: PlaybackManager
    let album: AlbumSummary

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    ArtworkView(artworkPath: album.artworkPath, cornerRadius: 30, size: 180)
                    Text(album.title)
                        .font(.title.weight(.bold))
                    Text(album.artist)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Button("Play Album") {
                        player.playQueue(album.songs)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 12)
            }

            Section("Tracks") {
                ForEach(album.songs) { song in
                    Button {
                        player.play(song: song, within: album.songs)
                    } label: {
                        SongRowView(song: song)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ArtistDetailView: View {
    @EnvironmentObject private var player: PlaybackManager
    let artist: ArtistSummary

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    ArtworkView(artworkPath: artist.artworkPath, cornerRadius: 30, size: 180)
                    Text(artist.name)
                        .font(.title.weight(.bold))
                    Text("\(artist.songCount) songs • \(artist.totalDuration.asDurationText)")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Button("Shuffle Artist") {
                        player.playQueue(artist.songs.shuffled())
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 12)
            }

            Section("Tracks") {
                ForEach(artist.songs) { song in
                    Button {
                        player.play(song: song, within: artist.songs)
                    } label: {
                        SongRowView(song: song)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditSongMetadataView: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss

    let song: Song

    @State private var title: String
    @State private var artist: String
    @State private var albumTitle: String
    @State private var notes: String

    init(song: Song) {
        self.song = song
        _title = State(initialValue: song.title)
        _artist = State(initialValue: song.artist)
        _albumTitle = State(initialValue: song.albumTitle)
        _notes = State(initialValue: song.notes ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("Title", text: $title)
                TextField("Artist", text: $artist)
                TextField("Album", text: $albumTitle)
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await library.updateSongMetadata(
                                songID: song.id,
                                title: title,
                                artist: artist,
                                albumTitle: albumTitle,
                                notes: notes
                            )
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
