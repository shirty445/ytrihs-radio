import SwiftUI

struct BannerOverlayView: View {
    @EnvironmentObject private var banners: BannerCenter

    var body: some View {
        VStack {
            if let banner = banners.currentBanner {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(banner.isError ? .red : .green)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(banner.title)
                            .font(.headline)
                        Text(banner.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        banners.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: banners.currentBanner?.id)
        .allowsHitTesting(true)
    }
}
