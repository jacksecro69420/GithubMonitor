import SwiftUI

struct PullRequestRowView: View {
    let pullRequest: PullRequest
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text("#\(pullRequest.number) \(pullRequest.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 6)

                    PillView(
                        text: pullRequest.status.rawValue,
                        color: pullRequest.status.pillColor
                    )
                }

                HStack(spacing: 6) {
                    Text(pullRequest.repositoryNameWithOwner)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.7))

                    Text(relativeDateText(from: pullRequest.updatedAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.7))

                    Text("@\(pullRequest.authorLogin)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private func relativeDateText(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
