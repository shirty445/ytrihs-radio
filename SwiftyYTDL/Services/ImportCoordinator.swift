import Combine
import Foundation

@MainActor
final class ImportCoordinator: ObservableObject {
    @Published private(set) var jobs: [ImportJobState] = []

    private let bridge: YTDLBridge
    private let library: MusicLibrary
    private let banners: BannerCenter

    private var processingTask: Task<Void, Never>?
    private var cancelRequested = Set<UUID>()

    init(bridge: YTDLBridge, library: MusicLibrary, banners: BannerCenter) {
        self.bridge = bridge
        self.library = library
        self.banners = banners
    }

    var activeJobs: [ImportJobState] {
        jobs.sorted { $0.createdAt > $1.createdAt }
    }

    func enqueue(_ candidates: [ImportCandidate], quality: AudioQualityPreference) {
        for candidate in candidates {
            jobs.append(
                ImportJobState(
                    title: candidate.title,
                    artist: candidate.artist,
                    detail: "Queued for download",
                    candidate: candidate,
                    requestedQuality: quality
                )
            )
        }

        processQueueIfNeeded()
    }

    func retry(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        guard jobs[index].status == .failed || jobs[index].status == .cancelled else { return }

        jobs[index].plannedSongID = UUID()
        jobs[index].status = .queued
        jobs[index].progress = 0
        jobs[index].bytesWritten = 0
        jobs[index].bytesExpected = 0
        jobs[index].detail = "Queued for retry"
        jobs[index].errorMessage = nil
        jobs[index].resolvedSongID = nil

        processQueueIfNeeded()
    }

    func cancel(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }

        switch jobs[index].status {
        case .queued:
            jobs[index].status = .cancelled
            jobs[index].detail = "Cancelled before download started"
        case .processing:
            cancelRequested.insert(jobID)
            jobs[index].detail = "Cancellation requested. The wrapper will stop after the current download step."
        case .failed, .cancelled, .completed, .duplicate:
            jobs.removeAll { $0.id == jobID }
        default:
            break
        }
    }

    private func processQueueIfNeeded() {
        guard processingTask == nil else { return }

        processingTask = Task { [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        while let index = jobs.firstIndex(where: { $0.status == .queued }) {
            var job = jobs[index]
            jobs[index].status = .processing
            jobs[index].detail = "Downloading audio..."

            do {
                let existingSong = library.findExistingSong(for: job.candidate)

                if let existing = existingSong {
                    if await library.hasPlayableLocalAsset(for: existing) {
                        updateCompletion(for: job.id, status: .duplicate, detail: "Already in your library", resolvedSongID: existing.id)
                        continue
                    }

                    jobs[index].detail = existing.isStreamBacked ? "Saving local copy..." : "Refreshing local copy..."
                }

                let outputTemplate = try await library.storage.outputTemplate(
                    for: existingSong?.id ?? job.plannedSongID,
                    title: job.title,
                    policy: library.database.preferences.downloadLocationPolicy
                )

                let fileURL = try await bridge.download(
                    candidate: job.candidate,
                    quality: job.requestedQuality,
                    outputTemplate: outputTemplate,
                    onProgress: { [weak self] written, expected in
                        Task { @MainActor in
                            self?.updateProgress(for: job.id, written: written, expected: expected)
                        }
                    }
                )

                if cancelRequested.contains(job.id) {
                    await library.storage.removeFile(at: fileURL)
                    cancelRequested.remove(job.id)
                    updateCompletion(for: job.id, status: .cancelled, detail: "Cancelled after download completed")
                    continue
                }

                let storedPath = await library.storage.relativeStoredPath(for: fileURL)
                let artworkPath: String?
                if library.database.preferences.artworkCachingEnabled,
                   let artworkURL = job.candidate.artworkURL {
                    artworkPath = try? await library.storage.storeArtwork(
                        from: artworkURL,
                        songID: existingSong?.id ?? job.plannedSongID
                    )
                } else {
                    artworkPath = existingSong?.artworkPath
                }

                if let existingSong {
                    guard let updatedSong = await library.attachLocalAsset(
                        to: existingSong.id,
                        localFileName: storedPath,
                        artworkPath: artworkPath,
                        duration: job.candidate.duration
                    ) else {
                        throw NSError(
                            domain: "ImportCoordinator",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "The library entry could not be updated."]
                        )
                    }

                    updateCompletion(for: job.id, status: .completed, detail: "Saved for offline playback", resolvedSongID: updatedSong.id)
                    banners.show(title: "Saved Offline", message: "\(updatedSong.title) is ready offline")
                } else {
                    let importedSong = await library.registerImportedSong(
                        candidate: job.candidate,
                        plannedSongID: job.plannedSongID,
                        localFileName: storedPath,
                        artworkPath: artworkPath
                    )

                    if importedSong.id != job.plannedSongID {
                        await library.storage.removeFile(at: fileURL)
                        updateCompletion(for: job.id, status: .duplicate, detail: "Matched an existing track while importing", resolvedSongID: importedSong.id)
                    } else {
                        updateCompletion(for: job.id, status: .completed, detail: "Saved for offline playback", resolvedSongID: importedSong.id)
                        banners.show(title: "Imported", message: "\(importedSong.title) is ready offline")
                    }
                }
            } catch {
                let isCancelled = cancelRequested.remove(job.id) != nil
                if isCancelled {
                    updateCompletion(for: job.id, status: .cancelled, detail: "Cancelled during import")
                } else {
                    let errorMessage = importFailureMessage(for: job.candidate, error: error)
                    await library.recordFailedImport(candidate: job.candidate, detail: errorMessage)
                    updateFailure(for: job.id, message: errorMessage)
                    banners.show(title: "Import Failed", message: errorMessage, isError: true)
                }
            }

            if let currentIndex = jobs.firstIndex(where: { $0.id == job.id }),
               jobs[currentIndex].status == .processing {
                jobs[currentIndex].status = .failed
                jobs[currentIndex].detail = "Import ended unexpectedly"
            }
        }

        processingTask = nil
    }

    private func updateProgress(for jobID: UUID, written: Int64, expected: Int64) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }

        jobs[index].bytesWritten = written
        jobs[index].bytesExpected = expected
        jobs[index].progress = expected > 0 ? Double(written) / Double(expected) : 0
        jobs[index].detail = expected > 0 ? "\(written.asByteText) of \(expected.asByteText)" : "Downloading..."
    }

    private func updateCompletion(for jobID: UUID, status: ImportJobStatus, detail: String, resolvedSongID: UUID? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }

        jobs[index].status = status
        jobs[index].detail = detail
        jobs[index].progress = 1
        jobs[index].resolvedSongID = resolvedSongID
    }

    private func updateFailure(for jobID: UUID, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }

        jobs[index].status = .failed
        jobs[index].errorMessage = message
        jobs[index].detail = message
    }

    private func importFailureMessage(for candidate: ImportCandidate, error: Error) -> String {
        if candidate.isYouTubeCandidate || error.isPythonSubprocessUnsupportedError {
            return ImportWorkaround.youtubeDownloadUnavailableMessage
        }

        return error.localizedDescription
    }
}
