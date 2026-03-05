# Somatiq — MVP Backlog

> Scope: только MVP (`v1.0 Core`) из `FEATURES.md` и `IMPLEMENTATION.md`.
> Формат: эпик → стори → таски.

## MVP Scope

- 3 ключевых скора: Stress, Sleep, Energy (все в диапазоне `0-100`)
- Главный экран Today (rings, insight, vitals, 7-day trends)
- Экран Trends (7/30/90 + графики)
- Источник данных: только HealthKit (read-only, Apple Watch)
- Хранение: SwiftData, 100% on-device
- Settings + privacy UX
- Background recalculation + базовая надежность
- Подготовка к релизу в App Store

## Out of Scope (после MVP)

- On-device LLM и AI Insights v2
- Lab parsing / biomarkers v3
- Apple Watch app/complications, Widgets, Export v4

## Delivery Status (2026-03-05)

### Implemented in repository

- Foundation, SwiftData models, services, score engine, Today/Trends/Settings/Labs placeholder UI
- Onboarding + HealthKit authorization flow
- Background task registration + unified recalculation pipeline for foreground/background
- Trends inspector interactions (tap/drag), stacked sleep breakdown, retry/empty states
- Unified app-level DI container (`AppDependencies`) and service-layer integration tests
- Unit tests for score logic, baseline blending, and data pipeline integration
- Release artifacts: privacy policy, disclaimer, listing draft, submit checklist, screenshot guide, TestFlight rollout plan

### Requires local/device execution

- Real-device validation with Apple Watch data (7+ days)
- TestFlight rollout and App Store submission actions
- Capture production screenshots on physical devices

## Priority Model

- `P0` — обязательно для релиза MVP
- `P1` — важно для качества MVP, можно добрать после `P0`
- `P2` — улучшения/полировка, не блокируют релиз

## Story Priorities (MVP)

| Story | Priority | Почему |
|---|---|---|
| E1-S1 | P0 | Без базовой конфигурации проект не стартует |
| E1-S2 | P0 | Нужен каркас приложения и навигация |
| E1-S3 | P1 | UI-система важна, но не блокирует первую поставку |
| E2-S1 | P0 | Модели данных — база всего пайплайна |
| E2-S2 | P0 | Нужна сохранность и чтение данных |
| E3-S1 | P0 | Без разрешений и онбординга нет данных |
| E3-S2 | P0 | Ключевой ingestion данных из HealthKit |
| E3-S3 | P1 | Background повышает ценность, но не блокирует MVP |
| E4-S1 | P0 | Baseline обязателен для персонализированных скоров |
| E4-S2 | P0 | Stress — один из 3 core-скоров |
| E4-S3 | P0 | Sleep — один из 3 core-скоров |
| E4-S4 | P0 | Energy — один из 3 core-скоров |
| E4-S5 | P1 | Insight важен, но может быть упрощен на старте |
| E5-S1 | P0 | TodayViewModel связывает расчет и UI |
| E5-S2 | P0 | Score rings — основной сценарий Today |
| E5-S3 | P0 | Vitals/insight/trends завершают MVP экран |
| E6-S1 | P0 | История и периоды — ядро Trends |
| E6-S2 | P1 | Расширенная визуализация и интерактив — улучшение |
| E7-S1 | P0 | Базовые настройки обязательны для пользователя |
| E7-S2 | P0 | Надежность и ошибки — обязательны для релиза |
| E7-S3 | P2 | Полировка UX не блокирует выпуск |
| E8-S1 | P0 | Тесты критичны для стабильного релиза |
| E8-S2 | P0 | App Store readiness обязателен для ship |

## Sprint Plan (MVP)

> Базовый план: `6` спринтов по `2 недели` (12 недель) + буфер на багфикс перед submit.

### Sprint 1 — Foundation & Data Base
- Goal: поднять рабочий каркас приложения и persistence-слой
- Stories: `E1-S1`, `E1-S2`, `E2-S1`, `E2-S2`, `E3-S1`
- Exit criteria: app запускается, HealthKit permission flow есть, SwiftData сохраняет/читает daily data

### Sprint 2 — Health Ingestion & Baseline
- Goal: стабильно забирать данные из HealthKit и считать baseline
- Stories: `E3-S2`, `E4-S1`, `E5-S1`, `E1-S3` (P1, если остается емкость)
- Exit criteria: данные HRV/sleep/HR/energy/steps поступают, baseline обновляется, Today VM отдает состояние

