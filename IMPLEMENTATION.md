# Somatiq — Architecture & Implementation

> Native Swift iOS app. Private health intelligence, on device.
> Target: iOS 17+, iPhone with Apple Watch.

---

## 1. Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI Views                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ TodayView│  │TrendsView│  │ AIChatView│  │Settings │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬────┘ │
│       │              │              │              │      │
├───────┴──────────────┴──────────────┴──────────────┴──────┤
│                     ViewModels (@Observable)               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │
│  │ TodayVM      │  │ TrendsVM     │  │ AIChatVM         │ │
│  │ - scores     │  │ - history    │  │ - messages       │ │
│  │ - vitals     │  │ - charts     │  │ - health context │ │
│  │ - insight    │  │              │  │                  │ │
│  └──────┬───────┘  └──────┬───────┘  └──────────────────┘ │
│         │                  │                               │
├─────────┴──────────────────┴───────────────────────────────┤
│                       Services                             │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────┐ │
│  │ HealthKitSvc   │  │ ScoreEngine    │  │ StorageSvc   │ │
│  │                │  │                │  │              │ │
│  │ - queryDaily() │  │ - compute()    │  │ - save()     │ │
│  │ - background() │  │ - baseline()   │  │ - fetch()    │ │
│  │ - authorize()  │  │ - publish()    │  │ - upsert()   │ │
│  └───────┬────────┘  └───────┬────────┘  └──────┬───────┘ │
│          │                   │                   │         │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────┐ │
│  │ WellnessReport │  │ InsightGen     │  │ AIModelMgr   │ │
│  │ Service        │  │                │  │ (MLX Swift)  │ │
│  └────────────────┘  └────────────────┘  └──────────────┘ │
│                                                           │
├───────────────────────────────────────────────────────────┤
│                       Data Layer                           │
│  ┌─────────────┐              ┌──────────────────────────┐ │
│  │  HealthKit   │              │  SwiftData               │ │
│  │  (read-only) │              │  ┌────────────────────┐  │ │
│  │              │              │  │ DailyScore         │  │ │
│  │  HRV ───────►│──── calc ───►│  │ WellnessReport     │  │ │
│  │  Sleep ──────►│             │  │ UserBaseline       │  │ │
│  │  HR ─────────►│             │  │ EnergyReading      │  │ │
│  │  Activity ───►│             │  │ UserPreferences    │  │ │
│  └──────────────┘              └──────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Apple Watch → HealthKitService → DashboardDataService
                                    │
                                    ├─ ScoreEngine (baseline + scoring)
                                    ├─ InsightGenerator
                                    ├─ WellnessReportService (trigger detection)
                                    ├─ StorageService (SwiftData)
                                    ▼
                              DashboardSnapshot → TodayViewModel → SwiftUI
```

```
Background:
  BGTaskScheduler (hourly)
      │
      ▼
  SomatiqAppDelegate
      │
      ├─ AppModelContainerFactory.makeContainer()
      └─ DashboardDataService.recalculateToday(
            requestAuthorization: false,
            energySource: "background_refresh"
         )
      ▼
  SwiftData.upsert(DailyScore)
```

---

## 2. Tech Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| UI | SwiftUI | iOS 17+ |
| Charts | Swift Charts | Trends visualization |
| Health Data | HealthKit | Read-only (HRV, HR, sleep, activity) |
| Storage | SwiftData | On-device persistence |
| State | @Observable (Observation) | iOS 17+ |
| AI | MLX Swift LM (MLXLLM) | On-device Qwen 3.5 inference |
| Project | XcodeGen | `project.yml` → `Somatiq.xcodeproj` |

### External Dependencies

- **MLXSwiftLM** v2.30.6 — on-device LLM runtime (MLXLLM + MLXLMCommon)

---

## 3. Data Model (SwiftData)

```swift
@Model
final class DailyScore {
    var date: Date                  // calendar day (midnight)

    var stressScore: Int            // 0-100
    var sleepScore: Int             // 0-100
    var bodyBatteryScore: Int       // 0-100
    var heartScore: Int             // 0-100 (HRV+RHR resilience proxy)

    var stressLevel: String         // "low" | "moderate" | "high"
    var sleepLevel: String          // "poor" | "fair" | "good" | "great"
    var bodyBatteryLevel: String    // "depleted" | "low" | "good" | "charged"

    var createdAt: Date
    var updatedAt: Date

    // Sleep breakdown
    var sleepDurationMin: Double
    var sleepEfficiency: Double     // 0-1
    var deepSleepMin: Double
    var remSleepMin: Double
    var coreSleepMin: Double
    var bedtimeAt: Date?

