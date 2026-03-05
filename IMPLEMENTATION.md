# Somatiq — MVP Implementation Plan

> Native Swift iOS app. Private health intelligence, on device.
> Target: iOS 17+, iPhone with Apple Watch.

---

## 1. Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI Views                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ TodayView│  │TrendsView│  │LabsPlaceholder│ │Settings │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬────┘ │
│       │              │              │              │      │
├───────┴──────────────┴──────────────┴──────────────┴──────┤
│                     ViewModels (@Observable)               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │
│  │ TodayVM      │  │ TrendsVM     │  │ SettingsVM       │ │
│  │ - scores     │  │ - history    │  │ - preferences    │ │
│  │ - vitals     │  │ - charts     │  │                  │ │
│  │ - insight    │  │              │  │                  │ │
│  └──────┬───────┘  └──────┬───────┘  └──────────────────┘ │
│         │                  │                               │
├─────────┴──────────────────┴───────────────────────────────┤
│                       Services                             │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────┐ │
│  │ HealthKitSvc   │  │ ScoreEngine    │  │ StorageSvc   │ │
│  │                │  │                │  │              │ │
│  │ - queryHRV()   │  │ - stress()     │  │ - save()     │ │
│  │ - querySleep() │  │ - sleep()      │  │ - fetch()    │ │
│  │ - queryHR()    │  │ - energy()     │  │ - baseline() │ │
│  │ - queryEnergy()│  │ - baseline()   │  │              │ │
│  └───────┬────────┘  └───────┬────────┘  └──────┬───────┘ │
│          │                   │                   │         │
├──────────┴───────────────────┴───────────────────┴─────────┤
│                       Data Layer                           │
│  ┌─────────────┐              ┌──────────────────────────┐ │
│  │  HealthKit   │              │  SwiftData               │ │
│  │  (read-only) │              │  ┌────────────────────┐  │ │
│  │              │              │  │ DailyScore         │  │ │
│  │  HRV ───────►│──── calc ───►│  │ HealthSample      │  │ │
│  │  Sleep ──────►│             │  │ UserBaseline       │  │ │
│  │  HR ─────────►│             │  │ UserPreferences    │  │ │
│  │  Energy ─────►│             │  └────────────────────┘  │ │
│  └──────────────┘              └──────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Apple Watch → HealthKitService → DashboardDataService
                                    │
                                    ├─ ScoreEngine + BaselineService + InsightGenerator
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

