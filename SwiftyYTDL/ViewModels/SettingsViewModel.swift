import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isRunningMaintenance = false
}
