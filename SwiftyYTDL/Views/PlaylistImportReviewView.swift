import SwiftUI

struct PlaylistImportReviewView: View {
    let draft: PlaylistImportDraft
    @Binding var selectedQuality: AudioQualityPreference
    @Binding var queueMissingTracks: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Summary") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(draft.name)
                            .font(.headline)
                        Text(draft.sourceDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(draft.matchedCount) matched • \(draft.importableCount) ready to import • \(draft.failedCount) failed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Import Options") {
                    Picker("Audio Quality", selection: $selectedQuality) {
                        ForEach(AudioQualityPreference.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }

                    Toggle("Queue missing tracks after creating the playlist", isOn: $queueMissingTracks)
                }

                Section("Tracks") {
                    ForEach(draft.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(item.position). \(item.title)")
                                    .font(.headline)
                                Spacer()
                                Text(item.status.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(statusColor(for: item.status))
                            }

                            Text("\(item.artist) • \(item.albumTitle)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Review Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onConfirm()
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func statusColor(for status: PlaylistReviewStatus) -> Color {
        switch status {
        case .matched:
            return .green
        case .needsImport:
            return .orange
        case .duplicate:
            return .purple
        case .failed:
            return .red
        }
    }
}
