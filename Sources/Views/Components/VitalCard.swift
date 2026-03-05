import SwiftUI

enum VitalTrend {
    case up(String)
    case down(String)
    case neutral(String)

    var text: String {
        switch self {
        case let .up(value), let .down(value), let .neutral(value):
            value
        }
    }

    var color: Color {
        switch self {
        case .up:
            SomatiqColor.success
        case .down:
            SomatiqColor.danger
        case .neutral:
            SomatiqColor.textTertiary
        }
    }
}

struct VitalCard: View {
    let symbol: String
    let label: String
    let value: String
    let trend: VitalTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SomatiqColor.textPrimary)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SomatiqColor.textTertiary)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(SomatiqColor.textPrimary)

            Text(trend.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(trend.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SomatiqColor.card.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium)
                .stroke(SomatiqColor.softBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium))
    }
}
