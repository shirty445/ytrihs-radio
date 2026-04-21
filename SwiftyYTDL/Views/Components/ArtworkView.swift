import SwiftUI
import UIKit

struct ArtworkView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var theme: ThemeManager

    let artworkPath: String?
    var artworkSourceURL: String? = nil
    var cornerRadius: CGFloat = 16
    var size: CGFloat? = nil

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: theme.placeholderGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: "\(artworkPath ?? "")|\(artworkSourceURL ?? "")") {
            await loadImage()
        }
    }

    private func loadImage() async {
        if let artworkPath {
            let url = await library.storage.absoluteURL(forStoredPath: artworkPath)
            if let localImage = await ArtworkImageRepository.image(for: url) {
                image = localImage
                return
            }
        }

        guard let artworkSourceURL,
              let remoteURL = URL(string: artworkSourceURL) else {
            image = nil
            return
        }

        if let remoteImage = await ArtworkImageRepository.image(for: remoteURL) {
            image = remoteImage
        } else {
            image = nil
        }
    }
}
