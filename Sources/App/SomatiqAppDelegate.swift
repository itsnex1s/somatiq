import BackgroundTasks
import UIKit

final class SomatiqAppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTaskIdentifier = "com.bioself.somatiq.refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerBackgroundTasks()
        scheduleAppRefresh()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleAppRefresh()
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            self.handleRefreshTask(task: task as! BGAppRefreshTask)
        }
    }

    private func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleRefreshTask(task: BGAppRefreshTask) {
        scheduleAppRefresh()

        let workTask = Task { @MainActor in
            do {
                let container = try AppModelContainerFactory.makeContainer()
                let dashboardService = DashboardDataService(context: container.mainContext)

                _ = try await dashboardService.recalculateToday(
                    requestAuthorization: false,
                    energySource: "background_refresh"
                )
                AppLog.info("Background refresh completed.")
                task.setTaskCompleted(success: true)
            } catch let error as HealthKitError where error == .noData {
                AppLog.info("Background refresh skipped: no data.")
                task.setTaskCompleted(success: true)
            } catch {
                AppLog.error("SomatiqAppDelegate.handleRefreshTask", error: error)
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            workTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
