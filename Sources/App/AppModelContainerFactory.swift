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
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
