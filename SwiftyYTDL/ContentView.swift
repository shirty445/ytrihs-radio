import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlaybackManager
    @EnvironmentObject private var searchCoordinator: SearchCoordinator
    @EnvironmentObject private var theme: ThemeManager
    @State private var selectedTab: AppTab = .home
    @State private var isPlayerPresented = false
    @State private var pendingFindSearchPresentation = false
    private let miniPlayerAnimation = Animation.spring(response: 0.35, dampingFraction: 0.9)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                shellBackground
                    .ignoresSafeArea()

                navigationContainer {
                    currentTabView
                }
            }
            .overlay(alignment: .bottom) {
                bottomOverlay(proxy: proxy)
                    .offset(y: proxy.safeAreaInsets.bottom)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $isPlayerPresented) {
            playerSheet
        }
        .onChange(of: player.currentSong?.id) { newValue in
            if newValue == nil {
                isPlayerPresented = false
            }
        }
        .onChange(of: selectedTab) { _ in
            searchCoordinator.reset()

            if selectedTab == .search, pendingFindSearchPresentation {
                searchCoordinator.isFindSearchPresented = true
            }
            pendingFindSearchPresentation = false
        }
        .overlay(alignment: .top) {
            BannerOverlayView()
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func bottomOverlay(proxy: GeometryProxy) -> some View {
        let outerMargin: CGFloat = 16
        let spacing: CGFloat = 10
        let controlSize: CGFloat = 64
        let availableWidth = max(0, proxy.size.width - outerMargin * 2)
        let navWidth = max(0, availableWidth - controlSize - spacing)
        let bottomPadding = outerMargin

        VStack(alignment: .leading, spacing: 10) {
            if player.currentSong != nil {
                MiniPlayerView {
                    isPlayerPresented = true
                }
                .frame(width: availableWidth, alignment: .leading)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: spacing) {
                navigationBar
                    .frame(width: navWidth, height: controlSize)

                searchButton
                    .frame(width: controlSize, height: controlSize)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, outerMargin)
        .padding(.bottom, bottomPadding)
        .animation(miniPlayerAnimation, value: player.currentSong?.id)
    }

    @ViewBuilder
    private var currentTabView: some View {
        switch selectedTab {
        case .home:
            HomeView()
        case .search:
            SearchView()
        case .library:
            LibraryView()
        case .playlists:
            PlaylistsView()
        case .settings:
            SettingsView()
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.title)
                            .font(.caption2.weight(selectedTab == tab ? .semibold : .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 62)
        .padding(.horizontal, 8)
        .modifier(FloatingTabBarGlass())
    }

    private var searchButton: some View {
        Button {
            handleSearchButtonTapped()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SearchButtonGlass())
    }

    private func handleSearchButtonTapped() {
        switch selectedTab {
        case .library:
            searchCoordinator.isLibrarySearchPresented = true
        case .playlists:
            searchCoordinator.isPlaylistsSearchPresented = true
        case .search:
            searchCoordinator.isFindSearchPresented = true
        default:
            pendingFindSearchPresentation = true
            selectedTab = .search
        }
    }

    @ViewBuilder
    private func navigationContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
            }
        } else {
            NavigationView {
                content()
            }
            .navigationViewStyle(.stack)
        }
    }

    @ViewBuilder
    private var playerSheet: some View {
        if #available(iOS 16.0, *) {
            PlayerView {
                isPlayerPresented = false
            }
                .presentationDetents([.large])
        } else {
            PlayerView {
                isPlayerPresented = false
            }
        }
    }

    private var shellBackground: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(
                colors: theme.subtleBackgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct FloatingTabBarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(false), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.18))
                        .allowsHitTesting(false)
                }
                .shadow(color: .white.opacity(0.16), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                .pressableScaleEffect(pressedScale: 1.03)
        } else {
            content
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .bottom)
                }
        }
    }
}

private struct SearchButtonGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(false), in: .circle)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.18))
                        .allowsHitTesting(false)
                }
                .pressableScaleEffect(pressedScale: 1.06)
        } else {
            content
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .bottom)
                }
        }
    }
}
private enum AppTab: String, CaseIterable, Identifiable {
    case home
    case search
    case library
    case playlists
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .search:
            return "Find"
        case .library:
            return "Library"
        case .playlists:
            return "Playlists"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house.fill"
        case .search:
            return "music.note"
        case .library:
            return "square.stack.fill"
        case .playlists:
            return "music.note.list"
        case .settings:
            return "gearshape.fill"
        }
    }
}
