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

    init(
        modelContext: ModelContext,
        healthDataProvider: any HealthDataProviding = HealthKitService()
    ) {
        self.healthDataProvider = healthDataProvider
        aiModelManager = AIModelManager()
        aiChatService = AIChatService(modelManager: aiModelManager)
        aiConversationStore = AIConversationStore()
        dashboardService = DashboardDataService(
            context: modelContext,
            healthDataProvider: healthDataProvider,
            reportNotifier: LocalReportNotificationService()
        )
        trendsService = TrendsDataService(context: modelContext)
        settingsService = SettingsDataService(
            context: modelContext,
            healthDataProvider: healthDataProvider,
            dashboardService: dashboardService
        )
    }
}
