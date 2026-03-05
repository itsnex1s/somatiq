import SwiftUI

struct AnalysesView: View {
    var body: some View {
        ZStack {
            SomatiqColor.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Analyses")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Labs are kept here")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SomatiqColor.textPrimary)

                        Text("Upload and interpretation flow can stay separate from AI chat. This screen is ready for the next lab features.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SomatiqColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(.horizontal, SomatiqSpacing.pageHorizontal)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle("Analyses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
