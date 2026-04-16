import SwiftUI

struct SongRowView: View {
    let song: Song
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(artworkPath: song.artworkPath, cornerRadius: 12, size: 56)

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
                if song.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                }

                Text(song.duration.asDurationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
