import SwiftUI

enum MetricKind: CaseIterable, Identifiable {
    case bodyBattery
    case stress
    case sleep
    case heart

    var id: String { title }

    var title: String {
        switch self {
        case .stress: "Stress"
        case .sleep: "Sleep"
        case .bodyBattery: "Battery"
        case .heart: "Heart"
        }
    }

    var icon: String {
        switch self {
        case .bodyBattery: "battery.100percent"
        case .stress: "brain.head.profile"
        case .sleep: "moon.stars.fill"
        case .heart: "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .bodyBattery: SomatiqColor.bodyBattery
        case .stress: SomatiqColor.stress
        case .sleep: SomatiqColor.sleep
        case .heart: SomatiqColor.heart
        }
    }

    var colorSecondary: Color {
        switch self {
        case .bodyBattery: SomatiqColor.bodyBatterySecondary
        case .stress: SomatiqColor.stressSecondary
        case .sleep: SomatiqColor.sleepSecondary
        case .heart: SomatiqColor.heartSecondary
        }
    }

    var unit: String {
        switch self {
        case .bodyBattery, .stress, .sleep: ""
        case .heart: "ms"
        }
    }

    @MainActor func extractValue(from vm: TodayViewModel) -> Int {
        switch self {
        case .bodyBattery:
            return vm.bodyBatteryScore
        case .stress:
            return vm.stressScore
        case .sleep:
            return vm.sleepScore
        case .heart:
            return vm.hrvValue
        }
    }

    @MainActor func extractStatus(from vm: TodayViewModel) -> String {
        switch self {
        case .bodyBattery: return vm.bodyBatteryLevel.rawValue.capitalized
        case .stress: return vm.stressLevel.rawValue.capitalized
        case .sleep: return vm.sleepLevel.rawValue.capitalized
        case .heart: return vm.hrvValue == 0 ? "--" : (vm.hrvValue > 50 ? "Balanced" : "Low")
        }
    }

    func extractHistoryValues(from scores: [DailyScore]) -> [Double] {
        switch self {
        case .bodyBattery:
            return scores.map { Double($0.bodyBatteryScore) }
        case .stress:
            return scores.map { Double($0.stressScore) }
        case .sleep:
            return scores.map { Double($0.sleepScore) }
        case .heart:
            return scores.map(\.avgSDNN)
        }
    }

    var chartDomain: ClosedRange<Double> {
        switch self {
        case .bodyBattery, .stress, .sleep:
            return 0...100
        case .heart:
            return 0...120
        }
    }
}

// MARK: - MetricCard

struct MetricCard: View {
    let kind: MetricKind
    let value: Int
    let status: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            cardBackground

