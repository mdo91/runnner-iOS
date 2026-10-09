#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-platform=iOS Simulator,name=iPhone 16,OS=26.0}"
if [[ "$DESTINATION" != *"platform=iOS Simulator"* ]]; then
  echo "This runner accepts simulator destinations only." >&2
  exit 2
fi
RESULT_DIR="${RUNNER_RESULTS_DIR:-/tmp/runner-ui-results}"
DERIVED_DIR="${RUNNER_DERIVED_DATA:-/tmp/runner-activity-derived}"
mkdir -p "$RESULT_DIR"
RESULT_PATH="$RESULT_DIR/$(date +%Y%m%d-%H%M%S)-$RANDOM.xcresult"
cd "$ROOT_DIR"
xcodebuild test -project 'The Runner.xcodeproj' -scheme 'The Runner' \
  -testPlan Runner -destination "$DESTINATION" -derivedDataPath "$DERIVED_DIR" \
  -resultBundlePath "$RESULT_PATH" -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 -jobs 2 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO "${@:2}"
echo "Results: $RESULT_PATH"
