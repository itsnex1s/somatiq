# Somatiq

**Know your body. Own your data.**
Private iOS wellness app that computes daily **Stress**, **Sleep**, **Energy**, and **Heart** scores from Apple Health data. On-device AI insights via local LLM.

---

## What is implemented

- Native SwiftUI app (iOS 17+)
- 4 tabs: `Today`, `Trends`, `AI Chat`, `Settings`
- HealthKit read-only integration:
  - HRV (SDNN + RMSSD from heartbeat series)
  - Heart rate / resting heart rate
  - Sleep analysis (stages, efficiency, bedtime)
  - Active energy + steps + workouts
  - Source ranking and purity tracking
- SwiftData persistence (fully on-device)
- Robust scoring engine with baseline-relative z-scores:
  - Stress score `0...100` (rest-window HRV + HR)
  - Sleep score `0...100` (duration, efficiency, regularity, physio recovery)
  - Body Battery score `0...100` (sleep charge - activity/stress drain)
  - Heart score `0...100` (HRV + RHR resilience proxy)
- Confidence-gated score publishing with smooth delta clamping
- Wellness reports with trigger detection (stress spike, battery low, HRV drop, etc.)
- On-device AI chat (Qwen 3.5 via MLX Swift)
- Lab analysis (PDF upload + on-device evaluation)
- Onboarding + Health permissions flow
- Background refresh recalculation pipeline
- Interactive Trends inspector (tap/drag on charts)
- Unified error mapping + local-only logging
- Unit and service-layer integration tests

---

## Tech stack

- `SwiftUI` (UI)
- `SwiftData` (local storage)
- `HealthKit` (health data source)
- `Swift Charts` (trends visualization)
- `Observation` (`@Observable` ViewModels)
- `MLX Swift LM` (on-device LLM inference — MLXLLM, MLXLMCommon)
- `XcodeGen` (project generation from `project.yml`)

---

## Requirements

1. macOS with Xcode installed
2. **iOS runtime/platform installed in Xcode Components**
   (`Xcode → Settings → Components`)
3. Xcode Command Line Tools
4. Homebrew (for `xcodegen`)

---

## Quick start

### 1) Install `xcodegen`

```bash
brew install xcodegen
```

### 2) Generate the Xcode project

```bash
xcodegen generate
```

This creates:

- `Somatiq.xcodeproj`

### 3) Open and run in Xcode

```bash
open Somatiq.xcodeproj
```

In Xcode:

1. Select scheme `Somatiq`
2. Choose iOS Simulator or real iPhone
3. Press `Run`

---

## Build and test from CLI

### List available destinations

```bash
xcodebuild -project Somatiq.xcodeproj -scheme Somatiq -showdestinations
```

### Run tests (example)

```bash
xcodebuild -project Somatiq.xcodeproj -scheme Somatiq -destination "platform=iOS Simulator,name=iPhone 16 Pro" test
```

> If this fails with "device not found" or "iOS platform is not installed", install the iOS runtime in Xcode Components and re-run.

---

## First-run behavior

- App shows onboarding
- User can grant Apple Health read access
- If user skips or denies permission, app still opens and shows fallback/empty states
- `Today` supports pull-to-refresh to recalculate scores

---

## Real-data testing recommendation

For realistic results, test on a **real iPhone + Apple Watch**:

1. Wear Apple Watch for several days
2. Ensure sleep tracking and heart data are present in Apple Health
3. Open app and refresh Today screen
4. Validate score changes and trend charts

Simulator HealthKit data is limited and often unsuitable for full validation.

---

## Project structure

```text
Somatiq/
├── Sources/
│   ├── App/                 # SomatiqApp, RootTabView, AppDependencies, AppDelegate
│   ├── Models/              # SwiftData models (DailyScore, WellnessReport, etc.) + health DTOs
│   ├── Services/            # HealthKit, ScoreEngine, DashboardDataService, AI, Storage
│   ├── ViewModels/          # @Observable VMs (Today, Trends, Settings, AIChat)
│   ├── Views/               # Screens (Today, Trends, AI, Settings, Analyses, Onboarding) + Components
│   ├── Design/              # Theme tokens (colors, gradients, spacing)
│   └── Utilities/           # Statistics, Date+Extensions, AppLog, AppErrorMapper
├── Tests/SomatiqTests/      # Unit + integration tests
├── Resources/               # Info.plist, entitlements, assets
├── design/                  # Core engine algorithm specification
├── project.yml              # XcodeGen project definition
└── Somatiq.xcodeproj        # Generated project
```

---

## Core architecture (data flow)

```text
TodayViewModel -> DashboardDataService
               -> HealthKitService + ScoreEngine + InsightGenerator + StorageService
               -> WellnessReportService
               -> DashboardSnapshot -> SwiftUI

TrendsViewModel -> TrendsDataService -> StorageService -> SwiftUI
AIChatViewModel -> AIChatService -> AIModelManager (MLX) + AIHealthContextService -> SwiftUI
SettingsViewModel -> SettingsDataService -> StorageService/HealthKitService -> SwiftUI

SomatiqApp -> AppModelContainerFactory -> AppDependencies -> RootTabView
SomatiqAppDelegate -> AppModelContainerFactory -> DashboardDataService (background refresh)
```

---

## Documentation

- Architecture and implementation: `IMPLEMENTATION.md`
- Core engine algorithm specification: `design/CORE_ENGINE_PRODUCTION_ALGORITHM.md`

---

## Privacy and medical notice

- Somatiq is local-first and read-only for HealthKit.
- AI runs fully on-device — no health data sent to cloud.
- No account and no telemetry.
- App provides wellness insights and is **not** a medical device.

---

## Troubleshooting

### `xcodebuild` says iOS destination/platform is unavailable

Install iOS runtime:

1. Open Xcode
2. `Settings → Components`
3. Install the required iOS platform/runtime
4. Retry `xcodebuild`

### No data appears in app

- Check Health permissions in iOS Settings
- Ensure Apple Watch is paired and worn
- Confirm Apple Health actually contains HRV/sleep/activity samples

### Trends screen is empty

You need at least a few days of saved `DailyScore` entries.
