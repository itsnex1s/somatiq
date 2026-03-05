import SwiftData

@MainActor
final class AppDependencies {
    let healthDataProvider: any HealthDataProviding
    let dashboardService: DashboardDataService
    let trendsService: TrendsDataService
    let settingsService: SettingsDataService
    let aiModelManager: AIModelManager
    let aiChatService: AIChatService
    let aiConversationStore: AIConversationStore
    let aiHealthContextService: AIHealthContextService

    init(
        modelContext: ModelContext,
        healthDataProvider: any HealthDataProviding = HealthKitService()
    ) {
        self.healthDataProvider = healthDataProvider
        dashboardService = DashboardDataService(
            context: modelContext,
            healthDataProvider: healthDataProvider,
            reportNotifier: LocalReportNotificationService()
        )
        aiHealthContextService = AIHealthContextService(snapshotProvider: dashboardService)
        aiModelManager = AIModelManager()
        aiChatService = AIChatService(modelManager: aiModelManager)
        aiConversationStore = AIConversationStore()
        trendsService = TrendsDataService(context: modelContext)
        settingsService = SettingsDataService(
            context: modelContext,
            healthDataProvider: healthDataProvider,
            dashboardService: dashboardService
        )
    }
}
