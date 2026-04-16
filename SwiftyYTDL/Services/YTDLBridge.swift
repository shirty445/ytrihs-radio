import Foundation
import YTDLKit

actor YTDLBridge {
    private let queue = DispatchQueue(label: "org.kostyshyn.YTRihsRadio.ytdl-bridge")

    func probe(url: URL) async throws -> YTDLImportProbe {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try YTDL.shared.probeAudioImport(from: url)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func search(query: String, maxResults: Int = 10) async throws -> [YTDLTrackProbe] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let results = try YTDL.shared.searchAudio(query, maxResults: maxResults)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func download(
        candidate: ImportCandidate,
        quality: AudioQualityPreference,
        outputTemplate: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let preference = self.preference(for: quality)
                    try YTDL.shared.downloadAudio(
                        from: candidate.requestURL,
                        playlistIndex: candidate.playlistIndex,
                        preference: preference,
                        outputTemplate: outputTemplate.path,
                        updateHandler: onProgress,
                        completionHandler: { result in
                            switch result {
                            case .success(let url):
                                continuation.resume(returning: url)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func preference(for quality: AudioQualityPreference) -> YTDLAudioDownloadPreference {
        switch quality {
        case .bestAvailable:
            return .bestAvailable
        case .aacPreferred:
            return .aacPreferred
        case .dataSaver:
            return .dataSaver
        }
    }
}
