import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(SomatiqSpacing.cardPadding)
            .background(SomatiqColor.card.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium)
                    .stroke(SomatiqColor.softBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium))
    }
}
