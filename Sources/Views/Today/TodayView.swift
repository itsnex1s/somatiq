import Observation
import SwiftUI
import UIKit

struct TodayView: View {
    @State private var viewModel: TodayViewModel
    private let trendsService: TrendsDataService

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sectionsAppeared = false
    @State private var selectedMetric: MetricKind?
    @State private var quickPeekMetric: MetricKind?
    @State private var isJournalPresented = false
    @State private var suppressTapAfterLongPressMetric: MetricKind?
    @State private var scrollOffset: CGFloat = 0

    init(dashboardService: DashboardDataService, trendsService: TrendsDataService) {
        self.trendsService = trendsService
        _viewModel = State(initialValue: TodayViewModel(dashboardService: dashboardService, trendsService: trendsService))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                SomatiqColor.bg.ignoresSafeArea()

                ScrollView {
                    SomatiqScrollOffsetReader(coordinateSpace: "todayScroll")
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        if viewModel.isLoading && viewModel.lastUpdated == nil {
                            shimmerSkeleton
                                .transition(contentTransition)
                        } else if let noDataMessage = viewModel.noDataMessage {
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
                            .transition(contentTransition)
                        } else if let errorMessage = viewModel.errorMessage {
                            EmptyStateView(
                                title: "Couldn't load today",
                                message: errorMessage,
                                buttonTitle: "Retry"
                            ) {
                                Task {
                                    await viewModel.refresh(forceRecalculate: true)
                                }
                            }
                            .transition(contentTransition)
                        } else {
                            metricCards
                                .modifier(StaggeredEntrance(index: 0, appeared: sectionsAppeared, reduceMotion: reduceMotion))

                            reportsTimelineSection
                                .modifier(StaggeredEntrance(index: 1, appeared: sectionsAppeared, reduceMotion: reduceMotion))

                            PrivacyBadge()
                                .modifier(StaggeredEntrance(index: 2, appeared: sectionsAppeared, reduceMotion: reduceMotion))
                        }

                        Spacer(minLength: 90)
                    }
                    .padding(.horizontal, SomatiqSpacing.pageHorizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .id(todayContentState)
                    .animation(SomatiqAnimation.stateSwap, value: todayContentState)
                }
                .coordinateSpace(name: "todayScroll")
                .scrollIndicators(.hidden)
                .refreshable {
                    await viewModel.refresh(forceRecalculate: true)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }

                SomatiqProgressiveHeaderBar(
                    title: "Today",
                    subtitle: todayDateText,
                    progress: headerProgress,
                    topInset: proxy.safeAreaInsets.top
                )

                if viewModel.isCalibrating {
                    Text("Calibrating")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SomatiqColor.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .padding(.top, proxy.safeAreaInsets.top + 8)
                        .padding(.trailing, 20)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .onPreferenceChange(SomatiqScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
        }
        .task {
            await viewModel.loadIfNeeded()
            withAnimation(SomatiqAnimation.sectionReveal) {
                sectionsAppeared = true
            }
        }
        .onAppear {
            viewModel.startLiveUpdates()
        }
        .onDisappear {
            viewModel.stopLiveUpdates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthReconnectDidComplete)) { _ in
            Task {
                await viewModel.refresh(forceRecalculate: true)
            }
        }
        .sheet(item: $selectedMetric) { metric in
            MetricDetailView(
                kind: metric,
                currentValue: metric.extractValue(from: viewModel),
                currentStatus: metric.extractStatus(from: viewModel),
                trendsService: trendsService
            )
            .presentationBackground(SomatiqColor.bg)
        }
        .sheet(item: $quickPeekMetric) { metric in
            MetricQuickPeekView(
                kind: metric,
                currentValue: metric.extractValue(from: viewModel),
                currentStatus: metric.extractStatus(from: viewModel),
                weekScores: viewModel.weekScores
            ) { selected in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    selectedMetric = selected
                }
            }
            .presentationBackground(SomatiqColor.bg)
        }
        .sheet(isPresented: $isJournalPresented) {
            JournalView(trendsService: trendsService)
                .presentationBackground(SomatiqColor.bg)
        }
    }

    // MARK: - 4 Hero metric cards (Welltory-style 2x2)

    private var metricCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(MetricKind.allCases.enumerated()), id: \.element.id) { index, metric in
                Button {
                    if suppressTapAfterLongPressMetric == metric {
                        suppressTapAfterLongPressMetric = nil
                        return
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedMetric = metric
                } label: {
                    MetricCard(
                        kind: metric,
                        value: metric.extractValue(from: viewModel),
                        status: metric.extractStatus(from: viewModel)
                    )
                }
                .buttonStyle(.somatiqPressable)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.38)
                        .onEnded { _ in
                            suppressTapAfterLongPressMetric = metric
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            quickPeekMetric = metric
                        }
                )
                .modifier(StaggeredEntrance(index: index, appeared: sectionsAppeared, reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shimmer loading skeleton

    private var shimmerSkeleton: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ShimmerPlaceholder(height: 158)
                ShimmerPlaceholder(height: 158)
                ShimmerPlaceholder(height: 158)
                ShimmerPlaceholder(height: 158)
            }
            ShimmerPlaceholder(height: 80)
            ShimmerPlaceholder(height: 200)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                Text(todayDateText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SomatiqColor.textTertiary)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isJournalPresented = true
            } label: {
                Label("Journal", systemImage: "book.pages")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule(style: .continuous)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.7
                            )
                    }
            }
            .buttonStyle(.somatiqPressable)
        }
        .padding(.bottom, 4)
    }

    private var reportsTimelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Reports Timeline")

            if viewModel.reports.isEmpty {
                GlassCard {
                    Text("Reports appear automatically when meaningful body changes are detected. Up to 3 reports per day.")
                        .font(.system(size: 14))
                        .foregroundStyle(SomatiqColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedReportsByDay, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(dayLabel(for: group.day))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SomatiqColor.textTertiary)

                            VStack(spacing: 10) {
                                ForEach(group.reports, id: \.id) { report in
                                    WellnessReportCard(report: report)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var groupedReportsByDay: [(day: Date, reports: [WellnessReport])] {
        let grouped = Dictionary(grouping: viewModel.reports) { $0.day.startOfDay }
        return grouped.keys
            .sorted(by: >)
            .map { day in
                let reports = (grouped[day] ?? [])
                    .sorted(by: { $0.createdAt > $1.createdAt })
                return (day, reports)
            }
    }

    private func dayLabel(for day: Date) -> String {
        if Calendar.current.isDateInToday(day) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(day) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(SomatiqColor.textMuted)
    }

    private var todayDateText: String {
        Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var todayContentState: TodayContentState {
        if viewModel.isLoading && viewModel.lastUpdated == nil {
            return .loading
        }
        if viewModel.noDataMessage != nil {
            return .empty
        }
        if viewModel.errorMessage != nil {
            return .error
        }
        return .content
    }

    private var headerProgress: CGFloat {
        CGFloat(Statistics.clamped(Double((-scrollOffset - 8) / 68), min: 0, max: 1))
    }

    private var contentTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.99))
    }
}

// MARK: - Staggered entrance modifier

private enum TodayContentState: String, Hashable {
    case loading
    case empty
    case error
    case content
}

private struct MetricQuickPeekView: View {
    let kind: MetricKind
    let currentValue: Int
    let currentStatus: String
    let weekScores: [DailyScore]
    let onOpenDetails: (MetricKind) -> Void

    @Environment(\.dismiss) private var dismiss

    private var trendValues: [Double] {
        Array(
            kind.extractHistoryValues(from: weekScores)
                .filter { $0 > 0 }
                .suffix(7)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(kind.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(SomatiqColor.textPrimary)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(currentValue > 0 ? "\(currentValue)" : "--")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(kind.color)

                            if !kind.unit.isEmpty, currentValue > 0 {
                                Text(kind.unit)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundStyle(kind.color.opacity(0.75))
                            }
                        }

                        Text(currentStatus)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SomatiqColor.textSecondary)
                    }

                    if trendValues.isEmpty {
                        Text("Need more real data to show a weekly quick trend.")
                            .font(.system(size: 13))
                            .foregroundStyle(SomatiqColor.textTertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("7-Day Quick Trend")
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(SomatiqColor.textMuted)

                            HStack(alignment: .bottom, spacing: 8) {
                                let maxValue = max(trendValues.max() ?? 1, 1)
                                ForEach(Array(trendValues.enumerated()), id: \.offset) { _, value in
                                    let normalized = max(0.16, value / maxValue)
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [kind.color.opacity(0.45), kind.color],
                                                startPoint: .bottom,
                                                endPoint: .top
                                            )
                                        )
                                        .frame(width: 16, height: 72 * normalized)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 80, alignment: .bottom)
                        }
                    }

                    Button("Open Full Report") {
                        dismiss()
                        onOpenDetails(kind)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [kind.color, kind.color.opacity(0.76)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .buttonStyle(.somatiqPressable)
                    .padding(.top, 4)
                }
                .padding(.horizontal, SomatiqSpacing.pageHorizontal)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            .background(SomatiqColor.bg.ignoresSafeArea())
            .navigationTitle("Quick Peek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct WellnessReportCard: View {
    let report: WellnessReport

    private var trigger: WellnessReportTrigger {
        WellnessReportTrigger(rawValue: report.triggerType) ?? .notableShift
    }

    private var tint: Color {
        switch trigger {
        case .firstCheckin:
            return SomatiqColor.accent
        case .stressSpike:
            return SomatiqColor.stress
        case .batteryLow:
            return SomatiqColor.bodyBattery
        case .sleepDebt:
            return SomatiqColor.sleep
        case .hrvDrop:
            return SomatiqColor.heart
        case .notableShift:
            return SomatiqColor.accent
        }
    }

    private var triggerTitle: String {
        switch trigger {
        case .firstCheckin:
            return "Check-in"
        case .stressSpike:
            return "Stress"
        case .batteryLow:
            return "Battery"
        case .sleepDebt:
            return "Sleep"
        case .hrvDrop:
            return "Heart"
        case .notableShift:
            return "Update"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.headline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SomatiqColor.textPrimary)

                    Text(report.createdAt.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SomatiqColor.textTertiary)
                }

                Spacer(minLength: 8)

                Text(triggerTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: Capsule(style: .continuous))
            }

            Text(report.body)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SomatiqColor.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metricChip(title: "Battery", value: "\(report.bodyBatteryScore)", icon: "battery.100", tint: SomatiqColor.bodyBattery)
                metricChip(title: "Stress", value: "\(report.stressScore)", icon: "brain.head.profile", tint: SomatiqColor.stress)
                metricChip(title: "Sleep", value: "\(report.sleepScore)", icon: "moon.stars.fill", tint: SomatiqColor.sleep)
                metricChip(title: "Heart", value: report.heartScore > 0 ? "\(report.heartScore) ms" : "--", icon: "heart.fill", tint: SomatiqColor.heart)
            }
        }
        .padding(14)
        .somatiqCardStyle(tint: tint, cornerRadius: 18)
    }

    private func metricChip(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SomatiqColor.textTertiary)

                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

private struct StaggeredEntrance: ViewModifier {
    let index: Int
    let appeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(
                reduceMotion ? .linear(duration: 0.1) : SomatiqAnimation.staggered(index: index),
                value: appeared
            )
    }
}
