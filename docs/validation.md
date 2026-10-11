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

## Run photo editor — October 11, 2026

The editor is implemented for Latest and History, with independent statistics and segmented-route overlays, crop controls, four formats, and local JPEG saving/sharing. Nine new unit tests cover unit conversion and moving time, missing metrics, hours, route gaps/duplicates/invalid coordinates/dateline crossings, very narrow canvas bounds, cropping, decoding/orientation, export colors/dimensions/metadata, and share-file cleanup. Four new UI scenarios cover the complete fixture workflow and error recovery.

The full shared plan executed **90 tests** on iPhone SE / iOS 26.0: all 68 unit/data tests and 21 UI scenarios passed; one editor contrast audit failed. Its retained bundle is `/tmp/runner-ui-results/20261011-152243-1866.xcresult` (log `/tmp/runner-photo-full-check.log`). The Change Photo button now has an opaque contrasting background, and the corrected audit passed in the focused compact-iPhone run `/tmp/runner-ui-results/20261011-153914-14473.xcresult`.

Subsequent validation covered the final refinements:

- iPad Air / iOS 26.0: all nine photo unit tests and four photo UI scenarios passed in `/tmp/runner-ui-results/20261011-154138-27040.xcresult`.
- Final compact-iPhone run: photo unit tests, landscape accessibility, independent drag/pinch gestures, crop/export, History, and missing GPS passed in `/tmp/runner-ui-results/20261011-160952-7981.xcresult`. The permission fallback assertion initially checked the toolbar while export was still running; it now waits for the completed export message.
- Final iPad repair: both landscape accessibility and loading/permission-denial/Share Instead passed with zero failures or skips in `/tmp/runner-ui-results/20261011-161357-29518.xcresult` (log `/tmp/runner-photo-accepted-ipad.log`). The scroll helper uses window bounds after rotation, and export confirmation stays beside the save actions. Together, the full and focused runs cover all 68 unit/data tests and all 22 UI scenarios; this is not a claim that the original full bundle was entirely green.

The final Release ARM64 simulator build passed after all code changes, using the shared `/tmp/runner-activity-derived` directory and one build worker. Log: `/tmp/runner-photo-release-complete.log`. `git diff --check` also passed.

Native Photos acceptance used a disposable iPad and isolated workout fixtures with `RUNNER_NATIVE_PHOTOS=1`: picker cancellation and local-image loading, add-only denial, native share-sheet presentation/dismissal after denial, permission configuration, and a successful actual Photos write were verified. The temporary share directory existed while sharing and was removed after dismissal. Actual shared and saved JPEGs were inspected at 2160×1441, sRGB, with upright images, unclipped white/yellow text, no editing controls, and no GPS IFD or XMP metadata. Examples remain at `/tmp/runner-native-photo-export.jpg` and `/tmp/runner-native-saved-photo.jpg`; fixture JPEG attachments cover every social format and segmented routes.

Changing Photos access in Settings restarted the simulator app. Because this version intentionally keeps compositions in memory, the denial alert now offers Share Instead directly and advises saving a copy before changing permissions. Ordinary denial and retry preserve edits. Real iCloud downloads and physical-device VoiceOver/Photos behavior remain device acceptance checks; no physical device was installed or tested.

Earlier failed bundles are retained. A later verification attempt encountered low disk space; the disposable simulator and the separate temporary Release cache created for this task were removed before retrying. Test compilation used one worker and one simulator at a time, and test simulators were shut down and deleted afterward. Existing uncommitted Xcode configuration and Xcode Cloud files were preserved.

## Run photo alignment, fonts, and branding — October 11, 2026

Statistics now support Leading, Center, and Trailing alignment and five system font styles. Cached font metrics keep the 260-point logical block, selection bounds, and clamping consistent. The fixed white/yellow wordmark uses an original vector R, and an optional rounded app-icon sticker has its own transform. Layer selection uses a menu; reset and photo replacement retain appearance choices and visibility. Preview and export share the same artwork view.