### Sprint 3 — Core Score Engine
- Goal: реализовать 3 core-скора с тестами формул
- Stories: `E4-S2`, `E4-S3`, `E4-S4`, `E8-S1` (часть unit-тестов)
- Stretch: `E4-S5` (P1)
- Exit criteria: Stress/Sleep/Energy считаются `0-100`, покрыты ключевые edge cases

### Sprint 4 — Today Experience
- Goal: собрать полноценный Today экран
- Stories: `E5-S2`, `E5-S3`, `E7-S1`, `E7-S2` (первая часть)
- Exit criteria: rings + insight + vitals + 7-day block работают на реальных данных, есть базовые empty/error states

### Sprint 5 — Trends, Background, Reliability
- Goal: завершить аналитический и фоновый контур
- Stories: `E6-S1`, `E6-S2` (P1), `E3-S3` (P1), `E7-S2` (завершение), `E7-S3` (P2 при наличии времени)
- Exit criteria: Trends 7/30/90 работает, background recalc активен, критические ошибки закрыты

### Sprint 6 — Release Readiness
- Goal: довести качество до production и отправить билд
- Stories: `E8-S1` (завершение), `E8-S2`
- Exit criteria: TestFlight пройден, privacy/disclaimer готовы, App Store пакет собран

## Scope Cutline при риске сроков

1. Сначала переносить `P2`: `E7-S3`
2. Затем переносить `P1`: `E6-S2`, `E4-S5`, `E3-S3`, `E1-S3`
3. `P0` не переносить без пересмотра MVP-цели

---

## EPIC E1 — Foundation & App Skeleton

### Story E1-S1 — Инициализировать iOS-проект и базовую конфигурацию
**Критерии приемки**
- Проект собирается на iOS 17+
- Включены нужные capabilities и Info.plist ключи

**Tasks**
- [ ] Создать Xcode-проект SwiftUI (`iOS 17+`, portrait only)
- [ ] Включить `HealthKit` capability
- [ ] Включить `Background Modes` (`Background fetch`)
- [ ] Добавить `NSHealthShareUsageDescription`
- [ ] Добавить `NSHealthUpdateUsageDescription`
- [ ] Настроить `SomatiqApp.swift` с `ModelContainer`

### Story E1-S2 — Подготовить структуру модулей
**Критерии приемки**
- Структура директорий соответствует архитектуре
- Есть каркас экранов и ViewModels

**Tasks**
- [ ] Создать папки `Models/`, `Services/`, `ViewModels/`, `Views/`, `Design/`, `Utilities/`
- [ ] Добавить каркасы `TodayView`, `TrendsView`, `SettingsView`, `LabsPlaceholderView`
- [ ] Добавить каркасы `TodayViewModel`, `TrendsViewModel`, `SettingsViewModel`
- [ ] Собрать `TabView` с 4 вкладками (`Labs` как placeholder “Coming in v3”)

### Story E1-S3 — Внедрить дизайн-токены и базовые UI-компоненты
**Критерии приемки**
- Тема и цветовые токены централизованы
- Базовые reusable-компоненты переиспользуются

**Tasks**
- [ ] Реализовать `Design/Theme.swift` (палитра, градиенты, semantic colors)
- [ ] Реализовать `Utilities/Color+Hex.swift`
- [ ] Создать `Views/Components/GlassCard.swift`
- [ ] Создать `Views/Components/AnimatedNumber.swift`

---

## EPIC E2 — Data Model & Persistence (SwiftData)

### Story E2-S1 — Описать модели данных MVP
**Критерии приемки**
- Модели покрывают хранение daily scores, baseline, energy history, prefs
- Есть миграционно-безопасные значения по умолчанию

**Tasks**
- [ ] Реализовать `DailyScore`
- [ ] Реализовать `UserBaseline`
- [ ] Реализовать `EnergyReading`
- [ ] Реализовать `UserPreferences`
- [ ] Добавить конвенции даты (`startOfDay`) для уникальности daily-записей

### Story E2-S2 — Реализовать Storage слой
**Критерии приемки**
- Можно сохранять/читать daily scores и baselines
- Есть запрос истории за период (7/30/90)

**Tasks**
- [ ] Создать `StorageService` с методами `save`, `fetchDailyScores`, `fetchLatest`
- [ ] Добавить upsert-логику для `DailyScore` по дате
- [ ] Добавить метод чтения `UserPreferences`
- [ ] Добавить метод чтения/обновления baseline-метрик

