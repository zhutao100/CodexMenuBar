#!/bin/bash
# Export attachments + diagnostics from a .xcresult bundle.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $(basename "${BASH_SOURCE[0]}") <results.xcresult> <out_dir> [--only-failures]" >&2
  exit 2
fi

BUNDLE="$1"
OUT_DIR="$2"
shift 2

ONLY_FAILURES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only-failures) ONLY_FAILURES=1; shift 1;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

ATT_DIR="$OUT_DIR/attachments"
DIAG_DIR="$OUT_DIR/diagnostics"
LOG_DIR="$OUT_DIR/logs"
META_JSON="$OUT_DIR/xcresult_metadata.json"
SUMMARY_JSON="$OUT_DIR/xcresult_summary.json"
TESTS_JSON="$OUT_DIR/xcresult_tests.json"
BUILD_RESULTS_JSON="$OUT_DIR/build_results.json"
INSIGHTS_JSON="$OUT_DIR/insights.json"
ACTION_LOG_TXT="$LOG_DIR/action.txt"
CONSOLE_LOG_TXT="$LOG_DIR/console.txt"

mkdir -p "$ATT_DIR" "$DIAG_DIR" "$LOG_DIR"

# Best-effort exports (do not fail the overall run if these change across Xcode versions).
xcrun xcresulttool metadata get --path "$BUNDLE" > "$META_JSON" || true

if xcrun xcresulttool get test-results summary --help >/dev/null 2>&1; then
  xcrun xcresulttool get test-results summary --path "$BUNDLE" --compact > "$SUMMARY_JSON" || true
  xcrun xcresulttool get test-results tests --path "$BUNDLE" --compact > "$TESTS_JSON" || true
  xcrun xcresulttool get test-results insights --path "$BUNDLE" --compact > "$INSIGHTS_JSON" || true
  xcrun xcresulttool get build-results --path "$BUNDLE" --compact > "$BUILD_RESULTS_JSON" || true
  xcrun xcresulttool get log --path "$BUNDLE" --type action --compact > "$ACTION_LOG_TXT" || true
  xcrun xcresulttool get log --path "$BUNDLE" --type console --compact > "$CONSOLE_LOG_TXT" || true
else
  # Older Xcodes: fall back to legacy JSON root.
  xcrun xcresulttool get --path "$BUNDLE" --format json > "$SUMMARY_JSON" || true
  xcrun xcresulttool get --path "$BUNDLE" --format json > "$TESTS_JSON" || true
fi

if [[ "$ONLY_FAILURES" -eq 1 ]]; then
  xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$ATT_DIR" --only-failures || true
else
  xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$ATT_DIR" || true
fi

xcrun xcresulttool export diagnostics --path "$BUNDLE" --output-path "$DIAG_DIR" || true
