# Somatiq TestFlight Rollout Plan (MVP)

## Build and upload

1. Archive `Somatiq` in Release configuration.
2. Upload build to App Store Connect.
3. Wait for processing completion.

## Internal QA phase

- Audience: team only
- Duration: 2-3 days
- Focus:
  - onboarding + Health permissions
  - Today refresh + trends rendering
  - Settings save/reconnect
  - denied/no-data fallback behavior

## External beta phase

- Audience: limited Apple Watch users
- Duration: 7 days minimum
- Required feedback:
  - score plausibility over multiple days
  - crashes/freezes
  - permission and privacy UX clarity

## Exit criteria to App Store submit

- No open `P0` defects
- No repeated crash in TestFlight analytics
- Privacy/medical wording approved
- Metadata + screenshots uploaded
- Release checklist completed
