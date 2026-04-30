#!/bin/bash
# Export attachments + diagnostics from a .xcresult bundle.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 2 ]]; then
  cat >&2 <<'USAGE'
Usage: xcresult_export.sh <results.xcresult> <out_dir> [options]

Options:
  --only-failures                         Export only attachments associated with failed tests
  --sanitize-screenshots <policy>         keep | redact | redact-suspect | crop
  --screenshot-crop <x,y,width,height>    Crop rectangle for --sanitize-screenshots crop
  --delete-raw-attachments                Remove attachments_raw after sanitized export
USAGE
  exit 2
fi

BUNDLE="$1"
OUT_DIR="$2"
shift 2

ONLY_FAILURES=0
SANITIZE_SCREENSHOTS=""
SCREENSHOT_CROP=""
DELETE_RAW_ATTACHMENTS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only-failures) ONLY_FAILURES=1; shift 1;;
    --sanitize-screenshots) SANITIZE_SCREENSHOTS="$2"; shift 2;;
    --screenshot-crop) SCREENSHOT_CROP="$2"; shift 2;;
    --delete-raw-attachments) DELETE_RAW_ATTACHMENTS=1; shift 1;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

case "$SANITIZE_SCREENSHOTS" in
  ""|keep|redact|redact-suspect|crop) ;;
  *) echo "--sanitize-screenshots must be keep, redact, redact-suspect, or crop" >&2; exit 2;;
esac
if [[ "$SANITIZE_SCREENSHOTS" == "crop" && -z "$SCREENSHOT_CROP" ]]; then
  echo "--sanitize-screenshots crop requires --screenshot-crop x,y,width,height" >&2
  exit 2
fi

ATT_DIR="$OUT_DIR/attachments"
RAW_ATT_DIR="$OUT_DIR/attachments_raw"
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

EXPORT_ATT_DIR="$ATT_DIR"
if [[ -n "$SANITIZE_SCREENSHOTS" && "$SANITIZE_SCREENSHOTS" != "keep" ]]; then
  EXPORT_ATT_DIR="$RAW_ATT_DIR"
  rm -rf "$RAW_ATT_DIR"
  mkdir -p "$RAW_ATT_DIR"
fi

if [[ "$ONLY_FAILURES" -eq 1 ]]; then
  xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$EXPORT_ATT_DIR" --only-failures || true
else
  xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$EXPORT_ATT_DIR" || true
fi

if [[ -n "$SANITIZE_SCREENSHOTS" && "$SANITIZE_SCREENSHOTS" != "keep" ]]; then
  SANITIZE_ARGS=("$EXPORT_ATT_DIR" "$ATT_DIR" "--clean" "--policy" "$SANITIZE_SCREENSHOTS" "--report" "$OUT_DIR/attachment_sanitization.json")
  if [[ -n "$SCREENSHOT_CROP" ]]; then
    SANITIZE_ARGS+=("--crop" "$SCREENSHOT_CROP")
  fi
  "$SCRIPT_DIR/xcresult_sanitize_attachments.py" "${SANITIZE_ARGS[@]}" || true
  if [[ "$DELETE_RAW_ATTACHMENTS" -eq 1 ]]; then
    rm -rf "$RAW_ATT_DIR"
  fi
fi

xcrun xcresulttool export diagnostics --path "$BUNDLE" --output-path "$DIAG_DIR" || true
