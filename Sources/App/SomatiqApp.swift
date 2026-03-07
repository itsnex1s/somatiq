import SwiftData
import SwiftUI

@main
struct SomatiqApp: App {
    @UIApplicationDelegateAdaptor(SomatiqAppDelegate.self) private var appDelegate

    private let sharedContainer: ModelContainer
    private let dependencies: AppDependencies

    @MainActor
    init() {
        do {
            let container = try AppModelContainerFactory.makeContainer()
            sharedContainer = container
            dependencies = AppDependencies(modelContext: container.mainContext)
        } catch {
            AppLog.error("SomatiqApp.init.makeContainer", error: error)
            do {
                let memoryContainer = try AppModelContainerFactory.makeContainer(isStoredInMemoryOnly: true)
                sharedContainer = memoryContainer
                dependencies = AppDependencies(modelContext: memoryContainer.mainContext)
            } catch {
                fatalError("Unable to initialize app dependencies: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(dependencies: dependencies)
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedContainer)
    }
}
