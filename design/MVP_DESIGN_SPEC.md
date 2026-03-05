# Somatiq — MVP Design Specification

> База: `/Users/ilyasavelyeu/Documents/Code/Personal/Bioself/somatiq/design-draft.html`  
> Скоуп: только `v1.0 Core (MVP)` из roadmap

## 1) Цель и рамки

Создать единый дизайн-стандарт для MVP Somatiq, чтобы:
- UI выглядел консистентно во всех экранах;
- разработка шла без неоднозначностей по токенам, состояниям и поведению;
- handoff в разработку был детерминированным.

В MVP входят:
- `Today` (основной дашборд),
- `Trends` (7/30/90 дней),
- `Labs` placeholder (`Coming in v3`),
- `Settings`,
- onboarding + запрос HealthKit.

---

## 2) Платформы и адаптация

## 2.1 Поддерживаемые устройства

- iOS 17+, iPhone only, portrait only.
- Базовый дизайн-артборд: `393x852` (iPhone 15/16 Pro).

## 2.2 Поддерживаемые ширины

- Compact: `375`
- Base: `390/393`
- Large: `428/430`

## 2.3 Правила адаптации

- Горизонтальные отступы контента: `20pt` на всех размерах.
- Ширина карточек рассчитывается формулой:
  - `cardWidth = (screenWidth - 40 - gap*2) / 3`, где `gap = 12`.
- Нижний `TabBar` всегда фиксирован; контент скролла имеет нижний inset `>= 90pt`.
- Использовать `SafeArea`; статус-бар и Dynamic Island не кастомизировать в нативной реализации.

---

## 3) Дизайн-принципы

- Dark-first premium интерфейс.
- Data-first: сначала ключевые метрики, затем объяснение и контекст.
- Privacy-visible: на каждом основном экране явный сигнал «on-device / no cloud».
- Calm motion: короткие, мягкие анимации без визуального шума.

---

## 4) Design Tokens

## 4.1 Colors

### Base

| Token | Value | Usage |
|---|---|---|
| `bg/app` | `#0D0D14` | Основной фон экрана |
| `bg/page` | `#0A0A0F` | Внешний фон превью/контейнера |
| `bg/card` | `#1A1A24` | Карточки и поверхности |
| `border/subtle` | `rgba(255,255,255,0.06)` | Границы карточек |
| `border/soft` | `rgba(255,255,255,0.04)` | Вторичные границы |

### Text

| Token | Value | Usage |
|---|---|---|
| `text/primary` | `#FFFFFF` | Основной текст |
| `text/secondary` | `#C4C4D4` | Длинные описания |
| `text/tertiary` | `#6B6B7B` | Лейблы, подписи |
| `text/muted` | `#4A4A5A` | Дата, caption, secondary UI |

### Semantic + Metric

| Token | Value | Usage |
|---|---|---|
| `accent/indigo` | `#6366F1` | Акцент, активная вкладка, insight dot |
| `metric/stress` | `#FBBF24` | Stress metric |
| `metric/sleep` | `#8B5CF6` | Sleep metric |
| `metric/energy` | `#34D399` | Energy metric |
| `state/success` | `#34D399` | Good / Great / Charged / Low stress |
| `state/warning` | `#FBBF24` | Fair / Moderate / Low energy |
| `state/error` | `#F87171` | Poor / High stress / Depleted |

### Gradients

| Token | Value |
|---|---|
| `gradient/stress` | `#F59E0B -> #FBBF24` |
| `gradient/sleep` | `#6366F1 -> #8B5CF6` |
| `gradient/energy` | `#10B981 -> #34D399` |
| `gradient/insight-bg` | `rgba(99,102,241,0.12) -> rgba(52,211,153,0.08)` |

## 4.2 Typography

База драфта: `Inter`.  
Для нативного iOS: системный `SF Pro` с эквивалентными размерами/весами.

| Style | Size | Weight | Usage |
|---|---:|---:|---|
| `display/title` | 26 | 800 | Имя/заголовок Today |
| `headline/card-value` | 22 | 700/800 | Значения ring/vitals |
| `body` | 14 | 400 | Insight text |
| `label/section` | 13 | 600 | Названия секций |
| `label/small` | 11 | 500/600 | Подписи карточек/метрик |
| `caption` | 10 | 500 | Tab label, privacy text |
| `micro` | 9 | 500 | Day label в sparkline |

## 4.3 Spacing

Шкала: `4, 6, 8, 10, 12, 14, 16, 20, 24, 32`.

Ключевые значения:
- Page horizontal: `20`
- Section gap major: `20-24`
- Card internal padding: `14-16`
- Grid gap (vitals): `10`
- Ring row gap: `12`

## 4.4 Radius

| Token | Value |
|---|---:|
| `radius/device` | 48 |
| `radius/card-lg` | 20 |
| `radius/card-md` | 16 |
| `radius/pill` | 20 |
| `radius/spark-bar` | `4 4 2 2` |

