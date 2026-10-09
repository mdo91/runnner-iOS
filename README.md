# Runner

A native iOS 18.5+ and watchOS 11.5+ running app. Latest Run shows the newest imported workout's actual distance, duration, pace, heart rate, splits, route, and performance assessment. History includes local route density; Activity charts run counts and kilometers with monthly and weekly performance; Trends uses comparable runs and dated Health measurements; Live mirrors workouts recorded by Runner on Apple Watch.

Open **The Runner.xcodeproj** and select the shared **The Runner** scheme. The bundle ID and App Store SKU remain `com.run.mdo.analyze.track`; the Watch companion is `com.run.mdo.analyze.track.watchkitapp`. The existing icon is preserved.

## Build and test

Use Xcode with iOS and watchOS platform support installed. The iOS scheme embeds the Watch app, so its asset compilation also needs the matching Watch platform/runtime.

```sh
xcodebuild -project 'The Runner.xcodeproj' -scheme 'The Runner' \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' test
swift test --package-path Packages/RunCore
```

If command-line tools are selected globally, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Use a build/DerivedData path without a colon if a tool rejects the local checkout's display name.

`RunCore` contains deterministic calculations, wire contracts, route filtering, density, and comparable-history rules. Its tests also run in the RunnerTests target. Debug builds launched with `--runner-fixtures` use a temporary in-memory store of clearly named synthetic Watch workouts, never the user's Health store. This switch is excluded from Release builds.

## Activity

The Activity tab defaults to **Current month** with the number of completed runs and daily bars. Switch between **Runs** and **Kilometers**, or select **3 Months**, **6 Months**, or **Year** for monthly bars. The multi-month ranges include the current month plus the previous two or five months; Year starts at the beginning of the current calendar year. Totals stop at the present time, empty days/months remain visible, and touching the chart shows a bucket's totals. This tab always uses kilometers, including when other screens use imperial units.

Below the graph, Current month, Last month, Current week, and Last week show run count, measured kilometers, moving time, and distance-weighted average pace. Improvements compare the same elapsed calendar-day/time portion of the previous month/week. If the previous month is shorter, both comparison windows are capped at that month's length. Comparison dates are displayed explicitly; decreases and unchanged values are shown as well as increases. These volume and pace changes are descriptive, not the comparable-effort fitness assessment on Trends.

Periods use the device calendar and time zone, with runs assigned by workout start date. Missing distance is never fabricated: known kilometers are labeled as partial when necessary, and distance/pace comparisons are withheld when their inputs are incomplete. Imported history may itself be incomplete if Health access or synchronization is limited.

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
