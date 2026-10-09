# Automated simulator UI tests

Runner requires iOS 26.0. UI tests run exclusively on simulators; they never install on a physical device.

## Run

Use Xcode 26 or newer and an installed iOS 26 simulator runtime. On this machine Xcode 27 is selected by the runner.

```sh
scripts/test-ui.sh
```

With no destination argument, the runner creates and removes a disposable iPhone 16 / iOS 26.0 simulator. An explicit destination reuses your chosen simulator. Builds use ARM64 with two workers to limit memory usage.

The shared `Runner.xctestplan` includes `RunnerTests` and `RunnerUITests`. To run a specific UI scenario:

```sh
scripts/test-ui.sh 'platform=iOS Simulator,name=iPhone 16,OS=26.0' -only-testing:RunnerUITests/RunnerUITests/testNavigationAndActivityCheckpointRegression
```

Set `RUNNER_DERIVED_DATA` to reuse a dependency checkout and `RUNNER_RESULTS_DIR` to choose an artifact directory. Defaults are `/tmp/runner-activity-derived` and `/tmp/runner-ui-results`. Every invocation creates a new `.xcresult`; failures are not automatically retried. Open the bundle in Xcode to inspect screenshots, failures, and test timings.

## Isolation

Debug builds accept `--ui-scenario SCENARIO`. Each test supplies a unique `RUNNER_TEST_ID` for an isolated preferences suite; workout data uses an in-memory SwiftData container. Relaunching with the same ID retains local settings within that test. Fixtures use a fixed October 9, 2026 clock, Gregorian calendar, Istanbul timezone, and Monday-start weeks.

Scenarios: `populated`, `empty`, `partial`, `paused`, `indoor`, `repeated-route`, `dashboard-expired`, `dashboard-review-failure`, and `dashboard-approval-failure`. Populated fixtures contain nine runs spanning the current month and earlier months, with routes, splits, heart rate, power, form data, and dated endurance measurements. Dashboard fixtures use a local service; a failure scenario fails its first request and supports a retry.

Fixture mode bypasses Firebase setup, Health authorization/imports, cloud sync, AI analysis, and Watch activation. Release builds ignore all fixture controls. Maps may retrieve standard MapKit tiles; tests assert recorded route data rather than tile imagery.

`RUNNER_APPEARANCE=light|dark` and `RUNNER_LARGE_TEXT=1` select deterministic appearance cases. Functional assertions use accessibility identifiers and measured values rather than screenshots. Screenshots remain visual-review evidence.

## Matrix

Run the full suite on iPhone 16 / iOS 26.0. Run navigation and appearance smoke tests on a recent iOS 26 runtime, iPhone SE, and iPad Air. Use portrait and landscape plus accessibility text sizes. Restore simulator accessibility preferences after Reduce Motion/Transparency checks. Numerical DST, interpolation, coverage, and route-matching edge cases belong in RunCore tests.

The contrast audit excludes content occluded behind the bottom glass tab bar. Fully visible app content remains subject to contrast checks. Simulator Settings automation enables Reduce Motion and Reduce Transparency and restores their initial values after its check.

## Interactive analytics scenarios

`testVolumeRangesMetricsAndBucketDrilldown` checks month/3-month/6-month/year fixture counts (3/7/8/9), all four metrics, custom dates, accessible chart data, and matching runs. `testCalendarAndHistoryFilters` checks day/month navigation, indoor/outdoor filters, pace sorting, and detail navigation. `testLinkedSamplesSplitsAndMissingSensors` checks sample selection, split selection, paused recordings, and missing power.

RunCore/iOS unit tests cover daily buckets across DST, validated distance interpolation, pause boundaries, rejected overlapping samples, unit conversion, missing altitude, source filtering, series caps and gaps, and cache invalidation. Numeric tests do not depend on chart rendering.
