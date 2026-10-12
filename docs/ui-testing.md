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

Set `RUNNER_BUILD_JOBS=1` to limit compilation to one worker when memory is constrained. Simulator destinations remain serial, and disposable simulators are shut down and deleted after each run.

After a successful `xcodebuild`, the runner verifies recorded test counts and failures through the compatible result-object reader and saves a sibling `-summary.json`. Empty/all-skipped results fail validation. This also avoids Xcode 27's newer summary reader returning `unknown` with zero tests for some iOS 26.5 bundles; the recorded action metrics still contain the executed counts and failures.

UI tests also save a direct screenshot and accessibility tree at teardown in the sibling `-screenshots` directory. The runner forwards this location with `TEST_RUNNER_RUNNER_EVIDENCE_DIR`; direct Xcode runs use `/tmp/runner-ui-results/direct-screenshots`. These copies survive disposable-simulator cleanup when a toolchain cannot decode older-runtime attachments. Failed accessibility audits record the detailed issue description. The original `.xcresult` and console log remain the authoritative test outcome; screenshot copies do not change failures or enable retries.

## Isolation

### Run photo editor

`RunPhotoTests` covers moving-time/unit formatting, segmented GPS projection and longitude wrapping, overlay bounds, crop coverage, image decoding/orientation, export dimensions and colors, metadata, and temporary share-file cleanup. JPEG attachments retain rendered artwork for visual inspection.

The six `testRunPhoto…` UI scenarios cover Latest and History entry points, independent gestures, accessible position/size controls, cropping, export, missing routes, loading retry, save denial, and large-text landscape layouts. Alignment/font previews, independently movable icon stickers, visibility restoration, reset, and photo replacement are included. Debug fixture mode supplies a deterministic image and renders real JPEGs while substituting Photos writes and share presentation; it never changes the user's photo library. `photo-load-failure` fails the first image attempt, and `photo-save-denied` simulates denied add-only access while still allowing the share fallback. Existing `indoor` and `partial` fixtures cover unavailable data. Release builds ignore all fixture controls.

Rendering tests exercise every font/alignment combination with metric, imperial/hour-long, and missing values. They check measured bounds and label alignment, a fixed vector wordmark, icon asset availability and clamping, overlap selection priority, and exports with the icon in all four formats.

The editor’s contrast audit covers visible controls, including revealed font previews. It excludes text inside the scalable photo artwork, whose background and scale are user-controlled, and offscreen ScrollView descendants beneath the fixed footer that iOS 26's audit still reports. The interaction scenario exercises all five font choices and their selected accessibility state. The complete metrics are also exposed as one VoiceOver label. Export tests inspect the actual artwork’s colors, dimensions, and orientation independently.

The full-screen editor explicitly inherits the presenting screen's dynamic text size. The large-text scenario asserts a single column of font previews at accessibility sizes before rotating and auditing the visible controls.

For native-device acceptance, select a local and an iCloud photo, cancel and retry selection, verify add-only permission denial and success, and open/dismiss the native share sheet on iPhone and iPad. Confirm the saved JPEG matches the preview. Native permissions and iCloud download behavior are separate from deterministic fixture coverage.

For manual native Photos checks in a disposable simulator, launch a Debug fixture scenario with `RUNNER_NATIVE_PHOTOS=1`. This uses the real picker, Photos writer, and share sheet while retaining isolated workout data and disabled cloud/Health services. Seed only that simulator’s library with `simctl addmedia`; the normal fixture suite never enables this override.

Debug builds accept `--ui-scenario SCENARIO`. Each test supplies a unique `RUNNER_TEST_ID` for an isolated preferences suite; workout data uses an in-memory SwiftData container. Relaunching with the same ID retains local settings within that test. Fixtures use a fixed October 9, 2026 clock, Gregorian calendar, Istanbul timezone, and Monday-start weeks.

Fixture launches wait for the Settings control's `Fixtures ready` accessibility value before interacting. This value is exposed only in fixture mode and follows analytics loading, so tests do not mistake a pending snapshot for measured zero totals. Zone assertions reveal the corresponding row before reading it, including after scrolling to trailing-load totals.

