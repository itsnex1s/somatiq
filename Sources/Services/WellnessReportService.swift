import Foundation
import UIKit
import UserNotifications

enum WellnessReportTrigger: String, CaseIterable {
    case firstCheckin
    case stressSpike
    case batteryLow
    case sleepDebt
    case hrvDrop
    case notableShift
}

@MainActor
final class WellnessReportService {
    private let storage: StorageService
    private let maxReportsPerDay = 3
    private let minimumInterval: TimeInterval = 3 * 60 * 60

    init(storage: StorageService) {
        self.storage = storage
    }

    func fetchRecentReports(limit: Int = 120) throws -> [WellnessReport] {
        try storage.fetchWellnessReports(limit: limit)
    }

    func generateReportIfNeeded(for score: DailyScore, source: String) throws -> WellnessReport? {
        let now = Date()
        let reportsToday = try storage.fetchWellnessReports(on: now)

        guard reportsToday.count < maxReportsPerDay else {
            return nil
        }

        let previous = reportsToday.first
        guard let trigger = resolveTrigger(current: score, previous: previous, now: now) else {
            return nil
        }

        let report = WellnessReport(
            createdAt: now,
            triggerType: trigger.rawValue,
            headline: headline(for: trigger),
            body: body(for: trigger, score: score, previous: previous),
            stressScore: score.stressScore,
            sleepScore: score.sleepScore,
            bodyBatteryScore: score.bodyBatteryScore,
            heartScore: Int(score.avgSDNN.rounded()),
            source: source
        )
        try storage.insertWellnessReport(report)
        return report
    }

    private func resolveTrigger(
        current: DailyScore,
        previous: WellnessReport?,
        now: Date
    ) -> WellnessReportTrigger? {
        guard let previous else {
            return .firstCheckin
        }

        guard now.timeIntervalSince(previous.createdAt) >= minimumInterval else {
            return nil
        }

        let currentHeart = Int(current.avgSDNN.rounded())

        if current.stressScore >= 72, previous.stressScore < 72 {
            return .stressSpike
        }
        if current.bodyBatteryScore <= 35, previous.bodyBatteryScore > 35 {
            return .batteryLow
        }
        if current.sleepScore <= 45, previous.sleepScore > 45 {
            return .sleepDebt
        }
        if currentHeart > 0, currentHeart <= 35, previous.heartScore > 35 {
            return .hrvDrop
        }

        let stressDelta = abs(current.stressScore - previous.stressScore)
        let sleepDelta = abs(current.sleepScore - previous.sleepScore)
        let batteryDelta = abs(current.bodyBatteryScore - previous.bodyBatteryScore)
        let heartDelta = abs(currentHeart - previous.heartScore)

        if stressDelta >= 12 || sleepDelta >= 10 || batteryDelta >= 12 || heartDelta >= 8 {
            return .notableShift
        }

        return nil
    }

    private func headline(for trigger: WellnessReportTrigger) -> String {
        switch trigger {
        case .firstCheckin:
            return "Daily Check-in"
        case .stressSpike:
            return "Stress Increased"
        case .batteryLow:
            return "Battery Is Low"
        case .sleepDebt:
            return "Sleep Debt Signal"
        case .hrvDrop:
            return "HRV Dropped"
        case .notableShift:
            return "Body State Updated"
        }
    }

    private func body(
        for trigger: WellnessReportTrigger,
        score: DailyScore,
        previous: WellnessReport?
    ) -> String {
        switch trigger {
        case .firstCheckin:
            return score.insightText.isEmpty ? "First summary for today is ready." : score.insightText
        case .stressSpike:
            return "Stress moved into a higher zone. Consider a short reset break."
        case .batteryLow:
            return "Body battery fell to a low zone. Keep load lighter for now."
        case .sleepDebt:
            return "Sleep recovery is below target. Prioritize earlier bedtime tonight."
        case .hrvDrop:
            return "HRV dropped below your comfortable range. Keep intensity moderate."
        case .notableShift:
            let metric = dominantShiftMetric(score: score, previous: previous)
            let insight = score.insightText.isEmpty ? "There is a visible shift versus the previous check-in." : score.insightText
            return "\(metric) changed noticeably. \(insight)"
        }
    }

    private func dominantShiftMetric(score: DailyScore, previous: WellnessReport?) -> String {
        guard let previous else { return "Body state" }

        let heartScore = Int(score.avgSDNN.rounded())
        let deltas: [(name: String, value: Int)] = [
            ("Stress", abs(score.stressScore - previous.stressScore)),
            ("Sleep", abs(score.sleepScore - previous.sleepScore)),
            ("Battery", abs(score.bodyBatteryScore - previous.bodyBatteryScore)),
            ("Heart", abs(heartScore - previous.heartScore)),
        ]
        return deltas.max(by: { $0.value < $1.value })?.name ?? "Body state"
    }
}

protocol ReportNotifying: Sendable {
    func notify(report: WellnessReport) async
}

struct NoopReportNotificationService: ReportNotifying {
    func notify(report: WellnessReport) async {
        _ = report
    }
}

struct LocalReportNotificationService: ReportNotifying {
    func notify(report: WellnessReport) async {
        let isActive = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        if isActive {
            return
        }

        let center = UNUserNotificationCenter.current()
        let settings = await notificationSettings(from: center)

        let authorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorized = true
        case .notDetermined:
            do {
                authorized = try await requestAuthorization(from: center)
            } catch {
                AppLog.error("LocalReportNotificationService.requestAuthorization", error: error)
                return
            }
        case .denied:
            authorized = false
        @unknown default:
            authorized = false
        }

        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = report.headline
        content.body = report.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "wellness-report-\(report.id.uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await addRequest(request, center: center)
        } catch {
            AppLog.error("LocalReportNotificationService.addRequest", error: error)
        }
    }

    private func notificationSettings(from center: UNUserNotificationCenter) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorization(from center: UNUserNotificationCenter) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: granted)
            }
        }
    }

    private func addRequest(_ request: UNNotificationRequest, center: UNUserNotificationCenter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }
}
