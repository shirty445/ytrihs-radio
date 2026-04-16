import Combine
import Foundation

@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published var isShowingCreateSheet = false
    @Published var isShowingRenameSheet = false
    @Published var draftName = ""
    @Published var playlistToRename: PlaylistModel?

    func startCreate() {
        draftName = ""
        playlistToRename = nil
        isShowingCreateSheet = true
    }

    func startRenaming(_ playlist: PlaylistModel) {
        playlistToRename = playlist
        draftName = playlist.name
        isShowingRenameSheet = true
    }
}
