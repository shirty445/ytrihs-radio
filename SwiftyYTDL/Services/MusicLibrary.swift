import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class MusicLibrary: ObservableObject {
    @Published private(set) var database = LibraryDatabase()
    @Published private(set) var isLoaded = false
    @Published private(set) var maintenanceMessage: String?

    let storage: FileStorageManager

    init(storage: FileStorageManager = FileStorageManager()) {
        self.storage = storage
    }

    var songs: [Song] {
        database.songs.applyingSort(database.preferences.librarySortMode)
    }

    var favoriteSongs: [Song] {
        songs.filter(\.isFavorite)
    }

    var recentlyAddedSongs: [Song] {
        Array(songs.prefix(20))
    }

    var offlineSongs: [Song] {
        songs.filter(\.hasLocalAssetReference)
    }

    var playlists: [PlaylistModel] {
        database.playlists.sorted { $0.updatedAt > $1.updatedAt }
    }

    var recentImports: [RecentImportRecord] {
        database.recentImports.sorted { $0.importedAt > $1.importedAt }
    }

    var logs: [AppLogEntry] {
        database.logs.sorted { $0.date > $1.date }
    }

    var albums: [AlbumSummary] {
        let grouped = Dictionary(grouping: songs) { song in
            [song.albumTitle.normalizedForMatching, song.artist.normalizedForMatching]
                .joined(separator: "::")
        }

        return grouped.values
            .map { group in
                let sortedSongs = group.sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                let first = sortedSongs.first!
                return AlbumSummary(
                    title: first.albumTitle,
                    artist: first.artist,
                    artworkPath: sortedSongs.compactMap(\.artworkPath).first,
                    artworkSourceURL: sortedSongs.compactMap(\.effectiveArtworkSourceURL).first,
                    songs: sortedSongs
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var artists: [ArtistSummary] {
        let grouped = Dictionary(grouping: songs, by: { $0.artist.normalizedForMatching })

        return grouped.values
            .map { group in
                let sortedSongs = group.sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                let first = sortedSongs.first!
                return ArtistSummary(
                    name: first.artist,
                    artworkPath: sortedSongs.compactMap(\.artworkPath).first,
                    artworkSourceURL: sortedSongs.compactMap(\.effectiveArtworkSourceURL).first,
                    songs: sortedSongs
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func load() async {
        guard !isLoaded else { return }
        maintenanceMessage = "Loading library..."

        do {
            try await storage.prepareDirectories()

            if let persisted = try await storage.loadDatabase() {
                database = persisted
            } else {
                database.songs = try await storage.loadSongsFromSidecars()
                await persistDatabase()
            }

            isLoaded = true
            maintenanceMessage = nil
        } catch {
            maintenanceMessage = nil
            appendLog(.error, "Library load failed: \(error.localizedDescription)")
        }
    }

    func localFileURL(for song: Song) async -> URL {
        await storage.absoluteURL(forStoredPath: song.localFileName)
    }

    func artworkURL(for song: Song) async -> URL? {
        if let artworkPath = song.artworkPath {
            return await storage.absoluteURL(forStoredPath: artworkPath)
        }
        if let artworkSourceURL = song.effectiveArtworkSourceURL {
            return URL(string: artworkSourceURL)
        }
        return nil
    }

    func song(withID id: UUID?) -> Song? {
        guard let id else { return nil }
        return database.songs.first(where: { $0.id == id })
    }

    func playlist(withID id: UUID) -> PlaylistModel? {
        database.playlists.first(where: { $0.id == id })
    }

    func songs(matching query: String) -> [Song] {
        let normalized = query.normalizedForMatching
        guard !normalized.isEmpty else { return songs }

        return songs.filter { song in
            song.title.normalizedForMatching.contains(normalized)
                || song.artist.normalizedForMatching.contains(normalized)
                || song.albumTitle.normalizedForMatching.contains(normalized)
        }
    }

    func albums(matching query: String) -> [AlbumSummary] {
        let normalized = query.normalizedForMatching
        guard !normalized.isEmpty else { return albums }

        return albums.filter { album in
            album.title.normalizedForMatching.contains(normalized)
                || album.artist.normalizedForMatching.contains(normalized)
        }
    }

    func artists(matching query: String) -> [ArtistSummary] {
        let normalized = query.normalizedForMatching
        guard !normalized.isEmpty else { return artists }

        return artists.filter { artist in
            artist.name.normalizedForMatching.contains(normalized)
        }
    }

    func findExistingSong(for candidate: ImportCandidate) -> Song? {
        findExistingSong(
            sourceID: candidate.sourceID,
            sourceURL: candidate.displayURL?.absoluteString ?? candidate.requestURL.absoluteString,
            title: candidate.title,
            artist: candidate.artist
        )
    }

    func findExistingSong(sourceID: String?, sourceURL: String?, title: String, artist: String) -> Song? {
        let key = [title.normalizedForMatching, artist.normalizedForMatching].joined(separator: "::")

        if let sourceID, let song = database.songs.first(where: { $0.sourceID == sourceID }) {
            return song
        }

        if let sourceURL, let song = database.songs.first(where: {
            $0.sourceURL == sourceURL && (sourceID != nil || $0.normalizedIdentityKey == key)
        }) {
            return song
        }

        return database.songs.first(where: { $0.normalizedIdentityKey == key })
    }

    func registerImportedSong(
        candidate: ImportCandidate,
        plannedSongID: UUID,
        localFileName: String,
        artworkPath: String?
    ) async -> Song {
        if let existing = findExistingSong(for: candidate),
           let index = database.songs.firstIndex(where: { $0.id == existing.id }) {
            if database.songs[index].artworkSourceURL == nil {
                database.songs[index].artworkSourceURL = candidate.artworkURL?.absoluteString
            }
            appendRecentImport(
                title: candidate.title,
                artist: candidate.artist,
                sourceURL: candidate.displayURL?.absoluteString ?? candidate.requestURL.absoluteString,
                succeeded: true,
                detail: "Already existed in the local library"
            )
            await persistDatabase()
            return database.songs[index]
        }

        let song = Song(
            id: plannedSongID,
            sourceID: candidate.sourceID,
            sourceURL: candidate.displayURL?.absoluteString ?? candidate.requestURL.absoluteString,
            title: candidate.title,
            artist: candidate.artist,
            albumTitle: candidate.albumTitle.isEmpty ? "Singles" : candidate.albumTitle,
            albumArtist: candidate.artist,
            artworkPath: artworkPath,
            artworkSourceURL: candidate.artworkURL?.absoluteString,
            localFileName: localFileName,
            duration: candidate.duration,
            importDate: .now,
            storageMode: .offline
        )

        database.songs.insert(song, at: 0)
        resolvePendingItems(matching: candidate, to: song.id)
        appendRecentImport(
            title: song.title,
            artist: song.artist,
            sourceURL: song.sourceURL ?? candidate.requestURL.absoluteString,
            succeeded: true,
            detail: "Imported into the local library"
        )
        appendLog(.info, "Imported \(song.title) by \(song.artist)")

        do {
            try await storage.saveSidecar(for: song)
        } catch {
            appendLog(.error, "Sidecar write failed for \(song.title): \(error.localizedDescription)")
        }

        await persistDatabase()
        return song
    }

    func registerStreamedSong(candidate: ImportCandidate) async -> (song: Song, wasInserted: Bool) {
        if let existing = findExistingSong(for: candidate),
           let index = database.songs.firstIndex(where: { $0.id == existing.id }) {
            if database.songs[index].artworkSourceURL == nil {
                database.songs[index].artworkSourceURL = candidate.artworkURL?.absoluteString
            }
            if database.songs[index].artworkPath == nil,
               let artworkPath = await cachedArtworkPath(for: candidate, songID: existing.id) {
                database.songs[index].artworkPath = artworkPath
                do {
                    try await storage.saveSidecar(for: database.songs[index])
                } catch {
                    appendLog(.error, "Sidecar update failed for \(database.songs[index].title): \(error.localizedDescription)")
                }
            }

            appendRecentImport(
                title: database.songs[index].title,
                artist: database.songs[index].artist,
                sourceURL: database.songs[index].sourceURL ?? candidate.requestURL.absoluteString,
                succeeded: true,
                detail: "Already existed in your library"
            )
            await persistDatabase()
            return (database.songs[index], false)
        }

        let songID = UUID()
        let artworkPath = await cachedArtworkPath(for: candidate, songID: songID)
        let song = Song(
            id: songID,
            sourceID: candidate.sourceID,
            sourceURL: candidate.displayURL?.absoluteString ?? candidate.requestURL.absoluteString,
            title: candidate.title,
            artist: candidate.artist,
            albumTitle: candidate.albumTitle.isEmpty ? "Singles" : candidate.albumTitle,
            albumArtist: candidate.artist,
            artworkPath: artworkPath,
            artworkSourceURL: candidate.artworkURL?.absoluteString,
            localFileName: "",
            duration: candidate.duration,
            importDate: .now,
            storageMode: .stream
        )

        database.songs.insert(song, at: 0)
        resolvePendingItems(matching: candidate, to: song.id)
        appendRecentImport(
            title: song.title,
            artist: song.artist,
            sourceURL: song.sourceURL ?? candidate.requestURL.absoluteString,
            succeeded: true,
            detail: "Added to the library for on-demand streaming"
        )
        appendLog(.info, "Added \(song.title) by \(song.artist) as a stream-backed library item")

        do {
            try await storage.saveSidecar(for: song)
        } catch {
            appendLog(.error, "Sidecar write failed for \(song.title): \(error.localizedDescription)")
        }

        await persistDatabase()
        return (song, true)
    }

    func hasPlayableLocalAsset(for song: Song) async -> Bool {
        guard let localFileName = song.localFileName.trimmedOrNil else { return false }

        let fileURL = await storage.absoluteURL(forStoredPath: localFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }

        let asset = AVURLAsset(url: fileURL)

        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else { return false }
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return !tracks.isEmpty
        } catch {
            appendLog(.error, "Asset validation failed for \(song.title): \(error.localizedDescription)")
            return false
        }
    }

    func replaceLocalAsset(for songID: UUID, with localFileName: String, duration: Double? = nil) async {
        _ = await attachLocalAsset(
            to: songID,
            localFileName: localFileName,
            artworkPath: nil,
            duration: duration
        )
    }

    func attachLocalAsset(
        to songID: UUID,
        localFileName: String,
        artworkPath: String?,
        duration: Double? = nil
    ) async -> Song? {
        guard let index = database.songs.firstIndex(where: { $0.id == songID }) else { return nil }

        let oldSong = database.songs[index]
        let oldFileName = oldSong.localFileName.trimmedOrNil

        database.songs[index].localFileName = localFileName
        database.songs[index].storageMode = .offline
        if let duration {
            database.songs[index].duration = duration
        }
        if database.songs[index].artworkPath == nil, let artworkPath {
            database.songs[index].artworkPath = artworkPath
        }

        do {
            try await storage.saveSidecar(for: database.songs[index])
        } catch {
            appendLog(.error, "Sidecar update failed for \(database.songs[index].title): \(error.localizedDescription)")
        }

        if let oldFileName, oldFileName != localFileName {
            let oldFileURL = await storage.absoluteURL(forStoredPath: oldFileName)
            await storage.removeFile(at: oldFileURL)
        }
        await persistDatabase()
        return database.songs[index]
    }

    func toggleFavorite(songID: UUID) async {
        guard let index = database.songs.firstIndex(where: { $0.id == songID }) else { return }
        database.songs[index].isFavorite.toggle()
        await persistDatabase()
    }

    func updateSongMetadata(
        songID: UUID,
        title: String,
        artist: String,
        albumTitle: String,
        notes: String
    ) async {
        guard let index = database.songs.firstIndex(where: { $0.id == songID }) else { return }

        database.songs[index].title = title
        database.songs[index].artist = artist
        database.songs[index].albumTitle = albumTitle
        database.songs[index].notes = notes.trimmedOrNil

        do {
            try await storage.saveSidecar(for: database.songs[index])
        } catch {
            appendLog(.error, "Sidecar update failed: \(error.localizedDescription)")
        }

        await persistDatabase()
    }

    func recordPlayback(songID: UUID, position: Double, incrementPlayCount: Bool) async {
        guard let index = database.songs.firstIndex(where: { $0.id == songID }) else { return }

        database.songs[index].resumePosition = position
        database.songs[index].lastPlayedAt = .now
        if incrementPlayCount {
            database.songs[index].playCount += 1
        }

        do {
            try await storage.saveSidecar(for: database.songs[index])
        } catch {
            appendLog(.error, "Playback bookmark save failed: \(error.localizedDescription)")
        }

        await persistDatabase()
    }

    func createPlaylist(named name: String) async -> PlaylistModel {
        let playlist = PlaylistModel(name: name)
        database.playlists.insert(playlist, at: 0)
        await persistDatabase()
        return playlist
    }

    func renamePlaylist(playlistID: UUID, name: String) async {
        guard let index = database.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        database.playlists[index].name = name
        database.playlists[index].updatedAt = .now
        await persistDatabase()
    }

    func deletePlaylist(playlistID: UUID) async {
        database.playlists.removeAll { $0.id == playlistID }
        await persistDatabase()
    }

    func duplicatePlaylist(playlistID: UUID) async {
        guard var playlist = playlist(withID: playlistID) else { return }
        playlist.id = UUID()
        playlist.name += " Copy"
        playlist.createdAt = .now
        playlist.updatedAt = .now
        database.playlists.insert(playlist, at: 0)
        await persistDatabase()
    }

    func addSongs(_ songIDs: [UUID], to playlistID: UUID) async {
        guard let index = database.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let existingIDs = Set(database.playlists[index].items.compactMap(\.songID))

        let newItems = songIDs
            .filter { !existingIDs.contains($0) }
            .map { PlaylistItem(songID: $0, pendingItem: nil) }

        database.playlists[index].items.append(contentsOf: newItems)
        database.playlists[index].updatedAt = .now
        await persistDatabase()
    }

    func removePlaylistItems(_ itemIDs: [UUID], from playlistID: UUID) async {
        guard let index = database.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        database.playlists[index].items.removeAll { itemIDs.contains($0.id) }
        database.playlists[index].updatedAt = .now
        await persistDatabase()
    }

    func movePlaylistItems(from offsets: IndexSet, to destination: Int, in playlistID: UUID) async {
        guard let index = database.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        database.playlists[index].items.move(fromOffsets: offsets, toOffset: destination)
        database.playlists[index].updatedAt = .now
        await persistDatabase()
    }

    func createPlaylist(from draft: PlaylistImportDraft, queueMissingTracks: Bool) async -> (PlaylistModel, [ImportCandidate]) {
        let playlist = PlaylistModel(
            name: draft.name,
            createdAt: .now,
            updatedAt: .now,
            items: draft.items.map { item in
                switch item.status {
                case .matched, .duplicate:
                    return PlaylistItem(
                        songID: item.matchedSongID,
                        pendingItem: item.matchedSongID == nil ? pendingItem(from: item) : nil
                    )
                case .needsImport, .failed:
                    return PlaylistItem(songID: nil, pendingItem: pendingItem(from: item))
                }
            }
        )

        database.playlists.insert(playlist, at: 0)
        await persistDatabase()

        let candidates = queueMissingTracks
            ? draft.items
                .filter { $0.status == .needsImport }
                .compactMap(candidate(from:))
            : []

        return (playlist, candidates)
    }

    func resolvePendingItems(matching candidate: ImportCandidate, to songID: UUID) {
        for playlistIndex in database.playlists.indices {
            for itemIndex in database.playlists[playlistIndex].items.indices {
                guard let pending = database.playlists[playlistIndex].items[itemIndex].pendingItem else { continue }

                let matchesSource = pending.sourceID != nil && pending.sourceID == candidate.sourceID
                    || pending.sourceURL != nil && pending.sourceURL == (candidate.displayURL?.absoluteString ?? candidate.requestURL.absoluteString)
                let matchesMetadata = pending.title.normalizedForMatching == candidate.title.normalizedForMatching
                    && pending.artist.normalizedForMatching == candidate.artist.normalizedForMatching

                guard matchesSource || matchesMetadata else { continue }
                database.playlists[playlistIndex].items[itemIndex].songID = songID
                database.playlists[playlistIndex].items[itemIndex].pendingItem = nil
                database.playlists[playlistIndex].updatedAt = .now
            }
        }
    }

    func removeSong(songID: UUID) async {
        guard let song = song(withID: songID) else { return }
        database.songs.removeAll { $0.id == songID }

        for playlistIndex in database.playlists.indices {
            for itemIndex in database.playlists[playlistIndex].items.indices {
                guard database.playlists[playlistIndex].items[itemIndex].songID == songID else { continue }
                database.playlists[playlistIndex].items[itemIndex].songID = nil
                database.playlists[playlistIndex].items[itemIndex].pendingItem = PlaylistPendingItem(
                    title: song.title,
                    artist: song.artist,
                    albumTitle: song.albumTitle,
                    sourceURL: song.sourceURL,
                    playlistIndex: nil,
                    sourceID: song.sourceID,
                    note: "Track removed from local storage",
                    status: .needsImport
                )
            }
        }

        do {
            try await storage.deleteAssets(for: song)
        } catch {
            appendLog(.error, "Failed to delete assets for \(song.title): \(error.localizedDescription)")
        }

        await persistDatabase()
    }

    func updatePreferences(_ mutate: (inout AppPreferences) -> Void) async {
        mutate(&database.preferences)
        await persistDatabase()
    }

    func clearArtworkCache() async -> Int {
        do {
            let removed = try await storage.clearArtworkCache()
            for index in database.songs.indices {
                database.songs[index].artworkPath = nil
            }
            await persistDatabase()
            return removed
        } catch {
            appendLog(.error, "Artwork cache clear failed: \(error.localizedDescription)")
            return 0
        }
    }

    func rebuildLibraryFromDisk() async -> Int {
        maintenanceMessage = "Rebuilding library..."
        defer { maintenanceMessage = nil }

        do {
            let rebuiltSongs = try await storage.loadSongsFromSidecars()
            database.songs = rebuiltSongs.applyingSort(database.preferences.librarySortMode)
            database.playlists = database.playlists.map { playlist in
                var updated = playlist
                updated.items = playlist.items.map { item in
                    guard let songID = item.songID, rebuiltSongs.contains(where: { $0.id == songID }) else {
                        return item
                    }
                    return item
                }
                return updated
            }
            await persistDatabase()
            return rebuiltSongs.count
        } catch {
            appendLog(.error, "Library rebuild failed: \(error.localizedDescription)")
            return 0
        }
    }

    func cleanupStorage() async -> CleanupReport {
        maintenanceMessage = "Cleaning cache..."
        defer { maintenanceMessage = nil }

        do {
            let report = try await storage.cleanupOrphanedAssets(using: database.songs)
            appendLog(.info, "Cleanup removed \(report.removedAudioFiles) audio files and \(report.removedArtworkFiles) artwork files")
            return report
        } catch {
            appendLog(.error, "Cleanup failed: \(error.localizedDescription)")
            return CleanupReport()
        }
    }

    func clearLogs() async {
        database.logs.removeAll()
        await persistDatabase()
    }

    func recordFailedImport(candidate: ImportCandidate, detail: String) async {
        appendRecentImport(
            title: candidate.title,
            artist: candidate.artist,
            sourceURL: candidate.displayURL?.absoluteString ?? candidate.requestURL.absoluteString,
            succeeded: false,
            detail: detail
        )
        appendLog(.error, "Import failed for \(candidate.title): \(detail)")
        await persistDatabase()
    }

    func appendLog(_ level: AppLogLevel, _ message: String) {
        database.logs.insert(AppLogEntry(level: level, message: message), at: 0)
        database.logs = Array(database.logs.prefix(100))
    }

    func appendRecentImport(title: String, artist: String, sourceURL: String, succeeded: Bool, detail: String) {
        database.recentImports.insert(
            RecentImportRecord(
                title: title,
                artist: artist,
                sourceURL: sourceURL,
                importedAt: .now,
                succeeded: succeeded,
                detail: detail
            ),
            at: 0
        )
        database.recentImports = Array(database.recentImports.prefix(40))
    }

    private func candidate(from item: PlaylistImportPreviewItem) -> ImportCandidate? {
        guard let requestURL = item.requestURL else { return nil }

        return ImportCandidate(
            requestURL: requestURL,
            displayURL: item.displayURL,
            playlistIndex: item.playlistIndex,
            sourceID: item.sourceID,
            title: item.title,
            artist: item.artist,
            albumTitle: item.albumTitle,
            duration: item.duration,
            artworkURL: item.artworkURL,
            playlistName: nil
        )
    }

    private func pendingItem(from item: PlaylistImportPreviewItem) -> PlaylistPendingItem {
        PlaylistPendingItem(
            title: item.title,
            artist: item.artist,
            albumTitle: item.albumTitle,
            sourceURL: item.displayURL?.absoluteString ?? item.requestURL?.absoluteString,
            playlistIndex: item.playlistIndex,
            sourceID: item.sourceID,
            note: item.detail,
            status: item.status == .failed ? .failed : item.status == .duplicate ? .duplicate : .needsImport
        )
    }

    private func cachedArtworkPath(for candidate: ImportCandidate, songID: UUID) async -> String? {
        guard database.preferences.artworkCachingEnabled, let artworkURL = candidate.artworkURL else {
            return nil
        }
        return try? await storage.storeArtwork(from: artworkURL, songID: songID)
    }

    private func persistDatabase() async {
        do {
            try await storage.saveDatabase(database)
        } catch {
            print("Failed to save library database: \(error.localizedDescription)")
        }
    }
}
