import Foundation
import PDFKit
import SwiftData

enum LabAnalysisError: LocalizedError {
    case invalidPDF
    case noReadableText
    case serviceNotReady

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "Selected file is not a readable PDF."
        case .noReadableText:
            return "No readable text was found in this PDF."
        case .serviceNotReady:
            return "Analysis service is not ready."
        }
    }
}

@MainActor
final class LabAnalysisService {
    private let context: ModelContext
    private let modelManager: AIModelManager

    init(context: ModelContext, modelManager: AIModelManager) {
        self.context = context
        self.modelManager = modelManager
    }

    func importPDF(from url: URL) throws -> LabAnalysisRecord {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let document = PDFDocument(data: data) else {
            throw LabAnalysisError.invalidPDF
        }

        let rawText = normalizedText(document.string ?? "")
        guard !rawText.isEmpty else {
            throw LabAnalysisError.noReadableText
        }

        let fileName = url.lastPathComponent
        let record = LabAnalysisRecord(
            fileName: fileName,
            pdfData: data,
            extractedText: String(rawText.prefix(48_000))
        )
        context.insert(record)
        try context.save()
        return record
    }

    func evaluate(record: LabAnalysisRecord) async throws {
        record.aiStatus = .analyzing
        record.aiError = nil
        record.updatedAt = Date()
        try context.save()

        do {
            if await modelManager.currentStatus().phase != .ready {
                try await modelManager.prepareModel()
            }

            let stream = try await modelManager.generateStream(prompt: evaluationPrompt(for: record.extractedText))
            var response = ""
            for try await chunk in stream {
                response += chunk
            }

            if let decoded = decodeEvaluation(from: response) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.withoutEscapingSlashes]
                let payloadData = try encoder.encode(decoded)
                record.aiRawJSON = String(data: payloadData, encoding: .utf8)
                record.aiScore = Statistics.clamped(Double(decoded.overallScore), min: 0, max: 100).roundedInt()
                record.aiScoreLabel = decoded.overallLabel
                record.aiSummary = decoded.summary
            } else {
                // Fallback: keep plain response so the user still sees an AI interpretation.
                let plain = normalizedText(stripMarkdownCodeFence(response))
                record.aiRawJSON = nil
                record.aiScore = 50
                record.aiScoreLabel = "Needs review"
                record.aiSummary = plain.isEmpty
                    ? "AI returned an empty response. Try running evaluation again."
                    : String(plain.prefix(800))
                record.aiError = "Structured parsing fallback was used."
            }

            record.aiStatus = .ready
            record.aiEvaluatedAt = Date()
            record.updatedAt = Date()
            try context.save()
        } catch {
            record.aiStatus = .failed
            record.aiError = AppErrorMapper.userMessage(for: error)
            record.updatedAt = Date()
            try context.save()
            throw error
        }
    }

    private func evaluationPrompt(for extractedText: String) -> String {
        let trimmedInput = String(extractedText.prefix(20_000))
        return """
        You are Somatiq AI, a non-medical wellness assistant.
        Analyze the lab report text and return STRICT JSON only.

        OUTPUT JSON SCHEMA:
        {
          "overallScore": 0-100 integer,
          "overallLabel": "Optimal" | "Watch" | "Attention",
          "summary": "short practical summary",
          "keyFindings": ["finding 1", "finding 2"],
          "markers": [
            {
              "name": "marker name",
              "value": "reported value",
              "unit": "unit",
              "reference": "reference range or interval",
              "status": "optimal" | "watch" | "attention" | "unknown",
              "comment": "brief interpretation"
            }
          ]
        }

        RULES:
        - Do not provide diagnosis.
        - Keep comments concise and practical.
        - If data is missing, use "unknown" status.
        - Return valid JSON, no markdown fences.

        LAB_REPORT_TEXT:
        \(trimmedInput)
        """
    }

    private func decodeEvaluation(from rawResponse: String) -> LabEvaluationPayload? {
        let cleaned = stripMarkdownCodeFence(rawResponse)
        let json = extractJSONObject(from: cleaned) ?? cleaned
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LabEvaluationPayload.self, from: data)
    }

    private func stripMarkdownCodeFence(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return nil
        }
        guard start <= end else { return nil }
        return String(text[start...end])
    }

    private func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private extension Double {
    func roundedInt() -> Int {
        Int(self.rounded())
    }
}
