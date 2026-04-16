import SwiftUI

struct ImportJobRowView: View {
    let job: ImportJobState
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.headline)
                    Text(job.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(job.status.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            if job.status == .processing {
                ProgressView(value: job.progress)
                    .tint(.orange)
            }

            Text(job.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if job.status == .failed || job.status == .cancelled {
                HStack {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                    Button("Remove") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
            } else if job.status == .queued || job.status == .processing {
                Button(job.status == .processing ? "Cancel Request" : "Cancel", action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var statusColor: Color {
        switch job.status {
        case .queued:
            return .orange
        case .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        case .duplicate:
            return .purple
        }
    }
}
