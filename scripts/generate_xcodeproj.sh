#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install it (e.g. \`brew install xcodegen\`)." >&2
  exit 2
fi

echo "==> Generating CodexMenuBar.xcodeproj"
xcodegen -q -s "$ROOT/project.yml" -p "$ROOT"
echo "==> Done"
