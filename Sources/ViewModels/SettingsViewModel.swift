import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    var name: String = ""
    var birthYear: Int?
    var targetSleepHours: Double = 8
    var lastSyncText: String = "Never"
    var appleWatchStatusTitle: String = "--"
    var appleWatchStatusHint: String = ""
    var shouldShowWatchPairingHelp = false
    var errorMessage: String?
    var isSaving = false
    var isAuthorizing = false

    private let settingsService: SettingsDataService
    private var preferences: UserPreferences?
    private var watchStatusRefreshTask: Task<Void, Never>?

    init(settingsService: SettingsDataService) {
        self.settingsService = settingsService
    }

    func load() {
        do {
            errorMessage = nil
            let preferences = try settingsService.loadPreferences()
            self.preferences = preferences
            name = preferences.name
            birthYear = preferences.birthYear
            targetSleepHours = preferences.targetSleepHours
            lastSyncText = format(date: preferences.lastSyncAt)
            refreshWatchStatus()
        } catch {
            AppLog.error("SettingsViewModel.load", error: error)
            errorMessage = AppErrorMapper.userMessage(for: error)
        }
    }

    func save() {
        guard let preferences else {
            errorMessage = "Unable to save. Please reload the screen."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            preferences.name = name
            preferences.birthYear = birthYear
            preferences.targetSleepHours = targetSleepHours
            try settingsService.savePreferences(preferences)
            lastSyncText = format(date: preferences.lastSyncAt)
        } catch {
            AppLog.error("SettingsViewModel.save", error: error)
            errorMessage = AppErrorMapper.userMessage(for: error)
        }
    }

    func reconnectHealth() async {
        isAuthorizing = true
        errorMessage = nil
        defer { isAuthorizing = false }

        do {
            let reconnectResult = try await settingsService.reconnectHealth()
            refreshWatchStatus()
            switch reconnectResult {
            case let .syncedWithData(lastSyncAt):
                lastSyncText = format(date: lastSyncAt)
                NotificationCenter.default.post(
                    name: .healthReconnectDidComplete,
                    object: nil
                )
            case .connectedNoData:
                errorMessage = "Apple Health connected, but no readable samples were found yet. Open Health, confirm HRV/Sleep permissions, then pull to refresh on Today."
            }
        } catch {
            AppLog.error("SettingsViewModel.reconnectHealth", error: error)
            errorMessage = AppErrorMapper.userMessage(for: error)
        }
    }

    private func refreshWatchStatus() {
        let status = settingsService.appleWatchStatus()
        applyWatchStatus(status)

        guard status.state == .checking else {
            watchStatusRefreshTask?.cancel()
            watchStatusRefreshTask = nil
            return
        }

        watchStatusRefreshTask?.cancel()
        watchStatusRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else {
                return
            }
            let latestStatus = self.settingsService.appleWatchStatus()
            self.applyWatchStatus(latestStatus)
        }
    }

    private func applyWatchStatus(_ status: AppleWatchIntegrationStatus) {
        appleWatchStatusTitle = status.title
        appleWatchStatusHint = status.hint
        shouldShowWatchPairingHelp = status.state == .notPaired || status.state == .checking
    }

    private func format(date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(
            .dateTime
                .hour()
                .minute()
                .day()
                .month(.abbreviated)
        )
    }
}
