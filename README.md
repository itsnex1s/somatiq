# Somatiq

**Know your body. Own your data.**  
Private iOS wellness app that computes daily **Stress**, **Sleep**, and **Energy** scores from Apple Health data.

---

## What is implemented (MVP)

- Native SwiftUI app (iOS 17+)
- 4 tabs: `Today`, `Trends`, `Labs (Coming in v3)`, `Settings`
- HealthKit read-only integration:
  - HRV (SDNN)
  - Heart rate / resting heart rate
  - Sleep analysis
  - Active energy
  - Steps
- SwiftData persistence (fully on-device)
- Refactored service orchestration layer:
  - `DashboardDataService` (Today pipeline + snapshot)
  - `TrendsDataService` (history loading by period)
  - `SettingsDataService` (preferences + Health reconnect)
- App-level dependency container: `AppDependencies` (single composition root for screens/services)
- Score engine:
  - Stress score `0...100`
  - Sleep score `0...100`
  - Energy score `0...100`
- Onboarding + Health permissions flow
- Background refresh recalculation pipeline (shared with foreground path)
- Interactive Trends inspector (tap/drag on charts)
- Unified error mapping + retry states + local-only logging
- Haptics polish (ring progress + tab switch)
- Unit and service-layer integration tests

---

## Tech stack

- `SwiftUI` (UI)
- `SwiftData` (local storage)
- `HealthKit` (health data source)
- `Swift Charts` (trends visualization)
- `Observation` (`@Observable` ViewModels)
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

> If this fails with “device not found” or “iOS platform is not installed”, install the iOS runtime in Xcode Components and re-run.

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
│   ├── App/                 # App entry, root tabs, app delegate
│   ├── Models/              # SwiftData models + health DTOs
│   ├── Services/            # HealthKit, orchestration, storage, baseline, scoring
│   ├── ViewModels/          # Thin UI state (Today/Trends/Settings)
│   ├── Views/               # Screens and reusable UI components
│   ├── Design/              # Theme tokens
│   └── Utilities/           # Date, statistics, color helpers
├── Tests/SomatiqTests/      # Unit tests
├── Resources/               # Info.plist, entitlements
├── backlog/                 # MVP backlog (epics/stories/tasks)
├── design/                  # Full design specification
├── release/                 # Privacy, disclaimer, App Store docs
├── project.yml              # XcodeGen project definition
└── Somatiq.xcodeproj        # Generated project
```

---

## Core architecture (data flow)

```text
TodayViewModel -> DashboardDataService
               -> HealthKitService + ScoreEngine + BaselineService + StorageService
               -> DashboardSnapshot -> SwiftUI

TrendsViewModel -> TrendsDataService -> StorageService -> SwiftUI
SettingsViewModel -> SettingsDataService -> StorageService/HealthKitService -> SwiftUI

SomatiqApp -> AppModelContainerFactory -> AppDependencies -> RootTabView
SomatiqAppDelegate -> AppModelContainerFactory -> DashboardDataService (background refresh)
```

---

## Important docs in this repo

- Product roadmap: `FEATURES.md`
- Implementation details: `IMPLEMENTATION.md`
- MVP backlog with priorities/sprints: `backlog/MVP_BACKLOG.md`
- Full design specification: `design/MVP_DESIGN_SPEC.md`
- Release docs:
  - `release/PRIVACY_POLICY.md`
  - `release/MEDICAL_DISCLAIMER.md`
  - `release/APP_STORE_LISTING.md`
  - `release/SUBMIT_CHECKLIST.md`
  - `release/SCREENSHOT_GUIDE.md`
  - `release/TESTFLIGHT_ROLLOUT.md`

---

## Privacy and medical notice

- Somatiq is local-first and read-only for HealthKit.
- No account and no telemetry are implemented in MVP.
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

---

## Next recommended steps

1. Install missing iOS runtime (if needed)
2. Run tests
3. Validate with real Apple Watch data (7+ days)
4. Complete TestFlight + App Store steps from `release/SUBMIT_CHECKLIST.md`
