import SwiftUI

struct IssueRowView: View {
    let issue: Issue
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text("#\(issue.number) \(issue.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 6)

                    PillView(
                        text: issue.statusText,
                        color: .blue
                    )
                }

                HStack(spacing: 6) {
                    Text(issue.repositoryNameWithOwner)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    separatorDot

                    Text(relativeDateText(from: issue.updatedAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    separatorDot

                    Text("@\(issue.authorLogin)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if !issue.labels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(issue.labels.prefix(3)) { label in
                                PillView(
                                    text: label.name,
                                    color: color(from: label.colorHex)
                                )
                            }
                        }
                    }
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

    private var separatorDot: some View {
        Text("•")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary.opacity(0.7))
    }

    private func relativeDateText(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func color(from hex: String) -> Color {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }

        guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
            return .secondary
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
