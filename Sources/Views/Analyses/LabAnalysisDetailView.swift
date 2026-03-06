import PDFKit
import SwiftData
import SwiftUI

struct LabAnalysisDetailView: View {
    @Bindable var record: LabAnalysisRecord
    let modelManager: AIModelManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext

    @State private var isEvaluating = false
    @State private var showExtractedText = false
    @State private var alertMessage: String?

    init(record: LabAnalysisRecord, modelManager: AIModelManager) {
        self.record = record
        self.modelManager = modelManager
    }

    var body: some View {
        ZStack {
            SomatiqColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    evaluationCard
                    pdfCard
                    extractedTextCard
                }
                .padding(.horizontal, SomatiqSpacing.pageHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Analysis", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var summaryCard: some View {
        GlassCard(tint: statusMeta.tint) {
            VStack(alignment: .leading, spacing: 12) {
                Text(record.fileName)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(SomatiqColor.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    statusChip

                    Text(record.createdAt.formatted(.dateTime.day().month().hour().minute()))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SomatiqColor.textTertiary)
                }

                if let aiEvaluatedAt = record.aiEvaluatedAt, record.aiStatus == .ready {
                    Text("Updated \(aiEvaluatedAt.formatted(.dateTime.hour().minute()))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SomatiqColor.textMuted)
                }

                Button {
                    Task { await runEvaluation() }
                } label: {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(evaluateButtonTitle)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(SomatiqColor.accent.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.somatiqPressable)
                .disabled(isBusy)
                .opacity(isBusy ? 0.7 : 1)

                Text("AI insight for wellness context only, not medical diagnosis.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SomatiqColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var evaluationCard: some View {
        GlassCard(tint: statusMeta.tint) {
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Evaluation")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                if isBusy {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(SomatiqColor.warning)
                        Text("Analyzing biomarkers...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SomatiqColor.textSecondary)
                    }
                } else if record.aiStatus == .failed {
                    Text(record.aiError ?? "AI evaluation failed. Try again.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SomatiqColor.danger)
                } else if let payload = record.parsedEvaluation {
                    payloadView(payload)
                } else {
                    Text(record.aiSummary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SomatiqColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let aiError = record.aiError, !aiError.isEmpty {
                        Text(aiError)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SomatiqColor.warning)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pdfCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Original PDF")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                LabAnalysisPDFPreview(data: record.pdfData)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var extractedTextCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(reduceMotion ? .linear(duration: 0.1) : SomatiqAnimation.stateSwap) {
                        showExtractedText.toggle()
                    }
                } label: {
                    HStack {
                        Text("Extracted text")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SomatiqColor.textPrimary)
                        Spacer()
                        Image(systemName: showExtractedText ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SomatiqColor.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                if showExtractedText {
                    Text(record.extractedText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(SomatiqColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func payloadView(_ payload: LabEvaluationPayload) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(payload.overallScore)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(statusMeta.tint)

            Text(payload.overallLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(statusMeta.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusMeta.tint.opacity(0.13), in: Capsule())
        }

        Text(payload.summary)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(SomatiqColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

        if !payload.keyFindings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Key findings")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(SomatiqColor.textMuted)

                ForEach(Array(payload.keyFindings.enumerated()), id: \.offset) { _, finding in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(statusMeta.tint)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(finding)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SomatiqColor.textSecondary)
                    }
                }
            }
        }

        if !payload.markers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Markers")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(SomatiqColor.textMuted)

                ForEach(payload.markers) { marker in
                    markerRow(marker)
                }
            }
        }
    }

    private func markerRow(_ marker: LabEvaluationMarker) -> some View {
        let tint = markerTint(for: marker.status)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(marker.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                Spacer()

                Text(marker.status.rawValue.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.13), in: Capsule())
            }

            Text("\(marker.value) \(marker.unit)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)

            if !marker.reference.isEmpty {
                Text("Reference: \(marker.reference)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SomatiqColor.textTertiary)
            }

            if !marker.comment.isEmpty {
                Text(marker.comment)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 0.7)
                )
        )
    }

    private func markerTint(for status: LabMarkerStatus) -> Color {
        switch status {
        case .optimal:
            return SomatiqColor.success
        case .watch:
            return SomatiqColor.warning
        case .attention:
            return SomatiqColor.danger
        case .unknown:
            return SomatiqColor.textMuted
        }
    }

    private var evaluateButtonTitle: String {
        switch record.aiStatus {
        case .pending:
            return "Run AI evaluation"
        case .analyzing:
            return "Analyzing..."
        case .ready:
            return "Re-run AI evaluation"
        case .failed:
            return "Retry AI evaluation"
        }
    }

    private var isBusy: Bool {
        isEvaluating || record.aiStatus == .analyzing
    }

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

    private var statusChip: some View {
        Text(statusMeta.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(statusMeta.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusMeta.tint.opacity(0.12), in: Capsule())
    }

    @MainActor
    private func runEvaluation() async {
        guard !isBusy else { return }
        isEvaluating = true
        defer { isEvaluating = false }

        do {
            let service = LabAnalysisService(context: modelContext, modelManager: modelManager)
            try await service.evaluate(record: record)
        } catch {
            alertMessage = AppErrorMapper.userMessage(
                for: error,
                fallback: "AI evaluation failed."
            )
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

private struct LabAnalysisPDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context _: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context _: Context) {
        if uiView.document == nil {
            uiView.document = PDFDocument(data: data)
        }
    }
}
