import SwiftUI
import UIKit

struct TodayView: View {
    @State private var viewModel: TodayViewModel

    init(dashboardService: DashboardDataService) {
        _viewModel = State(initialValue: TodayViewModel(dashboardService: dashboardService))
    }

    var body: some View {
        ZStack {
            SomatiqColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if let noDataMessage = viewModel.noDataMessage {
                        EmptyStateView(
                            title: "No data yet",
                            message: noDataMessage,
                            buttonTitle: "Connect Apple Health"
                        ) {
                            Task {
                                await viewModel.requestHealthAuthorization()
                                await viewModel.refresh(forceRecalculate: true)
                            }
                        }
                    } else if let errorMessage = viewModel.errorMessage {
                        EmptyStateView(
                            title: "Couldn’t load today",
                            message: errorMessage,
                            buttonTitle: "Retry"
                        ) {
                            Task {
                                await viewModel.refresh(forceRecalculate: true)
                            }
                        }
                    } else {
                        scoreRow
                        InsightCard(text: viewModel.insightText)
                        vitalsSection
                        trendsSection
                        PrivacyBadge()
                    }

                    Spacer(minLength: 90)
                }
                .padding(.horizontal, SomatiqSpacing.pageHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await viewModel.refresh(forceRecalculate: true)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.isCalibrating {
                Text("Calibrating")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SomatiqColor.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SomatiqColor.card.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .padding(.trailing, 20)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SomatiqColor.textTertiary)

            Text("Somatiq")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 13))
                .foregroundStyle(SomatiqColor.textMuted)

            if let lastUpdated = viewModel.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.dateTime.hour().minute()))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SomatiqColor.textTertiary)
            }
        }
        .padding(.bottom, 2)
    }

    private var scoreRow: some View {
        HStack(spacing: 12) {
            ScoreRing(kind: .stress, score: viewModel.stressScore, status: viewModel.stressLevel.rawValue)
            ScoreRing(kind: .sleep, score: viewModel.sleepScore, status: viewModel.sleepLevel.rawValue)
            ScoreRing(kind: .energy, score: viewModel.energyScore, status: viewModel.energyLevel.rawValue)
        }
    }

    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Vitals")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                VitalCard(
                    symbol: "heart.fill",
                    label: "Resting HR",
                    value: "\(viewModel.restingHeartRate) bpm",
                    trend: viewModel.restingHRTrend
                )
                VitalCard(
                    symbol: "waveform.path.ecg",
                    label: "HRV (SDNN)",
                    value: "\(viewModel.hrvValue) ms",
                    trend: viewModel.hrvTrend
                )
                VitalCard(
                    symbol: "moon.fill",
                    label: "Sleep Duration",
                    value: viewModel.sleepDurationText,
                    trend: viewModel.sleepTrend
                )
                VitalCard(
                    symbol: "flame.fill",
                    label: "Active Energy",
                    value: "\(viewModel.activeCalories) kcal",
                    trend: viewModel.energyTrend
                )
            }
        }
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("7-Day Trends")
            if viewModel.weekScores.isEmpty {
                GlassCard {
                    Text("Not enough data yet to render weekly trends.")
                        .font(.system(size: 14))
                        .foregroundStyle(SomatiqColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                WeeklyTrendCard(scores: viewModel.weekScores)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(SomatiqColor.textMuted)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5 ..< 12:
            return "Good morning"
        case 12 ..< 18:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

}