    // HRV & HR
    var avgSDNN: Double             // ms (published HRV)
    var restingHR: Double           // bpm (nightly RHR)

    // Activity
    var activeCalories: Double      // kcal
    var steps: Int

    // Metadata
    var insightText: String
    var scoreConfidence: Double?    // 0-1
    var qualityReason: String?      // comma-separated quality flags
}

@Model
final class WellnessReport {
    var id: UUID
    var createdAt: Date
    var day: Date
    var triggerType: String         // firstCheckin | stressSpike | batteryLow | sleepDebt | hrvDrop | notableShift
    var headline: String
    var body: String
    var stressScore: Int
    var sleepScore: Int
    var bodyBatteryScore: Int
    var heartScore: Int
    var source: String
}

@Model
final class UserBaseline {
    var metricName: String          // "sdnn" | "restingHR" | "sleepDuration"
    var median30Day: Double
    var updatedAt: Date
    var sampleCount: Int
}

@Model
final class EnergyReading {
    var timestamp: Date
    var level: Double               // 0-100
    var source: String
}

@Model
final class UserPreferences {
    var targetSleepHours: Double    // default 8.0
    var birthYear: Int?
    var isOnboardingComplete: Bool
    var userName: String?
}
```

---

## 4. HealthKit Integration

### Protocol

```swift
protocol HealthDataProviding: Sendable {
    func requestAuthorization() async throws
    func authorizeAndEnableBackgroundDelivery() async throws
    func queryDailyInput(for date: Date) async throws -> DailyHealthInput
}
```

### DailyHealthInput (DTO)

```swift
struct DailyHealthInput: Sendable {
    let sleep: SleepData
    let nightSDNNSamples: [HRVSample]
    let nightRMSDDSamples: [HRVSample]
    let nightHeartRateBins: [Double]
    let restWindows: [RestWindowSample]
    let activeEnergy: Double
    let steps: Int
    let workoutMinutes: Double
    let dayWatchWearCoverage: Double
    let nightHRCoverage: Double
    let sourcePurity: Double
    let qualityNotes: [String]
}
```

### Source Ranking

HealthKitService ranks sources: Apple Watch (3) > Phone (2) > Third-party (1) > User-entered (filtered out). Source purity tracks how much data comes from highest-ranked source.

---

## 5. Score Engine

### Architecture

ScoreEngine is a pure struct. It builds baselines inline from the last 60 days of DailyScore history — no separate BaselineService.

### Baseline (EngineBaseline)

Built from recent DailyScore history with robust statistics:
- **28-day** and **60-day** windows for HRV, RHR, duration, activity
- **7-day** window for bedtime stability (SD)
- Circular median for bedtime (handles midnight crossing)
- Population defaults: SDNN=35ms, RHR=62bpm, SleepDuration=7h

### Scoring Pipeline

```
Input → Quality gates → Physiological checks → Robust z-scores → Raw scores → Confidence-gated publishing
```

All scores use **robust z-scores** (`(value - median) / max(IQR/1.349, floor)`) clamped to [-3, +3], mapped through `goodZ`/`badZ` functions.

#### Heart Score (0-100)
- 65% nighttime HRV z-score (higher = better)
- 35% nighttime RHR z-score (lower = better)

#### Stress Score (0-100)
- Computed from rest windows only
- 55% HRV z-score + 45% HR z-score per window
- Takes P70 across windows

#### Sleep Score (0-100)
- 30% duration (vs baseline target)
- 20% efficiency
- 10% interruptions
- 20% regularity (bedtime shift + stability)
- 20% physio recovery (heart score component)

#### Body Battery Score (0-100)
- Morning charge: 55% sleep + 45% heart
- Drained by: activity (45%), stress (35%), workouts (20%)

### Confidence & Publishing

Confidence is a weighted blend:
- 35% coverage score (sleep hours, HR samples, HRV, rest windows, wear)
- 25% source purity
- 20% baseline maturity (valid nights / 14)
- 20% context validity (physiological plausibility)

Publishing policy:
- confidence < 0.4 → slow drift (limit ±2 from previous)
- confidence 0.4-0.7 → moderate drift (limit ±5)
- confidence ≥ 0.7 → normal drift (limit ±10)
- < 7 valid nights → hold at 50 (calibration mode)

---

## 6. Wellness Reports

`WellnessReportService` generates reports when triggers fire:

| Trigger | Condition |
|---------|-----------|
| firstCheckin | No prior report today |
| stressSpike | Stress ≥ 72, was < 72 |
| batteryLow | Battery ≤ 35, was > 35 |
| sleepDebt | Sleep ≤ 45, was > 45 |
| hrvDrop | Heart score ≤ 35, was > 35 |
| notableShift | Any score delta ≥ 8-12 |

Guards: max 3 reports/day, minimum 3-hour interval, confidence ≥ 0.80.

---

## 7. AI Chat

On-device LLM (Qwen 3.5 9B via MLX Swift):
- `AIModelManager` — model loading and text generation
- `AIChatService` — conversation orchestration
- `AIConversationStore` — SwiftData persistence
- `AIHealthContextService` — builds health context for prompts

No health data leaves the device.

---

## 8. Project Structure

```
Sources/
├── App/
│   ├── SomatiqApp.swift              # @main entry
│   ├── RootTabView.swift             # 4-tab navigation (Today/Trends/AI/Settings)
│   ├── AppDependencies.swift         # DI container
│   ├── AppModelContainerFactory.swift # SwiftData setup
│   ├── SomatiqAppDelegate.swift      # Background refresh
│   └── PreviewData.swift             # SwiftUI preview helpers
│
├── Models/
│   ├── DailyScore.swift              # @Model — core daily metrics
│   ├── WellnessReport.swift          # @Model — triggered reports
│   ├── HealthModels.swift            # HRVSample, SleepData, DailyHealthInput, BaselineMetric
│   ├── UserBaseline.swift            # @Model — rolling metric baselines
│   ├── EnergyReading.swift           # @Model — battery readings
│   ├── UserPreferences.swift         # @Model — user settings
│   ├── AIChatMessage.swift           # Chat message model
│   └── LabAnalysisRecord.swift       # Lab analysis data
│
├── Services/
│   ├── HealthKitService.swift        # HealthKit queries + source ranking
│   ├── ScoreEngine.swift             # Baseline + scoring (stress/sleep/battery/heart)
│   ├── DashboardDataService.swift    # Today pipeline orchestration
│   ├── DashboardSnapshotProviding.swift # Protocol
│   ├── WellnessReportService.swift   # Report triggers + generation
│   ├── InsightGenerator.swift        # Template-based insights
│   ├── TrendsDataService.swift       # Historical data loading
│   ├── SettingsDataService.swift     # Preferences management
│   ├── StorageService.swift          # SwiftData CRUD
│   ├── AIModelManager.swift          # MLX model lifecycle
│   ├── AIChatService.swift           # Chat orchestration
│   ├── AIConversationStore.swift     # Chat persistence
│   ├── AIHealthContextService.swift  # Health context for AI prompts
│   └── LabAnalysisService.swift      # Lab PDF analysis
│
├── ViewModels/
│   ├── TodayViewModel.swift          # Dashboard state + trends
│   ├── TrendsViewModel.swift         # History charts
│   ├── AIChatViewModel.swift         # Chat UI state
│   └── SettingsViewModel.swift       # Settings UI state
│
├── Views/
│   ├── Today/                        # TodayView, JournalView
│   ├── Trends/                       # TrendsView
│   ├── AI/                           # AIChatView
│   ├── Settings/                     # SettingsView
│   ├── Analyses/                     # AnalysesView, LabAnalysisDetailView
│   ├── Onboarding/                   # OnboardingView
│   └── Components/                   # ScoreRing, VitalCard, MetricCard,
│                                     # InsightCard, WeeklyTrendCard, GlassCard,
│                                     # AnimatedNumber, EmptyStateView, etc.
│
├── Design/
│   └── Theme.swift                   # Colors, gradients, spacing, radius, animations
│
└── Utilities/
    ├── Statistics.swift              # median, IQR, percentile, circularMedian, robustZ, etc.
    ├── Date+Extensions.swift         # startOfDay, calendar helpers
    ├── Color+Hex.swift               # Color(hex:) initializer
    ├── AppLog.swift                  # os.Logger wrapper
    ├── AppErrorMapper.swift          # Error → user message
    └── AppEvents.swift               # Analytics event definitions

Tests/SomatiqTests/
├── ScoreEngineTests.swift            # Score computation unit tests
└── ServiceLayerTests.swift           # Integration tests
```

---

## 9. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| ScoreEngine builds baseline inline | Simpler than separate service; single source of truth for scoring |
| Robust z-scores (IQR-based) | Resilient to outliers vs standard z-scores |
| Confidence-gated publishing | Prevents wild score swings on low-quality data |
| Circular median for bedtimes | Handles midnight-crossing correctly (23:30 + 00:30 ≠ noon) |
| Sleep locked after first calc | Prevents score changes from HealthKit sleep data arriving late |
| heartScore persisted on DailyScore | Avoids lossy reverse-engineering from sleep+battery proxy |
| Population defaults (35/62/7) | Medically reasonable anchors for early baseline blending |
| On-device AI only | No health data leaves the device — privacy by architecture |
