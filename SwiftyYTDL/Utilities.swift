import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct PressableScaleEffect: ViewModifier {
    let pressedScale: CGFloat
    let animation: Animation

    @GestureState private var isPressed = false

    init(
        pressedScale: CGFloat = 1.03,
        animation: Animation = .spring(response: 0.28, dampingFraction: 0.88)
    ) {
        self.pressedScale = pressedScale
        self.animation = animation
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? pressedScale : 1)
            .animation(animation, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
            )
    }
}

extension View {
    func pressableScaleEffect(
        pressedScale: CGFloat = 1.03,
        animation: Animation = .spring(response: 0.28, dampingFraction: 0.88)
    ) -> some View {
        modifier(PressableScaleEffect(pressedScale: pressedScale, animation: animation))
    }
}

enum MusicFormatting {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static let duration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()

    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

extension Double {
    var asDurationText: String {
        MusicFormatting.duration.string(from: self) ?? "0:00"
    }
}

extension Int64 {
    var asByteText: String {
        MusicFormatting.bytes.string(fromByteCount: self)
    }
}

extension String {
    var normalizedForMatching: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

extension URL {
    var isWebURL: Bool {
        guard let scheme else { return false }
        return scheme == "https" || scheme == "http"
    }

    var isYouTubeURL: Bool {
        guard let host else { return false }
        let normalizedHost = host.lowercased()
        return normalizedHost.contains("youtube.com")
            || normalizedHost.contains("youtu.be")
            || normalizedHost.contains("youtube-nocookie.com")
    }
}

enum ImportWorkaround {
    static let youtubeDownloadUnavailableMessage = "Direct YouTube downloads are currently unavailable in this iOS build because the bundled extraction engine requires subprocess support."
}

extension Error {
    var isPythonSubprocessUnsupportedError: Bool {
        let message = localizedDescription.lowercased()
        let debugMessage = String(describing: self).lowercased()
        return message.contains("subprocesses are not supported on ios")
            || debugMessage.contains("subprocesses are not supported on ios")
    }
}

extension ImportCandidate {
    var isYouTubeCandidate: Bool {
        requestURL.isYouTubeURL || displayURL?.isYouTubeURL == true
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element == Song {
    func applyingSort(_ sortMode: LibrarySortMode) -> [Song] {
        switch sortMode {
        case .recentlyAdded:
            return sorted { $0.importDate > $1.importDate }
        case .title:
            return sorted {
                if $0.title == $1.title { return $0.artist < $1.artist }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .artist:
            return sorted {
                if $0.artist == $1.artist { return $0.title < $1.title }
                return $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
            }
        case .duration:
            return sorted { $0.duration > $1.duration }
        }
    }
}

#if canImport(UIKit)
extension View {
    @ViewBuilder
    func applyHiddenNavBarBackgroundIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self
        }
    }
}

#endif
