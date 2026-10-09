#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_SIMULATOR=""
cleanup() {
  if [[ -n "$TEST_SIMULATOR" ]]; then
    xcrun simctl shutdown "$TEST_SIMULATOR" >/dev/null 2>&1 || true
    xcrun simctl delete "$TEST_SIMULATOR"
    TEST_SIMULATOR=""
  fi
}
trap cleanup EXIT
cd "$ROOT_DIR"
if [[ "${RUNNER_SKIP_FULL_SUITE:-0}" != "1" ]]; then scripts/test-ui.sh; fi
for SPEC in \
  'Runner-SE-UI|iPhone-SE-3rd-generation|iOS-26-0' \
  'Runner-iPad-UI|iPad-Air-11-inch-M3|iOS-26-0' \
  "Runner-Recent-UI|iPhone-17-Pro|${RUNNER_RECENT_RUNTIME:-iOS-26-5}" \
  "Runner-Cloud-SE-UI|iPhone-SE-3rd-generation|${RUNNER_RECENT_RUNTIME:-iOS-26-5}" \
  "Runner-Cloud-Max-UI|iPhone-16-Pro-Max|${RUNNER_RECENT_RUNTIME:-iOS-26-5}"; do
  IFS='|' read -r LABEL DEVICE RUNTIME <<< "$SPEC"
  if [[ -n "${RUNNER_MATRIX_FILTER:-}" && "$LABEL" != "$RUNNER_MATRIX_FILTER" ]]; then continue; fi
  TEST_SIMULATOR="$(xcrun simctl create "$LABEL" "com.apple.CoreSimulator.SimDeviceType.$DEVICE" "com.apple.CoreSimulator.SimRuntime.$RUNTIME")"
  if [[ "$LABEL" == Runner-Cloud-* ]]; then
    TESTS=(
      -only-testing:RunnerUITests/RunnerUITests/testCalendarAndHistoryFilters
      -only-testing:RunnerUITests/RunnerUITests/testDashboardApprovalRetry
      -only-testing:RunnerUITests/RunnerUITests/testZonesAndCompleteVersusIncompleteLoad
      -only-testing:RunnerUITests/RunnerUITests/testAppOwnedScreenAccessibility
    )
  else
    TESTS=(
      -only-testing:RunnerUITests/RunnerUITests/testAppearanceLargeTextAndLandscape
      -only-testing:RunnerUITests/RunnerUITests/testAccessibilityAudit
      -only-testing:RunnerUITests/RunnerUITests/testNavigationAndActivityCheckpointRegression
      -only-testing:RunnerUITests/RunnerUITests/testBestEffortExclusionAndRepeatedRouteNavigation
      -only-testing:RunnerUITests/RunnerUITests/testGoalsCreateEditPersistAndDelete
    )
  fi
  scripts/test-ui.sh "platform=iOS Simulator,id=$TEST_SIMULATOR" "${TESTS[@]}"
  cleanup
done
