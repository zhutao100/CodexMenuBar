#!/bin/bash
# Produce a machine-readable JSON summary from a .xcresult bundle.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $(basename "${BASH_SOURCE[0]}") <results.xcresult> <out.json>" >&2
  exit 2
fi

BUNDLE="$1"
OUT="$2"

if [[ ! -d "$BUNDLE" ]]; then
  echo "Not a directory: $BUNDLE" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT")"

# Prefer the structured subcommand for stability (Xcode 16+).
# Fall back to legacy "get --format json" when running on older Xcodes.
if xcrun xcresulttool get test-results summary --help >/dev/null 2>&1; then
  xcrun xcresulttool get test-results summary --path "$BUNDLE" --compact > "$OUT"
else
  # Legacy output is large, but still machine-parseable JSON.
  xcrun xcresulttool get --path "$BUNDLE" --format json > "$OUT"
fi
