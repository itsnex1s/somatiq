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

    var arrowSymbol: String? {
        switch self {
        case .up:
            "chevron.up"
        case .down:
            "chevron.down"
        case .neutral:
            nil
        }
    }
}

struct VitalCard: View {
    let symbol: String
    let label: String
    let value: String
    let trend: VitalTrend

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconTint)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SomatiqColor.textTertiary)

            Text(value)
                .font(.vitalNumber())
                .foregroundStyle(SomatiqColor.textPrimary)
                .contentTransition(.numericText())

            HStack(spacing: 3) {
                if let arrow = trend.arrowSymbol {
                    Image(systemName: arrow)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(trend.color)
                }
                Text(trend.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(trend.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .somatiqCardStyle(tint: iconTint)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(duration: 0.2), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private var iconTint: Color {
        switch symbol {
        case "heart.fill":
            SomatiqColor.heart
        case "waveform.path.ecg":
            SomatiqColor.accent
        case "moon.fill":
            SomatiqColor.sleepSecondary
        case "flame.fill":
            SomatiqColor.energy
        default:
            SomatiqColor.textPrimary
        }
    }
}
