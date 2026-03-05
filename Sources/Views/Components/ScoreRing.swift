import SwiftUI
import UIKit

enum ScoreKind: Equatable {
    case stress
    case sleep
    case bodyBattery

    var title: String {
        switch self {
        case .stress:
            "Stress"
        case .sleep:
            "Sleep"
        case .bodyBattery:
            "Battery"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .stress:
            SomatiqColor.stressGradient
        case .sleep:
            SomatiqColor.sleepGradient
        case .bodyBattery:
            SomatiqColor.energyGradient
        }
    }

    var angularGradient: AngularGradient {
        switch self {
        case .stress:
            SomatiqColor.stressAngular
        case .sleep:
            SomatiqColor.sleepAngular
        case .bodyBattery:
            SomatiqColor.energyAngular
        }
    }

    var glowColor: Color {
        switch self {
        case .stress:
            SomatiqColor.stress
        case .sleep:
            SomatiqColor.sleep
        case .bodyBattery:
            SomatiqColor.bodyBattery
        }
    }
}

struct ScoreRing: View {
    let kind: ScoreKind
    let score: Int
    let status: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedScore: Double = 0
    @State private var lastHapticBucket: Int = -1
    @State private var ringAppeared = false
    @State private var pulseGlow = false

    private let ringSize: CGFloat = 100
    private let strokeWidth: CGFloat = 7

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: strokeWidth)

                Circle()
                    .trim(from: 0, to: ringAppeared ? progress : 0)
                    .stroke(
                        kind.angularGradient,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: kind.glowColor.opacity(0.5), radius: 8)
                    .animation(
                        reduceMotion ? .linear(duration: 0.2) : SomatiqAnimation.ringFill,
                        value: ringAppeared
                    )
                    .animation(
                        reduceMotion ? .linear(duration: 0.2) : SomatiqAnimation.ringFill,
                        value: progress
                    )

                Text("\(Int(animatedScore.rounded()))")
                    .font(.scoreNumber())
                    .foregroundStyle(kind.glowColor)
                    .contentTransition(.numericText())
            }
            .frame(width: ringSize, height: ringSize)
            .shadow(
                color: score > 80 ? kind.glowColor.opacity(pulseGlow ? 0.25 : 0.1) : .clear,
                radius: 12
            )
            .padding(.top, 2)

            Text(kind.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(SomatiqColor.textTertiary)

            Text(status.capitalized)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .somatiqCardStyle(tint: kind.glowColor, cornerRadius: SomatiqRadius.cardLarge)
        .onAppear {
            ringAppeared = true
            animateScore()
            if score > 80 && !reduceMotion {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    pulseGlow = true
                }
            }
        }
        .onChange(of: score) { _, _ in
            animateScore()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title) score")
        .accessibilityValue("\(score), \(status)")
    }

    private var progress: CGFloat {
        let normalized = CGFloat(Statistics.clamped(Double(score) / 100, min: 0, max: 1))
        if kind == .stress {
            return 1 - normalized
        }
        return normalized
    }

    private var statusColor: Color {
        switch status.lowercased() {
        case "low", "good", "great", "charged":
            SomatiqColor.success
        case "moderate", "fair":
            SomatiqColor.warning
        case "high", "poor", "depleted":
            SomatiqColor.danger
        default:
            SomatiqColor.textTertiary
        }
    }

    private func animateScore() {
        if reduceMotion {
            animatedScore = Double(score)
            triggerHapticIfNeeded()
            return
        }
        withAnimation(SomatiqAnimation.scoreReveal) {
            animatedScore = Double(score)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            triggerHapticIfNeeded()
        }
    }

    private func triggerHapticIfNeeded() {
        let bucket = max(0, min(4, score / 25))
        guard bucket != lastHapticBucket else { return }
        lastHapticBucket = bucket

        if bucket >= 4 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
