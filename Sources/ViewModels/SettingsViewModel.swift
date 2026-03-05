import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    var name: String = ""
    var birthYear: Int?
    var targetSleepHours: Double = 8
    var lastSyncText: String = "Never"
    var errorMessage: String?
    var isSaving = false
    var isAuthorizing = false

    private let settingsService: SettingsDataService
    private var preferences: UserPreferences?

    init(settingsService: SettingsDataService) {
        self.settingsService = settingsService
    }

    func load() {
        do {
            let preferences = try settingsService.loadPreferences()
            self.preferences = preferences
            name = preferences.name
            birthYear = preferences.birthYear
            targetSleepHours = preferences.targetSleepHours
            lastSyncText = format(date: preferences.lastSyncAt)
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
        defer { isAuthorizing = false }

        do {
            try await settingsService.reconnectHealth()
        } catch {
            AppLog.error("SettingsViewModel.reconnectHealth", error: error)
            errorMessage = AppErrorMapper.userMessage(for: error)
        }
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