| Layer | Technology | Version | Link |
|-------|-----------|---------|------|
| UI | SwiftUI | iOS 17+ | [developer.apple.com/swiftui](https://developer.apple.com/xcode/swiftui/) |
| Charts | Swift Charts | iOS 16+ | [developer.apple.com/swift-charts](https://developer.apple.com/documentation/charts) |
| Health Data | HealthKit | iOS 8+ | [developer.apple.com/healthkit](https://developer.apple.com/documentation/healthkit) |
| Storage | SwiftData | iOS 17+ | [developer.apple.com/swiftdata](https://developer.apple.com/documentation/swiftdata) |
| Animations | SwiftUI Animations | iOS 17+ | [WWDC23 — Explore SwiftUI Animation](https://developer.apple.com/videos/play/wwdc2023/10156/) |
| Architecture | @Observable (Observation) | iOS 17+ | [developer.apple.com/observation](https://developer.apple.com/documentation/observation) |

### No External Dependencies

MVP uses zero SPM packages. Apple frameworks only.

### Dev Tools

| Tool | Command | Purpose |
|------|---------|---------|
| [sosumi](https://github.com/nshipster/sosumi) | `npx @nshipster/sosumi search "HealthKit"` | Apple docs in terminal (markdown) |
| | `npx @nshipster/sosumi fetch /documentation/healthkit/...` | Fetch specific API docs |
| | `npx @nshipster/sosumi fetch /videos/play/wwdc2022/10005` | WWDC session transcripts |

---

## 3. Data Model (SwiftData)

```swift
// MARK: - Models

@Model
final class DailyScore {
    var date: Date              // calendar day (midnight)
    var stressScore: Int        // 0-100
    var sleepScore: Int         // 0-100
    var energyScore: Int        // 0-100 (snapshot at calc time)
    var stressLevel: String     // "low" | "moderate" | "high"
    var sleepLevel: String      // "poor" | "fair" | "good" | "great"
    var energyLevel: String     // "depleted" | "low" | "good" | "charged"
    var createdAt: Date

    // Sleep breakdown
    var sleepDurationMin: Double
    var sleepEfficiency: Double     // 0-1
    var deepSleepMin: Double
    var remSleepMin: Double
    var coreSleepMin: Double

    // HRV data
    var avgSDNN: Double             // ms
    var restingHR: Double           // bpm

    // Activity
    var activeCalories: Double      // kcal
    var steps: Int
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
    var source: String              // "sleep_charge" | "activity_drain" | "rest_charge"
}

@Model
final class UserPreferences {
    var targetSleepHours: Double    // default 8.0
    var birthYear: Int?
    var isOnboardingComplete: Bool
}
```

### Schema Diagram

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ DailyScore   │     │ UserBaseline     │     │ EnergyReading   │
├──────────────┤     ├──────────────────┤     ├─────────────────┤
│ date (PK)    │     │ metricName (PK)  │     │ timestamp (PK)  │
│ stressScore  │     │ median30Day      │     │ level           │
│ sleepScore   │     │ updatedAt        │     │ source          │
│ energyScore  │     │ sampleCount      │     └─────────────────┘
│ avgSDNN      │     └──────────────────┘
│ restingHR    │     ┌──────────────────┐
│ sleepDuration│     │ UserPreferences  │
│ deepSleepMin │     ├──────────────────┤
│ remSleepMin  │     │ targetSleepHours │
│ activeCalorie│     │ birthYear        │
│ steps        │     │ isOnboarding...  │
└──────────────┘     └──────────────────┘
```

---

## 4. HealthKit Integration

### Required Permissions

```swift
let readTypes: Set<HKObjectType> = [
    HKQuantityType(.heartRateVariabilitySDNN),  // HRV
    HKQuantityType(.heartRate),                  // HR
    HKQuantityType(.restingHeartRate),            // Resting HR
    HKCategoryType(.sleepAnalysis),               // Sleep stages
    HKQuantityType(.activeEnergyBurned),          // Active cal
    HKQuantityType(.stepCount),                   // Steps
]
// Write: none. Read-only app.
```

### HealthKitService API

```swift
// Sources/Services/HealthKitService.swift

@Observable
final class HealthKitService {
    private let store = HKHealthStore()

    /// Request read-only authorization
    func requestAuthorization() async throws

    /// HRV samples from last N hours
    func queryHRV(last hours: Int = 24) async throws -> [HRVSample]

    /// Latest resting heart rate
    func queryRestingHR() async throws -> Double?

    /// Sleep samples for last night
    func querySleep(for date: Date) async throws -> SleepData

    /// Active energy burned today
    func queryActiveEnergy(for date: Date) async throws -> Double

    /// Step count today
    func querySteps(for date: Date) async throws -> Int

    /// Enable background delivery for hourly recalculation
    func enableBackgroundDelivery() async throws
}

struct HRVSample {
    let sdnn: Double    // ms
    let date: Date
}

struct SleepData {
    let segments: [SleepSegment]
    let inBedStart: Date?
    let inBedEnd: Date?

    var totalSleepMinutes: Double
    var deepMinutes: Double
    var remMinutes: Double
    var coreMinutes: Double
    var awakeMinutes: Double
    var efficiency: Double          // totalSleep / inBed
}

struct SleepSegment {
    let stage: SleepStage           // .deep, .rem, .core, .awake
    let start: Date
    let end: Date
}

enum SleepStage {
    case deep, rem, core, awake, unspecified
}
```

### Key HealthKit Gotchas

```
⚠️  Cannot detect denied permission — HealthKit returns empty data
    both when denied and when no data exists.
    → Show "No data yet. Make sure Apple Watch is worn" fallback.

⚠️  SDNN only (not RMSSD) from HKQuantityType.heartRateVariabilitySDNN.
    Apple Watch measures ~every 2-5 hours when still.
    → Use personal baseline comparison, not absolute thresholds.

⚠️  Sleep stages (deep/rem/core) require iOS 16+ and watchOS 9+.
    Older devices return .asleepUnspecified.
    → Graceful fallback: duration + efficiency only.

⚠️  Must test on real device with real Apple Watch.
    Simulator has minimal HealthKit support.
```

### References

- [Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Reading data from HealthKit](https://developer.apple.com/documentation/healthkit/reading-data-from-healthkit)
- [HKCategoryValueSleepAnalysis](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)
- [WWDC22 — What's new in HealthKit (sleep stages)](https://developer.apple.com/videos/play/wwdc2022/10005/)
- [WWDC19 — Exploring heartbeat series](https://developer.apple.com/videos/play/wwdc2019/218/)
- [Marco Altini — Apple Watch HRV explained](https://marcoaltini.substack.com/p/apple-watch-and-heart-rate-variability)

---

## 5. Score Algorithms

### 5.1 Stress Score (0-100)

```
Input:
  - currentSDNN: Double (latest HRV from HealthKit, ms)
  - currentRHR: Double (today's resting HR, bpm)
  - baselineSDNN: Double (30-day rolling median)
  - baselineRHR: Double (30-day rolling median)

Algorithm:
  ┌────────────────────────────────┐
  │ HRV Component (70% weight)     │
  │                                │
  │ lnSDNN = ln(currentSDNN)       │
  │ lnBase = ln(baselineSDNN)      │
  │ ratio  = lnSDNN / lnBase       │
  │ clamp ratio to [0.5, 1.5]     │
  │                                │
  │ hrvStress = (1.5 - ratio) / 1.0│
  │           × 100                │
  │ (inverted: low HRV = high     │
  │  stress)                       │
  └────────────────────────────────┘

  ┌────────────────────────────────┐
  │ HR Component (30% weight)      │
  │                                │
  │ deviation = (RHR - baseRHR)    │
  │           / baseRHR            │
  │ clamp to [-0.3, +0.3]         │
  │                                │
  │ hrStress = (deviation + 0.3)   │
  │          / 0.6 × 100           │
  └────────────────────────────────┘

  stressScore = hrvStress × 0.70 + hrStress × 0.30
  clamp to [0, 100]

Output:
  score: Int (0 = no stress, 100 = max stress)
  level: "low" (0-33) | "moderate" (34-66) | "high" (67-100)
```

### 5.2 Sleep Score (0-100)

```
Input:
  - SleepData from HealthKit (stages, timestamps)
  - previousWeekBedtimes: [Date] (for consistency)
  - targetHours: Double (user preference, default 8)

Components:
  ┌─────────────────────────────────────────┐
  │ 1. Duration (max 30 pts)                │
  │    7-9h = 30  │  6-7h = 20-30 linear   │
  │    4-6h = 5-20 linear  │  <4h = 0-5    │
  │    >9h = slight penalty                 │
  ├─────────────────────────────────────────┤
  │ 2. Efficiency (max 20 pts)              │
  │    efficiency = sleepMin / inBedMin     │
  │    ≥90% = 20  │  85-90% = 16-20        │
  │    70-85% = 0-16  │  <70% = 0-4        │
  ├─────────────────────────────────────────┤
  │ 3. Deep Sleep (max 20 pts)              │
  │    target: 15-25% of total sleep        │
  │    in range = 20  │  10-15% = 12-20     │
  │    5-10% = 5-12  │  <5% = 0-5          │
  ├─────────────────────────────────────────┤
  │ 4. REM (max 15 pts)                     │
  │    target: 20-30% of total sleep        │
  │    in range = 15  │  15-20% = 10-15     │
  │    10-15% = 5-10  │  <10% = 0-5        │
  ├─────────────────────────────────────────┤
  │ 5. Consistency (max 15 pts)             │
  │    stdDev of bedtimes over 7 days       │
  │    ≤30min = 15  │  30-60min = 10-15     │
  │    60-120min = 0-10  │  >120min = 0     │
  └─────────────────────────────────────────┘

  sleepScore = sum of all components (max 100)

Output:
  score: Int (0-100)
  level: "poor" (0-40) | "fair" (41-60) | "good" (61-80) | "great" (81-100)
```

### 5.3 Energy Score (0-100)

```
Model: Battery charge/drain over 24 hours.
Start of day: carry over from last night's sleep charge.

  ┌──────────────────────────────────────────┐
  │ CHARGE (during sleep)                     │
  │                                           │
  │ base rate × HRV quality × HR factor      │
  │                                           │
  │ Deep sleep:  10 pts/hr × quality          │
  │ REM:          6 pts/hr × quality          │
  │ Light sleep:  4 pts/hr × quality          │
  │ Restful wake: 2 pts/hr (if HRV > base)   │
  │                                           │
  │ quality = currentSDNN / baselineSDNN      │
  │ hrFactor = baselineRHR / currentHR        │
  ├──────────────────────────────────────────┤
  │ DRAIN (during activity/stress)            │
  │                                           │
  │ Workout:     5-30 pts/hr (by HR zone)     │
  │ Daily stress: 1-5 pts/hr (by HR elev.)   │
  │ + calorie factor: activeKcal/500 × 5     │
  ├──────────────────────────────────────────┤
  │ RECALCULATION                             │
  │                                           │
  │ Hourly via background delivery.           │
  │ On app open: reconstruct from last        │
  │ known state + HealthKit samples since.    │
  └──────────────────────────────────────────┘

Timeline example:
  ┌───────────────────────────────────────────┐
  │ 100│         ╭──╮                         │
  │    │    ╭───╯  ╰──╮                       │
  │  75│───╯           ╰──╮      charge       │
  │    │                   ╰──╮  during        │
  │  50│                      ╰──╮  rest       │
  │    │  drain during            ╰╮           │
  │  25│  activity                  ╰──        │
  │    │                                       │
  │   0└───────────────────────────────────    │
  │    6am  9am  12pm  3pm  6pm  9pm  12am    │
  └───────────────────────────────────────────┘

Output:
  level: Double (0-100)
  state: "depleted" (0-25) | "low" (26-50) | "good" (51-75) | "charged" (76-100)
```

### Baseline Calculation

```
Rolling 30-day median for each metric.
Recalculate daily.
First 7 days: use population defaults, gradually blend toward personal.

Population defaults:
  SDNN:        40 ms (healthy adult average)
  Resting HR:  65 bpm
  Sleep:       7.0 hours

Blending (first 30 days):
  weight = min(dayCount / 30, 1.0)
  baseline = personal × weight + population × (1 - weight)
```

---

## 6. UI Structure

### Navigation (TabView)

```
TabView {
    TodayView()          // tab 1: main dashboard
    TrendsView()         // tab 2: 7/30/90 day charts
    LabsPlaceholder()    // tab 3: "Coming in v3" placeholder
    SettingsView()       // tab 4: preferences
}
```

### Screen: TodayView

```
ScrollView {
    // 1. Header
    GreetingHeader(name:, date:)

    // 2. Three Score Rings (horizontal)
    HStack(spacing: 12) {
        ScoreRing(title: "Stress", score: 32, color: .amber, level: "Low")
        ScoreRing(title: "Sleep",  score: 82, color: .purple, level: "Great")
        ScoreRing(title: "Energy", score: 75, color: .green, level: "Good")
    }

    // 3. Insight Card (v1: template-based, v2: LLM)
    InsightCard(text: "Your stress is low thanks to...")

    // 4. Vitals Grid (2x2)
    VitalsGrid {
        VitalCard(icon: "heart", label: "Resting HR", value: "58", unit: "bpm")
        VitalCard(icon: "waveform", label: "HRV", value: "48", unit: "ms")
        VitalCard(icon: "moon", label: "Sleep", value: "7h 24m")
        VitalCard(icon: "flame", label: "Active", value: "410", unit: "kcal")
    }

    // 5. 7-Day Sparklines
    WeeklyTrendCard {
        SparklineRow(label: "Stress", data: [...], color: .amber)
        SparklineRow(label: "Sleep",  data: [...], color: .purple)
        SparklineRow(label: "Energy", data: [...], color: .green)
    }

    // 6. Privacy Badge
    PrivacyBadge()  // "100% on-device · zero cloud"
}
```

### Screen: TrendsView

```
ScrollView {
    // Period picker: 7D | 30D | 90D
    Picker("Period", selection: $period) { ... }

    // Score trend chart (Swift Charts)
    Chart {
        ForEach(scores) { score in
            LineMark(x: .value("Date", score.date),
                     y: .value("Stress", score.stressScore))
        }
    }

    // Sleep breakdown chart (stacked bar)
    Chart {
        ForEach(sleepHistory) { night in
            BarMark(...)  // deep + rem + core stacked
        }
    }

    // HRV trend with baseline overlay
    Chart {
        LineMark(...)       // daily HRV
        RuleMark(y: ...)    // baseline as dashed line
    }
}
```

### Screen: SettingsView

```
Form {
    Section("Profile") {
        TextField("Name", ...)
        Stepper("Birth year", ...)
        Stepper("Sleep target: \(hours)h", ...)
    }
    Section("Health Data") {
        Button("Reconnect Apple Health")
        Text("Last sync: 2 min ago")
    }
    Section("About") {
        Link("Source Code (GitHub)")
        Text("Version 1.0.0")
        Text("All data stored on this device only.")
    }
}
```

### Design Tokens

```swift
// Sources/Design/Theme.swift

enum SomatiqColor {
    // Backgrounds
    static let bg          = Color(hex: "#0D0D14")
    static let card        = Color(hex: "#1A1A24")
    static let cardBorder  = Color.white.opacity(0.06)

    // Text
    static let textPrimary   = Color.white
    static let textSecondary = Color(hex: "#A0A0B0")
    static let textTertiary  = Color(hex: "#6B6B7B")
    static let textMuted     = Color(hex: "#4A4A5A")

    // Semantic
    static let stress    = Color(hex: "#FBBF24")   // amber
    static let sleep     = Color(hex: "#8B5CF6")   // purple
    static let energy    = Color(hex: "#34D399")   // green
    static let danger    = Color(hex: "#EF4444")   // red
    static let accent    = Color(hex: "#6366F1")   // indigo

    // Gradients
    static let stressGradient = LinearGradient(
        colors: [Color(hex: "#F59E0B"), Color(hex: "#FBBF24")],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let sleepGradient = LinearGradient(
        colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let energyGradient = LinearGradient(
        colors: [Color(hex: "#10B981"), Color(hex: "#34D399")],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}
```

---

## 7. Project Structure

```
Somatiq/
├── SomatiqApp.swift                    # @main, ModelContainer, TabView
├── Info.plist                          # HealthKit usage descriptions
│
├── Models/
│   ├── DailyScore.swift               # @Model
│   ├── UserBaseline.swift             # @Model
│   ├── EnergyReading.swift            # @Model
│   └── UserPreferences.swift          # @Model
│
├── Services/
│   ├── HealthKitService.swift         # HealthKit queries
│   ├── ScoreEngine.swift              # Stress/Sleep/Energy calc
│   ├── BaselineService.swift          # 30-day rolling median
│   └── InsightGenerator.swift         # Template-based insights (v1)
│
├── ViewModels/
│   ├── TodayViewModel.swift           # @Observable
│   ├── TrendsViewModel.swift          # @Observable
│   └── SettingsViewModel.swift        # @Observable
│
├── Views/
│   ├── Today/
│   │   ├── TodayView.swift            # Main dashboard
│   │   ├── ScoreRing.swift            # Animated circular gauge
│   │   ├── InsightCard.swift          # Daily insight
│   │   ├── VitalsGrid.swift           # 2x2 vital cards
│   │   ├── VitalCard.swift            # Single vital metric
│   │   ├── WeeklyTrendCard.swift      # 7-day sparklines
│   │   └── PrivacyBadge.swift         # Footer badge
│   │
│   ├── Trends/
│   │   ├── TrendsView.swift           # Charts screen
│   │   ├── ScoreTrendChart.swift      # Line chart
│   │   ├── SleepBreakdownChart.swift  # Stacked bar
│   │   └── HRVTrendChart.swift        # Line + baseline
│   │
│   ├── Settings/
│   │   └── SettingsView.swift
│   │
│   ├── Onboarding/
│   │   ├── OnboardingView.swift       # Welcome + HealthKit permission
│   │   └── HealthKitPermissionView.swift
│   │
│   └── Components/
│       ├── GlassCard.swift            # Reusable glassmorphism card
│       └── AnimatedNumber.swift       # Count-up number animation
│
├── Design/
│   ├── Theme.swift                    # Colors, gradients, spacing
│   └── Fonts.swift                    # Typography scale
│
└── Utilities/
    ├── Date+Extensions.swift          # startOfDay, etc.
    ├── Color+Hex.swift                # Color(hex:) initializer
    └── Statistics.swift               # median(), stddev()
```

---

## 8. Implementation Phases

### Phase 1: Foundation (Week 1-2)

```
□ Create Xcode project (SwiftUI, iOS 17+)
□ Set up project structure (folders as above)
□ Configure capabilities:
    - HealthKit (read)
    - Background Modes (background fetch)
□ Add Info.plist keys:
    - NSHealthShareUsageDescription
    - NSHealthUpdateUsageDescription (even if not writing)
□ Implement Theme.swift (colors, gradients, typography)
□ Implement Color+Hex.swift extension
□ Implement SwiftData models (DailyScore, UserBaseline, etc.)
□ Create ModelContainer in SomatiqApp.swift
□ Build GlassCard reusable component
□ Build TabView shell with 4 tabs
```

### Phase 2: HealthKit (Week 3-4)

```
□ Implement HealthKitService
    □ requestAuthorization()
    □ queryHRV(last:)
    □ queryRestingHR()
    □ querySleep(for:)
    □ queryActiveEnergy(for:)
    □ querySteps(for:)
    □ enableBackgroundDelivery()
□ Implement BaselineService
    □ updateBaseline(metric:value:) — rolling 30-day median
    □ getBaseline(metric:) -> Double
    □ blendWithPopulationDefault(dayCount:personal:)
□ Build OnboardingView
    □ Welcome screen
    □ HealthKit permission request
    □ Handle "denied" gracefully (show explanation)
□ Test on real device with Apple Watch
```

**References:**
- [HealthKit Tutorial — Kodeco](https://www.kodeco.com/459-healthkit-tutorial-with-swift-getting-started)
- [Reading HealthKit data in SwiftUI — CreateWithSwift](https://www.createwithswift.com/reading-data-from-healthkit-in-a-swiftui-app/)
- [HealthKit + Swift Charts — Medium](https://medium.com/@joaovitormbj/healthkit-swift-charts-0fbb91ef2173)

### Phase 3: Score Engine (Week 5-6)

```
□ Implement ScoreEngine
    □ calculateStress(sdnn:rhr:baselineSDNN:baselineRHR:) -> StressResult
    □ calculateSleep(data:history:target:) -> SleepResult
    □ calculateEnergy(sleepData:hrvData:activityData:baseline:) -> EnergyResult
□ Implement InsightGenerator (template-based)
    □ Templates for each score combination
    □ "Your stress is {level} because {reason}"
    □ Dynamic reason selection based on data
□ Unit tests for score calculations
    □ Test edge cases: no data, first day, extreme values
    □ Test baseline blending
    □ Test energy charge/drain math
□ Integration test: HealthKit → ScoreEngine → SwiftData
```

### Phase 4: Today Screen (Week 7-8)

```
□ Implement TodayViewModel
    □ Load today's scores from SwiftData
    □ If no scores, trigger recalculation
    □ Format data for views
□ Build ScoreRing component
    □ SVG-like ring using Canvas or Shape
    □ Animated stroke from 0 to score
    □ Gradient stroke color
    □ Glow effect (shadow with score color)
    □ Score number with count-up animation
    □ Label + level text
□ Build InsightCard
□ Build VitalCard + VitalsGrid
□ Build WeeklyTrendCard with sparkline bars
□ Build PrivacyBadge
□ Compose TodayView
□ Add pull-to-refresh (recalculate scores)
□ Handle empty state (no Apple Watch data yet)
```

**References:**
- [Custom gauge/ring in SwiftUI — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10037/)
- [SwiftUI Canvas for custom drawing](https://developer.apple.com/documentation/swiftui/canvas)

### Phase 5: Trends Screen (Week 9-10)

```
□ Implement TrendsViewModel
    □ Fetch DailyScore history (7/30/90 days)
    □ Aggregate data for charts
□ Build period picker (7D / 30D / 90D segmented control)
□ Build ScoreTrendChart (Swift Charts)
    □ LineMark for each score type
    □ Gradient area fill
    □ Interactive: drag to inspect data point
    □ Baseline RuleMark as dashed line
□ Build SleepBreakdownChart
    □ Stacked BarMark (deep + rem + core)
    □ Color-coded per sleep stage
□ Build HRVTrendChart
    □ LineMark + AreaMark
    □ Baseline overlay
□ Compose TrendsView
```

**References:**
- [Swift Charts tutorial — CreateWithSwift](https://www.createwithswift.com/using-swift-charts-on-a-swiftui-app/)
- [WWDC22 — Hello Swift Charts](https://developer.apple.com/videos/play/wwdc2022/10136/)
- [WWDC23 — Explore pie charts](https://developer.apple.com/videos/play/wwdc2023/10037/)

### Phase 6: Settings + Polish (Week 11-12)

```
□ Build SettingsView
    □ Profile section (name, birth year, sleep target)
    □ Health data section (reconnect, last sync)
    □ About section (version, GitHub link, privacy statement)
□ Implement background score recalculation
    □ BGAppRefreshTask registration
    □ enableBackgroundDelivery for HRV + sleep
    □ Recalculate on new data arrival
□ Add haptic feedback
    □ .impact(.light) on score ring animation complete
    □ .selection on tab switch
□ Dark mode polish
    □ Test all screens in dark mode (only mode we support)
    □ Verify contrast ratios for accessibility
□ Empty states for all screens
□ Error handling (HealthKit unavailable, no Watch, etc.)
□ App icon design
□ Launch screen
```

### Phase 7: Testing + App Store (Week 13-14)

```
□ Test on multiple devices (iPhone 15, 15 Pro, 16)
□ Test with real Apple Watch data (wear for 7+ days)
□ TestFlight beta distribution
□ Write privacy policy (no data collection statement)
□ Prepare App Store listing
    □ Screenshots (6.7" and 6.1")
    □ App description
    □ Keywords: health, HRV, stress, sleep, private, local
    □ Category: Health & Fitness
□ Add medical disclaimer in app and listing
□ Submit to App Store review
```

---

## 9. Xcode Project Setup

### Capabilities

```
☑ HealthKit
    ☑ Clinical Health Records: OFF
    ☑ Background Delivery: ON
☑ Background Modes
    ☑ Background fetch
```

### Info.plist Keys

```xml
<key>NSHealthShareUsageDescription</key>
<string>Somatiq reads your heart rate, HRV, sleep, and activity data
to calculate your personal Stress, Sleep, and Energy scores.
All data stays on your device.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Somatiq does not write any data to Apple Health.</string>
```

### Build Settings

```
iOS Deployment Target: 17.0
Swift Language Version: 5.9+
Supported Destinations: iPhone
Device Orientation: Portrait only
```

---

## 10. Key Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Apple Watch data sparse (HRV every 2-5h) | Stress score jumpy | Use rolling average of last 3-5 samples; show "last updated" timestamp |
| No baseline data for first 7 days | Scores meaningless | Use population defaults, show "calibrating" badge on scores |
| Energy algorithm feels wrong | Users distrust app | Start conservative (smaller drain rates); add manual "how do you feel?" calibration in v2 |
| HealthKit permission denied silently | App shows empty | Prominent empty state with re-request CTA; link to Settings > Health |
| App Store rejection for health claims | Launch delayed | Never say "diagnose" or "medical". Use "wellness insights" language. Add disclaimer |
| Sleep reconstruction from HKCategorySample fragments | Incorrect sleep sessions | Group samples within 2h gap tolerance; filter by source (Apple Watch only) |

---

## 11. References

### Apple Documentation
- [HealthKit Framework](https://developer.apple.com/documentation/healthkit)
- [SwiftData Framework](https://developer.apple.com/documentation/swiftdata)
- [Swift Charts](https://developer.apple.com/documentation/charts)
- [Background Tasks](https://developer.apple.com/documentation/backgroundtasks)
- [App Store Review Guidelines — Health](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research)

### WWDC Sessions
- [WWDC22 — What's new in HealthKit](https://developer.apple.com/videos/play/wwdc2022/10005/) (sleep stages)
- [WWDC22 — Hello Swift Charts](https://developer.apple.com/videos/play/wwdc2022/10136/)
- [WWDC23 — Meet SwiftData](https://developer.apple.com/videos/play/wwdc2023/10187/)
- [WWDC23 — Explore SwiftUI Animation](https://developer.apple.com/videos/play/wwdc2023/10156/)
- [WWDC19 — Exploring Heartbeat Series](https://developer.apple.com/videos/play/wwdc2019/218/)

### HRV Science
- [Marco Altini — Apple Watch HRV](https://marcoaltini.substack.com/p/apple-watch-and-heart-rate-variability)
- [Elite HRV — RMSSD vs SDNN](https://help.elitehrv.com/article/68-what-are-hrv-score-rmssd-ln-rmssd-sdnn-nn50-and-pnn50)
- [Kubios — HRV Analysis Methods](https://www.kubios.com/blog/hrv-analysis-methods/)
- [Baevsky Stress Index](https://forum.intervals.icu/t/baevsky-stress-index/7457)

### Body Battery / Energy
- [Firstbeat — Stress & Recovery White Paper](https://www.firstbeat.com/en/stress-recovery-analysis-method-based-24-hour-heart-rate-variability-firstbeat-white-paper-2/)
- [Garmin Body Battery Wiki](https://wiki.garminrumors.com/Body_Battery)

### Sleep Science
- [AASM Sleep Staging Guidelines](https://aasm.org/clinical-resources/scoring-manual/)
- [Fitbit Sleep Score Breakdown](https://www.androidauthority.com/fitbit-sleep-score-1111682/)

### Tutorials
- [HealthKit Tutorial — Kodeco](https://www.kodeco.com/459-healthkit-tutorial-with-swift-getting-started)
- [SwiftUI + HealthKit — CreateWithSwift](https://www.createwithswift.com/reading-data-from-healthkit-in-a-swiftui-app/)
- [Swift Charts + HealthKit — Medium](https://medium.com/@joaovitormbj/healthkit-swift-charts-0fbb91ef2173)

### Competitor Reference (for UX inspiration)
- [Athlytic](https://www.athlyticapp.com/) — closest local-first competitor
- [HealthGPT (Stanford)](https://github.com/StanfordBDHG/HealthGPT) — local LLM + HealthKit reference
- [Halo (open source ring)](https://github.com/cyrilzakka/Halo) — Swift + BLE health tracking
