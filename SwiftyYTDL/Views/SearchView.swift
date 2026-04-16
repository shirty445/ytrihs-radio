import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var importer: ImportCoordinator

    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                linkImportCard
                youtubeSearchCard
                playlistCopyCard

                if let preview = viewModel.singleTrackPreview {
                    singleTrackPreview(preview)
                }

                if !viewModel.youtubeResults.isEmpty {
                    youtubeResults
                }

                if !library.recentImports.isEmpty {
                    recentHistory
                }

                if !importer.activeJobs.isEmpty {
                    importQueue
                }
            }
            .padding()
        }
        .navigationTitle("Search")
        .task {
            viewModel.syncPreferences(from: library)
        }
        .fileImporter(
            isPresented: $viewModel.isShowingFileImporter,
            allowedContentTypes: viewModel.supportedFileTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                await viewModel.analyzeFile(at: url, with: environment)
            }
        }
        .sheet(item: $viewModel.playlistDraft) { draft in
            playlistImportReviewView(for: draft)
        }
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

    private var youtubeSearchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search YouTube")
                .font(.title3.weight(.semibold))

            Text("Search YouTube directly, review the matches, and queue any result for offline import.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            youtubeSearchField

            qualityPicker

            HStack {
                Button("Paste") {
                    viewModel.youtubeQuery = UIPasteboard.general.string ?? ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(viewModel.isAnalyzing ? "Searching..." : "Search YouTube") {
                    Task {
                        await viewModel.searchYouTube(with: environment)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAnalyzing)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var playlistCopyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Copy A Playlist")
                .font(.title3.weight(.semibold))

            Text("Paste playlist exports, CSV/JSON/text link lists, or import a file. The app will match what it can locally and mark the rest for import.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            playlistDataEditor

            Toggle("Queue missing tracks after the playlist is created", isOn: $viewModel.queueMissingPlaylistTracks)

            HStack {
                Button("Import File") {
                    viewModel.isShowingFileImporter = true
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(viewModel.isAnalyzing ? "Analyzing..." : "Analyze Playlist Data") {
                    Task {
                        await viewModel.analyzePastedPlaylistData(with: environment)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAnalyzing)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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

    private var youtubeResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YouTube Results")
                .font(.title3.weight(.semibold))

            ForEach(viewModel.youtubeResults) { candidate in
                youtubeResultRow(candidate)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func youtubeResultRow(_ candidate: ImportCandidate) -> some View {
        HStack(spacing: 14) {
            if let artworkURL = candidate.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        ArtworkView(artworkPath: nil, cornerRadius: 18, size: 64)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ArtworkView(artworkPath: nil, cornerRadius: 18, size: 64)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(candidate.artist) • \(candidate.albumTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(candidate.duration.asDurationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Import") {
                viewModel.importSearchResult(candidate, with: environment)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private var recentHistory: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Imports")
                .font(.title3.weight(.semibold))

            ForEach(library.recentImports.prefix(5)) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(.headline)
                    Text("\(record.artist) • \(record.detail)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(MusicFormatting.relativeDate.localizedString(for: record.importedAt, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var importQueue: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Queue")
                .font(.title3.weight(.semibold))

            ForEach(importer.activeJobs.prefix(6)) { job in
                ImportJobRowView(
                    job: job,
                    onRetry: { importer.retry(jobID: job.id) },
                    onCancel: { importer.cancel(jobID: job.id) }
                )
            }
        }
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

    @ViewBuilder
    private var youtubeSearchField: some View {
        if #available(iOS 16.0, *) {
            TextField("Artist, track, remix, live set...", text: $viewModel.youtubeQuery, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            TextField("Artist, track, remix, live set...", text: $viewModel.youtubeQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private var playlistDataEditor: some View {
        if #available(iOS 16.0, *) {
            TextEditor(text: $viewModel.playlistDataText)
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            TextEditor(text: $viewModel.playlistDataText)
                .frame(minHeight: 140)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