## 4.5 Effects

- Card blur: `backdrop blur 10-20`
- Ring glow: drop shadow `0 0 6` с metric color `40%`
- Top shine line на score card: `1px` gradient white alpha
- Background glow: radial indigo/green haze над header

## 4.6 Motion

| Motion | Value | Notes |
|---|---|---|
| Ring progress | `1.5s ease-out` | На появлении/обновлении |
| Insight dot pulse | `2s ease-in-out infinite` | Если есть insight |
| Tab color transition | `0.2s` | Активная вкладка |
| Number count-up | `0.6-0.9s` | Score/vital value |

Если `Reduce Motion` включен:
- отключить pulse и count-up;
- ring обновлять без длительной анимации (`<= 0.2s`).

---

## 5) Информационная архитектура

Порядок вкладок:
1. `Today`
2. `Trends`
3. `Labs` (`Coming in v3`)
4. `Settings`

Навигация табовая, без глубоких стеков в MVP (кроме системных переходов в Settings/Health permissions).

---

## 6) Компонентные спецификации

## 6.1 `ScoreCard` + `ScoreRing`

### Назначение
Показать текущий score, визуальный прогресс и состояние.

### Состав
- контейнер карточки;
- ring (background + progress);
- значение score в центре;
- label метрики;
- статус (цветной текст).

### Размеры (base width 393)
- Карточка: `~109.7w x auto`
- Padding: `16 top/bottom`, `12 left/right`
- Radius: `20`
- Ring wrap: `80x80`
- Ring stroke: `6`
- Circle radius: `42`
- Circumference: `263.9`

### Правила прогресса
- `sleepProgress = sleepScore / 100`
- `energyProgress = energyScore / 100`
- `stressProgress = 1 - (stressScore / 100)`  
  (инверсия, т.к. меньший стресс = лучшее состояние)
- `dashOffset = 263.9 * (1 - progress)`

### Состояния текста
- Stress: `low / moderate / high`
- Sleep: `poor / fair / good / great`
- Energy: `depleted / low / good / charged`

### Цвет статуса
- Good/Great/Charged/Low stress → `state/success`
- Fair/Moderate/Low energy → `state/warning`
- Poor/High stress/Depleted → `state/error`

### Interaction
- Tap по карточке открывает объяснение score (MVP: in-place details / modal sheet).

### Accessibility
- VoiceOver label пример:  
  `“Stress score 32, low. Lower is better.”`

## 6.2 `InsightCard`

### Назначение
Показать короткое объяснение текущего состояния.

### Визуал
- Radius `16`, padding `16`
- Градиентный фон и мягкая рамка indigo alpha
- Header: пульсирующая точка + label `Daily Insight`
- Body: текст 2–3 строки, ключевые части в semibold

### Состояния
- `default`: есть insight текст
- `no-data`: “Insufficient data for insight yet”
- `stale`: “Last insight updated Xh ago”

## 6.3 `VitalCard`

### Назначение
Показать конкретную жизненную метрику и тренд против baseline.

### Сетка
- `2 columns`, gap `10`
- Card radius `16`, padding `14`

### Поля
- Icon (SF Symbol)
- Label
- Value + unit
- Trend line (`up/down/neutral`)

### SF Symbols mapping
- Resting HR: `heart.fill`
- HRV: `waveform.path.ecg`
- Sleep: `moon.fill`
- Active Energy: `flame.fill`

## 6.4 `WeeklyTrendCard` (Today)

### Назначение
Быстрый 7-дневный контекст без перехода в полный Trends.

### Структура
- Header: `Score History` + `This week`
- 3 ряда: Stress, Sleep, Energy
- В каждом ряду 7 bar-элементов + day labels

### Параметры
- Sparkline height: `48`
- Bar min-height: `8`
- Gap между барами: `6`
- Последний день выделяется тонкой рамкой цвета метрики

## 6.5 `PrivacyBadge`

### Текст
`100% ON-DEVICE · ZERO CLOUD · OPEN SOURCE`

### Правила
- На Today всегда видим внизу контента.
- Цвет текста `text/muted` / low-contrast, без доминирования.

## 6.6 `TabBar`

### Размеры
- Высота `82`
- Верхняя граница `1px` `border/subtle`
- Blur backdrop включен

### Контент
- 4 таба: иконка `22x22` + label `10`
- Active color: `accent/indigo`
- Inactive: `text/muted`

### Touch area
- Минимум `44x44` на элемент.

---

## 7) Спецификации экранов

## 7.1 Today

### Вертикальная структура
1. Header (`Good morning`, имя, дата)
2. Row из 3 score cards
3. Insight card
4. `Vitals` section + grid 2x2
5. `7-Day Trends` section + weekly trend card
6. Privacy badge
7. Bottom spacer (`>= 90`) под tab bar

