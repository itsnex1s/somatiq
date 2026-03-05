import Foundation
import Observation

@MainActor
@Observable
final class AIChatViewModel {
    var messages: [AIChatMessage] = []
    var draft = ""
    var isGenerating = false
    var errorMessage: String?
    var modelStatus: AIModelStatus = .initial
    var requiresInitialDownload = true

    private let store: AIConversationStore
    private let modelManager: AIModelManager
    private let chatService: AIChatService
    private let dashboardService: DashboardDataService

    private var hasLoaded = false
    private var modelStatusTask: Task<Void, Never>?

    init(
        store: AIConversationStore,
        modelManager: AIModelManager,
        chatService: AIChatService,
        dashboardService: DashboardDataService
    ) {
        self.store = store
        self.modelManager = modelManager
        self.chatService = chatService
        self.dashboardService = dashboardService
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        do {
            messages = try store.loadMessages().map { message in
                var normalized = message
                normalized.isStreaming = false
                return normalized
            }
        } catch {
            AppLog.error("AIChatViewModel.loadMessages", error: error)
            errorMessage = "Couldn't load chat history."
            messages = []
        }

        await observeModelStatus()

        requiresInitialDownload = await modelManager.requiresInitialDownload()
        if !requiresInitialDownload {
            await modelManager.warmupIfPrepared()
        }
    }

    func prepareModel() async {
        errorMessage = nil

        do {
            try await modelManager.prepareModel()
            requiresInitialDownload = false
        } catch {
            AppLog.error("AIChatViewModel.prepareModel", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func cancelModelPreparation() async {
        await modelManager.cancelPreparation()
    }

    func send() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isGenerating else { return }
        guard modelStatus.phase == .ready else {
            errorMessage = "Download and prepare the model first."
            return
        }

        errorMessage = nil
        isGenerating = true

        let userMessage = AIChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        draft = ""

        let assistantId = UUID()
        messages.append(
            AIChatMessage(
                id: assistantId,
                role: .assistant,
                text: "",
                isStreaming: true
            )
        )

        await persistMessages()

        do {
            let history = messages.filter { $0.id != assistantId }
            let healthContext = await buildHealthContext()
            let stream = try await chatService.generateResponseStream(
                history: history,
                userInput: trimmed,
                healthContext: healthContext
            )

            for try await chunk in stream {
                if let index = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[index].text += chunk
                }
            }

            if let index = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[index].isStreaming = false
            }
        } catch {
            if let index = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[index].isStreaming = false
                if messages[index].text.isEmpty {
                    messages[index].text = "Couldn't generate a response. Try again."
                }
            }

            if (error as? AIModelError) != .generationCancelled {
                AppLog.error("AIChatViewModel.send", error: error)
                errorMessage = error.localizedDescription
            }
        }

        await persistMessages()
        isGenerating = false
    }

    func stopGeneration() async {
        await chatService.cancelGeneration()
        isGenerating = false
    }

    private func observeModelStatus() async {
        modelStatusTask?.cancel()
        let stream = await modelManager.statusStream()

        modelStatusTask = Task { [weak self] in
            guard let self else { return }
            for await status in stream {
                await MainActor.run {
                    self.modelStatus = status
                    if status.phase == .ready {
                        self.requiresInitialDownload = false
                    }
                }
            }
        }
    }

    private func persistMessages() async {
        do {
            let normalized = messages.map { message in
                var copy = message
                copy.isStreaming = false
                return copy
            }
            try store.saveMessages(normalized)
        } catch {
            AppLog.error("AIChatViewModel.persistMessages", error: error)
        }
    }

    private func buildHealthContext() async -> String {
        do {
            let snapshot = try await dashboardService.fetchSnapshot(forceRecalculate: false)
            let reports = snapshot.reports.prefix(4)
            let reportText = reports.map { report in
                "- \(report.createdAt.formatted(.dateTime.hour().minute())) \(report.headline): \(report.body)"
            }.joined(separator: "\n")

            return """
            Today scores:
            - Battery: \(snapshot.today.bodyBatteryScore)
            - Stress: \(snapshot.today.stressScore)
            - Sleep: \(snapshot.today.sleepScore)
            - Heart: \(Int(snapshot.today.avgSDNN.rounded())) ms

            Latest reports:
            \(reportText.isEmpty ? "- none yet" : reportText)
            """
        } catch {
            return "No reliable health context available right now."
        }
    }
}
