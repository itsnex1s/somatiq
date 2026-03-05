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

                            trendsSection
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("somatiq.healthReconnectDidComplete"))) { _ in
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

private enum JournalMode: String, CaseIterable, Identifiable {
    case timeline
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline:
            return "Timeline"
        case .calendar:
            return "Calendar"
        }
    }
}

private enum JournalTag: String, CaseIterable, Identifiable {
    case stressSpike
    case sleepDebt
    case lowBattery
    case recoveryDay
    case lowHRV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stressSpike: return "Stress Spike"
        case .sleepDebt: return "Sleep Debt"
        case .lowBattery: return "Low Battery"
        case .recoveryDay: return "Recovery"
        case .lowHRV: return "Low HRV"
        }
    }

    var icon: String {
        switch self {
        case .stressSpike: return "bolt.fill"
        case .sleepDebt: return "moon.zzz.fill"
        case .lowBattery: return "battery.25"
        case .recoveryDay: return "figure.cooldown"
        case .lowHRV: return "heart.slash.fill"
        }
    }

    var color: Color {
        switch self {
        case .stressSpike: return SomatiqColor.stress
        case .sleepDebt: return SomatiqColor.sleep
        case .lowBattery: return SomatiqColor.bodyBattery
        case .recoveryDay: return SomatiqColor.success
        case .lowHRV: return SomatiqColor.heart
        }
    }
}

private struct JournalDaySummary: Identifiable, Hashable {
    let date: Date
    let stress: Int
    let sleep: Int
    let bodyBattery: Int
    let hrv: Int

    var id: Date { date }

    var overallScore: Int {
        let average = (Double(stress) + Double(sleep) + Double(bodyBattery)) / 3
        return Int(average.rounded())
    }

    var statusTitle: String {
        switch overallScore {
        case 80 ... 100:
            return "Excellent"
        case 65 ..< 80:
            return "Good"
        case 45 ..< 65:
            return "Watch"
        default:
            return "Low"
        }
    }

    var statusColor: Color {
        switch overallScore {
        case 80 ... 100:
            return SomatiqColor.success
        case 65 ..< 80:
            return SomatiqColor.bodyBattery
        case 45 ..< 65:
            return SomatiqColor.warning
        default:
            return SomatiqColor.heart
        }
    }

    var dayLabel: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var tags: [JournalTag] {
        var result: [JournalTag] = []

        if stress >= 70 {
            result.append(.stressSpike)
        }
        if sleep <= 45 {
            result.append(.sleepDebt)
        }
        if bodyBattery <= 40 {
            result.append(.lowBattery)
        }
        if overallScore >= 78 {
            result.append(.recoveryDay)
        }
        if hrv > 0 && hrv < 35 {
            result.append(.lowHRV)
        }

        return result
    }

    init(score: DailyScore) {
        date = score.date.startOfDay
        stress = score.stressScore
        sleep = score.sleepScore
        bodyBattery = score.bodyBatteryScore
        hrv = Int(score.avgSDNN.rounded())
    }
}

@MainActor
@Observable
private final class JournalViewModel {
    var isLoading = false
    var errorMessage: String?
    var entries: [JournalDaySummary] = []

    private let trendsService: TrendsDataService

    init(trendsService: TrendsDataService) {
        self.trendsService = trendsService
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            let raw = try trendsService.fetchHistory(for: .days90)
            errorMessage = nil
            entries = raw
                .filter { score in
                    score.stressScore > 0 ||
                        score.sleepScore > 0 ||
                        score.bodyBatteryScore > 0 ||
                        score.avgSDNN > 0 ||
                        score.sleepDurationMin > 0
                }
                .map(JournalDaySummary.init)
                .sorted(by: { $0.date > $1.date })
        } catch {
            AppLog.error("JournalViewModel.load", error: error)
            errorMessage = AppErrorMapper.userMessage(for: error)
            entries = []
        }
    }
}

private struct JournalView: View {
    @State private var viewModel: JournalViewModel
    @State private var mode: JournalMode = .timeline
    @State private var selectedTag: JournalTag?
    @State private var displayedMonth = Date()
    @State private var selectedDay: JournalDaySummary?
    @Environment(\.dismiss) private var dismiss