### Поведение
- Экран скроллируемый.
- Pull-to-refresh запускает перерасчет скоров.
- Если данных нет: показывать empty-state между header и footer.

### Empty-state (Today)
- Заголовок: `No data yet`
- Текст: `Wear Apple Watch and allow Health access to see your daily scores.`
- CTA: `Connect Apple Health`

## 7.2 Trends

### Блоки
1. Header + период-переключатель `7D / 30D / 90D`
2. `ScoreTrendChart` (3 линии)
3. `SleepBreakdownChart` (stacked bars)
4. `HRVTrendChart` + baseline rule

### Chart style
- Background прозрачный/карточка как в Today.
- Осевые линии low-contrast (`text/muted` alpha).
- Линии:
  - Stress: `metric/stress`
  - Sleep: `metric/sleep`
  - Energy: `metric/energy`
- Baseline: пунктир `text/tertiary`.

### Interaction
- Drag/tap inspection на точках данных.
- Tooltip: дата + значение + unit.

## 7.3 Labs (MVP placeholder)

### Цель
Не реализовывать функционал Labs в MVP, но явно коммуницировать roadmap.

### Состав
- Иконка документа/колбы
- Заголовок: `Labs are coming in v3`
- Подтекст: `Photo-to-biomarker import and tracking will be added in a future release.`

### CTA
- Secondary button: `Learn more` (можно вести на roadmap/info sheet).

## 7.4 Settings

### Секции
- `Profile`: Name, Birth year, Sleep target
- `Health Data`: reconnect, last sync
- `About`: version, GitHub link, privacy statement

### Стиль
- Темные grouped-card секции, единый radius `16`.
- Inline helper text для privacy и статуса синка.

## 7.5 Onboarding + Permission

### Экран 1: Welcome
- Value proposition + privacy promise.
- CTA `Continue`.

### Экран 2: HealthKit Permission
- Короткий список читаемых данных (HRV, HR, sleep, activity).
- Primary CTA `Allow Apple Health Access`.
- Secondary CTA `Not now`.

### Ошибка доступа
- Показывать инструкцию перехода в iOS Settings > Health.

---

## 8) Маппинг данных в UI

## 8.1 Форматирование

- Score: целое `0-100`
- Resting HR: `Int bpm`
- HRV SDNN: `Int ms`
- Sleep duration: `Xh Ym`
- Active energy: `Int kcal`
- Steps: тысячные разделители (`8,432`)

## 8.2 Freshness

- На Today отображать `Last updated`.
- Если данные старше `6h`, показывать `stale` style (subtle warning).

## 8.3 Baseline/Calibration

- Пока данных < 7 дней: бейдж `Calibrating`.
- Insight в этот период должен явно сообщать о lower confidence.

---

## 9) Accessibility Specification

- Минимальная touch target: `44x44`.
- Контраст текста:
  - основной текст `>= 4.5:1`;
  - крупный (`>= 18pt`) `>= 3:1`.
- Dynamic Type:
  - не обрезать critical copy в card/header/settings.
- VoiceOver:
  - все score cards и vital cards имеют читаемые label/value/state.
- Reduce Motion:
  - отключать pulse/count-up; сокращать длительность ring animation.
- Цвет не должен быть единственным носителем смысла:
  - всегда дублировать состояние текстом (`Low`, `High`, `Poor`, etc.).

---

## 10) Состояния и ошибки

Обязательные глобальные состояния:
- `loading` (skeleton/shimmer для карточек),
- `no-data`,
- `permission-denied`,
- `no-watch-detected`,
- `partial-data` (например, без sleep stages),
- `sync-error` (recoverable с Retry CTA).

Текст ошибок — в нейтральном wellness tone, без медицинских диагнозов.

---

## 11) Content & Tone Guidelines

- Тон: спокойный, поддерживающий, не алармистский.
- Запрещено: медицинские диагнозы/обещания лечения.
- Разрешено: объяснения трендов и лайфстайл-контекст (`wellness insights`).
- Insight copy: максимум 140 символов в компактной форме.

---

## 12) Handoff Checklist (Design → Dev)

- [ ] Все токены вынесены в `Theme` и не захардкожены по экранам
- [ ] Для каждого компонента есть default + empty + error states
- [ ] Формулы ring progress зафиксированы и одинаковы во всех местах
- [ ] Все строки для MVP согласованы и готовы к локализации
- [ ] Проверена адаптация на `375`, `393`, `430`
- [ ] Проверен `Reduce Motion` и VoiceOver
- [ ] Проверена консистентность с roadmap: Labs = `Coming in v3`

---

## 13) Версионирование спецификации

- Версия: `MVP Design Spec v1.0`
- Дата: `2026-03-04`
- Источник драфта: `design-draft.html`
- Владелец обновлений: Product/Design

