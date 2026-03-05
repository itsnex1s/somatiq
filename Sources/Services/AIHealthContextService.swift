import Foundation

@MainActor
protocol AIHealthContextProviding: AnyObject {
    func currentContext() async -> String
}

@MainActor
final class AIHealthContextService: AIHealthContextProviding {
    private let snapshotProvider: any DashboardSnapshotProviding

    init(snapshotProvider: any DashboardSnapshotProviding) {
        self.snapshotProvider = snapshotProvider
    }

    func currentContext() async -> String {
        do {
            guard let snapshot = try snapshotProvider.fetchCachedSnapshot() else {
                return "No reliable health context available right now."
            }

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
