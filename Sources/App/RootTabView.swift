import SwiftUI
import UIKit

enum RootTab: Hashable {
    case today
    case trends
    case labs
    case settings
}

struct RootTabView: View {
    private let dependencies: AppDependencies
    @AppStorage("somatiq.onboarding.complete") private var onboardingComplete = false
    @State private var selectedTab: RootTab = .today

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(dashboardService: dependencies.dashboardService)
                .tabItem {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("Today")
                }
                .tag(RootTab.today)

            TrendsView(trendsService: dependencies.trendsService)
                .tabItem {
                    Image(systemName: "waveform.path.ecg")
                    Text("Trends")
                }
                .tag(RootTab.trends)

            LabsPlaceholderView()
                .tabItem {
                    Image(systemName: "doc.text.fill")
                    Text("Labs")
                }
                .tag(RootTab.labs)

            SettingsView(settingsService: dependencies.settingsService)
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(RootTab.settings)
        }
        .tint(SomatiqColor.accent)
        .onChange(of: selectedTab) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView(healthDataProvider: dependencies.healthDataProvider) {
                onboardingComplete = true
            }
        }
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
