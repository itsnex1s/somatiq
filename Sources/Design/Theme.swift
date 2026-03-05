import SwiftUI

enum SomatiqColor {
    static let bg = Color(hex: "#0D0D14")
    static let page = Color(hex: "#0A0A0F")
    static let card = Color(hex: "#1A1A24")
    static let border = Color.white.opacity(0.06)
    static let softBorder = Color.white.opacity(0.08)

    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "#C4C4D4")
    static let textTertiary = Color(hex: "#8A8A9A")
    static let textMuted = Color(hex: "#666677")

    static let stress = Color(hex: "#FBBF24")
    static let sleep = Color(hex: "#8B5CF6")
    static let energy = Color(hex: "#34D399")
    static let success = Color(hex: "#34D399")
    static let warning = Color(hex: "#FBBF24")
    static let danger = Color(hex: "#F87171")
    static let accent = Color(hex: "#6366F1")

    static let stressGradient = LinearGradient(
        colors: [Color(hex: "#F59E0B"), Color(hex: "#FBBF24")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sleepGradient = LinearGradient(
        colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let energyGradient = LinearGradient(
        colors: [Color(hex: "#10B981"), Color(hex: "#34D399")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let insightGradient = LinearGradient(
        colors: [
            Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255, opacity: 0.12),
            Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255, opacity: 0.08),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum SomatiqRadius {
    static let cardLarge: CGFloat = 20
    static let cardMedium: CGFloat = 16
}

enum SomatiqSpacing {
    static let pageHorizontal: CGFloat = 20
    static let sectionGap: CGFloat = 20
    static let cardPadding: CGFloat = 16
}
