import SwiftData

@MainActor
final class AppDependencies {
    let healthDataProvider: any HealthDataProviding
    let dashboardService: DashboardDataService
    let trendsService: TrendsDataService
    let settingsService: SettingsDataService

    init(
        modelContext: ModelContext,
        healthDataProvider: any HealthDataProviding = HealthKitService()
    ) {
        self.healthDataProvider = healthDataProvider
        dashboardService = DashboardDataService(
            context: modelContext,
            healthDataProvider: healthDataProvider
        )
        trendsService = TrendsDataService(context: modelContext)
        settingsService = SettingsDataService(
            context: modelContext,
            healthDataProvider: healthDataProvider
        )
    }
}
