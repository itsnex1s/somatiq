import SwiftData
import XCTest
@testable import Somatiq

@MainActor
final class ServiceLayerTests: XCTestCase {
    func testDashboardFetchSnapshotUsesCachedScoreWithoutHealthQueries() async throws {
        let container = try AppModelContainerFactory.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let storage = StorageService(context: context)

        let cached = DailyScore(
            date: Date(),
            stressScore: 52,
            sleepScore: 68,
            energyScore: 74,
            stressLevel: StressLevel.moderate.rawValue,
            sleepLevel: SleepLevel.good.rawValue,
            energyLevel: EnergyLevel.good.rawValue,
            sleepDurationMin: 430,
            sleepEfficiency: 0.89,
            deepSleepMin: 90,
            remSleepMin: 95,
            coreSleepMin: 245,
            avgSDNN: 41,
            restingHR: 62,
            activeCalories: 380,
            steps: 7_200,
            insightText: "Cached insight"
        )
        try storage.upsertDailyScore(cached)

        let mock = MockHealthDataProvider()
        let service = DashboardDataService(context: context, healthDataProvider: mock)

        let snapshot = try await service.fetchSnapshot(forceRecalculate: false)

        XCTAssertEqual(snapshot.today.stressScore, 52)
        XCTAssertEqual(snapshot.today.sleepScore, 68)
        XCTAssertEqual(snapshot.today.energyScore, 74)
        XCTAssertEqual(snapshot.weekScores.count, 1)
        let queryHRVCallCount = await mock.queryHRVCallCount()
        XCTAssertEqual(queryHRVCallCount, 0)
    }

    func testDashboardRecalculateWithoutAuthorizationPersistsEnergySource() async throws {
        let container = try AppModelContainerFactory.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let mock = MockHealthDataProvider()
        let service = DashboardDataService(context: context, healthDataProvider: mock)
        let storage = StorageService(context: context)

        _ = try await service.recalculateToday(
            requestAuthorization: false,
            energySource: "unit_test_refresh"
        )

        let requestAuthorizationCallCount = await mock.requestAuthorizationCallCount()
        let queryHRVCallCount = await mock.queryHRVCallCount()
        XCTAssertEqual(requestAuthorizationCallCount, 0)
        XCTAssertEqual(queryHRVCallCount, 1)
        XCTAssertEqual(try storage.latestEnergyReading()?.source, "unit_test_refresh")
    }

    func testSettingsReconnectHealthCallsAuthorizationAndBackgroundDelivery() async throws {
        let container = try AppModelContainerFactory.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let mock = MockHealthDataProvider()
        let service = SettingsDataService(context: context, healthDataProvider: mock)

        try await service.reconnectHealth()

        let requestAuthorizationCallCount = await mock.requestAuthorizationCallCount()
        let enableBackgroundDeliveryCallCount = await mock.enableBackgroundDeliveryCallCount()
        XCTAssertEqual(requestAuthorizationCallCount, 1)
        XCTAssertEqual(enableBackgroundDeliveryCallCount, 1)
    }

    func testIntegrationPipelineRecalculateThenReadFromTrends() async throws {
        let container = try AppModelContainerFactory.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let mock = MockHealthDataProvider()
        let dashboardService = DashboardDataService(context: context, healthDataProvider: mock)
        let trendsService = TrendsDataService(context: context)

        let today = try await dashboardService.recalculateToday(
            requestAuthorization: true,
            energySource: "integration_test"
        )
        let history = try trendsService.fetchHistory(for: .days7)

        XCTAssertEqual(today.date, Date().startOfDay)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.energyScore, today.energyScore)

        let requestAuthorizationCallCount = await mock.requestAuthorizationCallCount()
        XCTAssertEqual(requestAuthorizationCallCount, 1)
    }
}

private actor MockHealthDataProvider: HealthDataProviding {
    private var requestAuthorizationCalls = 0
    private var queryHRVCalls = 0
    private var enableBackgroundDeliveryCalls = 0

    private let hrvSamples: [HRVSample] = [
        HRVSample(sdnn: 45, date: Date())
    ]
    private let restingHeartRate: Double? = 61
    private let sleepData = SleepData(
        segments: [],
        inBedStart: Date().addingTimeInterval(-8.5 * 3600),
        inBedEnd: Date().addingTimeInterval(-0.5 * 3600),
        totalSleepMinutes: 435,
        deepMinutes: 95,
        remMinutes: 100,
        coreMinutes: 240,
        awakeMinutes: 20,
        efficiency: 0.90,
        bedtime: Date().addingTimeInterval(-8.5 * 3600)
    )
    private let activeEnergy: Double = 420
    private let dailySteps: Int = 8_000

    func requestAuthorization() async throws {
        requestAuthorizationCalls += 1
    }

    func queryHRV(last hours: Int) async throws -> [HRVSample] {
        _ = hours
        queryHRVCalls += 1
        return hrvSamples
    }

    func queryRestingHR() async throws -> Double? {
        restingHeartRate
    }

    func querySleep(for date: Date) async throws -> SleepData {
        _ = date
        return sleepData
    }

    func queryActiveEnergy(for date: Date) async throws -> Double {
        _ = date
        return activeEnergy
    }

    func querySteps(for date: Date) async throws -> Int {
        _ = date
        return dailySteps
    }

    func enableBackgroundDelivery() async throws {
        enableBackgroundDeliveryCalls += 1
    }

    func requestAuthorizationCallCount() -> Int {
        requestAuthorizationCalls
    }

    func queryHRVCallCount() -> Int {
        queryHRVCalls
    }

    func enableBackgroundDeliveryCallCount() -> Int {
        enableBackgroundDeliveryCalls
    }
}
