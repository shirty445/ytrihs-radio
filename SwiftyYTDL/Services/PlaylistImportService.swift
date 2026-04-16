import Foundation
import YTDLKit

struct PlaylistImportService {
    let bridge: YTDLBridge

    func draftForPlaylistProbe(
        _ probe: YTDLPlaylistProbe,
        sourceDescription: String,
        library: MusicLibrary
    ) async -> PlaylistImportDraft {
        let rawTracks = probe.entries.map { track in
            RawPlaylistTrack(
                title: track.title,
                artist: track.artist,
                albumTitle: track.albumTitle,
                requestURL: track.requestURL,
                displayURL: track.displayURL,
                playlistIndex: track.playlistIndex,
                sourceID: track.id,
                duration: track.duration,
                artworkURL: track.thumbnailURL
            )
        }

        return await buildDraft(
            name: probe.title.isEmpty ? "Imported Playlist" : probe.title,
            sourceDescription: sourceDescription,
            rawTracks: rawTracks,
            library: library
        )
    }

    func draftForText(
        _ text: String,
        sourceDescription: String,
        suggestedName: String?,
        library: MusicLibrary
    ) async throws -> PlaylistImportDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "PlaylistImportService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Paste playlist data or links to continue."]
            )
        }

        if let parsed = try parseJSON(trimmed) {
            return await buildDraft(
                name: parsed.name ?? suggestedName ?? "Imported Playlist",
                sourceDescription: sourceDescription,
                rawTracks: parsed.tracks,
                library: library
            )
        }

        if let parsed = parseDelimited(trimmed) {
            return await buildDraft(
                name: suggestedName ?? "Imported Playlist",
                sourceDescription: sourceDescription,
                rawTracks: parsed,
                library: library
            )
        }

        let parsedLines = try await parseLineBasedInput(trimmed)
        return await buildDraft(
            name: suggestedName ?? "Imported Playlist",
            sourceDescription: sourceDescription,
            rawTracks: parsedLines,
            library: library
        )
    }

    func draftForFile(at url: URL, library: MusicLibrary) async throws -> PlaylistImportDraft {
        let text = try String(contentsOf: url, encoding: .utf8)
        let suggestedName = url.deletingPathExtension().lastPathComponent
        return try await draftForText(
            text,
            sourceDescription: url.lastPathComponent,
            suggestedName: suggestedName,
            library: library
        )
    }

    private func buildDraft(
        name: String,
        sourceDescription: String,
        rawTracks: [RawPlaylistTrack],
        library: MusicLibrary
    ) async -> PlaylistImportDraft {
        var seenKeys = Set<String>()
        var items: [PlaylistImportPreviewItem] = []

        for (offset, rawTrack) in rawTracks.enumerated() {
            let key = [
                rawTrack.sourceID ?? "",
                rawTrack.requestURL?.absoluteString ?? "",
                rawTrack.playlistIndex.map(String.init) ?? "",
                rawTrack.title.normalizedForMatching,
                rawTrack.artist.normalizedForMatching
            ].joined(separator: "::")

            if seenKeys.contains(key) {
                items.append(
                    PlaylistImportPreviewItem(
                        position: offset + 1,
                        title: rawTrack.title,
                        artist: rawTrack.artist,
                        albumTitle: rawTrack.albumTitle,
                        duration: rawTrack.duration,
                        requestURL: rawTrack.requestURL,
                        displayURL: rawTrack.displayURL,
                        playlistIndex: rawTrack.playlistIndex,
                        sourceID: rawTrack.sourceID,
                        artworkURL: rawTrack.artworkURL,
                        status: .duplicate,
                        matchedSongID: nil,
                        detail: "Duplicate entry in the imported playlist data"
                    )
                )
                continue
            }

            seenKeys.insert(key)

            let candidate = rawTrack.importCandidate
            let existingSong: Song?
            if let candidate {
                existingSong = await MainActor.run {
                    library.findExistingSong(for: candidate)
                }
            } else {
                existingSong = nil
            }

            let status: PlaylistReviewStatus
            let detail: String

            if let existingSong {
                status = .matched
                detail = "Matched to \(existingSong.title) in your library"
            } else if rawTrack.requestURL != nil {
                status = .needsImport
                detail = "Ready to import into the local library"
            } else {
                status = .failed
                detail = "Missing a usable source URL for this track"
            }

            items.append(
                PlaylistImportPreviewItem(
                    position: offset + 1,
                    title: rawTrack.title,
                    artist: rawTrack.artist,
                    albumTitle: rawTrack.albumTitle,
                    duration: rawTrack.duration,
                    requestURL: rawTrack.requestURL,
                    displayURL: rawTrack.displayURL,
                    playlistIndex: rawTrack.playlistIndex,
                    sourceID: rawTrack.sourceID,
                    artworkURL: rawTrack.artworkURL,
                    status: status,
                    matchedSongID: existingSong?.id,
                    detail: detail
                )
            )
        }

        return PlaylistImportDraft(
            name: name.trimmedOrNil ?? "Imported Playlist",
            sourceDescription: sourceDescription,
            items: items
        )
    }

    private func parseJSON(_ text: String) throws -> ParsedPlaylist? {
        guard let data = text.data(using: .utf8) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)

        if let dictionary = object as? [String: Any] {
            let title = dictionary["title"] as? String ?? dictionary["name"] as? String
            let tracks = (dictionary["tracks"] as? [[String: Any]] ?? dictionary["items"] as? [[String: Any]] ?? [])
                .map(rawTrack(from:))
            if !tracks.isEmpty {
                return ParsedPlaylist(name: title, tracks: tracks)
            }
        }

        if let array = object as? [[String: Any]] {
            let tracks = array.map(rawTrack(from:))
            return tracks.isEmpty ? nil : ParsedPlaylist(name: nil, tracks: tracks)
        }

        if let array = object as? [String] {
            return ParsedPlaylist(
                name: nil,
                tracks: array.map {
                    RawPlaylistTrack(
                        title: $0,
                        artist: "Unknown Artist",
                        albumTitle: "Imported Playlist",
                        requestURL: URL(string: $0),
                        displayURL: URL(string: $0),
                        playlistIndex: nil,
                        sourceID: nil,
                        duration: 0,
                        artworkURL: nil
                    )
                }
            )
        }

        return nil
    }

    private func parseDelimited(_ text: String) -> [RawPlaylistTrack]? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count > 1 else { return nil }

        let header = lines[0].lowercased()
        guard header.contains("title"), header.contains("artist") else { return nil }

        let separator: Character = header.contains("\t") ? "\t" : ","
        let headers = lines[0].split(separator: separator).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        return lines.dropFirst().compactMap { line in
            let parts = line.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty else { return nil }

            func value(for key: String) -> String {
                guard let index = headers.firstIndex(of: key), let value = parts[safe: index] else { return "" }
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let urlString = value(for: "url").trimmedOrNil ?? value(for: "link").trimmedOrNil

            return RawPlaylistTrack(
                title: value(for: "title").trimmedOrNil ?? value(for: "name"),
                artist: value(for: "artist").trimmedOrNil ?? "Unknown Artist",
                albumTitle: value(for: "album").trimmedOrNil ?? "Imported Playlist",
                requestURL: urlString.flatMap(URL.init(string:)),
                displayURL: urlString.flatMap(URL.init(string:)),
                playlistIndex: nil,
                sourceID: value(for: "source_id").trimmedOrNil,
                duration: Double(value(for: "duration")) ?? 0,
                artworkURL: value(for: "artwork_url").trimmedOrNil.flatMap(URL.init(string:))
            )
        }
    }

    private func parseLineBasedInput(_ text: String) async throws -> [RawPlaylistTrack] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var tracks: [RawPlaylistTrack] = []

        for line in lines {
            if let url = URL(string: line), url.isWebURL {
                let probe = try await bridge.probe(url: url)
                switch probe {
                case .single(let track):
                    tracks.append(
                        RawPlaylistTrack(
                            title: track.title,
                            artist: track.artist,
                            albumTitle: track.albumTitle,
                            requestURL: track.requestURL,
                            displayURL: track.displayURL,
                            playlistIndex: track.playlistIndex,
                            sourceID: track.id,
                            duration: track.duration,
                            artworkURL: track.thumbnailURL
                        )
                    )
                case .playlist(let playlist):
                    tracks.append(contentsOf: playlist.entries.map { track in
                        RawPlaylistTrack(
                            title: track.title,
                            artist: track.artist,
                            albumTitle: track.albumTitle,
                            requestURL: track.requestURL,
                            displayURL: track.displayURL,
                            playlistIndex: track.playlistIndex,
                            sourceID: track.id,
                            duration: track.duration,
                            artworkURL: track.thumbnailURL
                        )
                    })
                }
            } else {
                let components = line.split(separator: "-", maxSplits: 1).map(String.init)
                let artist = components.count > 1 ? components[0].trimmingCharacters(in: .whitespaces) : "Unknown Artist"
                let title = components.count > 1 ? components[1].trimmingCharacters(in: .whitespaces) : line

                tracks.append(
                    RawPlaylistTrack(
                        title: title,
                        artist: artist,
                        albumTitle: "Imported Playlist",
                        requestURL: nil,
                        displayURL: nil,
                        playlistIndex: nil,
                        sourceID: nil,
                        duration: 0,
                        artworkURL: nil
                    )
                )
            }
        }

        return tracks
    }

    private func rawTrack(from dictionary: [String: Any]) -> RawPlaylistTrack {
        let title = (dictionary["title"] as? String ?? dictionary["name"] as? String ?? "Unknown Track")
        let artist = dictionary["artist"] as? String
            ?? dictionary["creator"] as? String
            ?? dictionary["uploader"] as? String
            ?? "Unknown Artist"
        let album = dictionary["album"] as? String ?? dictionary["collection"] as? String ?? "Imported Playlist"
        let urlString = dictionary["url"] as? String
            ?? dictionary["link"] as? String
            ?? dictionary["source_url"] as? String

        return RawPlaylistTrack(
            title: title,
            artist: artist,
            albumTitle: album,
            requestURL: urlString.flatMap(URL.init(string:)),
            displayURL: urlString.flatMap(URL.init(string:)),
            playlistIndex: dictionary["playlist_index"] as? Int,
            sourceID: dictionary["source_id"] as? String ?? dictionary["id"] as? String,
            duration: dictionary["duration"] as? Double ?? dictionary["duration"] as? TimeInterval ?? 0,
            artworkURL: (dictionary["artwork_url"] as? String ?? dictionary["thumbnail"] as? String)
                .flatMap(URL.init(string:))
        )
    }
}

private struct ParsedPlaylist {
    var name: String?
    var tracks: [RawPlaylistTrack]
}

private struct RawPlaylistTrack {
    var title: String
    var artist: String
    var albumTitle: String
    var requestURL: URL?
    var displayURL: URL?
    var playlistIndex: Int?
    var sourceID: String?
    var duration: Double
    var artworkURL: URL?

    var importCandidate: ImportCandidate? {
        guard let requestURL else { return nil }

        return ImportCandidate(
            requestURL: requestURL,
            displayURL: displayURL,
            playlistIndex: playlistIndex,
            sourceID: sourceID,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            duration: duration,
            artworkURL: artworkURL,
            playlistName: nil
        )
    }
}
