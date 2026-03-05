import Foundation
import SwiftData

@MainActor
final class SettingsDataService {
    private let storage: StorageService
    private let healthDataProvider: any HealthDataProviding

    init(
        context: ModelContext,
        healthDataProvider: any HealthDataProviding = HealthKitService()
    ) {
        storage = StorageService(context: context)
        self.healthDataProvider = healthDataProvider
    }

    func loadPreferences() throws -> UserPreferences {
        try storage.fetchPreferences()
    }

    func savePreferences(_ preferences: UserPreferences) throws {
        try storage.savePreferences(preferences)
    }

    func reconnectHealth() async throws {
        try await healthDataProvider.authorizeAndEnableBackgroundDelivery()
    }
}
