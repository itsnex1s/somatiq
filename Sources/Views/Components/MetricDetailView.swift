import Charts
import SwiftUI
import UIKit

struct MetricDetailView: View {
    let kind: MetricKind
    let currentValue: Int
    let currentStatus: String
    let trendsService: TrendsDataService

    @Environment(\.dismiss) private var dismiss
    @Namespace private var pickerNamespace

    @State private var selectedPeriod: TrendPeriod = .days7
    @State private var history: [DailyScore] = []
    @State private var selectedDate: Date?
    @State private var lastSelectionHapticDate: Date?

    var body: some View {
        ZStack {
            SomatiqColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    periodPicker
                    heroValue
                    chartSection
                    summaryStats
                }
                .padding(.horizontal, SomatiqSpacing.pageHorizontal)
                .padding(.vertical, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { loadData() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .overlay {
                        Circle()
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

            Spacer()

            VStack(spacing: 2) {
                Text("\(kind.title) Report")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)
                Text("Today at \(Date().formatted(.dateTime.hour().minute()))")
                    .font(.system(size: 12))
                    .foregroundStyle(SomatiqColor.textTertiary)
            }

            Spacer()

            // Balance the layout
            Color.clear
                .frame(width: 36, height: 36)
        }
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(TrendPeriod.allCases) { period in
                Button {
                    withAnimation(SomatiqAnimation.tabSwitch) {
                        selectedPeriod = period
                    }
                    selectedDate = nil
                    loadData()
                } label: {
                    Text(periodLabel(period))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedPeriod == period ? .white : SomatiqColor.textTertiary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selectedPeriod == period {
                                Capsule()
                                    .fill(kind.color.opacity(0.3))
                                    .matchedGeometryEffect(id: "detailPeriod", in: pickerNamespace)
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

    // MARK: - Hero value

    private var heroValue: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kind.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(SomatiqColor.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let selectedEntry = selectedEntry {
                    Text("\(extractValue(from: selectedEntry))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(kind.color)
                        .contentTransition(.numericText())

                    if !kind.unit.isEmpty {
                        Text(kind.unit)
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(kind.color.opacity(0.6))
                    }
                } else {
                    Text("\(currentValue)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(kind.color)
                        .contentTransition(.numericText())

                    if !kind.unit.isEmpty {
                        Text(kind.unit)
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(kind.color.opacity(0.6))
                    }
                }
            }

            if let selectedEntry = selectedEntry {
                Text(selectedEntry.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.system(size: 14))
                    .foregroundStyle(SomatiqColor.textTertiary)
            } else {
                Text(currentStatus)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SomatiqColor.textSecondary)
            }
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        GlassCard {
            if chartHistory.count < minimumChartPoints {
                emptyChart
            } else {
                chart
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(chartHistory, id: \.date) { entry in
                    let val = extractValue(from: entry)

                    BarMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value(kind.title, val)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [kind.color.opacity(0.4), kind.color],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                }

                if let sel = selectedEntry {
                    RuleMark(x: .value("Selected", sel.date, unit: .day))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: kind.chartDomain)
            .chartXAxis {
                AxisMarks(values: chartHistory.map(\.date)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(xAxisFormat))
                                .font(.system(size: 10))
                                .foregroundStyle(SomatiqColor.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let intVal = value.as(Int.self) {
                            Text("\(intVal)")
                                .font(.system(size: 10))
                                .foregroundStyle(SomatiqColor.textMuted)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.04))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let frame = geometry[plotFrame]
                                    let x = value.location.x - frame.origin.x
                                    guard x >= 0, x <= frame.width else { return }

                                    guard let date: Date = proxy.value(atX: x),
                                          let snappedDate = nearestEntry(to: date)?.date.startOfDay
                                    else {
                                        return
                                    }

                                    let previousDay = selectedDate?.startOfDay
                                    selectedDate = snappedDate

                                    guard previousDay != snappedDate else { return }
                                    if lastSelectionHapticDate?.startOfDay != snappedDate {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        lastSelectionHapticDate = snappedDate
                                    }
                                }
                                .onEnded { _ in
                                    selectedDate = nil
                                    lastSelectionHapticDate = nil
                                }
                        )
                }
            }
            .frame(height: 220)
        }
    }

    private var emptyChart: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundStyle(kind.color.opacity(0.4))

            Text("Not enough data yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SomatiqColor.textSecondary)

            Text("Collect at least \(minimumChartPoints) days of real \(kind.title.lowercased()) measurements to see a trend.")
                .font(.system(size: 13))
                .foregroundStyle(SomatiqColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    // MARK: - Summary stats

    private var summaryStats: some View {
        Group {
            if chartHistory.count >= 2 {
                GlassCard {
                    HStack(spacing: 0) {
                        statItem(title: "Average", value: averageValue)
                        statItem(title: "Min", value: minValue)
                        statItem(title: "Max", value: maxValue)
                    }
                }
            }
        }
    }

    private func statItem(title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SomatiqColor.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(kind.color)

                if !kind.unit.isEmpty {
                    Text(kind.unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(kind.color.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func loadData() {
        do {
            let loadedHistory = try trendsService.fetchHistory(for: selectedPeriod)
            withAnimation(SomatiqAnimation.chartReveal) {
                history = loadedHistory
            }
        } catch {
            withAnimation(SomatiqAnimation.chartReveal) {
                history = []
            }
        }
    }

    private func extractValue(from score: DailyScore) -> Int {
        switch kind {
        case .bodyBattery:
            return score.bodyBatteryScore
        case .stress:
            return score.stressScore
        case .sleep:
            return score.sleepScore
        case .heart:
            return Int(score.avgSDNN.rounded())
        }
    }

    private var selectedEntry: DailyScore? {
        nearestEntry(to: selectedDate)
    }

    private func nearestEntry(to date: Date?) -> DailyScore? {
        guard let date else { return nil }
        return chartHistory.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private var values: [Int] {
        chartHistory.map { extractValue(from: $0) }
    }

    private var chartHistory: [DailyScore] {
        history.filter { score in
            guard extractValue(from: score) > 0 else { return false }
            return hasRealMeasurements(for: score)
        }
    }

    private var minimumChartPoints: Int {
        3
    }

    private func hasRealMeasurements(for score: DailyScore) -> Bool {
        switch kind {
        case .heart:
            return score.avgSDNN > 0 && score.restingHR > 0
        case .stress:
            return score.avgSDNN > 0 && score.restingHR > 0
        case .sleep:
            return score.sleepDurationMin > 0
        case .bodyBattery:
            return score.activeCalories > 0 || score.steps > 0
        }
    }

    private var averageValue: Int {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / values.count
    }

    private var minValue: Int {
        values.min() ?? 0
    }

    private var maxValue: Int {
        values.max() ?? 0
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedPeriod {
        case .days7: .dateTime.weekday(.abbreviated)
        case .days30: .dateTime.day().month(.abbreviated)
        case .days90: .dateTime.day().month(.abbreviated)
        }
    }

    private func periodLabel(_ period: TrendPeriod) -> String {
        switch period {
        case .days7: "Week"
        case .days30: "Month"
        case .days90: "3 Months"
        }
    }
}
