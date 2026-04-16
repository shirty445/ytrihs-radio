import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct SearchView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var searchCoordinator: SearchCoordinator
    @EnvironmentObject private var theme: ThemeManager

    @StateObject private var viewModel = SearchViewModel()
    @State private var scope: FindScope = .youtube
    @FocusState private var isSearchFocused: Bool
    @State private var hasSearchedYouTube = false
    @State private var hasSearchedSoundCloud = false
    private let searchBarAnimation = Animation.spring(response: 0.35, dampingFraction: 0.9)

    private enum FindScope: Hashable, CaseIterable, Identifiable {
        case youtube
        case soundcloud
        case link

        var id: Self { self }

        var title: String {
            switch self {
            case .youtube:
                return "YouTube"
            case .soundcloud:
                return "SoundCloud"
            case .link:
                return "Link"
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                switch scope {
                case .youtube:
                    resultsBody(
                        results: viewModel.youtubeResults,
                        showEmptyState: hasSearchedYouTube,
                        emptyTitle: "No Results",
                        emptyMessage: "No YouTube matches were returned."
                    )

                case .soundcloud:
                    resultsBody(
                        results: viewModel.soundcloudResults,
                        showEmptyState: hasSearchedSoundCloud,
                        emptyTitle: "No Results",
                        emptyMessage: "No SoundCloud matches were returned."
                    )

                case .link:
                    linkImportCard

                    if let preview = viewModel.singleTrackPreview {
                        singleTrackPreview(preview)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .applyHiddenNavBarBackgroundIfAvailable()
        .safeAreaInset(edge: .top, spacing: 0) {
            topChrome
        }
        .animation(searchBarAnimation, value: searchCoordinator.isFindSearchPresented)
        .onChange(of: scope) { _ in
            viewModel.reset()
            withAnimation(searchBarAnimation) {
                searchCoordinator.isFindSearchPresented = false
            }
            hasSearchedYouTube = false
            hasSearchedSoundCloud = false
        }
        .onChange(of: searchCoordinator.isFindSearchPresented) { isPresented in
            isSearchFocused = isPresented
        }
        .task {
            viewModel.syncPreferences(from: library)
        }
        .sheet(item: $viewModel.playlistDraft) { draft in
            playlistImportReviewView(for: draft)
        }
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
            scopePicker

            if searchCoordinator.isFindSearchPresented, scope != .link {
                findSearchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.clear)
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FindScope.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scope = item
                        }
                    } label: {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(scope == item ? Color.white : Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .background {
                        if scope == item {
                            Capsule(style: .continuous)
                                .fill(theme.accentColor)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var findSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search \(scope.title)", text: activeQuery)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    Task {
                        await performSearch()
                    }
                }

            if !activeQuery.wrappedValue.isEmpty {
                Button {
                    activeQuery.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Cancel") {
                activeQuery.wrappedValue = ""
                withAnimation(searchBarAnimation) {
                    searchCoordinator.isFindSearchPresented = false
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(false), in: Capsule())
            } else {
                Capsule()
                    .fill(.thinMaterial)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var activeQuery: Binding<String> {
        switch scope {
        case .youtube:
            return $viewModel.youtubeQuery
        case .soundcloud:
            return $viewModel.soundcloudQuery
        case .link:
            return .constant("")
        }
    }

    private func performSearch() async {
        guard scope != .link else { return }
        switch scope {
        case .youtube:
            await viewModel.searchYouTube(with: environment)
            hasSearchedYouTube = true
        case .soundcloud:
            await viewModel.searchSoundCloud(with: environment)
            hasSearchedSoundCloud = true
        case .link:
            break
        }
        withAnimation(searchBarAnimation) {
            searchCoordinator.isFindSearchPresented = false
        }
    }

    @ViewBuilder
    private func resultsBody(
        results: [ImportCandidate],
        showEmptyState: Bool,
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        if results.isEmpty {
            if showEmptyState {
                EmptyStateView(title: emptyTitle, message: emptyMessage, systemImage: "music.note")
                    .padding(.top, 16)
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(results) { candidate in
                    candidateRow(candidate)
                        .padding(.vertical, 10)
                    Divider()
                        .opacity(0.35)
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func candidateRow(_ candidate: ImportCandidate) -> some View {
        HStack(spacing: 14) {
            if let artworkURL = candidate.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        ArtworkView(artworkPath: nil, cornerRadius: 14, size: 54)
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ArtworkView(artworkPath: nil, cornerRadius: 14, size: 54)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(candidate.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                viewModel.importSearchResult(candidate, with: environment)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func playlistImportReviewView(for draft: PlaylistImportDraft) -> some View {
        let reviewView = PlaylistImportReviewView(
            draft: draft,
            selectedQuality: $viewModel.selectedQuality,
            queueMissingTracks: $viewModel.queueMissingPlaylistTracks
        ) {
            Task {
                await viewModel.commitPlaylistDraft(with: environment)
            }
        }

        if #available(iOS 16.0, *) {
            reviewView
                .presentationDetents([.large])
        } else {
            reviewView
        }
    }

    private var linkImportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import From Link")
                .font(.title3.weight(.semibold))

            Text("Paste a track or playlist URL, preview what the wrapper found, then download audio into the local library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            urlTextField

            qualityPicker

            HStack {
                Button("Paste") {
                    viewModel.urlText = UIPasteboard.general.string ?? ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(viewModel.isAnalyzing ? "Analyzing..." : "Analyze Link") {
                    Task {
                        await viewModel.analyzeURL(with: environment)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAnalyzing)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Quality")
                .font(.subheadline.weight(.semibold))

            Picker("Audio Quality", selection: $viewModel.selectedQuality) {
                ForEach(AudioQualityPreference.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var urlTextField: some View {
        if #available(iOS 16.0, *) {
            TextField("https://...", text: $viewModel.urlText, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            TextField("https://...", text: $viewModel.urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func singleTrackPreview(_ candidate: ImportCandidate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Metadata Preview")
                .font(.title3.weight(.semibold))

            HStack(spacing: 14) {
                if let artworkURL = candidate.artworkURL {
                    AsyncImage(url: artworkURL) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            ArtworkView(artworkPath: nil, cornerRadius: 22, size: 88)
                        }
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    ArtworkView(artworkPath: nil, cornerRadius: 22, size: 88)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(candidate.title)
                        .font(.headline)
                    Text("\(candidate.artist) • \(candidate.albumTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(candidate.duration.asDurationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button("Import Track") {
                viewModel.importSingleTrack(with: environment)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
