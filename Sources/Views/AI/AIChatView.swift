import SwiftUI

struct AIChatView: View {
    @State private var viewModel: AIChatViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showAnalyses = false
    @State private var isBottomVisible = true
    @State private var pendingNewMessages = 0

    private let bottomSentinelId = "ai-chat-bottom"

    init(
        dashboardService: DashboardDataService,
        conversationStore: AIConversationStore,
        modelManager: AIModelManager,
        chatService: AIChatService
    ) {
        _viewModel = State(
            initialValue: AIChatViewModel(
                store: conversationStore,
                modelManager: modelManager,
                chatService: chatService,
                dashboardService: dashboardService
            )
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SomatiqColor.bg.ignoresSafeArea()

            VStack(spacing: 12) {
                header

                if shouldShowSetupCard {
                    setupCard
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }

                messagesSection

                if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SomatiqColor.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                composer
            }
            .padding(.horizontal, SomatiqSpacing.pageHorizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if pendingNewMessages > 0 {
                Button {
                    pendingNewMessages = 0
                    NotificationCenter.default.post(name: Notification.Name("somatiq.ai.scrollToBottom"), object: nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                        Text("New")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(SomatiqColor.accent.opacity(0.85), in: Capsule())
                }
                .buttonStyle(.somatiqPressable)
                .padding(.trailing, 24)
                .padding(.bottom, 86)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .sheet(isPresented: $showAnalyses) {
            NavigationStack {
                AnalysesView()
                    .presentationBackground(SomatiqColor.bg)
            }
            .presentationBackground(SomatiqColor.bg)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(modelStatusColor)
                        .frame(width: 8, height: 8)

                    Text(modelStatusLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SomatiqColor.textTertiary)
                }
            }

            Spacer()

            Button {
                showAnalyses = true
            } label: {
                Label("Analyses", systemImage: "testtube.2")
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
    }

    private var setupCard: some View {
        GlassCard(tint: SomatiqColor.accent) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Set up on-device AI")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

                Text("Download Qwen 3.5 9B once (~5.2 GB). After setup, chat runs locally on your device.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.modelStatus.phase == .downloading || viewModel.modelStatus.phase == .preparing {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: viewModel.modelStatus.progress)
                            .tint(SomatiqColor.accent)

                        HStack {
                            Text(viewModel.modelStatus.detail)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SomatiqColor.textTertiary)
                            Spacer()
                            Text("\(Int(viewModel.modelStatus.progress * 100))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SomatiqColor.textSecondary)
                        }
                    }
                } else if let error = viewModel.modelStatus.errorText, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SomatiqColor.warning)
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            if viewModel.modelStatus.phase == .downloading || viewModel.modelStatus.phase == .preparing {
                                await viewModel.cancelModelPreparation()
                            } else {
                                await viewModel.prepareModel()
                            }
                        }
                    } label: {
                        Text(setupButtonTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(SomatiqColor.accent.opacity(0.85), in: Capsule())
                    }
                    .buttonStyle(.somatiqPressable)

                    Text("Required only on first AI launch.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SomatiqColor.textMuted)
                }
            }
        }
        .animation(SomatiqAnimation.stateSwap, value: viewModel.modelStatus)
    }

    private var messagesSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if viewModel.messages.isEmpty {
                        emptyState
                            .padding(.top, 24)
                    } else {
                        ForEach(viewModel.messages) { message in
                            AIMessageRow(message: message)
                                .id(message.id)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomSentinelId)
                        .onAppear {
                            isBottomVisible = true
                            pendingNewMessages = 0
                        }
                        .onDisappear {
                            isBottomVisible = false
                        }
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#111220"), Color(hex: "#0C0D16")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                    )
            )
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomSentinelId, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                guard newCount >= oldCount else { return }

                if isBottomVisible {
                    withAnimation(reduceMotion ? .linear(duration: 0.08) : SomatiqAnimation.sectionReveal) {
                        proxy.scrollTo(bottomSentinelId, anchor: .bottom)
                    }
                    pendingNewMessages = 0
                } else if newCount > oldCount {
                    pendingNewMessages += (newCount - oldCount)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("somatiq.ai.scrollToBottom"))) { _ in
                withAnimation(reduceMotion ? .linear(duration: 0.08) : SomatiqAnimation.sectionReveal) {
                    proxy.scrollTo(bottomSentinelId, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask about your health trends...", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SomatiqColor.textPrimary)
                .disabled(isComposerLocked)

            Button {
                if viewModel.isGenerating {
                    Task { await viewModel.stopGeneration() }
                } else {
                    Task { await viewModel.send() }
                }
            } label: {
                Image(systemName: viewModel.isGenerating ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        (viewModel.isGenerating ? SomatiqColor.warning : SomatiqColor.accent).opacity(0.9),
                        in: Circle()
                    )
            }
            .buttonStyle(.somatiqPressable)
            .disabled(sendButtonDisabled)
            .opacity(sendButtonDisabled ? 0.6 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(SomatiqColor.accent)
                .padding(12)
                .background(SomatiqColor.accent.opacity(0.14), in: Circle())

            Text("Ask AI about your body signals")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SomatiqColor.textPrimary)

            Text("Use simple questions like: Why is stress high today? What should I optimize tonight?")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SomatiqColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    private var shouldShowSetupCard: Bool {
        if viewModel.modelStatus.phase == .ready {
            return false
        }

        if viewModel.requiresInitialDownload {
            return true
        }

        return viewModel.modelStatus.phase == .preparing ||
            viewModel.modelStatus.phase == .downloading ||
            viewModel.modelStatus.phase == .failed
    }

    private var setupButtonTitle: String {
        switch viewModel.modelStatus.phase {
        case .downloading, .preparing:
            return "Cancel"
        case .failed:
            return "Retry"
        case .ready:
            return "Ready"
        case .notDownloaded:
            return "Download Qwen 3.5 9B"
        }
    }

    private var modelStatusLine: String {
        switch viewModel.modelStatus.phase {
        case .ready:
            return "Qwen 3.5 9B • Ready"
        case .downloading:
            return "Downloading model..."
        case .preparing:
            return "Preparing model..."
        case .failed:
            return "Model setup failed"
        case .notDownloaded:
            return "Model not downloaded"
        }
    }

    private var modelStatusColor: Color {
        switch viewModel.modelStatus.phase {
        case .ready:
            return SomatiqColor.success
        case .downloading, .preparing:
            return SomatiqColor.warning
        case .failed:
            return SomatiqColor.danger
        case .notDownloaded:
            return SomatiqColor.textMuted
        }
    }

    private var isComposerLocked: Bool {
        viewModel.modelStatus.phase != .ready || viewModel.isGenerating
    }

    private var sendButtonDisabled: Bool {
        if viewModel.isGenerating {
            return false
        }

        return isComposerLocked || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct AIMessageRow: View {
    let message: AIChatMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: .leading, spacing: 6) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SomatiqColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if message.isStreaming {
                    AIStreamingDots()
                }

                Text(timeText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(SomatiqColor.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .somatiqCardStyle(
                tint: message.role == .user ? SomatiqColor.accent : nil,
                cornerRadius: 16,
                shadowIntensity: .subtle
            )

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, 8)
    }

    private var timeText: String {
        message.createdAt.formatted(.dateTime.hour().minute())
    }
}

private struct AIStreamingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(phase == index ? SomatiqColor.accent : SomatiqColor.textMuted.opacity(0.5))
                    .frame(width: 6, height: 6)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(260))
                phase = (phase + 1) % 3
            }
        }
    }
}
