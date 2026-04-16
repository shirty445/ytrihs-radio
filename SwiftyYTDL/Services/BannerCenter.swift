import Combine
import Foundation

@MainActor
final class BannerCenter: ObservableObject {
    @Published var currentBanner: AppBanner?

    private var dismissTask: Task<Void, Never>?

    func show(title: String, message: String, isError: Bool = false) {
        dismissTask?.cancel()
        currentBanner = AppBanner(title: title, message: message, isError: isError)

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.currentBanner = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        currentBanner = nil
    }
}
