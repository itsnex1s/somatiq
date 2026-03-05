import Foundation

@MainActor
final class AIConversationStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadMessages() throws -> [AIChatMessage] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        let snapshot = try decoder.decode(AIConversationSnapshot.self, from: data)
        return snapshot.messages
    }

    func saveMessages(_ messages: [AIChatMessage]) throws {
        let snapshot = AIConversationSnapshot(messages: messages)
        let data = try encoder.encode(snapshot)

        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return base
            .appendingPathComponent("Somatiq", isDirectory: true)
            .appendingPathComponent("ai_chat_history.json", isDirectory: false)
    }
}