    init(trendsService: TrendsDataService) {
        _viewModel = State(initialValue: JournalViewModel(trendsService: trendsService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SomatiqColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        modePicker

                        if mode == .timeline, !availableTags.isEmpty {
                            tagFilterRow
                        }

                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(SomatiqColor.accent)
                                .frame(maxWidth: .infinity, minHeight: 220)
                        } else if let errorMessage = viewModel.errorMessage {
                            errorCard(message: errorMessage)
                        } else if viewModel.entries.isEmpty {
                            EmptyStateView(
                                title: "No journal entries",
                                message: "Connect Apple Health and wear Apple Watch to get daily scores.",
                                buttonTitle: "Close"
                            ) {
                                dismiss()
                            }
                        } else {
                            switch mode {
                            case .timeline:
                                timelineContent
                            case .calendar:
                                calendarContent
                            }
                        }
                    }
                    .padding(.horizontal, SomatiqSpacing.pageHorizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SomatiqColor.textSecondary)
                    }
                }
            }
            .task {
                viewModel.load()
                guard let latest = viewModel.entries.first else { return }
                selectedDay = latest
                displayedMonth = monthStart(for: latest.date)
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(JournalMode.allCases) { current in
                Button {
                    withAnimation(SomatiqAnimation.tabSwitch) {
                        mode = current
                    }
                } label: {
                    Text(current.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mode == current ? .white : SomatiqColor.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if mode == current {
                                Capsule(style: .continuous)
                                    .fill(SomatiqColor.accent.opacity(0.28))
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

    private var tagFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    title: "All",
                    icon: "line.3.horizontal.decrease.circle",
                    tint: SomatiqColor.textSecondary,
                    isActive: selectedTag == nil
                ) {
                    withAnimation(SomatiqAnimation.stateSwap) {
                        selectedTag = nil
                    }
                }

                ForEach(availableTags) { tag in
                    filterChip(
                        title: tag.title,
                        icon: tag.icon,
                        tint: tag.color,
                        isActive: selectedTag == tag
                    ) {
                        withAnimation(SomatiqAnimation.stateSwap) {
                            selectedTag = (selectedTag == tag) ? nil : tag
                        }
                    }
                }
            }
        }
    }

    private func filterChip(
        title: String,
        icon: String,
        tint: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? .white : tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            isActive
                                ? LinearGradient(
                                    colors: [SomatiqColor.accent, SomatiqColor.sleep],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                }
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

    private var availableTags: [JournalTag] {
        JournalTag.allCases.filter { tag in
            viewModel.entries.contains(where: { $0.tags.contains(tag) })
        }
    }

    private var filteredEntries: [JournalDaySummary] {
        guard let selectedTag else { return viewModel.entries }
        return viewModel.entries.filter { $0.tags.contains(selectedTag) }
    }

    private var timelineContent: some View {
        Group {
            if filteredEntries.isEmpty {
                GlassCard {
                    Text("No entries match this filter yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(SomatiqColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredEntries) { entry in
                        timelineCard(for: entry)
                    }
                }
            }
        }
    }

    private func timelineCard(for entry: JournalDaySummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            JournalStatusOrb(score: entry.overallScore, size: 42)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(entry.dayLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SomatiqColor.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(entry.statusTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(entry.statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(entry.statusColor.opacity(0.12), in: Capsule(style: .continuous))
                }

                HStack(spacing: 10) {
                    summaryValue(title: "Stress", value: "\(entry.stress)", tint: SomatiqColor.stress)
                    summaryValue(title: "Sleep", value: "\(entry.sleep)", tint: SomatiqColor.sleep)
                    summaryValue(title: "Battery", value: "\(entry.bodyBattery)", tint: SomatiqColor.bodyBattery)
                    summaryValue(title: "Avg", value: "\(entry.overallScore)", tint: entry.statusColor)
                }

                if !entry.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(entry.tags.prefix(3)) { tag in
                            Label(tag.title, systemImage: tag.icon)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tag.color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(tag.color.opacity(0.14), in: Capsule(style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(14)
        .somatiqCardStyle(tint: entry.statusColor, cornerRadius: 18)
    }

    private func summaryValue(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SomatiqColor.textTertiary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            monthHeader
            weekdayHeader
            monthGrid

            if let selectedDay {
                selectedDayCard(entry: selectedDay)
                    .padding(.top, 6)
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textSecondary)
            }
            .buttonStyle(.somatiqPressable)

            Spacer()

            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SomatiqColor.textPrimary)

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textSecondary)
            }
            .buttonStyle(.somatiqPressable)
            .disabled(!canMoveToNextMonth)
            .opacity(canMoveToNextMonth ? 1 : 0.35)
        }
    }

    private var weekdayHeader: some View {
        let symbols = reorderedWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SomatiqColor.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let cells = monthCells(for: displayedMonth)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    let day = calendar.component(.day, from: date)
                    let entry = entriesByDate[date.startOfDay]
                    let isSelected = selectedDay?.date.startOfDay == date.startOfDay
                    Button {
                        if let entry {
                            selectedDay = entry
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(day)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(entry == nil ? SomatiqColor.textMuted : SomatiqColor.textPrimary)

                            if let entry {
                                JournalStatusOrb(score: entry.overallScore, size: 24)
                            } else {
                                Circle()
                                    .fill(SomatiqColor.textMuted.opacity(0.35))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.1))
                            }
                        }
                    }
                    .buttonStyle(.somatiqPressable)
                    .disabled(entry == nil)
                } else {
                    Color.clear
                        .frame(height: 52)
                }
            }
        }
    }

    private func selectedDayCard(entry: JournalDaySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.dayLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.statusColor)
                        .frame(width: 8, height: 8)
                    Text(entry.statusTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(entry.statusColor)
                }
            }

            HStack(spacing: 10) {
                summaryValue(title: "Stress", value: "\(entry.stress)", tint: SomatiqColor.stress)
                summaryValue(title: "Sleep", value: "\(entry.sleep)", tint: SomatiqColor.sleep)
                summaryValue(title: "Battery", value: "\(entry.bodyBattery)", tint: SomatiqColor.bodyBattery)
                summaryValue(title: "HRV", value: entry.hrv > 0 ? "\(entry.hrv)ms" : "--", tint: SomatiqColor.heart)
            }
        }
        .padding(16)
        .somatiqCardStyle(tint: entry.statusColor, cornerRadius: 18)
    }

    private func errorCard(message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Couldn't load journal")
                    .font(.system(size: 15, weight: .semibold))
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

    private var calendar: Calendar {
        Calendar.current
    }

    private var entriesByDate: [Date: JournalDaySummary] {
        Dictionary(uniqueKeysWithValues: viewModel.entries.map { ($0.date.startOfDay, $0) })
    }

    private var reorderedWeekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let shift = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[shift...]) + Array(symbols[..<shift])
    }

    private func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date.startOfDay
    }

    private func monthCells(for date: Date) -> [Date?] {
        let start = monthStart(for: date)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: start)
        let leadingPadding = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells = Array<Date?>(repeating: nil, count: leadingPadding)
        for day in range {
            if let itemDate = calendar.date(byAdding: .day, value: day - 1, to: start) {
                cells.append(itemDate.startOfDay)
            }
        }
        return cells
    }

    private func changeMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = monthStart(for: next)
        if let firstInMonth = viewModel.entries.first(where: { calendar.isDate($0.date, equalTo: displayedMonth, toGranularity: .month) }) {
            selectedDay = firstInMonth
        }
    }

    private var canMoveToNextMonth: Bool {
        monthStart(for: displayedMonth) < monthStart(for: Date())
    }
}

private struct JournalStatusOrb: View {
    let score: Int
    let size: CGFloat

    private var color: Color {
        switch score {
        case 80 ... 100:
            return SomatiqColor.success
        case 65 ..< 80:
            return SomatiqColor.bodyBattery
        case 45 ..< 65:
            return SomatiqColor.warning
        default:
            return SomatiqColor.heart
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#0B0E17"), Color(hex: "#06070C")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.98), color.opacity(0.64)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(size * 0.08)

            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: size * 0.03)
                .padding(size * 0.09)

            Circle()
                .trim(from: 0.12, to: 0.46)
                .stroke(Color.white.opacity(0.34), lineWidth: size * 0.04)
                .rotationEffect(.degrees(205))
                .padding(size * 0.08)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.25), .clear],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: size * 0.5
                    )
                )
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.45), radius: size * 0.26, x: 0, y: size * 0.08)
        .shadow(color: Color.black.opacity(0.45), radius: size * 0.18, x: 0, y: size * 0.1)
    }
}
