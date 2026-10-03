# Runner

A native iOS 18.5+ and watchOS 11.5+ running app. Latest Run shows the newest imported workout's actual distance, duration, pace, heart rate, splits, route, and performance assessment. History includes local route density; Trends uses comparable runs and dated Health measurements; Live mirrors workouts recorded by Runner on Apple Watch.

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

## Health import and Watch recording

HealthKit runs from any source are imported with source attribution, including Apple's Workout app. The newest run loads first; anchored queries backfill 40 changes per page, reconcile deletion, and persist checkpoints only after successful processing. Route anchors and recent-workout refresh handle delayed route/sample arrival. A Health authorization sheet completing is never treated as proof of read access.

SwiftData stores runs and analysis locally under `ApplicationSupport/RunnerHealth`, excluded from device backups and protected until first unlock after restart. Missing measurements remain unavailable rather than becoming zero. GPS routes and raw samples are not sent to the Runner backend or Gemini.

Runner Watch owns HealthKit workout sessions and builders, records GPS when permitted, and can pause/resume/end/save independently of the phone. Session mirroring provides live measurements and optional AI notes when connected. Apple Workout sessions are imported after completion; they are not mirrored live by Runner. Targets and optional haptics work locally offline. Without user-configured targets, Runner does not invent heart-rate zones.

## AI and privacy

AI requires Sign in with Apple, adult confirmation, and explicit versioned sharing consent in Settings. After consent, the latest run and newly completed runs are analyzed automatically. Older runs require an explicit request. Numerical summaries, splits, quality flags, and a compact baseline go to the Firebase-protected Runner service and then Gemini; precise routes, names, email addresses, and raw HealthKit samples do not.

The app's `GoogleService-Info.plist` is public Firebase configuration, not a Gemini secret. Its key is restricted to Runner's bundle ID and Firebase authentication/attestation services. `ServiceConfig.plist` selects the HTTPS production endpoint. Private Apple/Gemini keys live in Runner Secret Manager, never in these repositories. App Attest is enforced by the API, so the simulator cannot establish a production AI session.

Measured stats stay available when offline, out of quota, or when AI validation fails. Reports include evidence and missing-data explanations. Fitness trends are not diagnoses; VO₂ max and heart-rate recovery are shown only when recorded, with dates. Pace/heart-rate comparisons need at least five comparable prior runs.

Settings supports metric/imperial units, local Health cache clearing, sign-out, and cloud account deletion after Apple reauthentication. Deleting the cloud account does not erase Apple Health workouts.

## Release validation

Automated checks cover measurements, units, overlapping pauses, sparse heart-rate data, GPS gaps, delayed analysis input changes, density weighting, and comparable-history thresholds. Simulator UI checks use realistic fixtures and accessibility text sizes.

Before public distribution, validate on a signed physical iPhone/Watch pair:

- Apple sign-in, explicit consent, App Attest, complete-run analysis, quota and offline fallback, and account deletion/revocation.
- Start/pause/resume/end/save outdoors with GPS and indoors without it; deny route/Health read access and verify unavailable states.
- Disconnect the iPhone during recording, continue local cues, reconnect, and confirm one Health workout and one imported run.
- Terminate/recover the Watch app during a workout and check retained metrics, pauses, and route gaps.
- Import Apple Workout runs, deliver a delayed route, sync repeatedly without duplicates, then delete a workout in Health and verify reconciliation.
- VoiceOver labels, large accessibility sizes, both units, empty states, and background Health refresh.

Xcode Cloud's **Runner main CI** workflow triggers on `main` with required archive and test actions for The Runner scheme, which includes the Watch companion. Both actions passed for the initial implementation on October 3, 2026. Local RunCore and iOS 18.5 simulator suites each passed 11 tests; fixture UI checks covered normal and accessibility text sizes. Cloud archives and simulator tests do not establish physical Watch recording or connectivity behavior. The physical-device checklist above remains a release gate. This work does not submit the app for App Store review.
