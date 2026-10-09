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
