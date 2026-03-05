# Somatiq — Feature Roadmap

> "Know your body. Own your data."
> Private health intelligence, on device.

## v1.0 — Core (MVP)

### 3 Score Cards
- **Stress Score** (0-100) — HRV (SDNN) + resting HR vs personal 30-day baseline
- **Sleep Score** (0-100) — duration + efficiency + deep/REM % + consistency
- **Energy Score** (0-100) — charge during sleep, drain during activity/stress

### Dashboard
- Today view with 3 score rings
- Trend sparklines (7 days)
- Color-coded states: green/yellow/red
- Labs tab as placeholder: "Coming in v3"

### Data Source
- HealthKit only (Apple Watch required)
- HRV, heart rate, resting HR, sleep stages, active energy, steps

### Storage
- SwiftData, 100% on-device
- No accounts, no cloud, no analytics

### Tech
- SwiftUI, iOS 17+, Swift Charts
- Dark premium UI (Welltory/Oura style)

---

## v2.0 — AI Insights

### On-Device LLM
- **Qwen3.5-9B** (4-bit) — the only on-device chat model
- Via MLX Swift, zero network calls

### Features
- Daily health summary ("your stress is elevated due to poor sleep")
- Score explanations (tap score → AI explains why)
- Trend analysis ("your HRV has been declining for 5 days")
- Thinking mode toggle: fast answers vs deep reasoning

### Model Download
- On-demand download from HuggingFace (one time)
- Stored locally, works offline after download

---

## v3.0 — Lab Results

### Photo → Biomarkers
- Qwen3.5 vision: photo of lab report → structured data
- No separate OCR step (model is natively multimodal)
- Manual entry as fallback

### Biomarker Tracking
- Optimal ranges (not just reference ranges)
- Trends over time
- AI interpretation of results

---

## v4.0 — Platform

### Apple Watch
- Complications: Energy Score, Stress Score
- Glance view with 3 scores

### Widgets
- Home screen widgets (WidgetKit)
- Lock screen widgets

### Export
- CSV/JSON export of all data
- No lock-in, your data is yours

---

## Principles
- Zero cloud. Everything on device.
- Zero accounts. No sign-up required.
- Zero tracking. No analytics, no telemetry.
- Open source.
