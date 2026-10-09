#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-}"
if [[ -z "$DESTINATION" ]]; then
  TEST_SIMULATOR="$(xcrun simctl create Runner-UI-26 com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-26-0)"
  DESTINATION="platform=iOS Simulator,id=$TEST_SIMULATOR"
  trap 'xcrun simctl shutdown "$TEST_SIMULATOR" >/dev/null 2>&1 || true; xcrun simctl delete "$TEST_SIMULATOR"' EXIT
fi
if [[ "$DESTINATION" != *"platform=iOS Simulator"* ]]; then
  echo "This runner accepts simulator destinations only." >&2
  exit 2
fi
RESULT_DIR="${RUNNER_RESULTS_DIR:-/tmp/runner-ui-results}"
DERIVED_DIR="${RUNNER_DERIVED_DATA:-/tmp/runner-activity-derived}"
mkdir -p "$RESULT_DIR"
RESULT_PATH="$RESULT_DIR/$(date +%Y%m%d-%H%M%S)-$RANDOM.xcresult"
cd "$ROOT_DIR"
TEST_STATUS=0
TEST_RUNNER_RUNNER_EVIDENCE_DIR="${RESULT_PATH%.xcresult}-screenshots" \
xcodebuild test -project 'The Runner.xcodeproj' -scheme 'The Runner' \
  -testPlan Runner -destination "$DESTINATION" -derivedDataPath "$DERIVED_DIR" \
  -resultBundlePath "$RESULT_PATH" -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 -jobs 2 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO "${@:2}" || TEST_STATUS=$?
SUMMARY_PATH="${RESULT_PATH%.xcresult}-summary.json"
# Xcode 27's new summary reader can return zero tests for iOS 26.5 bundles.
# The action metrics remain available through the compatible object reader.
xcrun xcresulttool get object --legacy --path "$RESULT_PATH" --format json > "$SUMMARY_PATH"
if [[ "$TEST_STATUS" != "0" ]]; then exit "$TEST_STATUS"; fi
python3 - "$SUMMARY_PATH" <<'PY'
import json
import sys

with open(sys.argv[1]) as summary:
    result = json.load(summary)
metrics = result.get("metrics", {})
def count(key):
    return int(metrics.get(key, {}).get("_value", "0"))
total, failed, skipped = (count(key) for key in ("testsCount", "testsFailedCount", "testsSkippedCount"))
if total <= skipped or failed or count("errorCount"):
    sys.exit(f"Incomplete or failed test result: {total} tests, {failed} failures, {skipped} skipped")
print(f"Verified result: {total} tests, {failed} failures, {skipped} skipped")
PY
echo "Results: $RESULT_PATH"