Scenarios: `populated`, `empty`, `partial`, `paused`, `indoor`, `repeated-route`, `dashboard-expired`, `dashboard-review-failure`, and `dashboard-approval-failure`. Populated fixtures contain nine runs spanning the current month and earlier months, with routes, splits, heart rate, power, form data, and dated endurance measurements. Dashboard fixtures use a local service; a failure scenario fails its first request and supports a retry.

Fixture mode bypasses Firebase setup, Health authorization/imports, cloud sync, AI analysis, and Watch activation. Release builds ignore all fixture controls. Maps may retrieve standard MapKit tiles; tests assert recorded route data rather than tile imagery.

`testFixtureConsentAnalysisAndCloudDeleteStayIsolated` enables adult/AI consent, confirms the fixture cloud-history action, and requests manual analysis. Analysis and API entry points reject fixture execution before reaching Firebase or the network, even when fixture settings enable consent.

`RUNNER_APPEARANCE=light|dark` records the requested fixture appearance; the production dark theme takes precedence. `RUNNER_LARGE_TEXT=1` selects accessibility-sized text. Functional assertions use accessibility identifiers and measured values rather than screenshots. Screenshots remain visual-review evidence.

## Matrix

Run the full suite on iPhone 16 / iOS 26.0. Run navigation and appearance smoke tests on a recent iOS 26 runtime, iPhone SE, and iPad Air. Use portrait and landscape plus accessibility text sizes. Restore simulator accessibility preferences after Reduce Motion/Transparency checks. Numerical DST, interpolation, coverage, and route-matching edge cases belong in RunCore tests.

The contrast audit excludes content occluded behind the bottom glass tab bar. Fully visible app content remains subject to contrast checks. Simulator Settings automation enables Reduce Motion, Reduce Transparency, and Increase Contrast and restores their initial values after its check.

## Interactive analytics scenarios

`testVolumeRangesMetricsAndBucketDrilldown` checks month/3-month/6-month/year fixture counts (3/7/8/9), all four metrics, custom dates, accessible chart data, and matching runs. `testCalendarAndHistoryFilters` checks day/month navigation, indoor/outdoor filters, pace sorting, and detail navigation. `testLinkedSamplesSplitsAndMissingSensors` checks sample selection, split selection, paused recordings, and missing power.

RunCore/iOS unit tests cover daily buckets across DST, validated distance interpolation, pause boundaries, rejected overlapping samples, unit conversion, missing altitude, source filtering, series caps and gaps, and cache invalidation. Numeric tests do not depend on chart rendering.

Custom-date regressions reopen and reapply past ranges across DST and verify through-now/midnight endpoints without expanding the selected dates. `AnalyticsStoreTests` delays and completes injected refreshes out of order; automatic analysis requires the completed payloads to match current rows, including before a new refresh task starts.

## Training performance scenarios

`testGoalsCreateEditPersistAndDelete` creates and edits a distance goal, relaunches with isolated preferences, and deletes it. `testZonesAndCompleteVersusIncompleteLoad` verifies invalid initial settings, explicit known maximum, generated boundaries, complete load, and a partial-heart-rate relaunch. `testBestEffortExclusionAndRepeatedRouteNavigation` checks the selected annual best, reranking/restoration, originating runs, and matching route completions. `testAppOwnedScreenAccessibility` audits the empty Latest, History, Trends, Live, and Settings screens; the separate Activity audit covers its performance cards.

The numerical suite also checks exact zone boundaries, below-zone and above-maximum time, paused pulse coverage, the inclusive 80% threshold, elapsed efforts with internal pauses, interpolation, exclusions, annual filtering, preference serialization, and route false matches.

Best-effort candidates include pause boundaries inside distance samples, so a fastest window ending before or beginning after an internal pause is considered without dropping pauses from elapsed time.

