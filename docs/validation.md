# Implementation validation

Executed October 9, 2026 with Xcode 27.0. The iOS minimum is 26.0; the Watch minimum remains 11.5. All execution used simulators or the standalone macOS RunCore package. No connected-device install, launch, or test was performed.

## Builds and numerical tests

- Debug simulator build and 54 iOS unit/storage/dashboard tests: passed. These include reopening and migrating saved checkpoints, dashboard state races/retries, calendar/DST boundaries, interpolation and pauses, missing sensors, cache invalidation, zone coverage, goal serialization, exclusions, annual rankings, and reverse route false matches.
- Standalone RunCore: 41 tests passed. Command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path Packages/RunCore --scratch-path /tmp/runner-final-core --jobs 2`. Log: `/tmp/runner-final-core.log`.
- Release ARM64 simulator build: passed (`/tmp/runner-accepted-final-release.log`). Command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project 'The Runner.xcodeproj' -scheme 'The Runner' -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/runner-activity-derived -jobs 2 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO`.

The iOS numerical tests passed in `/tmp/runner-ui-results/20261009-130742-13498.xcresult`. That combined run had one UI scroll failure; its result is retained, not represented as a passing combined run.

## Functional UI suite

The 17 scenarios cover all tabs and repeated Activity navigation, empty states, four volume metrics and every preset, custom dates, chart drill-down, calendar navigation, History settings/source/distance/date filters and sorting, all seven recorded charts and both axes, paused/missing samples, goal CRUD/relaunch and invalid input, zones and coverage-aware load, effort exclusions/restoration and annual bests, repeated routes, dashboard states/retries, appearance/landscape/large text, screen accessibility audits, and Reduce Motion/Transparency restoration.

All 17 scenarios passed in a clean iPhone 16 / iOS 26.0 run: `/tmp/runner-ui-results/20261009-132355-2963.xcresult`. Command: `scripts/test-ui.sh '' -only-testing:RunnerUITests`. Log: `/tmp/runner-accepted-final-ui.log`. Test values come from named isolated fixtures; charts have accessible data actions. Screenshots capture the entire screen and remain in each bundle on success and failure.

## Simulator matrix

SE, iPad Air, and iPhone 17 Pro / iOS 26.5 coverage includes navigation, light-mode contrast, large-text dark landscape, goal persistence, and best-effort/route navigation. The serial runner deletes each disposable simulator before starting another. Repairs use bounded element/keyboard waits, and keep the initial failure bundles.

- SE / 26.0: five scenarios passed in `/tmp/runner-ui-results/20261009-123152-11580.xcresult`; the final goal editor’s invalid-input, creation, editing, persistence, and deletion check also passed in `/tmp/runner-ui-results/20261009-133530-7198.xcresult`.
- iPad Air / 26.0: contrast, appearance, route/bests, and navigation passed in `/tmp/runner-ui-results/20261009-124039-16124.xcresult`; that run exposed goal automation with stale modal coordinates. The corrected goal CRUD/relaunch scenario passed in `/tmp/runner-ui-results/20261009-125431-1008.xcresult`.
- iPhone 17 Pro / 26.5: all five scenarios passed in `/tmp/runner-ui-results/20261009-130302-13826.xcresult`.

## Reproduction and artifacts

Use `scripts/test-ui.sh` for the full test plan or `scripts/test-matrix.sh` for serial matrix coverage. Set `RUNNER_SKIP_FULL_SUITE=1` after a completed full run, and `RUNNER_MATRIX_FILTER` for an explicit repair on one destination. Exact fixture scenarios and attachment export commands are in `ui-testing.md`.

All uniquely named `.xcresult` bundles are retained under `/tmp/runner-ui-results`, including initial failures. Retries are manual and documented rather than automatic. This machine's global command-line selection points to Command Line Tools: optional Xcode simulator diagnostic collection reports missing `simctl`, but the test runner explicitly selects Xcode and preserves test results, logs, and screenshots. This does not change test outcomes.

Build caches and disposable simulators can be removed after validation without deleting these results. Cloud authentication, actual Health imports, AI calls, and Watch connections are outside fixture execution; web-dashboard parity remains a follow-up.

## Pre-merge correctness review

The October 9 review found four P2 issues, all corrected before merge:

- Custom-date editors now convert the exclusive query endpoint to the last included day. Repeated past-range edits preserve dates, including DST, midnight, and through-now boundaries.
- Automatic analysis checks the completed snapshot's exact payload revision against current rows, and completion retriggers analysis. Delayed and out-of-order refresh tests cover the scheduling window before a refresh task starts.
- Estimated best efforts include pause distances inside sample intervals among candidate boundaries. A 400 m regression now finds the valid 115-second effort previously missed at 120 seconds, while internal pauses still count toward elapsed time.
- Fixture analysis and API entry points return before Firebase or network access, even after enabling AI consent or confirming cloud deletion.

