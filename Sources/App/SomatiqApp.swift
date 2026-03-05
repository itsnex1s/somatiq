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
            fatalError("Unable to initialize app dependencies: \(error)")
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
