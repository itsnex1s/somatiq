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

    // MARK: - Metric colors (primary)
    static let stress = Color(hex: "#FBBF24")
    static let sleep = Color(hex: "#8B5CF6")
    static let energy = Color(hex: "#34D399")
    static let heart = Color(hex: "#FF4D6A")
    static let bodyBattery = energy

    // MARK: - Metric colors (secondary / lighter variant)
    static let stressSecondary = Color(hex: "#FCD34D")
    static let sleepSecondary = Color(hex: "#A78BFA")
    static let energySecondary = Color(hex: "#6EE7B7")
    static let heartSecondary = Color(hex: "#FF8FA3")
    static let bodyBatterySecondary = energySecondary

    // MARK: - Semantic colors
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

    static let heartGradient = LinearGradient(
        colors: [Color(hex: "#E8364F"), heart],
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

    // MARK: - Angular gradients for score rings

    static let stressAngular = AngularGradient(
        colors: [Color(hex: "#F59E0B"), Color(hex: "#FBBF24"), Color(hex: "#FCD34D"), Color(hex: "#F59E0B")],
        center: .center
    )

    static let sleepAngular = AngularGradient(
        colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6"), Color(hex: "#A78BFA"), Color(hex: "#6366F1")],
        center: .center
    )

    static let energyAngular = AngularGradient(
        colors: [Color(hex: "#10B981"), Color(hex: "#34D399"), Color(hex: "#6EE7B7"), Color(hex: "#10B981")],
        center: .center
    )

    static let heartAngular = AngularGradient(
        colors: [Color(hex: "#E8364F"), heart, heartSecondary, Color(hex: "#E8364F")],
        center: .center
    )
}

enum SomatiqRadius {
    static let cardLarge: CGFloat = 20
    static let cardMedium: CGFloat = 16
    static let continuousStyle = RoundedCornerStyle.continuous
}

enum SomatiqSpacing {
    static let pageHorizontal: CGFloat = 20
    static let sectionGap: CGFloat = 20
    static let cardPadding: CGFloat = 20

    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Animation presets

enum SomatiqAnimation {
    static let scoreReveal = Animation.spring(duration: 1.2, bounce: 0.15)
    static let cardEntrance = Animation.spring(duration: 0.6, bounce: 0.15)
    static let ringFill = Animation.spring(duration: 1.5, bounce: 0.2)
    static let tabSwitch = Animation.spring(duration: 0.35, bounce: 0.15)
    static let screenSwitch = Animation.easeInOut(duration: 0.28)
    static let sectionReveal = Animation.spring(duration: 0.45, bounce: 0.1)
    static let chartReveal = Animation.easeOut(duration: 0.35)
    static let press = Animation.spring(duration: 0.22, bounce: 0.25)
    static let stateSwap = Animation.easeInOut(duration: 0.24)

    static func staggered(index: Int) -> Animation {
        cardEntrance.delay(Double(index) * 0.08)
    }
}

// MARK: - Scroll helpers

struct SomatiqScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SomatiqScrollOffsetReader: View {
    let coordinateSpace: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: SomatiqScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpace)).minY
                )
        }
        .frame(height: 0)
    }
}

// MARK: - Progressive top header

struct SomatiqProgressiveHeaderBar: View {
    let title: String
    let subtitle: String?
    let progress: CGFloat
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: topInset)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SomatiqColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SomatiqSpacing.pageHorizontal)
            .padding(.bottom, 8)
        }
        .frame(height: topInset + 56, alignment: .top)
        .background {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                SomatiqColor.bg.opacity(0.96),
                                SomatiqColor.bg.opacity(0.86),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.6)
            }
        }
        .opacity(progress)
        .animation(SomatiqAnimation.stateSwap, value: progress)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

// MARK: - Card background (multi-layer gradient matching MetricCard)

struct SomatiqCardBackground: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let tint {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(0.07))
                }

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )

                if let tint {
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.clear, tint.opacity(0.32)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 58)
                            .blur(radius: 2)
                    }
                }
            }
        }
    }
}

// MARK: - Card border (gradient stroke matching MetricCard)

struct SomatiqCardBorder: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if let tint {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                tint.opacity(0.35),
                                Color.white.opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.95
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.06),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
        }
    }
}

// MARK: - Shadow presets

enum SomatiqShadowIntensity {
    case subtle
    case standard
    case prominent
}

struct SomatiqShadow: ViewModifier {
    let tintColor: Color
    let intensity: SomatiqShadowIntensity

    init(tintColor: Color, intensity: SomatiqShadowIntensity = .subtle) {
        self.tintColor = tintColor
        self.intensity = intensity
    }

    func body(content: Content) -> some View {
        switch intensity {
        case .subtle:
            content
                .shadow(color: tintColor.opacity(0.12), radius: 4, x: 0, y: 2)
                .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 10)
        case .standard:
            content
                .shadow(color: tintColor.opacity(0.22), radius: 10, x: 0, y: 6)
                .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
        case .prominent:
            content
                .shadow(color: tintColor.opacity(0.34), radius: 16, x: 0, y: 8)
                .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 7)
        }
    }
}

extension View {
    func somatiqShadow(tint: Color = .black, intensity: SomatiqShadowIntensity = .subtle) -> some View {
        modifier(SomatiqShadow(tintColor: tint, intensity: intensity))
    }

    func somatiqCardStyle(
        tint: Color? = nil,
        cornerRadius: CGFloat = SomatiqRadius.cardMedium,
        shadowIntensity: SomatiqShadowIntensity = .standard
    ) -> some View {
        self
            .modifier(SomatiqCardBackground(tint: tint, cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .modifier(SomatiqCardBorder(tint: tint, cornerRadius: cornerRadius))
            .somatiqShadow(tint: tint ?? .black, intensity: shadowIntensity)
    }
}

struct SomatiqPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let scale: CGFloat
    private let pressedOpacity: Double

    init(scale: CGFloat = 0.97, pressedOpacity: Double = 0.94) {
        self.scale = scale
        self.pressedOpacity = pressedOpacity
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(
                reduceMotion ? .linear(duration: 0.08) : SomatiqAnimation.press,
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == SomatiqPressableButtonStyle {
    static var somatiqPressable: SomatiqPressableButtonStyle {
        SomatiqPressableButtonStyle()
    }
}

// MARK: - Rounded font helpers

extension Font {
    static func scoreNumber(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func vitalNumber(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
