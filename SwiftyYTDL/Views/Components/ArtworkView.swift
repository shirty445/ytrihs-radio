import SwiftUI
import UIKit

struct ArtworkView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var theme: ThemeManager

    let artworkPath: String?
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
        .task(id: artworkPath) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let artworkPath else {
            image = nil
            return
        }

        let url = await library.storage.absoluteURL(forStoredPath: artworkPath)
        image = UIImage(contentsOfFile: url.path)
    }
}
