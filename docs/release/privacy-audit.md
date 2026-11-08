# Runner release privacy evidence

Reviewed November 8, 2026. This is an implementation/disclosure audit, not a claim that all provider processing is controlled by Runner. The initial audit was read-only. Subsequent release configuration and verification are recorded below; no credential values or user logs were printed.

## Result and proposed App Store mapping

The current four categories are incomplete: **Other Diagnostic Data is definitely required by the installed Firebase Auth SDK with its current defaults.** Production security/request logging also warrants disclosing network identifiers. Proposed release answers:

- **Health, Fitness, Precise Location, User ID:** linked to the user; App Functionality; no tracking. Keep the existing declarations. Explain that AI, cloud history, and precise-route sync are separately optional; local-only processing is not collection.
- **Other Diagnostic Data:** include SDK telemetry and operational request metadata. Firebase's SDK telemetry itself is **not linked**, purpose **Analytics**. Treat the category as **linked** for the aggregate store answer when it also covers identifiable server request diagnostics; purposes **App Functionality and Analytics**. Do not describe the app as collecting no analytics at all while this default SDK telemetry remains enabled.
- **Device ID:** recommended **linked / App Functionality / no tracking**, covering retained IP/network identifiers used for authentication, fraud prevention, and rate limits. This classification is an inference from their actual use, not a claim that the app reads IDFA/IDFV. Apple instructs developers to classify retained IP addresses by use; avoid an unverified “not linked” answer for authenticated security records.
- **Other Data Types:** no separate catch-all category is supported by the evidence reviewed. Attestation material is transient; measured workouts, identifiers, and diagnostics already have specific categories. Do not add Other Data merely because a security token exists.
- **Tracking:** no evidence of tracking, advertising identifiers, advertising use, or data-broker sharing. Keep tracking **No**. No Crashlytics, Performance Monitoring, Analytics, or Advertising SDK product is linked by the app target.

