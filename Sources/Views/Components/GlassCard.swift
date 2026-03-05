import SwiftUI

struct GlassCard<Content: View>: View {
    let tint: Color?
    let content: Content

    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(SomatiqSpacing.cardPadding)
            .somatiqCardStyle(tint: tint)
    }
}
