import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var banners: BannerCenter

    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        List {
            Section("Import Preferences") {
                Picker("Audio Quality", selection: audioQualityBinding) {
                    ForEach(AudioQualityPreference.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }

                Picker("Download Location", selection: downloadLocationBinding) {
                    ForEach(DownloadLocationPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                Toggle("Cache artwork locally", isOn: artworkCachingBinding)
                Toggle("Auto-queue playlist imports", isOn: autoQueuePlaylistBinding)
                Toggle("Save resume progress", isOn: saveResumeBinding)
            }

            Section("Maintenance") {
                Button(viewModel.isRunningMaintenance ? "Working..." : "Clear Artwork Cache") {
                    runMaintenance {
                        let removed = await library.clearArtworkCache()
                        banners.show(title: "Artwork Cache Cleared", message: "Removed \(removed) cached artwork files")
                    }
                }
                .disabled(viewModel.isRunningMaintenance)

                Button(viewModel.isRunningMaintenance ? "Working..." : "Rebuild Library From Files") {
                    runMaintenance {
                        let rebuilt = await library.rebuildLibraryFromDisk()
                        banners.show(title: "Library Rebuilt", message: "Recovered \(rebuilt) songs from local sidecars")
                    }
                }
                .disabled(viewModel.isRunningMaintenance)

                Button(viewModel.isRunningMaintenance ? "Working..." : "Cleanup Orphaned Files") {
                    runMaintenance {
                        let report = await library.cleanupStorage()
                        banners.show(
                            title: "Cleanup Finished",
                            message: "Removed \(report.removedAudioFiles) audio files and \(report.removedArtworkFiles) artwork files"
                        )
                    }
                }
                .disabled(viewModel.isRunningMaintenance)
            }

            Section("Debug") {
                if let maintenanceMessage = library.maintenanceMessage {
                    Text(maintenanceMessage)
                        .foregroundStyle(.secondary)
                }

                ForEach(library.logs.prefix(12)) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.level.rawValue.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(entry.level == .error ? .red : .secondary)
                        Text(entry.message)
                            .font(.subheadline)
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Button("Clear Logs") {
                    Task {
                        await library.clearLogs()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
    }

    private var audioQualityBinding: Binding<AudioQualityPreference> {
        Binding(
            get: { library.database.preferences.audioQuality },
            set: { quality in
                Task {
                    await library.updatePreferences { $0.audioQuality = quality }
                }
            }
        )
    }

    private var downloadLocationBinding: Binding<DownloadLocationPolicy> {
        Binding(
            get: { library.database.preferences.downloadLocationPolicy },
            set: { policy in
                Task {
                    await library.updatePreferences { $0.downloadLocationPolicy = policy }
                }
            }
        )
    }

    private var artworkCachingBinding: Binding<Bool> {
        Binding(
            get: { library.database.preferences.artworkCachingEnabled },
            set: { value in
                Task {
                    await library.updatePreferences { $0.artworkCachingEnabled = value }
                }
            }
        )
    }

    private var autoQueuePlaylistBinding: Binding<Bool> {
        Binding(
            get: { library.database.preferences.autoQueuePlaylistImports },
            set: { value in
                Task {
                    await library.updatePreferences { $0.autoQueuePlaylistImports = value }
                }
            }
        )
    }

    private var saveResumeBinding: Binding<Bool> {
        Binding(
            get: { library.database.preferences.saveResumeProgress },
            set: { value in
                Task {
                    await library.updatePreferences { $0.saveResumeProgress = value }
                }
            }
        )
    }

    private func runMaintenance(_ operation: @escaping () async -> Void) {
        viewModel.isRunningMaintenance = true
        Task {
            await operation()
            viewModel.isRunningMaintenance = false
        }
    }
}
