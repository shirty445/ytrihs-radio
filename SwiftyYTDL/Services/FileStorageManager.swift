import Foundation
import UniformTypeIdentifiers

struct CleanupReport {
    var removedAudioFiles: Int = 0
    var removedArtworkFiles: Int = 0
    var removedSidecars: Int = 0
}

actor FileStorageManager {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let appFolderName = "YTRihsRadio"

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    private var applicationSupportRoot: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appFolderName, isDirectory: true)
    }

    private var documentsRoot: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appFolderName, isDirectory: true)
    }

    private var artworkRoot: URL {
        applicationSupportRoot.appendingPathComponent("Artwork", isDirectory: true)
    }

    private var sidecarRoot: URL {
        applicationSupportRoot.appendingPathComponent("Sidecars", isDirectory: true)
    }

    private var databaseURL: URL {
        applicationSupportRoot.appendingPathComponent("library.json")
    }

    private func audioRoot(for policy: DownloadLocationPolicy) -> URL {
        switch policy {
        case .applicationSupport:
            return applicationSupportRoot.appendingPathComponent("Audio", isDirectory: true)
        case .documents:
            return documentsRoot.appendingPathComponent("Audio", isDirectory: true)
        }
    }

    func prepareDirectories() throws {
        try createDirectoryIfNeeded(applicationSupportRoot)
        try createDirectoryIfNeeded(documentsRoot)
        try createDirectoryIfNeeded(artworkRoot)
        try createDirectoryIfNeeded(sidecarRoot)
        try createDirectoryIfNeeded(audioRoot(for: .applicationSupport))
        try createDirectoryIfNeeded(audioRoot(for: .documents))
    }

    func loadDatabase() throws -> LibraryDatabase? {
        try prepareDirectories()
        guard fileManager.fileExists(atPath: databaseURL.path) else { return nil }
        let data = try Data(contentsOf: databaseURL)
        return try decoder.decode(LibraryDatabase.self, from: data)
    }

    func saveDatabase(_ database: LibraryDatabase) throws {
        try prepareDirectories()
        let data = try encoder.encode(database)
        try data.write(to: databaseURL, options: .atomic)
    }

    func outputTemplate(for songID: UUID, title: String, policy: DownloadLocationPolicy) throws -> URL {
        try prepareDirectories()
        let safeTitle = sanitizedComponent(from: title)
        return audioRoot(for: policy)
            .appendingPathComponent("\(songID.uuidString)-\(safeTitle)-%(id)s.%(ext)s")
    }

    func relativeStoredPath(for fileURL: URL) -> String {
        let path = fileURL.path
        if path.hasPrefix(applicationSupportRoot.path) {
            return String(path.dropFirst(applicationSupportRoot.path.count + 1))
        }
        if path.hasPrefix(documentsRoot.path) {
            return "Documents/\(String(path.dropFirst(documentsRoot.path.count + 1)))"
        }
        return fileURL.lastPathComponent
    }

    func absoluteURL(forStoredPath path: String) -> URL {
        if path.hasPrefix("Documents/") {
            return documentsRoot.appendingPathComponent(String(path.dropFirst("Documents/".count)))
        }
        return applicationSupportRoot.appendingPathComponent(path)
    }

    func sidecarURL(for songID: UUID) -> URL {
        sidecarRoot.appendingPathComponent("\(songID.uuidString).json")
    }

    func saveSidecar(for song: Song) throws {
        try prepareDirectories()
        let data = try encoder.encode(song)
        try data.write(to: sidecarURL(for: song.id), options: .atomic)
    }

    func loadSongsFromSidecars() throws -> [Song] {
        try prepareDirectories()
        let urls = try fileManager.contentsOfDirectory(
            at: sidecarRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
            .filter { $0.pathExtension == "json" }

        return try urls.compactMap { url in
            let data = try Data(contentsOf: url)
            return try decoder.decode(Song.self, from: data)
        }
    }

    func storeArtwork(from remoteURL: URL, songID: UUID) async throws -> String {
        try prepareDirectories()

        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let ext = resolvedArtworkExtension(from: response, remoteURL: remoteURL)
        let destination = artworkRoot.appendingPathComponent("\(songID.uuidString).\(ext)")
        try data.write(to: destination, options: .atomic)
        return relativeStoredPath(for: destination)
    }

    func clearArtworkCache() throws -> Int {
        try prepareDirectories()
        let artworkFiles = try fileManager.contentsOfDirectory(
            at: artworkRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for file in artworkFiles {
            try? fileManager.removeItem(at: file)
        }

        return artworkFiles.count
    }

    func removeFile(at fileURL: URL) async {
        try? fileManager.removeItem(at: fileURL)
    }

    func cleanupOrphanedAssets(using songs: [Song]) throws -> CleanupReport {
        try prepareDirectories()

        let knownPaths = Set(songs.map(\.localFileName))
        let knownArtwork = Set(songs.compactMap(\.artworkPath))
        let knownSidecars = Set(songs.map { sidecarURL(for: $0.id).lastPathComponent })

        var report = CleanupReport()

        for root in [audioRoot(for: .applicationSupport), audioRoot(for: .documents)] {
            let files = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for file in files where !knownPaths.contains(relativeStoredPath(for: file)) {
                try? fileManager.removeItem(at: file)
                report.removedAudioFiles += 1
            }
        }

        let artworkFiles = (try? fileManager.contentsOfDirectory(
            at: artworkRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for file in artworkFiles where !knownArtwork.contains(relativeStoredPath(for: file)) {
            try? fileManager.removeItem(at: file)
            report.removedArtworkFiles += 1
        }

        let sidecarFiles = (try? fileManager.contentsOfDirectory(
            at: sidecarRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for file in sidecarFiles where !knownSidecars.contains(file.lastPathComponent) {
            try? fileManager.removeItem(at: file)
            report.removedSidecars += 1
        }

        return report
    }

    func deleteAssets(for song: Song) throws {
        try prepareDirectories()

        if let localFileName = song.localFileName.trimmedOrNil {
            try? fileManager.removeItem(at: absoluteURL(forStoredPath: localFileName))
        }
        try? fileManager.removeItem(at: sidecarURL(for: song.id))

        if let artworkPath = song.artworkPath {
            try? fileManager.removeItem(at: absoluteURL(forStoredPath: artworkPath))
        }
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    private func sanitizedComponent(from rawValue: String) -> String {
        let trimmed = rawValue.normalizedForMatching
        let fallback = trimmed.isEmpty ? "track" : trimmed
        return fallback
            .replacingOccurrences(of: " ", with: "-")
            .prefix(48)
            .description
    }

    private func resolvedArtworkExtension(from response: URLResponse, remoteURL: URL) -> String {
        if let mimeType = response.mimeType {
            if mimeType == UTType.png.preferredMIMEType {
                return "png"
            }
            if mimeType == UTType.jpeg.preferredMIMEType {
                return "jpg"
            }
            if mimeType == UTType.gif.preferredMIMEType {
                return "gif"
            }
        }
        let remoteExtension = remoteURL.pathExtension.lowercased()
        return remoteExtension.isEmpty ? "jpg" : remoteExtension
    }
}
