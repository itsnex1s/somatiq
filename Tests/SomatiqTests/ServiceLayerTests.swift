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
            bodyBatteryScore: 74,
            stressLevel: StressLevel.moderate.rawValue,
            sleepLevel: SleepLevel.good.rawValue,
            bodyBatteryLevel: BatteryLevel.good.rawValue,
            sleepDurationMin: 430,
            sleepEfficiency: 0.89,
            deepSleepMin: 90,
            remSleepMin: 95,
            coreSleepMin: 245,
            avgSDNN: 41,
            restingHR: 62,
            activeCalories: 380,
            steps: 7_200,
            insightText: "Cached insight",
            scoreConfidence: 0.8,
            qualityReason: "stable"
        )
        try storage.upsertDailyScore(cached)

        let mock = MockHealthDataProvider()
        let service = DashboardDataService(context: context, healthDataProvider: mock)

        let snapshot = try await service.fetchSnapshot(forceRecalculate: false)

        XCTAssertEqual(snapshot.today.stressScore, 52)
        XCTAssertEqual(snapshot.today.sleepScore, 68)
        XCTAssertEqual(snapshot.today.bodyBatteryScore, 74)
        XCTAssertEqual(snapshot.weekScores.count, 1)
        let queryDailyInputCallCount = await mock.queryDailyInputCallCount()
        XCTAssertEqual(queryDailyInputCallCount, 0)
    }

    func testDashboardFetchSnapshotWithoutCacheDoesNotAutoRequestAuthorization() async throws {
        let container = try AppModelContainerFactory.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let mock = MockHealthDataProvider()
        let service = DashboardDataService(context: context, healthDataProvider: mock)

        let snapshot = try await service.fetchSnapshot(forceRecalculate: false)

        XCTAssertEqual(snapshot.today.date, Date().startOfDay)
        XCTAssertGreaterThanOrEqual(snapshot.today.sleepScore, 0)
        let requestAuthorizationCallCount = await mock.requestAuthorizationCallCount()
        let queryDailyInputCallCount = await mock.queryDailyInputCallCount()
        XCTAssertEqual(requestAuthorizationCallCount, 0)
        XCTAssertEqual(queryDailyInputCallCount, 1)
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
        let queryDailyInputCallCount = await mock.queryDailyInputCallCount()
        XCTAssertEqual(requestAuthorizationCallCount, 0)
        XCTAssertEqual(queryDailyInputCallCount, 1)
        XCTAssertEqual(try storage.latestBatteryReading()?.source, "unit_test_refresh")
    }

    func testSettingsReconnectHealthCallsAuthorizationAndBackgroundDelivery() async throws {
        let container = try AppModelContainerFactory.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let mock = MockHealthDataProvider()
        let service = SettingsDataService(context: context, healthDataProvider: mock)

        let reconnectResult = try await service.reconnectHealth()

        let requestAuthorizationCallCount = await mock.requestAuthorizationCallCount()
        let enableBackgroundDeliveryCallCount = await mock.enableBackgroundDeliveryCallCount()
        XCTAssertEqual(requestAuthorizationCallCount, 1)
        XCTAssertEqual(enableBackgroundDeliveryCallCount, 1)
        switch reconnectResult {
        case .connectedNoData:
            break
        case .syncedWithData:
            XCTFail("Expected reconnect without dashboard service to return connectedNoData.")
        }
    }

    func testSettingsReconnectWithDashboardUpdatesLastSync() async throws {
        let container = try AppModelContainerFactory.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let mock = MockHealthDataProvider()
        let dashboardService = DashboardDataService(context: context, healthDataProvider: mock)
        let service = SettingsDataService(
            context: context,
            healthDataProvider: mock,
            dashboardService: dashboardService
        )

        let reconnectResult = try await service.reconnectHealth()

        switch reconnectResult {
        case let .syncedWithData(lastSyncAt):
            XCTAssertLessThanOrEqual(abs(lastSyncAt.timeIntervalSinceNow), 5)
        case .connectedNoData:
            XCTFail("Expected reconnect with dashboard service to sync data.")
        }

        let preferences = try StorageService(context: context).fetchPreferences()
        XCTAssertNotNil(preferences.lastSyncAt)
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
        XCTAssertEqual(history.first?.bodyBatteryScore, today.bodyBatteryScore)

        let requestAuthorizationCallCount = await mock.requestAuthorizationCallCount()
        XCTAssertEqual(requestAuthorizationCallCount, 1)
    }

    func testDashboardLocksSleepForDayButRefreshesStress() async throws {
        let container = try AppModelContainerFactory.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext

        let firstInput = SequenceHealthDataProvider.makeInput(
            sleepMinutes: 435,
            sleepEfficiency: 0.90,
            stressHR: 46,
            stressLnHRV: log(92),
            hrv: 52
        )
        let secondInput = SequenceHealthDataProvider.makeInput(
            sleepMinutes: 300,
            sleepEfficiency: 0.75,
            stressHR: 122,
            stressLnHRV: log(12),
            hrv: 18
        )

        let provider = SequenceHealthDataProvider(inputs: [firstInput, secondInput])
        let service = DashboardDataService(context: context, healthDataProvider: provider)

        let first = try await service.recalculateToday(requestAuthorization: false, energySource: "test_first")
        let second = try await service.recalculateToday(requestAuthorization: false, energySource: "test_second")

        XCTAssertEqual(second.sleepDurationMin, first.sleepDurationMin)
        XCTAssertEqual(second.sleepScore, first.sleepScore)
        XCTAssertTrue((0 ... 100).contains(second.stressScore))
        XCTAssertTrue((second.qualityReason ?? "").contains("sleep_locked"))
        let queryDailyInputCalls = await provider.queryDailyInputCallCount()
        XCTAssertEqual(queryDailyInputCalls, 2)
    }
}