To review a specific screenshot in a bundle, use Xcode or `xcrun xcresulttool export attachments --path RESULT.xcresult --output-path OUTPUT --test-id 'RunnerUITests/TEST_NAME()'`. Keep the initial failure bundle when rerunning a repaired test.

`mixed-source` adds a second Health workout source for filter assertions. `testRecordedChartsAndDistanceAxes` switches every recorded chart, time/distance axes, and sample selection; `testHistorySourceAndDistanceFilters` covers source, measured-distance thresholds, resetting, and custom-date application. All screen-edge scrolling accounts for an onscreen keyboard and stays outside route maps on iPad. Goal tests submit numeric input and wait for keyboard dismissal before saving, avoiding stale modal coordinates in the iOS 26 iPad runtime. Screenshots capture the full screen, including landscape, and are retained on both success and failure.

## Serial matrix runner

The matrix includes eight Xcode Cloud regression scenarios on iPhone SE and iPhone 16 Pro Max / the recent runtime (26.5 by default): calendar/history filters, dashboard approval retry, zone/load visibility, screen accessibility, large-text landscape date selection, photo-editor accessibility, independent icon toggling, and historical/no-GPS photo sessions. To reproduce only either cloud layout:

```sh
RUNNER_SKIP_FULL_SUITE=1 RUNNER_MATRIX_FILTER=Runner-Cloud-SE-UI scripts/test-matrix.sh
RUNNER_SKIP_FULL_SUITE=1 RUNNER_MATRIX_FILTER=Runner-Cloud-Max-UI scripts/test-matrix.sh
```

Fixture launches set `TZ=America/Los_Angeles` independently of the Istanbul analytics calendar. Calendar month/day labels explicitly use the analytics calendar's timezone; this exercises the previous-month/day regression seen on cloud hosts. Tests reveal lazy/offscreen Form controls before checking them, keep targets above the bottom tab bar, scroll explicitly toward earlier fields, wait for sheet/keyboard dismissal, and wait for asynchronous labels with a bounded expectation. Accessibility checks wait for SpringBoard notification banners to disappear, so a simulator's Apple Intelligence notification cannot obscure the app. Contrast and clipping remain audited without a new exclusion.

Settings uses adaptive readable footer colors, heading rows within opaque cards, persistent wrapping target labels, inline unit choices, and a compact title. Run rows include their empty spacing in their tap area, so their center opens details on wide screens.

`scripts/test-matrix.sh` runs the full iPhone 16 / iOS 26.0 suite and then appearance, accessibility, navigation, goals, and personal-best/route smoke on disposable SE / 26.0, iPad Air / 26.0, and iPhone 17 Pro / 26.5 destinations. Each simulator is deleted before the next starts, including on failure. Set `RUNNER_RECENT_RUNTIME=iOS-26-4` (or another installed iOS 26 runtime) to change the recent runtime. Set `RUNNER_SKIP_FULL_SUITE=1` to run only the matrix after an already completed functional run. Use `RUNNER_MATRIX_FILTER=Runner-SE-UI`, `Runner-iPad-UI`, or `Runner-Recent-UI` to check a single matrix destination after a specific repair. Results use the same unique bundle directory as `test-ui.sh`.

## Yellow dashboard theme

The two `testYellowDashboard…` scenarios check production dark appearance even when a fixture requests light, yellow rendered pixels, metric-grid column placement, large-text reflow, minimum photo-action hit size, History navigation, the native dark tab bar on every tab and after pushing Run Details, and accessibility auditing. On iPad, the appearance scenario rotates to landscape and checks that the summary and route use separate columns. Screenshots of all five tabs are retained alongside the test result. Native-bar pixel checks convert point coordinates using the screenshot/window dimension ratios, since XCTest can return Retina pixels with image scale 1. Scroll gestures use the visible scroll-view bounds rather than a fixed fraction of the screen, including with opaque native bars and the keyboard. The icon rendering test checks opaque 1024-pixel artwork with a yellow runner and black background. Existing scenario coverage continues to exercise filters, chart selections, goals, Settings, units, reduced motion/transparency, and the photo editor.
