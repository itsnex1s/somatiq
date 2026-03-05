# Somatiq Screenshot Guide (MVP)

## Required iPhone sizes

- 6.1" display (for example iPhone 16 Pro / iPhone 17 Pro)
- 6.7" display (for example iPhone 16 Pro Max / iPhone 17 Pro Max)

## Mandatory screens

1. Today — score rings + insight + vitals
2. Today — weekly trends block
3. Trends — score trend chart (7D or 30D with data)
4. Trends — sleep breakdown + HRV chart
5. Settings — profile + health reconnect + privacy note

## Capture rules

- Dark mode enabled
- Realistic data (no empty states)
- Status bar time `9:41`
- No debug overlays
- Localized language for release market

## Capture flow

1. Install RC build from TestFlight/internal distribution.
2. Open each required screen and wait for animations to settle.
3. Capture clean screenshots on both sizes.
4. Store files in:
   - `release/assets/iphone-61/`
   - `release/assets/iphone-67/`
5. Verify text legibility and chart labels before upload.
