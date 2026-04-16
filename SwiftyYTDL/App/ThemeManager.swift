import SwiftUI

@MainActor
final class ThemeManager: ObservableObject {
    enum Accent: String, CaseIterable, Identifiable {
        case orange
        case pink
        case purple
        case blue
        case teal
        case green
        case red
        case gray

        var id: String { rawValue }

        var title: String {
            rawValue.capitalized
        }

        var color: Color {
            switch self {
            case .orange:
                return .orange
            case .pink:
                return .pink
            case .purple:
                return .purple
            case .blue:
                return .blue
            case .teal:
                return .teal
            case .green:
                return .green
            case .red:
                return .red
            case .gray:
                return .gray
            }
        }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            rawValue.capitalized
        }

        var preferredColorScheme: ColorScheme? {
            switch self {
            case .system:
                return nil
            case .light:
                return .light
            case .dark:
                return .dark
            }
        }
    }

    private static let accentKey = "theme.accent"
    private static let appearanceKey = "theme.appearance"

    @Published var accent: Accent {
        didSet {
            UserDefaults.standard.set(accent.rawValue, forKey: Self.accentKey)
        }
    }

    @Published var appearance: Appearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    init() {
        let storedAccent = UserDefaults.standard.string(forKey: Self.accentKey)
        accent = Accent(rawValue: storedAccent ?? "") ?? .orange

        let storedAppearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
        appearance = Appearance(rawValue: storedAppearance ?? "") ?? .system
    }

    var accentColor: Color {
        accent.color
    }

    var accentSecondaryColor: Color {
        switch accent {
        case .orange:
            return .pink
        case .pink:
            return .purple
        case .purple:
            return .blue
        case .blue:
            return .teal
        case .teal:
            return .blue
        case .green:
            return .teal
        case .red:
            return .orange
        case .gray:
            return .blue
        }
    }

    var accentTertiaryColor: Color {
        switch accent {
        case .orange:
            return .brown
        case .pink:
            return .red
        case .purple:
            return .pink
        case .blue:
            return .purple
        case .teal:
            return .green
        case .green:
            return .blue
        case .red:
            return .pink
        case .gray:
            return .purple
        }
    }

    var strongGradientColors: [Color] {
        [accentColor, accentSecondaryColor, accentTertiaryColor]
    }

    var placeholderGradientColors: [Color] {
        [accentColor.opacity(0.9), accentSecondaryColor.opacity(0.65), accentTertiaryColor.opacity(0.45)]
    }

    var subtleBackgroundGradientColors: [Color] {
        [accentColor.opacity(0.16), accentSecondaryColor.opacity(0.10), .clear]
    }

    var preferredColorScheme: ColorScheme? {
        appearance.preferredColorScheme
    }
}