All **13 photo unit tests** passed, including 45 font/alignment/data combinations, metric and imperial values, missing data, hour-long durations, fixed wordmark pixels, icon asset availability, bounds, overlap selection, and exports in all four formats. Representative JPEGs were inspected for bold values, white/yellow branding, unclipped text, square icon proportions, and absence of editor controls. Results: `/tmp/runner-ui-results/20261011-165214-12956.xcresult`; final bold-font example: `/tmp/runner-photo-style-bold-images/175249FB-3046-40CE-91F2-6ADDA5CCBA7D.jpeg`.

The complete shared plan executed **95 tests** on iPhone SE / iOS 26.0: all 72 unit/data tests and 20 UI scenarios passed, with three UI failures. Two launches could not reveal the expected Latest run controls; the partial-data training-load assertion also failed. The full failed bundle is retained at `/tmp/runner-ui-results/20261011-170032-14968.xcresult`, with log `/tmp/runner-photo-style-full.log`. The alignment/font/icon scenario had passed separately on compact iPhone before that full run (`/tmp/runner-photo-style-ui-final.log`).

All **five photo UI scenarios passed on iPad Air / iOS 26.0**, including every font/alignment, independent icon dragging/pinching and accessible movement, hide/re-enable, reset, photo replacement, route/crop/export, loading and save-denial recovery, historical sessions, and large-text landscape accessibility. Result: `/tmp/runner-ui-results/20261011-172237-6870.xcresult`; log: `/tmp/runner-photo-style-ipad.log`. That additional run also attempted two existing Settings regression cases; both failed because their generic scroll helper dragged outside the narrower iPad Settings sheet. Their screenshots are retained. This is not a claim that the full iPad bundle was green.

The final compact-iPhone recheck passed all four selected scenarios with zero failures or skips: both existing fixture regressions, editor landscape accessibility, and the complete alignment/font/icon workflow. Result: `/tmp/runner-ui-results/20261011-photo-style-se-final.xcresult`; log: `/tmp/runner-photo-style-se-final.log`. This recovers all three failures from the full run. Across the full and focused runs, all 72 unit/data tests and all 23 UI scenarios have passing coverage; the original full bundle remains failed.

Screenshot inspection then showed the root large-text fixture setting was not inherited by the full-screen editor. The presentation now explicitly carries the host screen's dynamic text size, and the landscape test asserts that font previews use one column at accessibility sizes. The strengthened test passed with zero failures or skips on compact iPhone (`/tmp/runner-ui-results/20261011-174504-4167.xcresult`, log `/tmp/runner-photo-styles-large-text-se.log`) and iPad (`/tmp/runner-ui-results/20261011-photo-style-ipad-large-final.xcresult`, log `/tmp/runner-photo-styles-large-text-ipad.log`). Both final screenshots show the accessibility-size font labels and single-column previews.

The final Release ARM64 simulator build passed after the text-size adjustment with one build worker (`/tmp/runner-photo-style-release-final.log`). `git diff --check` passed. Xcode was reopened on the shared checkout and its branch control confirmed `feat/run-photo-editor`. All disposable simulators created for these checks were deleted, and temporary compiler caches were removed to reclaim space. Physical-device VoiceOver and real iCloud downloads remain acceptance checks; the unchanged native Photos/save/share integration was exercised in the base-editor checks above.

## Run photo route colors and sharing — October 11, 2026

The route now supports nine fixed sRGB presets: White, Runner yellow (`#D7FF00`), Orange, Red, Green, Blue, Purple, Pink, and Black. Named swatches and checkmarks expose selection without relying on color alone. Appearance changes retain independent layer positions and survive reset, hiding/re-enabling the route, and replacing photos. The shared artwork renderer applies the same route color to preview and export.