---

## EPIC E3 — HealthKit Integration

### Story E3-S1 — Разрешения и онбординг HealthKit
**Критерии приемки**
- Пользователь проходит онбординг и запрос доступа
- При denied/empty корректный fallback UX

**Tasks**
- [ ] Реализовать `OnboardingView` + `HealthKitPermissionView`
- [ ] Реализовать `requestAuthorization()`
- [ ] Добавить обработку состояний: authorized / denied / no data
- [ ] Показать CTA для перехода в Settings при denied

### Story E3-S2 — Сбор метрик из HealthKit
**Критерии приемки**
- Доступны API для HRV, resting HR, sleep, active energy, steps
- Запросы отдают нормализованные DTO без UI-логики

**Tasks**
- [ ] Реализовать `queryHRV(last:)`
- [ ] Реализовать `queryRestingHR()`
- [ ] Реализовать `querySleep(for:)` с сегментами (`deep/rem/core/awake/unspecified`)
- [ ] Реализовать `queryActiveEnergy(for:)`
- [ ] Реализовать `querySteps(for:)`
- [ ] Учесть fallback на устройствах без sleep stages

### Story E3-S3 — Фоновая доставка данных
**Критерии приемки**
- Включена background delivery для ключевых типов
- Фоновая обработка не дублирует записи

**Tasks**
- [x] Реализовать `enableBackgroundDelivery()`
- [x] Зарегистрировать `BGAppRefreshTask`
- [x] Добавить перезапрос и recalc при приходе новых данных

---

## EPIC E4 — Baseline & Score Engine

### Story E4-S1 — Baseline service (30-day median)
**Критерии приемки**
- Baseline считается по rolling median
- Для первых дней работает blending с population defaults

**Tasks**
- [ ] Реализовать `BaselineService.updateBaseline(metric:value:)`
- [ ] Реализовать `BaselineService.getBaseline(metric:)`
- [ ] Реализовать blending `personal ↔ population` на первых 30 днях
- [ ] Добавить daily job обновления baseline

### Story E4-S2 — Stress score (0-100)
**Критерии приемки**
- Формула использует HRV+RHR и baseline
- Возвращается score + level (`low/moderate/high`)

**Tasks**
- [ ] Реализовать расчет HRV-компонента (логарифмический ratio + clamp)
- [ ] Реализовать расчет HR-компонента (deviation + clamp)
- [ ] Скомбинировать веса `0.7 / 0.3`
- [ ] Добавить классификацию уровня

### Story E4-S3 — Sleep score (0-100)
**Критерии приемки**
- Учитываются duration, efficiency, deep/REM, consistency
- Возвращается score + level (`poor/fair/good/great`)

**Tasks**
- [ ] Реализовать duration component
- [ ] Реализовать efficiency component
- [ ] Реализовать deep/REM components
- [ ] Реализовать consistency по stddev bedtime
- [ ] Добавить fallback без stage-данных

### Story E4-S4 — Energy score (0-100)
**Критерии приемки**
- Реализована модель charge/drain
- Возвращается score + state (`depleted/low/good/charged`)

**Tasks**
- [ ] Реализовать charge во время сна (deep/rem/light/restful wake)
- [ ] Реализовать drain для активности/стресса
- [ ] Добавить clamp итогового уровня `0...100`
- [ ] Сохранить `EnergyReading` таймлайн

### Story E4-S5 — Insight generator (template-based для MVP)
**Критерии приемки**
- Инсайт объясняет причины изменения score
- Тексты детерминированные и без медицинских claim’ов

**Tasks**
- [ ] Реализовать `InsightGenerator` c шаблонами по уровням score
- [ ] Добавить reason selection из доступных метрик
- [ ] Добавить безопасный wording (`wellness insights`, не diagnosis)

---

## EPIC E5 — Today Experience

### Story E5-S1 — TodayViewModel и загрузка состояния дня
**Критерии приемки**
- При открытии экрана видны актуальные данные
- При пустых данных запускается recalc + empty-state

**Tasks**
- [ ] Реализовать загрузку `DailyScore` за сегодня
- [ ] Реализовать fallback recalc при отсутствии записи
- [ ] Добавить pull-to-refresh
- [ ] Добавить timestamp `last updated`

### Story E5-S2 — Score rings (Stress/Sleep/Energy)
**Критерии приемки**
- Анимированные кольца корректно визуализируют `0-100`
- Цвета и уровни соответствуют теме

