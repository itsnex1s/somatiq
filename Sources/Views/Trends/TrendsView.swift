import Charts
import SwiftUI

struct TrendsView: View {
    @State private var viewModel: TrendsViewModel
    @State private var selectedScoreDate: Date?
    @State private var selectedSleepDate: Date?
    @State private var selectedHRVDate: Date?

    init(trendsService: TrendsDataService) {
        _viewModel = State(initialValue: TrendsViewModel(trendsService: trendsService))
    }

    var body: some View {
        ZStack {
            SomatiqColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Trends")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(SomatiqColor.textPrimary)

                    periodPicker
                    summaryCard

                    if let errorMessage = viewModel.errorMessage {
                        errorCard(message: errorMessage)
                    } else if viewModel.hasInsufficientData {
                        GlassCard {
                            Text("Collect at least 3 days of data to unlock full trend analysis.")
                                .font(.system(size: 14))
                                .foregroundStyle(SomatiqColor.textSecondary)
                        }
                    }

                    scoreTrendChart
                    sleepBreakdownChart
                    hrvChart
                }
                .padding(.horizontal, SomatiqSpacing.pageHorizontal)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            viewModel.load()
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: Binding(
            get: { viewModel.selectedPeriod },
            set: { viewModel.updatePeriod($0) }
        )) {
            ForEach(TrendPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var summaryCard: some View {
        GlassCard {
            ViewThatFits(in: .horizontal) {
                HStack {
                    summaryItem(title: "Stress", value: "\(viewModel.averageStress)", color: SomatiqColor.stress)
                    summaryItem(title: "Sleep", value: "\(viewModel.averageSleep)", color: SomatiqColor.sleep)
                    summaryItem(title: "Energy", value: "\(viewModel.averageEnergy)", color: SomatiqColor.energy)
                }
                VStack(spacing: 12) {
                    summaryItem(title: "Stress", value: "\(viewModel.averageStress)", color: SomatiqColor.stress)
                    summaryItem(title: "Sleep", value: "\(viewModel.averageSleep)", color: SomatiqColor.sleep)
                    summaryItem(title: "Energy", value: "\(viewModel.averageEnergy)", color: SomatiqColor.energy)
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
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreTrendChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Score Trends")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                Chart {
                    ForEach(viewModel.history, id: \.date) { entry in
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Stress", entry.stressScore)
                        )
                        .foregroundStyle(SomatiqColor.stress)
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Sleep", entry.sleepScore)
                        )
                        .foregroundStyle(SomatiqColor.sleep)
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Energy", entry.energyScore)
                        )
                        .foregroundStyle(SomatiqColor.energy)
                        .interpolationMethod(.catmullRom)
                    }

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
                            y: .value("Energy", selectedEntry.energyScore)
                        )
                        .foregroundStyle(SomatiqColor.energy)
                        .annotation(position: .top, alignment: .leading) {
                            selectionCallout {
                                Text(selectedEntry.date.formatted(.dateTime.day().month(.abbreviated)))
                                Text("Stress \(selectedEntry.stressScore)")
                                Text("Sleep \(selectedEntry.sleepScore)")
                                Text("Energy \(selectedEntry.energyScore)")
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
                    selectionOverlay(proxy: proxy, selectedDate: $selectedScoreDate)
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
                }
                .frame(height: 180)
                .chartForegroundStyleScale([
                    "Deep": SomatiqColor.sleep,
                    "REM": SomatiqColor.accent,
                    "Core": SomatiqColor.textTertiary,
                ])
                .chartOverlay { proxy in
                    selectionOverlay(proxy: proxy, selectedDate: $selectedSleepDate)
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
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("HRV", entry.avgSDNN)
                        )
                        .foregroundStyle(SomatiqColor.accent)
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
                    selectionOverlay(proxy: proxy, selectedDate: $selectedHRVDate)
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
    private func selectionOverlay(proxy: ChartProxy, selectedDate: Binding<Date?>) -> some View {
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
                            if let date: Date = proxy.value(atX: xPosition) {
                                selectedDate.wrappedValue = date
                            }
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
        .background(SomatiqColor.card.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SomatiqColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func errorCard(message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Couldn’t load trends")
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
}

private struct SleepBreakdownPoint: Identifiable {
    let id = UUID()
    let date: Date
    let stage: String
    let value: Double
}
