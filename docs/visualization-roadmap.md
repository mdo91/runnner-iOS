# Running visualization comparison

This audit covers private running data visualization. Social feeds, leaderboards, and integrations with Strava accounts are outside this work.

## Existing capabilities

Runner imports Apple Health workouts, distance, heart rate, GPS, power, and running-form measurements. It already provides run totals, moving/elapsed time, splits, colored routes, route-density maps, current-period volume, matched-period comparisons, dated VO₂ max, heart-rate recovery, and comparisons with runs of similar distance/effort. These work from recorded measurements; missing values remain unavailable.

## Implemented additions

1. iOS 26: adaptive light/dark surfaces, native Liquid Glass navigation and actions, compact period summaries, accessible layouts, and automated simulator UI-test infrastructure.
2. Exploration: time/elevation volume, custom ranges, calendar views, chart-to-run navigation, history filters, linked pace/elevation/power/form charts and split selections.
3. Performance: local recurring goals, estimated elapsed-time personal bests, editable heart-rate zones, coverage-aware observed training load, and private repeated-route comparisons.

Strava's [Training Log](https://support.strava.com/en-us/articles/15402077-training-log) emphasizes a visual weekly history with distance/time/elevation filters. Its [Progress Summary](https://support.strava.com/en-us/articles/15401618-progress-summary-chart) offers custom ranges and totals. Runner's calendar and drill-down views address the same need using imported running data.

Strava's [run analysis](https://support.strava.com/en-us/articles/15401883-run-activity-pages) connects splits, maps, elevation, pace, and heart-rate analysis. Runner's linked selection makes its already-imported samples easier to explore.

Strava offers [goals](https://support.strava.com/en-us/articles/15401694-goals-on-the-strava-app), [Best Efforts](https://support.strava.com/hc/en-us/articles/19685360245005-Best-Efforts-Overview), [matched activities](https://support.strava.com/en-us/articles/15401955-how-do-i-view-my-matched-activities), and [training zones](https://support.strava.com/en-us/articles/15401569-training-zones-on-strava). Runner's new equivalents are local, running-specific, and expose data coverage and calculation assumptions.

## Remaining opportunities

- Grade-adjusted pace: needs a validated hill-cost model and sufficiently reliable altitude. [Strava GAP](https://support.strava.com/en-us/articles/15402117-what-is-grade-adjusted-pace-gap-on-strava).
- Race predictions and personalized pace zones: need explicit reference performances, calibration, and uncertainty.
- Recorded laps: requires importing and retaining HealthKit lap events separately from calculated distance splits.
- Fitness/fatigue modeling: needs validated physiological assumptions. The initial observed zone-weighted load is a transparent workload measure, not Strava's proprietary Relative Effort or a readiness prediction. [Strava Fitness & Freshness](https://support.strava.com/en-us/articles/15402032-how-fitness-freshness-is-calculated).
- Additional benchmark distances and manual race-time corrections.
- Web-dashboard parity for the new local analytics and preferences.

## Design principles

Glass belongs to navigation and controls; data remains on readable surfaces. Follow [Apple's adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass). Use adaptive labels, consistent units, visible sample gaps, honest partial totals, and accessible equivalents for chart interactions.
