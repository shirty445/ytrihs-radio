import Foundation

enum AudioQualityPreference: String, Codable, CaseIterable, Identifiable {
    case bestAvailable
    case aacPreferred
    case dataSaver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestAvailable:
            return "Best Available"
        case .aacPreferred:
            return "AAC Preferred"
        case .dataSaver:
            return "Data Saver"
        }
    }

    var subtitle: String {
        switch self {
        case .bestAvailable:
            return "Highest quality audio the source provides"
        case .aacPreferred:
            return "Prefer M4A/AAC when it is available"
        case .dataSaver:
            return "Prefer smaller audio files for offline listening"
        }
    }
}

enum RepeatMode: String, Codable, CaseIterable, Identifiable {
    case off
    case all
    case one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .all:
            return "All"
        case .one:
            return "One"
        }
    }
}

enum LibrarySortMode: String, Codable, CaseIterable, Identifiable {
    case recentlyAdded
    case title
    case artist
    case duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded:
            return "Recently Added"
        case .title:
            return "Title"
        case .artist:
            return "Artist"
        case .duration:
            return "Duration"
        }
    }
}

enum DownloadLocationPolicy: String, Codable, CaseIterable, Identifiable {
    case applicationSupport
    case documents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applicationSupport:
            return "App Support"
        case .documents:
            return "Documents"
        }
    }
}

enum ImportJobStatus: String, Codable, CaseIterable, Identifiable {
    case queued
    case processing
    case completed
    case failed
    case cancelled
    case duplicate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queued:
            return "Queued"
        case .processing:
            return "Processing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .duplicate:
            return "Duplicate"
        }
    }
}

enum PendingTrackStatus: String, Codable, CaseIterable, Identifiable {
    case needsImport
    case unavailable
    case failed
    case duplicate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsImport:
            return "Needs Import"
        case .unavailable:
            return "Unavailable"
        case .failed:
            return "Failed"
        case .duplicate:
            return "Duplicate"
        }
    }
}

enum PlaylistReviewStatus: String, CaseIterable, Identifiable, Codable {
    case matched
    case needsImport
    case duplicate
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matched:
            return "Matched"
        case .needsImport:
            return "Needs Import"
        case .duplicate:
            return "Duplicate"
        case .failed:
            return "Failed"
        }
    }
}

enum AppLogLevel: String, Codable, CaseIterable, Identifiable {
    case info
    case error

    var id: String { rawValue }
}

struct AppBanner: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let isError: Bool
}

struct AppLogEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date = .now
    var level: AppLogLevel
    var message: String
}

struct RecentImportRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var sourceURL: String
    var importedAt: Date = .now
    var succeeded: Bool
    var detail: String
}

struct AppPreferences: Codable, Hashable {
    var audioQuality: AudioQualityPreference = .bestAvailable
    var downloadLocationPolicy: DownloadLocationPolicy = .applicationSupport
    var artworkCachingEnabled: Bool = true
    var autoQueuePlaylistImports: Bool = true
    var saveResumeProgress: Bool = true
    var librarySortMode: LibrarySortMode = .recentlyAdded
}

struct Song: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var sourceID: String?
    var sourceURL: String?
    var title: String
    var artist: String
    var albumTitle: String
    var albumArtist: String?
    var artworkPath: String?
    var localFileName: String
    var duration: Double
    var importDate: Date = .now
    var lastPlayedAt: Date?
    var playCount: Int = 0
    var resumePosition: Double = 0
    var isFavorite: Bool = false
    var genre: String?
    var notes: String?

    var normalizedIdentityKey: String {
        [title.normalizedForMatching, artist.normalizedForMatching]
            .joined(separator: "::")
    }
}

struct PlaylistPendingItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var albumTitle: String
    var sourceURL: String?
    var playlistIndex: Int?
    var sourceID: String?
    var note: String?
    var status: PendingTrackStatus
}

struct PlaylistItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var songID: UUID?
    var pendingItem: PlaylistPendingItem?
}

struct PlaylistModel: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var items: [PlaylistItem] = []
}

struct LibraryDatabase: Codable {
    var songs: [Song] = []
    var playlists: [PlaylistModel] = []
    var recentImports: [RecentImportRecord] = []
    var logs: [AppLogEntry] = []
    var preferences: AppPreferences = .init()
}

struct AlbumSummary: Identifiable, Hashable {
    var title: String
    var artist: String
    var artworkPath: String?
    var songs: [Song]

    var id: String {
        [title.normalizedForMatching, artist.normalizedForMatching]
            .joined(separator: "::")
    }

    var songCount: Int { songs.count }
    var totalDuration: Double { songs.reduce(0) { $0 + $1.duration } }
}

struct ArtistSummary: Identifiable, Hashable {
    var name: String
    var artworkPath: String?
    var songs: [Song]

    var id: String { name.normalizedForMatching }
    var songCount: Int { songs.count }
    var totalDuration: Double { songs.reduce(0) { $0 + $1.duration } }
}

struct ImportCandidate: Identifiable, Hashable {
    var id: UUID = UUID()
    var requestURL: URL
    var displayURL: URL?
    var playlistIndex: Int?
    var sourceID: String?
    var title: String
    var artist: String
    var albumTitle: String
    var duration: Double
    var artworkURL: URL?
    var playlistName: String?

    var matchingKey: String {
        [title.normalizedForMatching, artist.normalizedForMatching]
            .joined(separator: "::")
    }
}

struct ImportJobState: Identifiable, Equatable {
    var id: UUID = UUID()
    var plannedSongID: UUID = UUID()
    var title: String
    var artist: String
    var createdAt: Date = .now
    var status: ImportJobStatus = .queued
    var progress: Double = 0
    var bytesWritten: Int64 = 0
    var bytesExpected: Int64 = 0
    var detail: String = ""
    var errorMessage: String?
    var resolvedSongID: UUID?
    var candidate: ImportCandidate
    var requestedQuality: AudioQualityPreference
}

struct PlaylistImportPreviewItem: Identifiable, Hashable {
    var id: UUID = UUID()
    var position: Int
    var title: String
    var artist: String
    var albumTitle: String
    var duration: Double
    var requestURL: URL?
    var displayURL: URL?
    var playlistIndex: Int?
    var sourceID: String?
    var artworkURL: URL?
    var status: PlaylistReviewStatus
    var matchedSongID: UUID?
    var detail: String
}

struct PlaylistImportDraft: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sourceDescription: String
    var items: [PlaylistImportPreviewItem]
    var createdAt: Date = .now

    var matchedCount: Int { items.filter { $0.status == .matched }.count }
    var importableCount: Int { items.filter { $0.status == .needsImport && $0.requestURL != nil }.count }
    var failedCount: Int { items.filter { $0.status == .failed }.count }
}