[Apple's definitions](https://developer.apple.com/app-store/app-privacy-details/) distinguish on-device processing and transient request data from retained collection, and require IP classification according to use. App manifests and SDK manifests do not replace the store questionnaire.

## Installed SDK evidence

`Package.resolved` pins Firebase iOS **12.19.2** (`8c29ca981990a32e626c8617544fa65d22b1834f`), App Check **11.3.2**, GoogleUtilities **8.1.4**, GTMSessionFetcher **5.3.1**, and Promises **2.4.1**. Inspected the matching checkouts in `/tmp/runner-release-derived/SourcePackages/checkouts`.

- The app target explicitly links `FirebaseAuth` and `FirebaseAppCheck`. Their source dependency graph brings Core/CoreInternal/CoreExtension, Auth/AppCheck interop, AppCheckCore/RecaptchaProvider, GoogleUtilities, GTMSessionFetcherCore, and FBLPromises. AppCheck's reCAPTCHA provider code is present as a dependency, but Runner instantiates only App Attest.
- [Firebase Auth's pinned manifest](https://github.com/firebase/firebase-ios-sdk/blob/8c29ca981990a32e626c8617544fa65d22b1834f/FirebaseAuth/Sources/Resources/PrivacyInfo.xcprivacy) declares unlinked `OtherDiagnosticData` for `Analytics`, linked `UserID` for `AppFunctionality`, no tracking, and UserDefaults reason `CA92.1`.
- Core/CoreInternal/CoreExtension, the inspected GoogleUtilities bundles, GTMSessionFetcherCore, and FBLPromises declare no collected data or tracking. Required-reason APIs occur in their own manifests. No standalone privacy manifest was found under FirebaseAppCheck or AppCheckCore in these versions.
- GoogleDataTransport's checked-out manifest declares unlinked diagnostics, but **that product is not in the Auth/AppCheck dependency path**. Likewise, Analytics/Ads packages appearing in the package lock do not establish that their products ship in Runner.
- No collection opt-out (`FirebaseDataCollectionDefaultEnabled` or runtime equivalent) is configured. Runner initializes Firebase at app launch, before optional cloud consent; do not promise that every network operation waits for AI consent.

Firebase describes its default user-agent collection as device/OS/app/platform version information, unlinked to an individual or device identifier. Auth creates account identifiers; App Check sends provider-specific attestation material. These behaviors match the manifest and initialization evidence. [Firebase Apple disclosure guide](https://firebase.google.com/docs/ios/app-store-data-collection)

## Authentication and security data

`AccountManager` requests no Apple name/email scopes and passes `fullName: nil`. It uses the Firebase UID; no phone authentication is implemented. A first-time and returning synthetic Apple login should still confirm whether a provider token supplies an email claim before the policy promises that an email can never reach Firebase. Do not log token values while checking this.

The backend verifies App Check without replay-protection consumption. Firebase says attestation material is not retained by App Check and ordinary non-replay tokens are not retained; provider terms still apply. Firebase Auth retains security IP logs for weeks and other authentication information until deletion, with removal from live/backups within 180 days. Auth operates in US data centers, so the policy must not imply all processing stays in `europe-west1`. [Firebase privacy and retention](https://firebase.google.com/support/privacy)

Runner's dashboard persists an hourly hash derived from IP for rate limits (two-hour expiry), truncated browser user-agent text in link records (ten-minute expiry), and account-linked session hashes (12-hour maximum/30-minute idle timeout). These are security records, not advertising tracking; hashing alone does not establish anonymization.

## Verified production settings and retention

Read-only Google Cloud queries confirmed for `runner-mdo-production`:

- `billingEnabled = True`.
- Global `_Default` log bucket retention is **30 days**.
- `_Default` sink is enabled and has no exclusions; its filter excludes the usual audit categories, not Cloud Run requests.

`Fastify({logger:false})` disables the application logger, **not Cloud Run request logs**. Cloud Run automatically emits request/system logs. Its HTTP log schema supports remote IP, user agent, request URL, status, latency, and sizes. Production configuration therefore does not support “no server logs” or “no retained IP addresses.” [Cloud Run logging](https://docs.cloud.google.com/run/docs/logging), [HTTP log schema](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#HttpRequest), [log retention](https://docs.cloud.google.com/logging/docs/store-log-entries)

Runner's source separately expires completed analysis cache entries after 24 hours, live entries after 60 seconds, and quota records after two days. Firestore TTL deletion is asynchronous. Consented history has no TTL and persists until deletion. Local reports and provider retention are separate from these cache periods.

## Gemini processing

The backend uses `GoogleGenAI({apiKey})` with `models.generateContent`, sending only numerical metrics, splits, quality flags, and the historical baseline. It does not send raw HealthKit samples, routes, names, email, or the Firebase UID. It does not use the Interactions API, grounding, uploaded media, or explicit caches.

Active billing is verified for Runner's project; the deployment/README identify the project-managed Gemini secret. Google's paid-service terms say prompts/responses are not used to improve its products. This does **not** mean zero retention or no human review. [Gemini terms](https://ai.google.dev/gemini-api/terms)

Google's abuse-monitoring documentation specifies **55-day** retention of prompts, context, and output, with authorized review of flagged content. Describe this separately from Runner's 24-hour cache. [Gemini abuse monitoring](https://ai.google.dev/gemini-api/docs/usage-policies)

## Remaining focused verification

- Inspect the final signed archive's aggregated privacy report and embedded SDK bundles. The simulator app was subsequently inspected as recorded below; it is not a signed distribution archive.
- Verified on 2026-11-08: deployed Secret Manager version1 matches the API key named Runner Gemini backend in billed project runner-mdo-production. Only the boolean comparison was printed; no secret was logged. AI Studio subsequently showed optional GenerateContent request storage enabled for Runner. Disabled it on November 8 and verified the switch remains off. The page showed no logs and no named datasets; no contributed logs were present. The unused Interactions API setting was left unchanged. Provider abuse-monitoring retention remains separate. [Gemini logs and datasets](https://ai.google.dev/gemini-api/docs/logs-datasets)
- Verify Firebase/Apple claim presence using a disposable test account, and confirm no extra organization-level logging sink retains Runner request logs beyond the verified project bucket. Current evidence does not establish an across-all-providers maximum deletion period.

## Built simulator bundle verification

Later on November 8, inspected `/tmp/runner-release-derived/Build/Products/Debug-iphonesimulator/Runner: Analyzer & Tracking.app` rather than inferring shipping resources from the package lock. Its `UIDeviceFamily` is `[1]` and it contains no embedded Watch app.

The app contains **15 privacy manifests**: its own; Firebase Auth, Core, CoreExtension and CoreInternal; GTMSessionFetcherCore; GoogleUtilities AppDelegateSwizzler, Environment, Logger, NSData, Network, Reachability and UserDefaults; and FBLPromises and Promises. All declare tracking false. The SDK manifests add only **Other Diagnostic Data (unlinked, Analytics)** and **User ID (linked, App Functionality)** to the app's four declarations. No embedded manifest declares Device ID, Other Data, Crash Data, or Performance Data. No Firebase Analytics, GoogleDataTransport, FirebaseInstallations, advertising, Crashlytics, or Performance privacy bundle was present.

This confirms the diagnostic-disclosure finding. It does **not** by itself establish retained server IP handling: the recommended Device ID mapping above comes from the verified security/logging behavior and remains explicitly an interpretation of Apple's categories, not a claim that an SDK manifest declares it. The App Store privacy answers must account for both the app bundle and backend/provider processing. A final distribution-archive check remains necessary after the selected build is created.

## Release verification update

- A live synthetic-only provider smoke test returned a valid German summary, insight, and next-run text using the configured Gemini model. No real workout or account data was sent.
- Project-level logging sinks are the standard `_Required` and `_Default` sinks only. Organization-level sinks remain outside this evidence.
