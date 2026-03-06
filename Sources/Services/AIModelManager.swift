import Foundation

#if canImport(MLX) && os(macOS)
import MLX
#endif

#if canImport(MLXLLM) && canImport(MLXLMCommon) && os(macOS) && !targetEnvironment(simulator)
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
        title: "On-device AI",
        detail: "Preparing on-device AI setup.",
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

enum AIModelProfile: String, Sendable {
    case primary
    case compact

    var modelRepo: String {
        switch self {
        case .primary:
            return "mlx-community/Qwen3.5-9B-MLX-4bit"
        case .compact:
            return "mlx-community/Qwen3.5-0.9B-MLX-4bit"
        }
    }

    var modelName: String {
        switch self {
        case .primary:
            return "Qwen 3.5 9B"
        case .compact:
            return "Qwen 3.5 0.9B"
        }
    }

    var preparedDefaultsKey: String {
        switch self {
        case .primary:
            return "somatiq.ai.qwen9.prepared"
        case .compact:
            return "somatiq.ai.qwen0_9.prepared"
        }
    }

    var maxTokens: Int {
        switch self {
        case .primary:
            return 520
        case .compact:
            return 440
        }
    }

    var initialDetail: String {
        switch self {
        case .primary:
            return "Download once to run private on-device AI chat."
        case .compact:
            return "Compact on-device model recommended for this device."
        }
    }
}

actor AIModelManager {
    private static let primaryModelMinMemoryBytes: UInt64 = 10 * 1_024 * 1_024 * 1_024
    private let modelProfile: AIModelProfile

    private struct FallbackSnapshot {
        let userInput: String
        let battery: Int?
        let stress: Int?
        let sleep: Int?
        let heart: Int?
        let confidence: Int?
        let qualityReason: String?
        let latestReports: [String]
    }

    private enum FallbackIntent {
        case battery
        case stress
        case sleep
        case heart
        case actionPlan
        case summary
        case unknown
    }

    private var status: AIModelStatus
    private var observers: [UUID: AsyncStream<AIModelStatus>.Continuation] = [:]
    private var preparationTask: Task<Void, Error>?
    private var generationTask: Task<Void, Never>?

#if canImport(MLXLLM) && canImport(MLXLMCommon) && os(macOS) && !targetEnvironment(simulator)
    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
#endif

    init() {
        modelProfile = Self.recommendedProfile()

        if UserDefaults.standard.bool(forKey: modelProfile.preparedDefaultsKey) {
            status = AIModelStatus(
                phase: .preparing,
                progress: 0,
                title: modelProfile.modelName,
                detail: "Preparing local runtime...",
                errorText: nil
            )
        } else {
            status = AIModelStatus(
                phase: .notDownloaded,
                progress: 0,
                title: modelProfile.modelName,
                detail: modelProfile.initialDetail,
                errorText: nil
            )
        }
    }

    private static func recommendedProfile() -> AIModelProfile {
#if os(iOS)
        #if targetEnvironment(simulator)
        return .compact
        #else
        let memory = ProcessInfo.processInfo.physicalMemory
        return memory >= primaryModelMinMemoryBytes ? .primary : .compact
        #endif
#else
        return .primary
#endif
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
        !UserDefaults.standard.bool(forKey: modelProfile.preparedDefaultsKey)
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
                        detail: "Downloading \(modelProfile.modelName)...",
                        errorText: nil
                    )
                }

#if canImport(MLXLLM) && canImport(MLXLMCommon) && os(macOS) && !targetEnvironment(simulator)
                let config = ModelConfiguration(id: modelProfile.modelRepo)
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
                        maxTokens: modelProfile.maxTokens,
                        temperature: 0.45,
                        topP: 0.9
                    )
                )
                modelContainer = container

#if canImport(MLX) && os(macOS)
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
                        detail: hasPreparedBefore ? "Preparing local runtime..." : "Downloading \(modelProfile.modelName)...",
                        errorText: nil
                    )
                }
#endif

                UserDefaults.standard.set(true, forKey: modelProfile.preparedDefaultsKey)
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

#if canImport(MLXLLM) && canImport(MLXLMCommon) && os(macOS) && !targetEnvironment(simulator)
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
            title: modelProfile.modelName,
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
            detail: wasCached ? "Preparing local runtime..." : "Downloading \(modelProfile.modelName)...",
            errorText: nil
        )
    }

