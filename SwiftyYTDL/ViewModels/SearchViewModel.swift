import Combine
import Foundation
import UniformTypeIdentifiers
import YTDLKit

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var youtubeQuery = ""
    @Published var playlistDataText = ""
    @Published var selectedQuality: AudioQualityPreference = .bestAvailable
    @Published var queueMissingPlaylistTracks = true
    @Published var isAnalyzing = false
    @Published var singleTrackPreview: ImportCandidate?
    @Published var playlistDraft: PlaylistImportDraft?
    @Published var youtubeResults: [ImportCandidate] = []
    @Published var isShowingFileImporter = false

    let supportedFileTypes: [UTType] = [.plainText, .json, .commaSeparatedText]

    func syncPreferences(from library: MusicLibrary) {
        selectedQuality = library.database.preferences.audioQuality
        queueMissingPlaylistTracks = library.database.preferences.autoQueuePlaylistImports
    }

    func analyzeURL(with environment: AppEnvironment) async {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)), url.isWebURL else {
            environment.banners.show(title: "Invalid Link", message: "Paste a valid playlist or track URL.", isError: true)
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            switch try await environment.bridge.probe(url: url) {
            case .single(let track):
                singleTrackPreview = importCandidate(from: track)
                playlistDraft = nil
                youtubeResults = []

            case .playlist(let playlist):
                singleTrackPreview = nil
                youtubeResults = []
                playlistDraft = await environment.playlistImportService.draftForPlaylistProbe(
                    playlist,
                    sourceDescription: url.absoluteString,
                    library: environment.library
                )
            }
        } catch {
            environment.banners.show(title: "Analyze Failed", message: error.localizedDescription, isError: true)
        }
    }

    func searchYouTube(with environment: AppEnvironment) async {
        let trimmedQuery = youtubeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            environment.banners.show(title: "Missing Search", message: "Enter something to search on YouTube.", isError: true)
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let results = try await environment.bridge.search(query: trimmedQuery, maxResults: 12)
            youtubeResults = results.map(importCandidate(from:))
            singleTrackPreview = nil
            playlistDraft = nil

            if youtubeResults.isEmpty {
                environment.banners.show(title: "No Results", message: "No YouTube matches were returned for \"\(trimmedQuery)\".", isError: true)
            }
        } catch {
            environment.banners.show(title: "Search Failed", message: error.localizedDescription, isError: true)
        }
    }

    func analyzePastedPlaylistData(with environment: AppEnvironment) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            singleTrackPreview = nil
            youtubeResults = []
            playlistDraft = try await environment.playlistImportService.draftForText(
                playlistDataText,
                sourceDescription: "Pasted Playlist Data",
                suggestedName: "Imported Playlist",
                library: environment.library
            )
        } catch {
            environment.banners.show(title: "Playlist Analysis Failed", message: error.localizedDescription, isError: true)
        }
    }

    func analyzeFile(at url: URL, with environment: AppEnvironment) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let shouldStop = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStop {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            singleTrackPreview = nil
            youtubeResults = []
            playlistDraft = try await environment.playlistImportService.draftForFile(at: url, library: environment.library)
        } catch {
            environment.banners.show(title: "File Import Failed", message: error.localizedDescription, isError: true)
        }
    }

    func importSingleTrack(with environment: AppEnvironment) {
        guard let candidate = singleTrackPreview else { return }
        queue(candidate, with: environment)
    }

    func importSearchResult(_ candidate: ImportCandidate, with environment: AppEnvironment) {
        queue(candidate, with: environment)
    }

    private func queue(_ candidate: ImportCandidate, with environment: AppEnvironment) {
        environment.importer.enqueue([candidate], quality: selectedQuality)
        environment.banners.show(title: "Queued", message: "\(candidate.title) was added to the import queue")
    }

    func commitPlaylistDraft(with environment: AppEnvironment) async {
        guard let playlistDraft else { return }

        let (playlist, candidates) = await environment.library.createPlaylist(
            from: playlistDraft,
            queueMissingTracks: queueMissingPlaylistTracks
        )

        if queueMissingPlaylistTracks, !candidates.isEmpty {
            environment.importer.enqueue(candidates, quality: selectedQuality)
        }

        environment.banners.show(
            title: "Playlist Added",
            message: "\(playlist.name) is now in your library"
        )
        self.playlistDraft = nil
    }

    func reset() {
        singleTrackPreview = nil
        playlistDraft = nil
        youtubeResults = []
    }

    private func importCandidate(from track: YTDLTrackProbe) -> ImportCandidate {
        ImportCandidate(
            requestURL: track.requestURL,
            displayURL: track.displayURL,
            playlistIndex: track.playlistIndex,
            sourceID: track.id,
            title: track.title,
            artist: track.artist,
            albumTitle: track.albumTitle,
            duration: track.duration,
            artworkURL: track.thumbnailURL,
            playlistName: nil
        )
    }
}
