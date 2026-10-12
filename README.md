# Runner

A native iOS 26.0+ and watchOS 11.5+ running app. Latest Run shows recorded metrics, linked charts, splits, routes, and performance assessment. History provides filters, sorting, and local route density. Activity includes volume charts, a training calendar, recurring goals, and period comparisons. Trends includes comparable runs, dated Health measurements, estimated best efforts, intensity, and observed training load. Live mirrors workouts recorded by Runner on Apple Watch.

Open **The Runner.xcodeproj** and select the shared **The Runner** scheme. The bundle ID and App Store SKU remain `com.run.mdo.analyze.track`; the Watch companion is `com.run.mdo.analyze.track.watchkitapp`. The existing icon is preserved.

## Build and test

Use Xcode 26 or newer with iOS and watchOS platform support installed. Validation uses installed Xcode 27 and iOS 26 simulators. The iOS scheme embeds the Watch app, so its asset compilation also needs the matching Watch platform/runtime.

```sh
scripts/test-ui.sh
scripts/test-matrix.sh
swift test --package-path Packages/RunCore
```

If command-line tools are selected globally, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Use a build/DerivedData path without a colon if a tool rejects the local checkout's display name.

`RunCore` contains deterministic calculations, wire contracts, route filtering, density, and comparable-history rules. Its tests also run in the RunnerTests target. Debug builds launched with `--runner-fixtures` use a temporary in-memory store of clearly named synthetic Watch workouts, never the user's Health store. This switch is excluded from Release builds.

## Visual theme

Runner uses a dark interface with sporty yellow (`#D7FF00`) highlights, charcoal cards, and condensed metric values. Metric grids adapt to two columns on compact screens, four when their container is at least 720 points wide, and one at accessibility text sizes. Analytics sections use two columns from 840 points of available content width, including iPad split-view reflow. Yellow primary buttons have black labels; warnings and destructive actions retain their semantic colors.

Latest and historical runs share a compact summary with independent metric tiles. Activity and Trends group related analytics into dashboards, and History places its run journal before the density map. The iOS icon and photo sticker use a yellow runner on black; Watch styling remains unchanged. Measurements, unit preferences, missing-data handling, routes, and photo-export typography remain the same.

