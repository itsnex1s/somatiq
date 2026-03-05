import BackgroundTasks
import UIKit
import WatchConnectivity

final class SomatiqAppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTaskIdentifier = "com.bioself.somatiq.refresh"
    private let watchSessionDelegate = WatchSessionDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureWatchSession()
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

    private func configureWatchSession() {
        guard WCSession.isSupported() else {
            return
        }
        let session = WCSession.default
        session.delegate = watchSessionDelegate
        session.activate()
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
                let dashboardService = DashboardDataService(
                    context: container.mainContext,
                    reportNotifier: LocalReportNotificationService()
                )

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

private final class WatchSessionDelegate: NSObject, WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            AppLog.error("WatchSessionDelegate.activationDidComplete", error: error)
            return
        }
        AppLog.info("Watch session activation state: \(activationState.rawValue)")
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        AppLog.info("Watch session became inactive.")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        AppLog.info("Watch session deactivated. Re-activating.")
        session.activate()
    }
}
