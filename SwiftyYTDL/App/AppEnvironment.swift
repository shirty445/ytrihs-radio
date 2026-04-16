import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let banners = BannerCenter()
    let library = MusicLibrary()
    let bridge = YTDLBridge()
    lazy var playlistImportService = PlaylistImportService(bridge: bridge)
    lazy var importer = ImportCoordinator(bridge: bridge, library: library, banners: banners)
    lazy var player = PlaybackManager(library: library, banners: banners, bridge: bridge)

    func startup() async {
        await library.load()
    }
}
