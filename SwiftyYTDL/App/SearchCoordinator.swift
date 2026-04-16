import SwiftUI

@MainActor
final class SearchCoordinator: ObservableObject {
    @Published var isLibrarySearchPresented = false
    @Published var isPlaylistsSearchPresented = false
    @Published var isFindSearchPresented = false

    func reset() {
        isLibrarySearchPresented = false
        isPlaylistsSearchPresented = false
        isFindSearchPresented = false
    }
}
