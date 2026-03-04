import SwiftUI

struct PillView: View {
    let text: String
    let color: Color
    var isSelected: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        if isSelected {
            return color.opacity(0.28)
        }
        return color.opacity(0.16)
    }

    private var foregroundColor: Color {
        if isSelected {
            return color.opacity(0.95)
        }
        return color.opacity(0.85)
    }
}

extension PullRequestStatus {
    var pillColor: Color {
        switch self {
        case .draft:
            return .gray
        case .approved:
            return .green
        case .changesRequested:
            return .orange
        case .reviewRequired:
            return .blue
        }
    }
}
