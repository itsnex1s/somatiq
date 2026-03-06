import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AnalysesView: View {
    let modelManager: AIModelManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\LabAnalysisRecord.createdAt, order: .reverse)])
    private var records: [LabAnalysisRecord]

    @State private var showImporter = false
    @State private var isImporting = false
    @State private var alertMessage: String?
    @State private var transientMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            SomatiqColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let transientMessage, !transientMessage.isEmpty {
                        statusBanner(message: transientMessage)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }

                    if records.isEmpty {
                        emptyState
                    } else {
                        timeline
                    }
                }
                .padding(.horizontal, SomatiqSpacing.pageHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Analyses")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task { await importAndAnalyze(url) }
            case let .failure(error):
                alertMessage = AppErrorMapper.userMessage(
                    for: error,
                    fallback: "Could not open the selected file."
                )
            }
        }
        .alert("Analyses", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Analyses")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                Text("Upload PDF reports and get AI interpretation.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SomatiqColor.textTertiary)
            }

            Spacer(minLength: 12)

            Button {
                showImporter = true
            } label: {
                Label(isImporting ? "Importing..." : "Upload PDF", systemImage: "plus")
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
            .disabled(isImporting)
            .opacity(isImporting ? 0.65 : 1)
        }
    }

    private func statusBanner(message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SomatiqColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#181B2A"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                    )
            )
    }

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("No analyses yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                Text("Import a PDF blood test report. We save it as a timeline entry and run AI interpretation.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showImporter = true
                } label: {
                    Text("Select PDF")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(SomatiqColor.accent.opacity(0.85), in: Capsule())
                }
                .buttonStyle(.somatiqPressable)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Timeline".uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(SomatiqColor.textMuted)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(groupedByDay, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayLabel(for: group.day))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomatiqColor.textTertiary)

                        VStack(spacing: 10) {
                            ForEach(group.records, id: \.persistentModelID) { record in
                                NavigationLink {
                                    LabAnalysisDetailView(record: record, modelManager: modelManager)
                                } label: {
                                    LabAnalysisTimelineRow(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.08) : SomatiqAnimation.sectionReveal, value: records.count)
    }

    private var groupedByDay: [(day: Date, records: [LabAnalysisRecord])] {
        let grouped = Dictionary(grouping: records) { $0.createdAt.startOfDay }
        return grouped.keys
            .sorted(by: >)
            .map { day in
                let items = (grouped[day] ?? [])
                    .sorted { $0.createdAt > $1.createdAt }
                return (day, items)
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

    @MainActor
    private func importAndAnalyze(_ url: URL) async {
        isImporting = true

        do {
            let service = LabAnalysisService(context: modelContext, modelManager: modelManager)
            let record = try service.importPDF(from: url)
            transientMessage = "Imported \(record.fileName). Running AI evaluation..."
            isImporting = false

            do {
                try await service.evaluate(record: record)
                transientMessage = "AI evaluation is ready."
            } catch {
                alertMessage = "PDF imported, but AI evaluation failed: \(AppErrorMapper.userMessage(for: error))"
            }
        } catch {
            isImporting = false
            alertMessage = AppErrorMapper.userMessage(
                for: error,
                fallback: "Could not import PDF."
            )
        }

        guard transientMessage != nil else { return }
        let snapshot = transientMessage
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard snapshot == transientMessage else { return }
            withAnimation(reduceMotion ? .linear(duration: 0.1) : SomatiqAnimation.stateSwap) {
                transientMessage = nil
            }
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    alertMessage = nil
                }
            }
        )
    }
}

private struct LabAnalysisTimelineRow: View {
    let record: LabAnalysisRecord

    private var statusMeta: (title: String, tint: Color) {
        switch record.aiStatus {
        case .pending:
            return ("Imported", SomatiqColor.textMuted)
        case .analyzing:
            return ("Analyzing", SomatiqColor.warning)
        case .ready:
            return ("Ready", SomatiqColor.success)
        case .failed:
            return ("Failed", SomatiqColor.danger)
        }
    }

    private var cardTint: Color {
        switch record.aiStatus {
        case .pending:
            return SomatiqColor.textMuted
        case .analyzing:
            return SomatiqColor.warning
        case .ready:
            return SomatiqColor.accent
        case .failed:
            return SomatiqColor.danger
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Circle()
                    .fill(statusMeta.tint)
                    .frame(width: 8, height: 8)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1, height: 46)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.fileName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SomatiqColor.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    statusChip
                }

                HStack(spacing: 8) {
                    Text(record.createdAt.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SomatiqColor.textMuted)

                    if record.aiStatus == .ready {
                        scoreChip
                    }
                }

                Text(record.aiSummary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .lineLimit(2)

                if record.aiStatus == .analyzing {
                    ProgressView()
                        .tint(SomatiqColor.warning)
                }
            }
            .padding(14)
            .somatiqCardStyle(tint: cardTint, cornerRadius: 16, shadowIntensity: .subtle)
        }
    }

    private var statusChip: some View {
        Text(statusMeta.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(statusMeta.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusMeta.tint.opacity(0.12), in: Capsule())
    }

    private var scoreChip: some View {
        Text("\(record.aiScore) • \(record.aiScoreLabel)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SomatiqColor.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06), in: Capsule())
    }
}