The visual hierarchy references [Nike Run Club](https://www.nike.com/nrc-app) and [Strava’s Training Log](https://support.strava.com/en-us/articles/15402077-training-log). Contrast, scalable typography, and accessible controls follow [Apple’s accessibility guidance](https://developer.apple.com/documentation/accessibility/testing-system-accessibility-features-in-your-app).

See the [redesign screenshots and export examples](docs/redesign/README.md) and [validation notes](docs/validation.md).

## Run photos

Tap the photo icon in **Latest Run → Run summary**, or open an older run from History, to create a run photo. Choose a still image, then drag or pinch the statistics block and optional GPS route independently. **Crop** reframes the background; position buttons and the size slider provide alternatives to gestures. Original, Story (9:16), Portrait (4:5), and Square formats are available.

The overlay uses the selected run’s measured distance, average pace, and moving time with the current unit preference. **The Runner** appears in white and sporty yellow. GPS is drawn as solid route segments without map tiles or markers; pauses and missing/invalid GPS remain gaps. Select **Route** in **Edit layer** to choose White, Runner yellow (`#D7FF00`), Orange, Red, Green, Blue, Purple, Pink, or Black. Color choices survive reset, route toggling, and photo replacement. Indoor runs and runs without GPS still support photo statistics.

Select **Stats** in **Edit layer** to choose Leading, Center, or Trailing alignment and preview Sport, Clean, Rounded, Mono, or Serif fonts. The wordmark keeps its distinctive yellow R across metric fonts. **Include app icon** adds the yellow-on-black Runner icon as an independent sticker; select Icon to move or resize it. Changing photos keeps your styling and overlays. Reset restores crop and layer positions/sizes while retaining styling and visible layers.

**Save Photo** requests add-only Photos access. Successful saving closes the editor and shows **Image saved**, with **Share Image** to send the exported image onward. **Share to apps** opens the native iOS chooser with a photo payload, allowing compatible installed social apps and other services to appear. Completed sharing closes the editor and shows **Image shared**; cancelling or a sharing error keeps the edit available. App availability and final posting behavior depend on each destination’s share extension. Editing stays on-device, requires no account, and does not attach images to history or upload them to Runner’s services. Exports are JPEGs with fresh pixels and no source-photo location metadata. Original exports retain the photo’s ratio up to a 2160-pixel long edge; social exports are 1080 pixels wide. Editable compositions last only while the editor is open.

The route palette uses familiar UI colors plus the app’s yellow, including orange seen in [Strava route artwork](https://www.strava.com/sports/walking) and blue used in [Google’s route examples](https://developers.google.com/maps/documentation/routes/traffic_on_polylines). Preset names and checkmarks follow [Apple’s color guidance](https://developer.apple.com/design/human-interface-guidelines/color), so selection does not depend on color alone. Sharing uses [Apple’s activity controller](https://developer.apple.com/documentation/uikit/uiactivityviewcontroller) rather than app-specific posting integrations. The presets are curated for photo contrast and familiar route styling.

If Photos access is denied, **Share Instead** keeps the current composition available. Share a copy before changing access in Settings: iOS can restart Runner when permissions change, discarding an in-memory edit.

## Activity

The Activity tab defaults to **Current month** with the number of completed runs and daily bars. Switch between **Runs**, **Distance**, **Moving Time**, and **Elevation Gain**, or select **3 Months**, **6 Months**, or **Year** for monthly bars. Multi-month ranges include the current month plus the previous two or five months; Year starts at the beginning of the current calendar year. Custom dates use daily buckets through 31 days, weekly through 180 days, and monthly thereafter. Totals stop at the present time, empty buckets remain visible, and selecting a bucket reveals totals and matching runs. Distance and elevation honor unit preferences, with metric as the default. The monthly calendar provides intensity and day-to-run navigation.

Below the graph, goals show progress and active-day consistency. Two compact comparison groups retain Current month, Last month, Current week, and Last week totals for runs, measured distance, moving time, and distance-weighted average pace. Improvements compare the same elapsed calendar-day/time portion of the previous month/week. If the previous month is shorter, both comparison windows are capped at that month's length. Comparison dates are displayed explicitly; decreases and unchanged values are shown as well as increases. These volume and pace changes are descriptive, not the comparable-effort fitness assessment on Trends.

Periods use the device calendar and time zone, with runs assigned by workout start date. Missing distance is never fabricated: available totals are labeled as partial when necessary, and distance/pace comparisons are withheld when their inputs are incomplete. Imported history may itself be incomplete if Health access or synchronization is limited.

## Health import and Watch recording

HealthKit runs from any source are imported with source attribution, including Apple's Workout app. The newest run loads first; anchored queries backfill 40 changes per page, reconcile deletion, and persist checkpoints only after successful processing. Route anchors and recent-workout refresh handle delayed route/sample arrival. A Health authorization sheet completing is never treated as proof of read access.

SwiftData stores runs and analysis locally under `ApplicationSupport/RunnerHealth`, excluded from device backups and protected until first unlock after restart. Missing measurements remain unavailable rather than becoming zero. Raw HealthKit samples are not uploaded. Precise GPS routes stay on-device unless the user separately enables route sync; routes are never sent to Gemini.

Runner Watch owns HealthKit workout sessions and builders, records GPS when permitted, and can pause/resume/end/save independently of the phone. Session mirroring provides live measurements and optional AI notes when connected. Apple Workout sessions are imported after completion; they are not mirrored live by Runner. Targets and optional haptics work locally offline. Without user-configured targets, Runner does not invent heart-rate zones.

## AI and privacy

AI requires Sign in with Apple, adult confirmation, and explicit versioned sharing consent in Settings. After consent, the latest run and newly completed runs are analyzed automatically. Older runs require an explicit request. Numerical summaries, splits, quality flags, and a compact baseline go to the Firebase-protected Runner service and then Gemini; precise routes, names, email addresses, and raw HealthKit samples do not.

The app's `GoogleService-Info.plist` is public Firebase configuration, not a Gemini secret. Its key is restricted to Runner's bundle ID and Firebase authentication/attestation services. `ServiceConfig.plist` selects the HTTPS production endpoint. Private Apple/Gemini keys live in Runner Secret Manager, never in these repositories. App Attest is enforced by the API, so the simulator cannot establish a production AI session.

Measured stats stay available when offline, out of quota, or when AI validation fails. Reports include evidence and missing-data explanations. Fitness trends are not diagnoses; VO₂ max and heart-rate recovery are shown only when recorded, with dates. Pace/heart-rate comparisons need at least five comparable prior runs.

Settings supports metric/imperial units, local Health cache clearing, sign-out, and cloud account deletion after Apple reauthentication. Deleting the cloud account does not erase Apple Health workouts.

## Private cloud history and dashboard

In Settings, sign in with Apple and enable **Sync running history** to consent to durable storage of all imported runs, measured metrics, splits, chart aggregates, dated VO₂ max/recovery measurements, and saved AI reports in the Runner Firestore database. **Also sync precise GPS routes** is a separate opt-in. Disabling GPS sharing removes uploaded coordinates across the account. Offline withdrawals are persisted and retried when the phone reconnects. Disabling history pauses uploads and removes routes; numerical history remains until **Delete uploaded history** or **Delete cloud account**.

Each phone must opt in under the same Runner Apple identity. Runner uploads only Health records available on that phone; it cannot remotely query all Apple devices or recover Health records that have not synced to the phone. HealthKit read completion does not establish read access. Workout and measurement anchors propagate explicit deletions; empty reads do not imply deletion. Workout and deleted-route tombstones prevent older phones from restoring removed data. Per-user local checkpoints and server hashes deduplicate uploads; privacy revisions reject stale in-flight GPS uploads and invalidate checkpoints after cloud history is cleared.

The dashboard is at https://runner-api-lradqed2xa-ew.a.run.app/dashboard. Request a code in the browser, then open **Settings → Cloud history → Connect dashboard** in Runner. Enter the code, review the requesting browser, and explicitly approve access to your uploaded history. Apple identity and App Check are verified on the phone; no Apple password or Health authorization is entered in the dashboard. Browser sessions are read-only, use secure HttpOnly cookies, last at most 12 hours, and expire after 30 minutes without API activity. Sign out from shared computers.

The iOS connection flow separates validated codes and dated browser requests, authenticated transport (`DashboardLinkService`), and presentation state (`DashboardConnectionModel`). It accepts formatted hexadecimal codes, checks expiry again before approval, and invalidates reviews when the code or account changes or the sheet closes. Tests inject a service and clock to cover delayed responses, expiry, retries, and duplicate approval attempts without granting a real browser access.

Cloud checkpoint digests use `payloadDigest`, with `originalName: "hash"` for an in-place migration. The previous property name collided with Core Data's numeric `hash` accessor and could crash when saved checkpoints were fetched. Storage regressions cover reopening saved checkpoints and migrating an old populated store while preserving workouts, Health anchors, measurements, and deletion records. Updating does not require clearing local data.

The dashboard shows Latest Run, History, Trends, numerical tables, dated endurance measurements, saved AI assessments, and separately consented route maps. Chart aggregates retain gaps and pauses; numerical metrics use the same RunCore calculations as iOS. Maps render in the browser without transmitting coordinates to an external map provider. Historical density counts one traversal per run per approximate 100-meter cell. GPS paths are simplified to bounded representations; this is a performance dashboard, not a raw HealthKit backup.

## Release validation

Automated checks cover measurements, units, overlapping pauses, sparse heart-rate data, GPS gaps, delayed analysis input changes, density weighting, and comparable-history thresholds. Simulator UI checks use realistic fixtures and accessibility text sizes.

Before public distribution, validate on a signed physical iPhone/Watch pair:

- Apple sign-in, explicit consent, App Attest, complete-run analysis, quota and offline fallback, and account deletion/revocation.
- Start/pause/resume/end/save outdoors with GPS and indoors without it; deny route/Health read access and verify unavailable states.
- Disconnect the iPhone during recording, continue local cues, reconnect, and confirm one Health workout and one imported run.
- Terminate/recover the Watch app during a workout and check retained metrics, pauses, and route gaps.
- Import Apple Workout runs, deliver a delayed route, sync repeatedly without duplicates, then delete a workout in Health and verify reconciliation.
- VoiceOver labels, large accessibility sizes, both units, empty states, and background Health refresh.

Xcode Cloud's **Runner main CI** workflow triggers on `main` with required archive and test actions for The Runner scheme, which includes the Watch companion. Both actions passed for the initial implementation on October 3, 2026. The original local RunCore and iOS 18.5 simulator suites each passed 11 tests; fixture UI checks covered normal and accessibility text sizes. Cloud archives and simulator tests do not establish physical Watch recording or connectivity behavior. The physical-device checklist above remains a release gate. This work does not submit the app for App Store review.

History sync validation: 16 RunCore tests and 17 iOS 18.5 simulator tests passed, including migration from the previous saved-workout schema using the actual storage models. The Swift history payload passed the backend contract; database persistence and GPS withdrawal also passed a disposable real-Firestore smoke test. Chrome checks covered graphs, tables, routes, units, and phone-width layout. Real Health uploads, native Apple authentication/App Attest, and Watch recording still require the physical-device checklist.

## iOS 26 UI and simulator automation

Runner now targets iOS 26.0+, follows system light/dark appearance, and uses native Liquid Glass navigation and actions. The Watch minimum remains watchOS 11.5. See [automated simulator UI tests](docs/ui-testing.md) for reproducible test commands and isolated fixtures, and [the visualization comparison](docs/visualization-roadmap.md) for the Strava-inspired analytics roadmap.

Local goals, best efforts, zones, training load, and repeated-route rules are documented in [training analytics](docs/training-analytics.md). Current test evidence is recorded in [implementation validation](docs/validation.md).
