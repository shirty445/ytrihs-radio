import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit
import YTDLKit

@MainActor
final class PlaybackManager: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex = 0
    @Published var shuffleEnabled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isPresentingPlayer = false

    private let player = AVPlayer()
    private let library: MusicLibrary
    private let banners: BannerCenter
    private let bridge: YTDLBridge

    private var canonicalQueue: [Song] = []
    private var timeObserver: Any?
    private var lastPersistedSecond: Double = 0
    private var currentArtworkImage: UIImage?
    private var completionObserver: NSObjectProtocol?

    init(library: MusicLibrary, banners: BannerCenter, bridge: YTDLBridge) {
        self.library = library
        self.banners = banners
        self.bridge = bridge

        configureAudioSession()
        configureRemoteCommands()
        observePlaybackState()
        observeTrackCompletion()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let completionObserver {
            NotificationCenter.default.removeObserver(completionObserver)
        }
    }

    func play(song: Song, within songs: [Song]) {
        canonicalQueue = songs
        applyQueueOrdering(startingWith: song.id)
        playCurrentItem()
    }

    func play(song: Song) {
        play(song: song, within: [song])
    }

    func playPlaylist(_ playlistSongs: [Song]) {
        guard let first = playlistSongs.first else { return }
        play(song: first, within: playlistSongs)
    }

    func playQueue(_ songs: [Song], startingAt index: Int = 0) {
        guard let startSong = songs[safe: index] else { return }
        play(song: startSong, within: songs)
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
            Task {
                await persistProgress(incrementPlayCount: false)
            }
        } else {
            player.play()
            isPlaying = true
            updateNowPlaying()
        }
    }

    func seek(to seconds: Double) {
        guard let item = player.currentItem else { return }
        let clamped = min(max(seconds, 0), item.duration.seconds.isFinite ? item.duration.seconds : seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
        updateNowPlaying()
    }

    func skipToNext() {
        guard !queue.isEmpty else { return }

        if currentIndex + 1 < queue.count {
            currentIndex += 1
            playCurrentItem()
            return
        }

        if repeatMode == .all {
            currentIndex = 0
            playCurrentItem()
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func skipToPrevious() {
        if currentTime > 5 {
            seek(to: 0)
            return
        }

        guard currentIndex > 0 else {
            seek(to: 0)
            return
        }

        currentIndex -= 1
        playCurrentItem()
    }

    func queueNext(_ song: Song) {
        let insertionIndex = min(currentIndex + 1, canonicalQueue.count)
        canonicalQueue.insert(song, at: insertionIndex)
        applyQueueOrdering(startingWith: currentSong?.id ?? song.id)
        banners.show(title: "Up Next", message: "\(song.title) will play next")
    }

    func appendToQueue(_ songs: [Song]) {
        canonicalQueue.append(contentsOf: songs)
        applyQueueOrdering(startingWith: currentSong?.id ?? songs.first?.id)
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        applyQueueOrdering(startingWith: currentSong?.id)
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
    }

    private func playCurrentItem() {
        guard let song = queue[safe: currentIndex] else { return }

        currentSong = song

        Task {
            guard let preparedPlayback = await prepareSongForPlayback(song) else {
                isPlaying = false
                return
            }

            currentSong = preparedPlayback.song
            currentArtworkImage = await loadArtworkImage(for: preparedPlayback.song)
            player.replaceCurrentItem(with: preparedPlayback.item)
            player.play()
            isPlaying = true
            duration = preparedPlayback.song.duration
            currentTime = 0
            lastPersistedSecond = 0

            if library.database.preferences.saveResumeProgress,
               preparedPlayback.song.resumePosition > 10,
               preparedPlayback.song.resumePosition < max(preparedPlayback.song.duration - 10, 10) {
                await player.seek(to: CMTime(seconds: preparedPlayback.song.resumePosition, preferredTimescale: 600))
                currentTime = preparedPlayback.song.resumePosition
            }

            updateNowPlaying()
        }
    }

    private func prepareSongForPlayback(_ song: Song) async -> PreparedPlayback? {
        if await library.hasPlayableLocalAsset(for: song) {
            let playableSong = library.song(withID: song.id) ?? song
            let fileURL = await library.localFileURL(for: playableSong)
            return PreparedPlayback(song: playableSong, item: AVPlayerItem(url: fileURL))
        }

        guard let candidate = playbackCandidate(for: song) else {
            banners.show(
                title: "Playback Failed",
                message: "This track's local file is invalid and it cannot be refreshed because the original source URL is missing.",
                isError: true
            )
            return nil
        }

        if song.isStreamBacked {
            do {
                let stream = try await bridge.resolveAudioStream(
                    candidate: candidate,
                    quality: library.database.preferences.audioQuality
                )
                let playableSong = library.song(withID: song.id) ?? song
                return PreparedPlayback(song: playableSong, item: playerItem(for: stream))
            } catch {
                banners.show(title: "Playback Failed", message: error.localizedDescription, isError: true)
                return nil
            }
        }

        do {
            banners.show(title: "Repairing Track", message: "Refreshing \(song.title) before playback.")
            let outputTemplate = try await library.storage.outputTemplate(
                for: song.id,
                title: song.title,
                policy: library.database.preferences.downloadLocationPolicy
            )
            let fileURL = try await bridge.download(
                candidate: candidate,
                quality: library.database.preferences.audioQuality,
                outputTemplate: outputTemplate,
                onProgress: { _, _ in }
            )
            let storedPath = await library.storage.relativeStoredPath(for: fileURL)
            await library.replaceLocalAsset(for: song.id, with: storedPath)

            guard let refreshedSong = library.song(withID: song.id),
                  await library.hasPlayableLocalAsset(for: refreshedSong) else {
                banners.show(title: "Playback Failed", message: "The refreshed audio file is still not playable.", isError: true)
                return nil
            }

            return PreparedPlayback(song: refreshedSong, item: AVPlayerItem(url: fileURL))
        } catch {
            banners.show(title: "Playback Failed", message: error.localizedDescription, isError: true)
            return nil
        }
    }

    private func playbackCandidate(for song: Song) -> ImportCandidate? {
        guard let sourceURLString = song.sourceURL,
              let sourceURL = URL(string: sourceURLString),
              sourceURL.isWebURL else {
            return nil
        }

        return ImportCandidate(
            requestURL: sourceURL,
            displayURL: sourceURL,
            playlistIndex: nil,
            sourceID: song.sourceID,
            title: song.title,
            artist: song.artist,
            albumTitle: song.albumTitle,
            duration: song.duration,
            artworkURL: nil,
            playlistName: nil
        )
    }

    private func playerItem(for stream: YTDLResolvedAudioStream) -> AVPlayerItem {
        var options: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ]

        if let userAgent = stream.httpHeaders["User-Agent"] ?? stream.httpHeaders["user-agent"],
           #available(iOS 16.0, *) {
            options[AVURLAssetHTTPUserAgentKey] = userAgent
        }

        let cookies = cookies(from: stream.httpHeaders, for: stream.url)
        if !cookies.isEmpty {
            options[AVURLAssetHTTPCookiesKey] = cookies
            HTTPCookieStorage.shared.setCookies(cookies, for: stream.url, mainDocumentURL: stream.webpageURL ?? stream.url)
        }

        let asset = AVURLAsset(url: stream.url, options: options)
        return AVPlayerItem(asset: asset)
    }

    private func loadArtworkImage(for song: Song) async -> UIImage? {
        guard let artworkURL = await library.artworkURL(for: song) else { return nil }
        return await ArtworkImageRepository.image(for: artworkURL)
    }

    private func cookies(from headers: [String: String], for url: URL) -> [HTTPCookie] {
        guard let rawCookieHeader = headers["Cookie"] ?? headers["cookie"],
              let host = url.host else {
            return []
        }

        return rawCookieHeader
            .split(separator: ";")
            .compactMap { cookiePair in
                let components = cookiePair.split(separator: "=", maxSplits: 1)
                guard components.count == 2 else { return nil }

                return HTTPCookie(properties: [
                    .domain: host,
                    .path: "/",
                    .name: String(components[0]).trimmingCharacters(in: .whitespaces),
                    .value: String(components[1]).trimmingCharacters(in: .whitespaces),
                    .secure: (url.scheme ?? "").lowercased() == "https" ? "TRUE" : "FALSE"
                ])
            }
    }

    private func applyQueueOrdering(startingWith songID: UUID?) {
        guard let currentSongID = songID ?? canonicalQueue.first?.id else {
            queue = []
            currentIndex = 0
            return
        }

        let baseQueue = canonicalQueue
        guard let startIndex = baseQueue.firstIndex(where: { $0.id == currentSongID }) else {
            queue = baseQueue
            currentIndex = 0
            return
        }

        if shuffleEnabled {
            let current = baseQueue[startIndex]
            let before = Array(baseQueue[..<startIndex])
            let after = Array(baseQueue[(startIndex + 1)...])
            queue = [current] + (before + after).shuffled()
            currentIndex = 0
        } else {
            queue = baseQueue
            currentIndex = startIndex
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    private func observePlaybackState() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            currentTime = time.seconds.isFinite ? time.seconds : 0
            duration = player.currentItem?.duration.seconds.isFinite == true ? player.currentItem?.duration.seconds ?? duration : duration
            updateNowPlaying()

            guard abs(currentTime - lastPersistedSecond) >= 10, let currentSong else { return }
            lastPersistedSecond = currentTime
            Task {
                await self.library.recordPlayback(songID: currentSong.id, position: self.currentTime, incrementPlayCount: false)
            }
        }
    }

    private func observeTrackCompletion() {
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleTrackEnded()
        }
    }

    private func handleTrackEnded() {
        Task {
            await persistProgress(incrementPlayCount: true)
        }

        if repeatMode == .one {
            seek(to: 0)
            player.play()
            return
        }

        skipToNext()
    }

    private func persistProgress(incrementPlayCount: Bool) async {
        guard let currentSong else { return }
        await library.recordPlayback(songID: currentSong.id, position: currentTime, incrementPlayCount: incrementPlayCount)
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipToNext()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipToPrevious()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentSong.title,
            MPMediaItemPropertyArtist: currentSong.artist,
            MPMediaItemPropertyAlbumTitle: currentSong.albumTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0
        ]

        if let image = currentArtworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

private struct PreparedPlayback {
    let song: Song
    let item: AVPlayerItem
}