private actor MockHealthDataProvider: HealthDataProviding {
    private var requestAuthorizationCalls = 0
    private var queryDailyInputCalls = 0
    private var enableBackgroundDeliveryCalls = 0

    func requestAuthorization() async throws {
        requestAuthorizationCalls += 1
    }

    func queryDailyInput(for date: Date) async throws -> DailyHealthInput {
        _ = date
        queryDailyInputCalls += 1

        let sleep = SleepData(
            segments: [],
            inBedStart: Date().addingTimeInterval(-8.5 * 3_600),
            inBedEnd: Date().addingTimeInterval(-0.5 * 3_600),
            totalSleepMinutes: 435,
            deepMinutes: 95,
            remMinutes: 100,
            coreMinutes: 240,
            awakeMinutes: 20,
            efficiency: 0.90,
            bedtime: Date().addingTimeInterval(-8.5 * 3_600),
            stageCoverage: 0.82,
            sourcePurity: 1.0,
            interruptionsCount: 2
        )

        return DailyHealthInput(
            sleep: sleep,
            nightSDNNSamples: [
                HRVSample(value: 45, date: Date().addingTimeInterval(-2 * 3_600), sourceRank: 3, algorithmVersion: "1")
            ],
            nightRMSDDSamples: [],
            nightHeartRateBins: [56, 57, 58, 55, 54, 56, 57, 58],
            restWindows: [
                RestWindowSample(timestamp: Date().addingTimeInterval(-4 * 3_600), heartRate: 62, lnHRV: log(42), sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-3 * 3_600), heartRate: 60, lnHRV: log(44), sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-2 * 3_600), heartRate: 61, lnHRV: log(43), sourceRank: 3),
            ],
            activeEnergy: 420,
            steps: 8_000,
            workoutMinutes: 25,
            dayWatchWearCoverage: 0.85,
            nightHRCoverage: 0.65,
            sourcePurity: 0.95,
            qualityNotes: []
        )
    }

    func enableBackgroundDelivery() async throws {
        enableBackgroundDeliveryCalls += 1
    }

    func requestAuthorizationCallCount() -> Int {
        requestAuthorizationCalls
    }

    func queryDailyInputCallCount() -> Int {
        queryDailyInputCalls
    }

    func enableBackgroundDeliveryCallCount() -> Int {
        enableBackgroundDeliveryCalls
    }
}

private actor SequenceHealthDataProvider: HealthDataProviding {
    private var queue: [DailyHealthInput]
    private var enableCalls = 0
    private var authCalls = 0
    private var queryCalls = 0

    init(inputs: [DailyHealthInput]) {
        queue = inputs
    }

    func requestAuthorization() async throws {
        authCalls += 1
    }

    func queryDailyInput(for date: Date) async throws -> DailyHealthInput {
        _ = date
        queryCalls += 1
        guard !queue.isEmpty else {
            return Self.makeInput(
                sleepMinutes: 420,
                sleepEfficiency: 0.88,
                stressHR: 62,
                stressLnHRV: log(44),
                hrv: 44
            )
        }
        return queue.removeFirst()
    }

    func enableBackgroundDelivery() async throws {
        enableCalls += 1
    }

    func queryDailyInputCallCount() -> Int {
        queryCalls
    }

    static func makeInput(
        sleepMinutes: Double,
        sleepEfficiency: Double,
        stressHR: Double,
        stressLnHRV: Double?,
        hrv: Double
    ) -> DailyHealthInput {
        let bedtime = Date().addingTimeInterval(-8.5 * 3_600)
        let inBedEnd = bedtime.addingTimeInterval((sleepMinutes / max(sleepEfficiency, 0.01)) * 60)

        let sleep = SleepData(
            segments: [],
            inBedStart: bedtime,
            inBedEnd: inBedEnd,
            totalSleepMinutes: sleepMinutes,
            deepMinutes: sleepMinutes * 0.24,
            remMinutes: sleepMinutes * 0.23,
            coreMinutes: sleepMinutes * 0.53,
            awakeMinutes: max((sleepMinutes / max(sleepEfficiency, 0.01)) - sleepMinutes, 0),
            efficiency: sleepEfficiency,
            bedtime: bedtime,
            stageCoverage: 0.82,
            sourcePurity: 1.0,
            interruptionsCount: 2
        )

        return DailyHealthInput(
            sleep: sleep,
            nightSDNNSamples: [
                HRVSample(value: hrv, date: Date().addingTimeInterval(-2 * 3_600), sourceRank: 3, algorithmVersion: "1")
            ],
            nightRMSDDSamples: [],
            nightHeartRateBins: [56, 57, 58, 55, 54, 56, 57, 58],
            restWindows: [
                RestWindowSample(timestamp: Date().addingTimeInterval(-3 * 3_600), heartRate: stressHR, lnHRV: stressLnHRV, sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-2 * 3_600), heartRate: stressHR + 1, lnHRV: stressLnHRV, sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-1 * 3_600), heartRate: stressHR + 2, lnHRV: stressLnHRV, sourceRank: 3),
            ],
            activeEnergy: 420,
            steps: 8_000,
            workoutMinutes: 20,
            dayWatchWearCoverage: 0.88,
            nightHRCoverage: 0.72,
            sourcePurity: 0.96,
            qualityNotes: []
        )
    }
}
