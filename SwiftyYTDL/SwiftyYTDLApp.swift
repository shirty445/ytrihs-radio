import SwiftUI

@main
struct SwiftyYTDLApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                .task {
                    await environment.startup()
                }
                .tint(.orange)
                .preferredColorScheme(nil)
        }
    }
}