After these fixes, 44 RunCore tests passed (`/tmp/runner-review-core-repaired.log`) and all 59 app/storage/dashboard/refresh tests passed in `/tmp/runner-ui-results/20261009-145239-7050.xcresult`. That iPhone 16 / 26.0 run also passed the 17 existing UI scenarios; the new fixture case stopped at a duplicated native confirmation button. A focused recent-runtime attempt then exposed label taps that had not enabled the native switches. Both initial reports are retained, including `/tmp/runner-ui-results/20261009-150608-4307.xcresult`.

The corrected fixture case explicitly enables and asserts both switches, confirms cloud deletion, requests manual analysis, and navigates to Activity without accessing live services. It passed on iPhone 16 / iOS 26.0 in `/tmp/runner-ui-results/20261009-151203-26753.xcresult`, completing coverage of all 18 UI scenarios across the full run and focused repair. Exact focused command: `scripts/test-ui.sh '' -only-testing:RunnerUITests/RunnerUITests/testFixtureConsentAnalysisAndCloudDeleteStayIsolated`. Log: `/tmp/runner-review-fixture-final.log`.

The final Release ARM64 simulator build also passed after the review fixes (`/tmp/runner-review-release.log`), using the Release command above. No physical device was installed, launched, or tested.

## Xcode Cloud regression repair

The main pipeline after PR #4 (merge `b65ce29`) archived successfully but failed four UI scenarios on iOS 26.5: calendar month navigation on all four destinations, dashboard approval retry and zone-save visibility on SE, and Settings contrast on Pro Max. The calendar used the analytics calendar for buckets but the host timezone for labels; midnight in Istanbul could display the preceding month in a US timezone. Labels now use the same calendar and timezone, and fixture launches independently set a Pacific process timezone to keep this regression reproducible.

The UI checks now reveal lazy Form controls, scroll explicitly back to earlier fields, and wait for keyboard/sheet dismissal and calculated summaries. Accessibility checks also wait out simulator system banners; an exported failure screenshot showed an Apple Intelligence notification over Settings. Settings uses readable adaptive footer colors, heading rows within opaque cards, persistent target labels, inline unit choices, and a compact title. A further wide-screen History check exposed transparent gaps in plain run-row links; the complete row now participates in hit testing.

Original and intermediate failures remain under `/tmp/runner-ui-results`. The test runner retains compatible action-metric summaries and direct screenshots/accessibility trees, because Xcode 27's newer summary reader can report zero tests for iOS 26.5 results. Successful execution is accepted only with nonzero recorded test counts and no failures; failures are never automatically retried or filtered out of the audit.

A full regression run then exposed two startup races that read zero totals before the initial analytics snapshot, and a zone assertion after its row had scrolled out of the lazy view. Fixture launches now wait for the analytics snapshot's explicit accessibility readiness value, and the zone assertion reveals its row before checking it. The failing run and its screenshots remain available; the readiness signal is limited to fixture launches.

The retained startup/visibility failure is `/tmp/runner-ui-results/20261009-190947-9938.xcresult` (59 unit tests and 15 UI scenarios passed, three UI scenarios failed). After those repairs, the complete shared test plan passed on iPhone 16 / iOS 26.0: **77 tests, zero failures, zero skipped**, including all 59 app/storage/dashboard tests and all 18 UI scenarios. Command: `scripts/test-ui.sh`. Result: `/tmp/runner-ui-results/20261009-192743-29775.xcresult`; console log: `/tmp/runner-ci-full-ready.log`; verified counts: `/tmp/runner-ui-results/20261009-192743-29775-summary.json`.

The final Release ARM64 simulator build passed using the Release command above (`/tmp/runner-ci-release-ready.log`). All four cloud regression scenarios then passed on iPhone SE / iOS 26.5, zero failures or skipped tests. Command: `RUNNER_SKIP_FULL_SUITE=1 RUNNER_MATRIX_FILTER=Runner-Cloud-SE-UI scripts/test-matrix.sh`. Result: `/tmp/runner-ui-results/20261009-194430-1727.xcresult`; log: `/tmp/runner-cloud-se-ready.log`.

All four scenarios also passed on iPhone 16 Pro Max / iOS 26.5, zero failures or skipped tests. Command: `RUNNER_SKIP_FULL_SUITE=1 RUNNER_MATRIX_FILTER=Runner-Cloud-Max-UI scripts/test-matrix.sh`. Result: `/tmp/runner-ui-results/20261009-194957-6019.xcresult`; log: `/tmp/runner-cloud-max-ready.log`. Both recent-runtime counts were independently verified in their sibling `-summary.json` files. The read-only correctness review found no additional actionable issues. All execution remained on simulators, and each disposable device was deleted after its run.
