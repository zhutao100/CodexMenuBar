#!/bin/bash
set -euo pipefail

echo "sw_vers:"
if command -v sw_vers >/dev/null 2>&1; then
  sw_vers
else
  echo "(sw_vers not available)"
fi

echo
echo "xcode-select -p:"
if command -v xcode-select >/dev/null 2>&1; then
  xcode-select -p
else
  echo "(xcode-select not available)"
fi

echo
echo "xcodebuild -version:"
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version
else
  echo "(xcodebuild not available)"
fi

echo
echo "xcresulttool version:"
if command -v xcrun >/dev/null 2>&1; then
  # xcresulttool exists in modern Xcode installs
  xcrun xcresulttool version || true
else
  echo "(xcrun not available)"
fi
