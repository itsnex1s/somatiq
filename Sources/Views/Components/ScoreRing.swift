import SwiftUI
import UIKit

enum ScoreKind: Equatable {
    case stress
    case sleep
    case energy

    var title: String {
        switch self {
        case .stress:
            "Stress"
        case .sleep:
            "Sleep"
        case .energy:
            "Energy"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .stress:
            SomatiqColor.stressGradient
        case .sleep:
            SomatiqColor.sleepGradient
        case .energy:
            SomatiqColor.energyGradient
        }
    }

    var glowColor: Color {
        switch self {
        case .stress:
            SomatiqColor.stress
        case .sleep:
            SomatiqColor.sleep
        case .energy:
            SomatiqColor.energy
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

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        kind.gradient,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: kind.glowColor.opacity(0.35), radius: 6)
                    .animation(
                        reduceMotion ? .linear(duration: 0.2) : .easeOut(duration: 1.5),
                        value: progress
                    )

                Text("\(Int(animatedScore.rounded()))")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(kind.glowColor)
            }
            .frame(width: 80, height: 80)
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
        .background(SomatiqColor.card.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: SomatiqRadius.cardLarge)
                .stroke(SomatiqColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SomatiqRadius.cardLarge))
        .onAppear {
            animateScore()
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
        withAnimation(.easeOut(duration: 0.9)) {
            animatedScore = Double(score)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
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
