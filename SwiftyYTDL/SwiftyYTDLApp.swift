import SwiftUI

@main
struct SwiftyYTDLApp: App {
    @StateObject private var environment = AppEnvironment()
    @StateObject private var searchCoordinator = SearchCoordinator()
    @StateObject private var theme = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                .environmentObject(searchCoordinator)
                .environmentObject(theme)
                .environmentObject(environment.library)
                .environmentObject(environment.player)
                .environmentObject(environment.importer)
                .environmentObject(environment.banners)
                .task {
                    await environment.startup()
                }
                .tint(theme.accentColor)
                .preferredColorScheme(theme.preferredColorScheme)
        }
    }
}