**Tasks**
- [ ] Реализовать `ScoreRing` (shape/canvas)
- [ ] Добавить animation stroke + glow
- [ ] Добавить count-up анимацию числа
- [ ] Добавить отображение label + level

### Story E5-S3 — Insight + Vitals + Weekly trends
**Критерии приемки**
- Экран содержит InsightCard, VitalsGrid, WeeklyTrendCard
- Блоки корректно работают с partial/empty данными

**Tasks**
- [ ] Реализовать `InsightCard`
- [ ] Реализовать `VitalCard` + `VitalsGrid`
- [ ] Реализовать `WeeklyTrendCard` со спарклайнами на 7 дней
- [ ] Добавить `PrivacyBadge` внизу экрана

---

## EPIC E6 — Trends Experience

### Story E6-S1 — TrendsViewModel и агрегация истории
**Критерии приемки**
- Периоды `7D/30D/90D` переключаются без ошибок
- История агрегируется и сортируется по датам

**Tasks**
- [x] Реализовать fetch истории по выбранному периоду
- [x] Добавить агрегации для charts
- [x] Добавить placeholder при недостатке данных

### Story E6-S2 — Графики трендов
**Критерии приемки**
- Есть line charts для score/HRV и stacked bar для sleep stages
- Пользователь может просматривать точки данных

**Tasks**
- [x] Реализовать `ScoreTrendChart`
- [x] Реализовать `SleepBreakdownChart`
- [x] Реализовать `HRVTrendChart` с baseline overlay
- [x] Добавить интерактив (tap/drag inspector)

---

## EPIC E7 — Settings, Privacy & Reliability

### Story E7-S1 — Settings и пользовательские предпочтения
**Критерии приемки**
- Пользователь может менять sleep target и профильные параметры
- Видно состояние синка и действие reconnect

**Tasks**
- [ ] Реализовать Profile section (имя, год рождения, sleep target)
- [ ] Реализовать Health Data section (reconnect, last sync)
- [ ] Реализовать About section (версия, GitHub, privacy text)

### Story E7-S2 — Надежность и обработка ошибок
**Критерии приемки**
- Приложение корректно обрабатывает no-watch/no-data/denied
- Нет критических падений при пустых или частичных данных

**Tasks**
- [x] Реализовать единый error mapping для HealthKit/Storage
- [x] Добавить empty-states для Today/Trends/Settings
- [x] Добавить retry actions для recoverable ошибок
- [x] Добавить логирование ошибок только локально (без telemetry)

### Story E7-S3 — UX polish
**Критерии приемки**
- Интерфейс консистентный в dark mode
- Контраст и micro-interactions соответствуют дизайну

**Tasks**
- [x] Добавить haptics (ring complete, tab select)
- [x] Проверить контрастность текста и semantic colors
- [x] Проверить адаптивность на 6.1"/6.7" iPhone

---

## EPIC E8 — Quality, Compliance & Release

### Story E8-S1 — Тестирование расчётов и интеграций
**Критерии приемки**
- Unit-тесты покрывают ключевые формулы и edge cases
- Интеграционный сценарий `HealthKit -> ScoreEngine -> SwiftData` стабилен

**Tasks**
- [x] Написать unit-тесты для stress/sleep/energy расчетов
- [x] Написать тесты baseline blending + clamping
- [x] Написать интеграционный тест пайплайна данных
- [ ] Провести device testing c реальными данными Apple Watch (7+ дней)

### Story E8-S2 — App Store readiness
**Критерии приемки**
- Собраны все маркетинговые и юридические артефакты
- Билд проходит TestFlight и готов к submit

**Tasks**
- [x] Подготовить privacy policy (no data collection / on-device only)
- [x] Добавить medical disclaimer в приложении и listing
- [ ] Подготовить скриншоты 6.1" и 6.7"
- [x] Подготовить App Store description + keywords
- [ ] Выполнить TestFlight beta rollout
- [x] Подготовить релиз-кандидат и submit checklist

---

## Release Milestone (MVP)

- [ ] Все стори из E1-E7 завершены и приняты
- [ ] Критические дефекты (`P0/P1`) закрыты
- [ ] Точность скоров валидирована на реальных данных
- [ ] Privacy/medical copy проверены перед релизом
- [ ] TestFlight feedback triage завершен
- [ ] App Store build отправлен на review
