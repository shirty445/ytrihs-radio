import Combine
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case songs
        case albums
        case artists
        case favorites
        case recent
        case downloads

        var id: String { rawValue }

        var title: String {
            switch self {
            case .songs:
                return "Songs"
            case .albums:
                return "Albums"
            case .artists:
                return "Artists"
            case .favorites:
                return "Liked"
            case .recent:
                return "Recent"
            case .downloads:
                return "Offline"
            }
        }
    }

    @Published var selectedSection: Section = .songs
    @Published var searchText = ""
    @Published var editedSong: Song?
}
