import SwiftUI

struct SongRowView: View {
    @EnvironmentObject private var theme: ThemeManager
    let song: Song
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(artworkPath: song.artworkPath, artworkSourceURL: song.effectiveArtworkSourceURL, cornerRadius: 12, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle ?? "\(song.artist) • \(song.albumTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    if song.isStreamBacked {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                    }

                    if song.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(theme.accentColor)
                    }
                }

                Text(song.duration.asDurationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
