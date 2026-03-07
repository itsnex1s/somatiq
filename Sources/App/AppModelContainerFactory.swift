import Foundation
import SwiftData

enum AppModelContainerFactory {
    static var schema: Schema {
        Schema([
            DailyScore.self,
            UserBaseline.self,
            EnergyReading.self,
            UserPreferences.self,
            WellnessReport.self,
            LabAnalysisRecord.self,
        ])
    }

    static func makeContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard !isStoredInMemoryOnly else {
                throw error
            }

            AppLog.error("AppModelContainerFactory.makeContainer.firstAttempt", error: error)
            do {
                let removedArtifactsCount = try purgeStoreArtifacts()
                AppLog.info("Purged \(removedArtifactsCount) SwiftData artifact(s) after migration failure.")
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                AppLog.error("AppModelContainerFactory.makeContainer.recoveryAttempt", error: error)
                AppLog.info("Falling back to in-memory store for this launch.")
                let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [memoryConfiguration])
            }
        }
    }

    private static func purgeStoreArtifacts() throws -> Int {
        let fileManager = FileManager.default
        let appSupportDirectory = try applicationSupportDirectory()

        let removableSuffixes = [
            ".store",
            ".store-wal",
            ".store-shm",
        ]
        var removedCount = 0

        if let enumerator = fileManager.enumerator(
            at: appSupportDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let fileName = url.lastPathComponent
                let shouldRemove = removableSuffixes.contains(where: { fileName.hasSuffix($0) })
                guard shouldRemove else { continue }

                do {
                    try fileManager.removeItem(at: url)
                    removedCount += 1
                } catch {
                    AppLog.error("AppModelContainerFactory.purgeStoreArtifacts.removeItem", error: error)
                }
            }
        }

        return removedCount
    }

    private static func applicationSupportDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory
    }
}
