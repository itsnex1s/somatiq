import Foundation

actor AIChatService {
    private let modelManager: AIModelManager

    init(modelManager: AIModelManager) {
        self.modelManager = modelManager
    }

    func generateResponseStream(
        history: [AIChatMessage],
        userInput: String,
        healthContext: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let prompt = composePrompt(history: history, userInput: userInput, healthContext: healthContext)
        return try await modelManager.generateStream(prompt: prompt)
    }

    func cancelGeneration() async {
        await modelManager.cancelGeneration()
    }

    private func composePrompt(history: [AIChatMessage], userInput: String, healthContext: String) -> String {
        let recentHistory = history
            .suffix(8)
            .map { message in
                let role = message.role == .assistant ? "assistant" : "user"
                let text = String(message.text.prefix(550))
                return "\(role): \(text)"
            }
            .joined(separator: "\n")

        let safeInput = String(userInput.prefix(2000))

        return """
        HEALTH_CONTEXT
        \(healthContext)

        RECENT_MESSAGES
        \(recentHistory)

        CURRENT_USER_MESSAGE
        \(safeInput)

        RESPONSE_POLICY
        - Keep it concise and practical.
        - Non-medical guidance only.
        - Suggest 1-2 concrete next actions.
        """
    }
}
