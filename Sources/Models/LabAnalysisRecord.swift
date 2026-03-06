import Foundation
import SwiftData

enum LabAIStatus: String, Codable, Sendable {
    case pending
    case analyzing
    case ready
    case failed
}

enum LabMarkerStatus: String, Codable, Sendable {
    case optimal
    case watch
    case attention
    case unknown
}

struct LabEvaluationMarker: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var value: String
    var unit: String
    var reference: String
    var status: LabMarkerStatus
    var comment: String

    var id: String {
        "\(name)|\(value)|\(unit)|\(reference)|\(status.rawValue)"
    }
}

struct LabEvaluationPayload: Codable, Hashable, Sendable {
    var overallScore: Int
    var overallLabel: String
    var summary: String
    var keyFindings: [String]
    var markers: [LabEvaluationMarker]
}

@Model
final class LabAnalysisRecord {
    var fileName: String
    var createdAt: Date
    var updatedAt: Date

    @Attribute(.externalStorage)
    var pdfData: Data
    var extractedText: String

    var aiStatusRaw: String
    var aiScore: Int
    var aiScoreLabel: String
    var aiSummary: String
    var aiRawJSON: String?
    var aiError: String?
    var aiEvaluatedAt: Date?

    init(
        fileName: String,
        pdfData: Data,
        extractedText: String,
        aiStatus: LabAIStatus = .pending
    ) {
        self.fileName = fileName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.pdfData = pdfData
        self.extractedText = extractedText
        aiStatusRaw = aiStatus.rawValue
        aiScore = 0
        aiScoreLabel = "Not evaluated"
        aiSummary = "Run AI evaluation to get a structured interpretation."
        aiRawJSON = nil
        aiError = nil
        aiEvaluatedAt = nil
    }

    var aiStatus: LabAIStatus {
        get { LabAIStatus(rawValue: aiStatusRaw) ?? .pending }
        set { aiStatusRaw = newValue.rawValue }
    }

    var parsedEvaluation: LabEvaluationPayload? {
        guard let aiRawJSON, !aiRawJSON.isEmpty else { return nil }
        guard let data = aiRawJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LabEvaluationPayload.self, from: data)
    }
}