#if canImport(MLXLLM) && canImport(MLXLMCommon) && os(macOS) && !targetEnvironment(simulator)
    private static let systemInstructions = """
    You are Somatiq AI, a concise non-medical wellbeing assistant.
    Use only the supplied health context and user messages.
    Never present diagnosis. Keep answers practical and short.
    """
#endif

    private func fallbackResponse(for prompt: String) -> String {
        let snapshot = parseFallbackSnapshot(from: prompt)
        let intent = detectFallbackIntent(from: snapshot.userInput)

        switch intent {
        case .stress:
            return stressFallbackResponse(snapshot)
        case .battery:
            return batteryFallbackResponse(snapshot)
        case .sleep:
            return sleepFallbackResponse(snapshot)
        case .heart:
            return heartFallbackResponse(snapshot)
        case .actionPlan:
            return actionPlanFallbackResponse(snapshot)
        case .summary:
            return summaryFallbackResponse(snapshot)
        case .unknown:
            if snapshot.userInput.isEmpty {
                return summaryFallbackResponse(snapshot)
            }
            return """
            I can answer this better with your current metrics. Right now: Battery \(formattedMetric(snapshot.battery))/100, Stress \(formattedMetric(snapshot.stress))/100, Sleep \(formattedMetric(snapshot.sleep))/100, HRV \(formattedMetric(snapshot.heart)) ms. Ask me about battery, stress, sleep, HRV, or what to optimize next.
            """
        }
    }

    private func parseFallbackSnapshot(from prompt: String) -> FallbackSnapshot {
        let healthContext = extractPromptSection(
            in: prompt,
            marker: "HEALTH_CONTEXT",
            nextMarkers: ["RECENT_MESSAGES"]
        )
        let userInput = extractPromptSection(
            in: prompt,
            marker: "CURRENT_USER_MESSAGE",
            nextMarkers: ["RESPONSE_POLICY"]
        ).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        let reportsPart = healthContext
            .components(separatedBy: "Latest reports:")
            .dropFirst()
            .joined(separator: " ")

        let latestReports = reportsPart
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("- ") && !$0.localizedCaseInsensitiveContains("none yet") }
            .map { String($0.dropFirst(2)) }
            .prefix(3)
            .map { $0 }

        return FallbackSnapshot(
            userInput: userInput,
            battery: parseMetric(named: "Battery", in: healthContext),
            stress: parseMetric(named: "Stress", in: healthContext),
            sleep: parseMetric(named: "Sleep", in: healthContext),
            heart: parseMetric(named: "Heart", in: healthContext),
            confidence: parseMetric(named: "Confidence", in: healthContext),
            qualityReason: parseTextMetric(named: "Quality reason", in: healthContext),
            latestReports: Array(latestReports)
        )
    }

    private func detectFallbackIntent(from input: String) -> FallbackIntent {
        let text = input.lowercased()
        if text.isEmpty {
            return .summary
        }
        if text.contains("stress") || text.contains("стресс") || text.contains("нерв") {
            return .stress
        }
        if text.contains("battery") || text.contains("energy") || text.contains("батар") || text.contains("энерг") {
            return .battery
        }
        if text.contains("sleep") || text.contains("сон") {
            return .sleep
        }
        if text.contains("hrv") || text.contains("heart") || text.contains("серд") || text.contains("пульс") {
            return .heart
        }
        if text.contains("what should") || text.contains("what to do") || text.contains("plan")
            || text.contains("оптимиз") || text.contains("что делать") || text.contains("как улучш") {
            return .actionPlan
        }
        if text.contains("summary") || text.contains("overall") || text.contains("status")
            || text.contains("как я") || text.contains("что со мной") {
            return .summary
        }
        return .unknown
    }

    private func stressFallbackResponse(_ snapshot: FallbackSnapshot) -> String {
        guard let stress = snapshot.stress else {
            return "I can’t read enough stress data yet. Keep the watch on and refresh again in a few minutes."
        }

        let label: String
        if stress >= 70 {
            label = "high"
        } else if stress >= 45 {
            label = "moderate"
        } else {
            label = "low"
        }

        var advice = "Take a 3–5 minute breathing reset, then keep the next hour low-intensity."
        if stress < 45 {
            advice = "Stress looks controlled. This is a good slot for focused work."
        } else if stress >= 70 {
            advice = "Delay heavy decisions for 20–30 minutes and avoid extra caffeine right now."
        }

        return "Stress is \(stress)/100 (\(label)). \(advice)"
    }

    private func batteryFallbackResponse(_ snapshot: FallbackSnapshot) -> String {
        guard let battery = snapshot.battery else {
            return "Battery data is not ready yet. Open Today once more after Health sync."
        }

        let label: String
        if battery >= 70 {
            label = "high"
        } else if battery >= 40 {
            label = "medium"
        } else {
            label = "low"
        }

        let stressPart = snapshot.stress.map { "Current stress is \($0)/100." } ?? ""
        let recommendation: String
        if battery < 40 {
            recommendation = "Protect recovery: light activity, hydration, and shorter cognitive blocks."
        } else if battery >= 70 {
            recommendation = "You can schedule your hardest task now."
        } else {
            recommendation = "Stay in moderate load and re-check in 2–3 hours."
        }

        return "Body Battery is \(battery)/100 (\(label)). \(stressPart) \(recommendation)"
    }

    private func sleepFallbackResponse(_ snapshot: FallbackSnapshot) -> String {
        guard let sleep = snapshot.sleep else {
            return "Sleep score is unavailable yet; it appears after enough overnight data is synced."
        }

        let label: String
        if sleep >= 75 {
            label = "strong"
        } else if sleep >= 55 {
            label = "fair"
        } else {
            label = "weak"
        }

        return "Sleep is \(sleep)/100 (\(label)). In Somatiq, sleep is based on the completed night and stays stable during the day; daytime updates mostly affect stress and battery."
    }

    private func heartFallbackResponse(_ snapshot: FallbackSnapshot) -> String {
        guard let heart = snapshot.heart else {
            return "HRV is not available right now. Keep Apple Watch data synced and check again."
        }

        let interpretation: String
        if heart >= 65 {
            interpretation = "recovery signal is strong"
        } else if heart >= 40 {
            interpretation = "recovery is moderate"
        } else {
            interpretation = "recovery is suppressed"
        }

        return "Night HRV is \(heart) ms, so \(interpretation). Use this together with stress and battery before planning load."
    }

    private func actionPlanFallbackResponse(_ snapshot: FallbackSnapshot) -> String {
        let stress = snapshot.stress ?? 50
        let battery = snapshot.battery ?? 50
        let sleep = snapshot.sleep ?? 50

        var actions: [String] = []
        if stress >= 70 {
            actions.append("Run a 5-minute downshift before the next work block.")
        } else {
            actions.append("Start with one 45–60 minute focused block.")
        }

        if battery < 40 || sleep < 55 {
            actions.append("Keep training light today and prioritize earlier sleep.")
        } else {
            actions.append("You can keep normal training volume.")
        }

        return "Action plan based on current signals (Battery \(battery), Stress \(stress), Sleep \(sleep)): \(actions.joined(separator: " "))"
    }

    private func summaryFallbackResponse(_ snapshot: FallbackSnapshot) -> String {
        let headline = "Current snapshot: Battery \(formattedMetric(snapshot.battery))/100, Stress \(formattedMetric(snapshot.stress))/100, Sleep \(formattedMetric(snapshot.sleep))/100, HRV \(formattedMetric(snapshot.heart)) ms."
        let confidence = snapshot.confidence.map { " Confidence \($0)%." } ?? ""
        let quality = snapshot.qualityReason.map { " Quality: \($0)." } ?? ""
        let report = snapshot.latestReports.first.map { " Latest signal: \($0)." } ?? ""
        return "\(headline)\(confidence)\(quality)\(report)"
    }

    private func extractPromptSection(in text: String, marker: String, nextMarkers: [String]) -> String {
        guard let markerRange = text.range(of: marker) else {
            return ""
        }

        let afterMarker = text[markerRange.upperBound...]
        let sectionStart = afterMarker.startIndex

        var sectionEnd = afterMarker.endIndex
        for nextMarker in nextMarkers {
            if let nextRange = afterMarker.range(of: nextMarker), nextRange.lowerBound < sectionEnd {
                sectionEnd = nextRange.lowerBound
            }
        }

        return String(afterMarker[sectionStart..<sectionEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseMetric(named name: String, in text: String) -> Int? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?i)\(escapedName):\\s*(\\d{1,3})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[valueRange])
    }

    private func parseTextMetric(named name: String, in text: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?i)\(escapedName):\\s*([^\\n]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = text[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func formattedMetric(_ value: Int?) -> String {
        guard let value else { return "--" }
        return String(value)
    }
}
