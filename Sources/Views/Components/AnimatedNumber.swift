import SwiftUI

struct AnimatedNumber: View {
    let value: Double
    let format: String
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedValue: Double = 0

    init(value: Double, format: String = "%.0f", color: Color = SomatiqColor.textPrimary) {
        self.value = value
        self.format = format
        self.color = color
    }

    var body: some View {
        Text(String(format: format, animatedValue))
            .foregroundStyle(color)
            .onAppear {
                runAnimation()
            }
            .onChange(of: value) { _, _ in
                runAnimation()
            }
    }

    private func runAnimation() {
        guard !reduceMotion else {
            animatedValue = value
            return
        }
        withAnimation(.easeOut(duration: 0.8)) {
            animatedValue = value
        }
    }
}
