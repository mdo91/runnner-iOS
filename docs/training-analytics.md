# Local training analytics

These views require neither sign-in nor AI consent. Workouts retain their existing storage and cloud contracts. Local preferences use versioned JSON under `trainingAnalytics.v1`; clearing device data also clears goals, zones, and effort exclusions.

## Goals

Weekly, monthly, and annual targets recur by the user's calendar. Completed workouts count by start date, including eligible workouts imported before goal creation. Runs use counts, distance/elevation use meters internally, and time uses seconds. Editors convert the selected display units; metric is the default. One goal per period/metric can be edited or deleted. Partial measurement totals disclose missing data.

## Estimated best efforts

Benchmarks are 400 m, 1 km, 1 mile, 5 km, 10 km, half marathon, and marathon. Each eligible workout contributes its fastest elapsed effort per benchmark. Lifetime top three, annual best, history, and originating workouts are available. Excluding an inaccurate benchmark reranks results without deleting a workout; exclusions can be restored.

Distance intervals must be finite, positive, nonoverlapping, and agree with the workout total within 5%. Boundaries interpolate recorded active distance; internal pauses count toward elapsed effort. Unexplained gaps and intervals with more than 30 seconds of unobserved active movement are conservatively rejected. Estimates are not certified race times.

## Heart-rate zones and load

Supply a known maximum heart rate; Runner does not estimate it from age. Initial lower boundaries are 50%, 60%, 70%, 80%, and 90% of maximum, and can be edited. Maximum must be 80–240 bpm; five boundaries must increase by at least 1 bpm and stay below maximum. History recalculates when settings change.

Each valid recorded pulse represents at most 30 seconds, ends at the next sample, and excludes pauses. Below-Zone-1 time is separate. Valid readings above maximum are flagged and counted in Zone 5. Missing pulse is never filled across recording gaps. An invalid reading ends the previous observation; it does not become measured zero or contribute to coverage.

Observed effort is minutes in Zones 1–5 multiplied by weights 1–5. Daily and weekly bars show observed effort, with incomplete recordings distinguished. Trailing 7/28 calendar-day totals include today's elapsed portion and are unavailable if any contributing run has less than 80% heart-rate coverage. This is not a validated fitness/fatigue model or a medical assessment.

## Repeated routes

Only reliable outdoor GPS routes with a continuous trustworthy recording and plausible measured distance are eligible. Routes are resampled to 101 corresponding distance positions. The direction must match, endpoints must be within 100 m, distances within 10%, and at least 90% of corresponding points within 60 m. Open-route alignment must fit the recorded order better than its reverse. Closed loops must have matching signed orientation; ambiguous self-intersecting loops are conservatively excluded. This rejects reverse small loops even when every point lies within the 60 m tolerance. Reverse, distant, indoor, and unreliable recordings are rejected. Completion counts and pace histories open the originating runs.

Weather, stops, effort, altitude noise, and sample resolution affect all comparisons. Remaining opportunities and Strava source references are documented in `visualization-roadmap.md`; web-dashboard parity remains a follow-up.
