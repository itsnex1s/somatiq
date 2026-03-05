import Foundation

#if canImport(MLX)
import MLX
#endif

#if canImport(MLXLLM) && canImport(MLXLMCommon) && !targetEnvironment(simulator)
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon
#endif

enum AIModelPhase: String, Sendable {
    case notDownloaded
    case downloading
    case preparing
    case ready
    case failed
}

struct AIModelStatus: Equatable, Sendable {
    var phase: AIModelPhase
    var progress: Double
    var title: String
    var detail: String
    var errorText: String?

    static let initial = AIModelStatus(
        phase: .notDownloaded,
        progress: 0,
        title: "Qwen 3.5 9B",
        detail: "Download once to run private on-device AI chat.",
        errorText: nil
    )
}

enum AIModelError: LocalizedError, Equatable {
    case notReady
    case generationCancelled

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "AI model is not ready yet."
        case .generationCancelled:
            return "Generation was cancelled."
        }
    }
}

actor AIModelManager {
    private static let modelRepo = "mlx-community/Qwen3.5-9B-MLX-4bit"
    private static let modelName = "Qwen 3.5 9B"
    private static let preparedDefaultsKey = "somatiq.ai.qwen9.prepared"

    private var status: AIModelStatus
    private var observers: [UUID: AsyncStream<AIModelStatus>.Continuation] = [:]
    private var preparationTask: Task<Void, Error>?
    private var generationTask: Task<Void, Never>?

#if canImport(MLXLLM) && canImport(MLXLMCommon) && !targetEnvironment(simulator)
    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
#endif

    init() {
        if UserDefaults.standard.bool(forKey: Self.preparedDefaultsKey) {
            status = AIModelStatus(
                phase: .preparing,
                progress: 0,
                title: Self.modelName,
                detail: "Preparing local runtime...",
                errorText: nil
            )
        } else {
            status = AIModelStatus(
                phase: .notDownloaded,
                progress: 0,
                title: Self.modelName,
                detail: "Download once to run private on-device AI chat.",
                errorText: nil
            )
        }
    }

    func statusStream() -> AsyncStream<AIModelStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(status)
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeObserver(id) }
            }
        }
    }

    func currentStatus() -> AIModelStatus {
        status
    }

    func requiresInitialDownload() -> Bool {
        !UserDefaults.standard.bool(forKey: Self.preparedDefaultsKey)
    }

    func warmupIfPrepared() async {
        guard !requiresInitialDownload() else { return }
        guard status.phase != .ready else { return }

        do {
            try await prepareModel()
        } catch {
            AppLog.error("AIModelManager.warmupIfPrepared", error: error)
        }
    }

    func prepareModel() async throws {
        if status.phase == .ready {
            return
        }

        if let preparationTask {
            return try await preparationTask.value
        }

        let hasPreparedBefore = !requiresInitialDownload()
        let task = Task<Void, Error> {
            do {
                if hasPreparedBefore {
                    updateStatus(
                        phase: .preparing,
                        progress: 0.05,
                        detail: "Preparing local runtime...",
                        errorText: nil
                    )
                } else {
                    updateStatus(
                        phase: .downloading,
                        progress: 0.03,
                        detail: "Downloading Qwen 3.5 9B...",
                        errorText: nil
                    )
                }

#if canImport(MLXLLM) && canImport(MLXLMCommon) && !targetEnvironment(simulator)
                let config = ModelConfiguration(id: Self.modelRepo)
                let container = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
                    Task {
                        await self.handleModelProgress(progress: progress.fractionCompleted, wasCached: hasPreparedBefore)
                    }
                }

                updateStatus(
                    phase: .preparing,
                    progress: 0.94,
                    detail: "Preparing tokenizer and context...",
                    errorText: nil
                )

                chatSession = ChatSession(
                    container,
                    instructions: Self.systemInstructions,
                    generateParameters: GenerateParameters(
                        maxTokens: 520,
                        temperature: 0.45,
                        topP: 0.9
                    )
                )
                modelContainer = container

#if canImport(MLX)
                Memory.clearCache()
#endif
#else
                // Simulator / fallback runtime.
                var progress: Double = 0.06
                while progress < 0.92 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(160))
                    progress += 0.05
                    updateStatus(
                        phase: hasPreparedBefore ? .preparing : .downloading,
                        progress: min(progress, 0.92),
                        detail: hasPreparedBefore ? "Preparing local runtime..." : "Downloading Qwen 3.5 9B...",
                        errorText: nil
                    )
                }
