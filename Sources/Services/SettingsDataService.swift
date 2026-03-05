import Foundation
import SwiftData
import WatchConnectivity

enum AppleWatchIntegrationState: Sendable {
    case unavailable
    case checking
    case notPaired
    case paired
    case connected
}

struct AppleWatchIntegrationStatus {
    let state: AppleWatchIntegrationState
    let title: String
    let hint: String
}

enum HealthReconnectResult {
    case syncedWithData(lastSyncAt: Date)
    case connectedNoData
}

protocol AppleWatchStatusProviding: Sendable {
    func currentStatus() -> AppleWatchIntegrationStatus
}

struct AppleWatchStatusService: AppleWatchStatusProviding {
    func currentStatus() -> AppleWatchIntegrationStatus {
        guard WCSession.isSupported() else {
            return AppleWatchIntegrationStatus(
                state: .unavailable,
                title: "Unavailable",
                hint: "Watch connectivity is unavailable on this iPhone."
            )
        }

        let session = WCSession.default
        if session.activationState != .activated {
            session.activate()
            return AppleWatchIntegrationStatus(
                state: .checking,
                title: "Checking…",
                hint: "Checking Apple Watch pairing status. Keep Bluetooth enabled."
            )
        }

        guard session.isPaired else {
            return AppleWatchIntegrationStatus(
                state: .notPaired,
                title: "Not paired",
                hint: "Pair an Apple Watch to collect HRV and detailed sleep stages."
            )
        }

        if session.isReachable {
            return AppleWatchIntegrationStatus(
                state: .connected,
                title: "Connected",
                hint: "Apple Watch is paired and currently reachable."
            )
        }

        return AppleWatchIntegrationStatus(
            state: .paired,
            title: "Paired",
            hint: "Watch is paired. Keep it unlocked and on your wrist for faster Health sync."
        )
    }
}

@MainActor
final class SettingsDataService {
    private let storage: StorageService
    private let healthDataProvider: any HealthDataProviding
    private let watchStatusProvider: any AppleWatchStatusProviding
    private let dashboardService: DashboardDataService?

    init(
        context: ModelContext,
        healthDataProvider: any HealthDataProviding = HealthKitService(),
        watchStatusProvider: any AppleWatchStatusProviding = AppleWatchStatusService(),
        dashboardService: DashboardDataService? = nil
    ) {
        storage = StorageService(context: context)
        self.healthDataProvider = healthDataProvider
        self.watchStatusProvider = watchStatusProvider
        self.dashboardService = dashboardService
    }

    func loadPreferences() throws -> UserPreferences {
        try storage.fetchPreferences()
    }

    func savePreferences(_ preferences: UserPreferences) throws {
        try storage.savePreferences(preferences)
    }

    @discardableResult
    func reconnectHealth() async throws -> HealthReconnectResult {
        try await healthDataProvider.authorizeAndEnableBackgroundDelivery()

        guard let dashboardService else {
            return .connectedNoData
        }

        do {
            _ = try await dashboardService.recalculateToday(
                requestAuthorization: false,
                energySource: "settings_reconnect"
            )
            let syncDate = Date()
            try storage.markHealthSync(at: syncDate)
            return .syncedWithData(lastSyncAt: syncDate)
        } catch let healthError as HealthKitError where healthError == .noData || healthError == .noRecentWatchData {
            return .connectedNoData
        }
    }

    func appleWatchStatus() -> AppleWatchIntegrationStatus {
        watchStatusProvider.currentStatus()
    }
}
