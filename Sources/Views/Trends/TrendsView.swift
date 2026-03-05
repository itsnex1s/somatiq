import Charts
import SwiftUI
import UIKit

struct TrendsView: View {
    @State private var viewModel: TrendsViewModel
    @State private var selectedScoreDate: Date?
    @State private var selectedSleepDate: Date?
    @State private var selectedHRVDate: Date?
    @State private var chartContentID = UUID()
    @State private var sectionsAppeared = false
    @State private var scrollOffset: CGFloat = 0
    @State private var lastScoreHapticDate: Date?
    @State private var lastSleepHapticDate: Date?
    @State private var lastHRVHapticDate: Date?

    @Namespace private var pickerNamespace

    init(trendsService: TrendsDataService) {
        _viewModel = State(initialValue: TrendsViewModel(trendsService: trendsService))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                SomatiqColor.bg.ignoresSafeArea()

                ScrollView {
                    SomatiqScrollOffsetReader(coordinateSpace: "trendsScroll")
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Trends")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(SomatiqColor.textPrimary)
                            .modifier(TrendSectionEntrance(index: 0, appeared: sectionsAppeared))

                        periodPicker
                            .modifier(TrendSectionEntrance(index: 1, appeared: sectionsAppeared))
                        summaryCard
                            .modifier(TrendSectionEntrance(index: 2, appeared: sectionsAppeared))

                        if viewModel.isLoading && viewModel.history.isEmpty {
                            trendLoadingSkeleton
                                .transition(chartTransition)
                        } else if let errorMessage = viewModel.errorMessage {
                            errorCard(message: errorMessage)
                                .transition(chartTransition)
                        } else if viewModel.hasInsufficientData {
                            GlassCard {
                                Text("Collect at least \(minimumTrendPoints) days of real data to unlock trend charts.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(SomatiqColor.textSecondary)
                            }
                            .transition(chartTransition)
                        } else {
                            VStack(spacing: 20) {
                                scoreTrendChart
                                sleepBreakdownChart
                                hrvChart
                            }
                            .id(chartContentID)
                            .transition(chartTransition)
                            .modifier(TrendSectionEntrance(index: 3, appeared: sectionsAppeared))
                        }
                    }
                    .padding(.horizontal, SomatiqSpacing.pageHorizontal)
                    .padding(.vertical, 16)
                    .animation(SomatiqAnimation.chartReveal, value: viewModel.history.count)
                }
                .coordinateSpace(name: "trendsScroll")
                .scrollIndicators(.hidden)

                SomatiqProgressiveHeaderBar(
                    title: "Trends",
                    subtitle: nil,
                    progress: headerProgress,
                    topInset: proxy.safeAreaInsets.top
                )
            }
            .onPreferenceChange(SomatiqScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
        }
        .task {
            viewModel.load()
            withAnimation(SomatiqAnimation.sectionReveal) {
                sectionsAppeared = true
            }
        }
        .onChange(of: viewModel.selectedPeriod) { _, _ in
            selectedScoreDate = nil
            selectedSleepDate = nil
            selectedHRVDate = nil
            withAnimation(SomatiqAnimation.chartReveal) {
                chartContentID = UUID()
            }
        }
    }

    // MARK: - Custom period picker

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(TrendPeriod.allCases) { period in
                Button {
                    withAnimation(SomatiqAnimation.tabSwitch) {
                        viewModel.updatePeriod(period)
                    }
                } label: {
                    Text(period.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewModel.selectedPeriod == period ? .white : SomatiqColor.textTertiary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if viewModel.selectedPeriod == period {
                                Capsule()
                                    .fill(SomatiqColor.accent.opacity(0.3))
                                    .matchedGeometryEffect(id: "periodIndicator", in: pickerNamespace)
                            }
                        }
                }
                .buttonStyle(.somatiqPressable)
            }
        }
        .padding(4)
        .background(
            LinearGradient(
                colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Capsule())
        .overlay {
            Capsule()
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

    private var summaryCard: some View {
        GlassCard {
            ViewThatFits(in: .horizontal) {
                HStack {
                    summaryItem(title: "Stress", value: "\(viewModel.averageStress)", color: SomatiqColor.stress)
                    summaryItem(title: "Sleep", value: "\(viewModel.averageSleep)", color: SomatiqColor.sleep)
                    summaryItem(title: "Battery", value: "\(viewModel.averageBodyBattery)", color: SomatiqColor.bodyBattery)
                }
                VStack(spacing: 12) {
                    summaryItem(title: "Stress", value: "\(viewModel.averageStress)", color: SomatiqColor.stress)
                    summaryItem(title: "Sleep", value: "\(viewModel.averageSleep)", color: SomatiqColor.sleep)
                    summaryItem(title: "Battery", value: "\(viewModel.averageBodyBattery)", color: SomatiqColor.bodyBattery)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func summaryItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SomatiqColor.textTertiary)
            Text(value)
                .font(.scoreNumber(24))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private var trendLoadingSkeleton: some View {
        VStack(spacing: 12) {
            ShimmerPlaceholder(height: 80)
            ShimmerPlaceholder(height: 220)
            ShimmerPlaceholder(height: 190)
            ShimmerPlaceholder(height: 190)
        }
    }

    // MARK: - Score trend chart

    private var scoreTrendChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Score Trends")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                Chart {
                    ForEach(viewModel.history, id: \.date) { entry in
                        // Area fills
                        AreaMark(
                            x: .value("Date", entry.date),
                            y: .value("Stress", entry.stressScore)
                        )
                        .foregroundStyle(SomatiqColor.stress.opacity(0.15).gradient)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", entry.date),
                            y: .value("Sleep", entry.sleepScore)
                        )
                        .foregroundStyle(SomatiqColor.sleep.opacity(0.15).gradient)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", entry.date),
                            y: .value("Battery", entry.bodyBatteryScore)
                        )
                        .foregroundStyle(SomatiqColor.bodyBattery.opacity(0.15).gradient)
                        .interpolationMethod(.catmullRom)

                        // Line marks
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Stress", entry.stressScore)
                        )
                        .foregroundStyle(SomatiqColor.stress)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Sleep", entry.sleepScore)
                        )
                        .foregroundStyle(SomatiqColor.sleep)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Battery", entry.bodyBatteryScore)
                        )
                        .foregroundStyle(SomatiqColor.bodyBattery)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        // Symbol marks at data points
                        PointMark(
                            x: .value("Date", entry.date),
                            y: .value("Stress", entry.stressScore)
                        )
                        .foregroundStyle(SomatiqColor.stress)
                        .symbolSize(16)

                        PointMark(
                            x: .value("Date", entry.date),
                            y: .value("Sleep", entry.sleepScore)
                        )
                        .foregroundStyle(SomatiqColor.sleep)
                        .symbolSize(16)

                        PointMark(
                            x: .value("Date", entry.date),
                            y: .value("Battery", entry.bodyBatteryScore)
                        )
                        .foregroundStyle(SomatiqColor.bodyBattery)
                        .symbolSize(16)
                    }

                    // Grid lines
                    RuleMark(y: .value("", 25))
                        .foregroundStyle(Color.white.opacity(0.03))
                    RuleMark(y: .value("", 50))
                        .foregroundStyle(Color.white.opacity(0.03))
                    RuleMark(y: .value("", 75))
                        .foregroundStyle(Color.white.opacity(0.03))

                    if let selectedEntry = selectedScoreEntry {
                        RuleMark(x: .value("Selected Date", selectedEntry.date))
                            .foregroundStyle(SomatiqColor.textTertiary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))

                        PointMark(
                            x: .value("Date", selectedEntry.date),
                            y: .value("Stress", selectedEntry.stressScore)
                        )
                        .foregroundStyle(SomatiqColor.stress)

                        PointMark(
                            x: .value("Date", selectedEntry.date),
                            y: .value("Sleep", selectedEntry.sleepScore)
                        )
                        .foregroundStyle(SomatiqColor.sleep)

                        PointMark(
                            x: .value("Date", selectedEntry.date),
                            y: .value("Battery", selectedEntry.bodyBatteryScore)
                        )
                        .foregroundStyle(SomatiqColor.bodyBattery)
                        .annotation(position: .top, alignment: .leading) {
                            selectionCallout {
                                Text(selectedEntry.date.formatted(.dateTime.day().month(.abbreviated)))
                                Text("Stress \(selectedEntry.stressScore)")
                                Text("Sleep \(selectedEntry.sleepScore)")
                                Text("Battery \(selectedEntry.bodyBatteryScore)")
                            }
                        }
                    }
                }
                .frame(height: 200)
                .chartYScale(domain: 0 ... 100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5))
                }
                .chartOverlay { proxy in
                    selectionOverlay(
                        proxy: proxy,
                        selectedDate: $selectedScoreDate,
                        hapticDate: $lastScoreHapticDate
                    )
                }
            }
        }
    }

    private var sleepBreakdownChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sleep Breakdown")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                Chart(sleepBreakdownPoints) { point in
                    BarMark(
                        x: .value("Date", point.date),
                        y: .value("Minutes", point.value)
                    )
                    .foregroundStyle(by: .value("Stage", point.stage))
                    .cornerRadius(4)
                }
                .frame(height: 180)
                .chartForegroundStyleScale([
                    "Deep": SomatiqColor.sleep,
                    "REM": SomatiqColor.accent,
                    "Core": SomatiqColor.textTertiary,
                ])
                .chartOverlay { proxy in
                    selectionOverlay(
                        proxy: proxy,
                        selectedDate: $selectedSleepDate,
                        hapticDate: $lastSleepHapticDate
                    )
                }

                if let selectedEntry = selectedSleepEntry {
                    selectionCallout {
                        Text(selectedEntry.date.formatted(.dateTime.day().month(.abbreviated)))
                        Text("Deep \(Int(selectedEntry.deepSleepMin.rounded())) min")
                        Text("REM \(Int(selectedEntry.remSleepMin.rounded())) min")
                        Text("Core \(Int(selectedEntry.coreSleepMin.rounded())) min")
                    }
                }
            }
        }
    }

    private var hrvChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("HRV vs Baseline")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                let baseline = (Statistics.mean(viewModel.history.map(\.avgSDNN)) ?? 40)

                Chart {
                    ForEach(viewModel.history, id: \.date) { entry in
                        AreaMark(
                            x: .value("Date", entry.date),
                            y: .value("HRV", entry.avgSDNN)
                        )
                        .foregroundStyle(SomatiqColor.accent.opacity(0.12).gradient)

                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("HRV", entry.avgSDNN)
                        )
                        .foregroundStyle(SomatiqColor.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        PointMark(
                            x: .value("Date", entry.date),
                            y: .value("HRV", entry.avgSDNN)
                        )
                        .foregroundStyle(SomatiqColor.accent)
                        .symbolSize(16)
                    }

                    RuleMark(y: .value("Baseline", baseline))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(SomatiqColor.textTertiary)

                    if let selectedEntry = selectedHRVEntry {
                        RuleMark(x: .value("Selected Date", selectedEntry.date))
                            .foregroundStyle(SomatiqColor.textTertiary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))

                        PointMark(
                            x: .value("Date", selectedEntry.date),
                            y: .value("HRV", selectedEntry.avgSDNN)
                        )
                        .foregroundStyle(SomatiqColor.accent)
                        .annotation(position: .top, alignment: .leading) {
                            selectionCallout {
                                Text(selectedEntry.date.formatted(.dateTime.day().month(.abbreviated)))
                                Text("HRV \(Int(selectedEntry.avgSDNN.rounded())) ms")
                                Text("Baseline \(Int(baseline.rounded())) ms")
                            }
                        }
                    }
                }
                .frame(height: 180)
                .chartOverlay { proxy in
                    selectionOverlay(
                        proxy: proxy,
                        selectedDate: $selectedHRVDate,
                        hapticDate: $lastHRVHapticDate
                    )
                }
            }
        }
    }

    private var sleepBreakdownPoints: [SleepBreakdownPoint] {
        viewModel.history.flatMap { score in
            [
                SleepBreakdownPoint(date: score.date, stage: "Deep", value: score.deepSleepMin),
                SleepBreakdownPoint(date: score.date, stage: "REM", value: score.remSleepMin),
                SleepBreakdownPoint(date: score.date, stage: "Core", value: score.coreSleepMin),
            ]
        }
    }

    private var selectedScoreEntry: DailyScore? {
        nearestScore(to: selectedScoreDate)
    }

    private var selectedSleepEntry: DailyScore? {
        nearestScore(to: selectedSleepDate)
    }

    private var selectedHRVEntry: DailyScore? {
        nearestScore(to: selectedHRVDate)
    }

    private func nearestScore(to date: Date?) -> DailyScore? {
        guard let date else { return nil }
        return viewModel.history.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    @ViewBuilder
    private func selectionOverlay(
        proxy: ChartProxy,
        selectedDate: Binding<Date?>,
        hapticDate: Binding<Date?>
    ) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let frame = geometry[plotFrame]
                            let xPosition = value.location.x - frame.origin.x
                            guard xPosition >= 0, xPosition <= frame.width else {
                                return
                            }
                            guard let date: Date = proxy.value(atX: xPosition),
                                  let snappedDate = nearestScore(to: date)?.date.startOfDay
                            else {
                                return
                            }

                            let previousDay = selectedDate.wrappedValue?.startOfDay
                            selectedDate.wrappedValue = snappedDate

                            guard previousDay != snappedDate else { return }
                            if hapticDate.wrappedValue?.startOfDay != snappedDate {
                                UISelectionFeedbackGenerator().selectionChanged()
                                hapticDate.wrappedValue = snappedDate
                            }
                        }
                        .onEnded { _ in
                            selectedDate.wrappedValue = nil
                            hapticDate.wrappedValue = nil
                        }
                )
        }
    }

    private func selectionCallout<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func errorCard(message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Couldn't load trends")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(SomatiqColor.textSecondary)

                Button("Retry") {
                    viewModel.load()
                }
                .buttonStyle(.borderedProminent)
                .tint(SomatiqColor.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var minimumTrendPoints: Int {
        3
    }

    private var headerProgress: CGFloat {
        CGFloat(Statistics.clamped(Double((-scrollOffset - 8) / 68), min: 0, max: 1))
    }

    private var chartTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.992))
    }
}

private struct SleepBreakdownPoint: Identifiable {
    let id = UUID()
    let date: Date
    let stage: String
    let value: Double
}

private struct TrendSectionEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
            .animation(
                reduceMotion ? .linear(duration: 0.1) : SomatiqAnimation.staggered(index: index),
                value: appeared
            )
    }
}
