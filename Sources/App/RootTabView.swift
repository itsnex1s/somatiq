import SwiftUI
import UIKit

enum RootTab: Hashable {
    case today
    case trends
    case labs
    case settings

    var title: String {
        switch self {
        case .today: "Today"
        case .trends: "Trends"
        case .labs: "Labs"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .today: "square.grid.2x2.fill"
        case .trends: "waveform.path.ecg"
        case .labs: "doc.text.fill"
        case .settings: "gearshape.fill"
        }
    }

    static let allTabs: [RootTab] = [.today, .trends, .labs, .settings]
}

struct RootTabView: View {
    private let dependencies: AppDependencies
    @AppStorage("somatiq.onboarding.complete") private var onboardingComplete = false
    @State private var selectedTab: RootTab = .today

    @Namespace private var tabNamespace

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .today:
                    TodayView(dashboardService: dependencies.dashboardService, trendsService: dependencies.trendsService)
                case .trends:
                    TrendsView(trendsService: dependencies.trendsService)
                case .labs:
                    LabsPlaceholderView()
                case .settings:
                    SettingsView(settingsService: dependencies.settingsService)
                }
            }
            .id(selectedTab)
            .transition(screenTransition)
            .animation(SomatiqAnimation.screenSwitch, value: selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            customTabBar
        }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView(healthDataProvider: dependencies.healthDataProvider) {
                onboardingComplete = true
            }
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 8) {
            ForEach(RootTab.allTabs, id: \.self) { tab in
                Button {
                    if selectedTab != tab {
                        withAnimation(SomatiqAnimation.tabSwitch) {
                            selectedTab = tab
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .symbolEffect(.bounce, value: selectedTab == tab)

                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : SomatiqColor.textTertiary)
                    .frame(width: 74)
                    .padding(.vertical, 9)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(SomatiqColor.accent.opacity(0.22))
                                .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                        }
                    }
                }
                .buttonStyle(.somatiqPressable)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            SomatiqColor.accent.opacity(0.20),
                            Color.white.opacity(0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .somatiqShadow(tint: SomatiqColor.accent, intensity: .standard)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var screenTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.992)),
            removal: .opacity
        )
    }

    private var onboardingBinding: Binding<Bool> {
        Binding {
            !onboardingComplete
        } set: { newValue in
            if !newValue {
                onboardingComplete = true
            }
        }
    }
}
