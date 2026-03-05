import SwiftUI

struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.08),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: phase * (geometry.size.width * 1.6))
                    .clipped()
                }
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

struct ShimmerPlaceholder: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#1B1D2A").opacity(0.6), Color(hex: "#10111A").opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: height)
            .shimmer()
    }
}