            metricHalo
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 4)
                .padding(.trailing, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(kind.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.trailing, titleTrailingPadding)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(valueText)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(SomatiqColor.textPrimary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if !kind.unit.isEmpty && value > 0 {
                        Text(kind.unit)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(SomatiqColor.textTertiary)
                    }

                    Spacer(minLength: 4)

                    statusBadge
                }

                Text(recommendationText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1.0, contentMode: .fit)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: SomatiqRadius.cardLarge, style: .continuous))
        .shadow(color: kind.color.opacity(glowPulse ? 0.42 : 0.26), radius: glowPulse ? 20 : 14, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 7)
        .onAppear {
            appeared = true
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title)")
        .accessibilityValue("\(valueText) \(kind.unit), \(badgeText). \(recommendationText)")
        .accessibilityAddTraits(.isButton)
    }

    private var cardBackground: some View {
        Color.clear
            .modifier(SomatiqCardBackground(tint: kind.color, cornerRadius: SomatiqRadius.cardLarge))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: SomatiqRadius.cardLarge, style: .continuous)
            .stroke(Color.clear)
            .modifier(SomatiqCardBorder(tint: kind.color, cornerRadius: SomatiqRadius.cardLarge))
    }

    private var metricHalo: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            kind.color.opacity(glowPulse ? 0.9 : 0.75),
                            kind.colorSecondary.opacity(0.58),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 42
                    )
                )
                .frame(width: 90, height: 90)
                .blur(radius: glowPulse ? 3 : 2)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.65), Color.black.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 62, height: 62)

            Circle()
                .stroke(Color.white.opacity(0.26), lineWidth: 1.1)
                .frame(width: 62, height: 62)

            Circle()
                .stroke(kind.color.opacity(0.22), lineWidth: 6)
                .frame(width: 62, height: 62)

            Circle()
                .trim(from: 0.0, to: appeared ? arcProgress : 0)
                .stroke(
                    AngularGradient(
                        colors: [Color.white.opacity(0.92), kind.colorSecondary, kind.color, kind.color],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(-90))
                .shadow(color: kind.color.opacity(0.95), radius: 8, x: 0, y: 2)
                .animation(
                    reduceMotion ? .linear(duration: 0.2) : SomatiqAnimation.ringFill,
                    value: appeared
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 20, height: 20)
                .offset(x: -7, y: -8)

            metricIcon
                .foregroundStyle(Color.white.opacity(0.96))
                .shadow(color: kind.color.opacity(0.75), radius: 5, x: 0, y: 1)
        }
        .frame(width: 96, height: 96)
    }

    private var arcProgress: CGFloat {
        CGFloat(Statistics.clamped(Double(value) / 100, min: 0, max: 1))
    }

    @ViewBuilder
    private var metricIcon: some View {
        if kind == .bodyBattery {
            HStack(spacing: 3) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10, weight: .bold))
                Image(systemName: "battery.100")
                    .font(.system(size: 11, weight: .bold))
            }
        } else {
            Image(systemName: kind.icon)
                .font(.system(size: 17, weight: .bold))
        }
    }

    private var titleTrailingPadding: CGFloat {
        82
    }

    private var valueText: String {
        if kind == .heart && value == 0 {
            return "--"
        }
        return "\(value)"
    }

    private var badgeText: String {
        switch kind {
        case .bodyBattery:
            switch metricState {
            case .strong: return "Charged"
            case .balanced: return "Steady"
            case .caution, .critical: return "Low battery"
            case .unknown: return "No data"
            }
        case .stress:
            switch metricState {
            case .strong: return "Calm"
            case .balanced: return "Watch"
            case .caution, .critical: return "Need break"
            case .unknown: return status
            }
        case .sleep:
            switch metricState {
            case .strong: return "Recovered"
            case .balanced: return "Okay"
            case .caution, .critical: return "Sleep debt"
            case .unknown: return "No data"
            }
        case .heart:
            switch metricState {
            case .strong: return "Resilient"
            case .balanced: return "Balanced"
            case .caution, .critical: return "Low HRV"
            case .unknown: return "No data"
            }
        }
    }

    private var recommendationText: String {
        switch kind {
        case .bodyBattery:
            switch metricState {
            case .strong: return "Good capacity for focused work."
            case .balanced: return "Pace is fine for this block."
            case .caution, .critical: return "Reduce load and hydrate now."
            case .unknown: return "Need more real data."
            }
        case .stress:
            switch metricState {
            case .strong: return "Nervous system is stable now."
            case .balanced: return "Keep workload moderate."
            case .caution, .critical: return "Take a 5-minute reset break."
            case .unknown: return "Need more real data."
            }
        case .sleep:
            switch metricState {
            case .strong: return "Recovery trend looks strong."
            case .balanced: return "Recovery is acceptable today."
            case .caution, .critical: return "Aim for +30–60 min sleep tonight."
            case .unknown: return "Need more real data."
            }
        case .heart:
            switch metricState {
            case .strong: return "Autonomic adaptation looks good."
            case .balanced: return "Heart balance is okay."
            case .caution, .critical: return "Keep intensity low today."
            case .unknown: return "Need more HRV measurements."
            }
        }
    }

    private var statusBadge: some View {
        Text(badgeText)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(metricState.color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(metricState.color.opacity(0.16), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(metricState.color.opacity(0.45), lineWidth: 0.8)
            }
    }

    private var metricState: MetricState {
        switch kind {
        case .bodyBattery:
            if value == 0 { return .unknown }
            if value >= 70 { return .strong }
            if value >= 45 { return .balanced }
            if value >= 30 { return .caution }
            return .critical
        case .stress:
            if value <= 35 { return .strong }
            if value <= 60 { return .balanced }
            if value <= 75 { return .caution }
            return .critical
        case .sleep:
            if value == 0 { return .unknown }
            if value >= 75 { return .strong }
            if value >= 55 { return .balanced }
            if value >= 40 { return .caution }
            return .critical
        case .heart:
            if value == 0 { return .unknown }
            if value >= 65 { return .strong }
            if value >= 45 { return .balanced }
            if value >= 30 { return .caution }
            return .critical
        }
    }
}

private enum MetricState {
    case strong
    case balanced
    case caution
    case critical
    case unknown

    var color: Color {
        switch self {
        case .strong:
            return SomatiqColor.success
        case .balanced:
            return SomatiqColor.bodyBattery
        case .caution:
            return SomatiqColor.warning
        case .critical:
            return SomatiqColor.danger
        case .unknown:
            return SomatiqColor.textTertiary
        }
    }
}