#endif

                UserDefaults.standard.set(true, forKey: Self.preparedDefaultsKey)
                updateStatus(
                    phase: .ready,
                    progress: 1,
                    detail: "Model is ready.",
                    errorText: nil
                )
            } catch is CancellationError {
                updateStatus(
                    phase: requiresInitialDownload() ? .notDownloaded : .failed,
                    progress: 0,
                    detail: "Preparation cancelled.",
                    errorText: nil
                )
                throw AIModelError.generationCancelled
            } catch {
                updateStatus(
                    phase: .failed,
                    progress: 0,
                    detail: "Could not prepare model.",
                    errorText: error.localizedDescription
                )
                throw error
            }
        }

        preparationTask = task
        defer { preparationTask = nil }
        try await task.value
    }

    func cancelPreparation() {
        preparationTask?.cancel()
        preparationTask = nil
    }

    func generateStream(prompt: String) throws -> AsyncThrowingStream<String, Error> {
        guard status.phase == .ready else {
            throw AIModelError.notReady
        }

        generationTask?.cancel()

#if canImport(MLXLLM) && canImport(MLXLMCommon) && !targetEnvironment(simulator)
        guard let session = chatSession else {
            throw AIModelError.notReady
        }

        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task {
            do {
                let response = session.streamResponse(to: prompt)
                for try await chunk in response {
                    try Task.checkCancellation()
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: AIModelError.generationCancelled)
            } catch {
                continuation.finish(throwing: error)
            }
        }

        generationTask = task
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return stream
#else
        let response = fallbackResponse(for: prompt)
        let chunks = response.split(separator: " ").map { "\($0) " }
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        let task = Task {
            do {
                for chunk in chunks {
                    try Task.checkCancellation()
                    continuation.yield(chunk)
                    try await Task.sleep(for: .milliseconds(36))
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: AIModelError.generationCancelled)
            } catch {
                continuation.finish(throwing: error)
            }
        }

        generationTask = task
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return stream
#endif
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func updateStatus(
        phase: AIModelPhase,
        progress: Double,
        detail: String,
        errorText: String?
    ) {
        status = AIModelStatus(
            phase: phase,
            progress: Statistics.clamped(progress, min: 0, max: 1),
            title: Self.modelName,
            detail: detail,
            errorText: errorText
        )

        for continuation in observers.values {
            continuation.yield(status)
        }
    }

    private func handleModelProgress(progress: Double, wasCached: Bool) {
        let mappedProgress = wasCached
            ? (0.1 + progress * 0.8)
            : (0.03 + progress * 0.86)

        updateStatus(
            phase: wasCached ? .preparing : .downloading,
            progress: mappedProgress,
            detail: wasCached ? "Preparing local runtime..." : "Downloading Qwen 3.5 9B...",
            errorText: nil
        )
    }

#if canImport(MLXLLM) && canImport(MLXLMCommon) && !targetEnvironment(simulator)
    private static let systemInstructions = """
    You are Somatiq AI, a concise non-medical wellbeing assistant.
    Use only the supplied health context and user messages.
    Never present diagnosis. Keep answers practical and short.
    """
#endif

    private func fallbackResponse(for prompt: String) -> String {
        if prompt.lowercased().contains("stress") {
            return "Stress is elevated versus your recent baseline. Try a 5-minute downshift and reduce cognitive load for the next hour."
        }

        return "I can help interpret your trends and reports. Ask about battery, stress, sleep, or heart variability."
    }
}
