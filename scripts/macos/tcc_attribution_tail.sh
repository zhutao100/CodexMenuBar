#!/usr/bin/env bash
# Capture a short TCC attribution log slice while reproducing a privacy prompt.
set -euo pipefail

DURATION=30
OUT="tcc-attribution.log"
STYLE="compact"

usage() {
  cat <<'USAGE'
Usage: tcc_attribution_tail.sh [--duration seconds] [--out path]

Captures macOS TCC AttributionChain log entries. Run it in one terminal, then
reproduce the UI-test permission prompt in another terminal during the capture
window. The output helps identify the responsible executable/bundle for PPPC.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2;;
  esac
done

mkdir -p "$(dirname "$OUT")"
PREDICATE='subsystem == "com.apple.TCC" AND eventMessage BEGINSWITH "AttributionChain"'

printf 'Capturing TCC attribution logs for %ss -> %s\n' "$DURATION" "$OUT" >&2
: > "$OUT"
log stream --debug --style "$STYLE" --predicate "$PREDICATE" >> "$OUT" 2>&1 &
LOG_PID=$!

cleanup() {
  kill "$LOG_PID" >/dev/null 2>&1 || true
  wait "$LOG_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep "$DURATION"
cleanup
trap - EXIT
printf 'Wrote %s\n' "$OUT" >&2
