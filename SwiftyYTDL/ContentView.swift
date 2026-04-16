import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selectedTab: AppTab = .home
    @State private var isPlayerPresented = false

    var body: some View {
        ZStack {
            shellBackground
                .ignoresSafeArea()

            navigationContainer {
                currentTabView
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                MiniPlayerView {
                    isPlayerPresented = true
                }
                customTabBar
            }
        }
        .sheet(isPresented: $isPlayerPresented) {
            playerSheet
        }
        .onChange(of: environment.player.currentSong?.id) { newValue in
            if newValue == nil {
                isPlayerPresented = false
            }
        }
        .overlay(alignment: .top) {
            BannerOverlayView()
                .padding(.top, 8)
        }
        .environmentObject(environment.library)
        .environmentObject(environment.player)
        .environmentObject(environment.importer)
        .environmentObject(environment.banners)
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

    private var customTabBar: some View {
        VStack(spacing: 0) {
            Divider()

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
                        .frame(maxWidth: .infinity)
                        .padding(.top, 9)
                        .padding(.bottom, 6)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.white.opacity(0.22))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.22))
                    )
                    .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .background(.ultraThinMaterial)
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
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.95, blue: 0.92),
                Color(red: 0.99, green: 0.98, blue: 0.96),
                Color(red: 0.93, green: 0.92, blue: 0.90)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
            return "Search"
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
            return "magnifyingglass"
        case .library:
            return "square.stack.fill"
        case .playlists:
            return "music.note.list"
        case .settings:
            return "gearshape.fill"
        }
    }
}