Successful saving dismisses the editor before the presenting run screen shows **Image saved**, with a **Share Image** action. Sharing supplies a photo payload to the native iOS activity controller so compatible installed social-app extensions can appear. The editor closes with **Image shared** only after successful activity completion; cancellation and errors preserve edits. Temporary share files are removed after dismissal. Debug fixtures simulate save/share outcomes without posting to apps or writing to the real Photos library.

The first compile stopped because fixture presentation code referenced `AppRuntime` from the isolated rendering test target. That UI code now lives with the editor, leaving image IO usable by isolated tests. The failed bundle remains `/tmp/runner-ui-results/20261011-180832-8500.xcresult` (log `/tmp/runner-photo-colors-se.log`). All **73 unit/data tests**, including 14 photo tests and nine route-color pixel/selection-free-export checks, subsequently passed in the compact-iPhone validation run.

That compact run executed 79 tests: 73 unit/data tests and five photo workflow scenarios passed, with the landscape accessibility case failing to scroll past a size slider. Bundle: `/tmp/runner-ui-results/20261011-180923-16756.xcresult`; log: `/tmp/runner-photo-colors-se-final.log`. Every route preset, layer placement, retained color on reset/replacement/toggling, successful save dismissal and receipt, save-to-share receipt flow, completed sharing, cancellation, share failure/retry, History, and missing GPS passed. Runner-yellow JPEG artwork was visually inspected at `/tmp/runner-photo-route-color-images/904425C9-E19C-4602-BA66-DEAA11D7FE33.jpeg`.

Two focused accessibility attempts are also retained: `/tmp/runner-ui-results/20261011-182148-24413.xcresult` (dragging in noninteractive padding failed to scroll) and `/tmp/runner-ui-results/20261011-182453-21533.xcresult` (iOS raised a hit-point exception for an offscreen menu). The helper now starts above a slider when needed and checks element bounds before querying hittability. Route visibility is set in portrait before the landscape palette audit.

The corrected compact-iPhone landscape/large-text scenario passed with zero failures or skips in `/tmp/runner-ui-results/20261011-182739-19620.xcresult` (log `/tmp/runner-photo-colors-se-accessibility-accepted.log`). Both font and route-palette accessibility audits passed, and the final screenshot confirms the named one-column swatches and selected Runner-yellow route. Across the full and focused compact runs, all 73 unit/data tests and all six photo UI scenarios have passing coverage; the original bundles remain failed.

All four focused iPad Air / iOS 26.0 scenarios passed with **zero failures and zero skips**, using the existing build: `/tmp/runner-ui-results/20261011-photo-colors-ipad.xcresult`, log `/tmp/runner-photo-colors-ipad.log`. The compatible action summary independently confirms four executed tests. Coverage includes landscape/large-text font and palette audits, gestures/crop/save-to-share, loading/save denial/share failure/retry/cancellation, and all route colors with retained transforms and appearance.

The final Release ARM64 simulator build passed with one worker (`/tmp/runner-photo-colors-release.log`). `git diff --check` passed. Xcode's open project is the shared checkout and its branch control identifies PR #6, whose source is `feat/run-photo-editor`.

Native acceptance on the disposable iPad used isolated run fixtures with `RUNNER_NATIVE_PHOTOS=1`. The system picker loaded a simulator sample photo; add-only authorization, an actual Photos write, editor dismissal, and the **Image saved** receipt were verified. **Share Image** presented the native iPad activity chooser with photo actions, and its temporary JPEG existed while the chooser was visible. The exported file `/tmp/runner-photo-colors-native.jpg` was inspected at 2160×1441, sRGB, with upright unclipped artwork and no GPS IFD or XMP metadata. The Mac locked before the final manual native activity completion; completion/cancellation/error behavior passed fixture UI checks on both devices. Third-party social extensions, real iCloud downloads, and physical-device VoiceOver remain device acceptance checks. No external messages or social posts were sent.

Both disposable simulators were removed after validation, and temporary compiler caches were cleared. Test results and representative exports remain available.
