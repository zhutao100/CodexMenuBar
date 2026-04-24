#!/usr/bin/env bash
# swift-gui-verifiable-loop: end-to-end deterministic GUI verification run
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  scripts/ui/ui_loop.sh --scheme <name> [options]

  # Xcode mode (optional):
  scripts/ui/ui_loop.sh (--workspace <path> | --project <path>) --scheme <name> [options]

Required:
  --scheme <name>                 Xcode scheme name

Xcode mode (optional):
  --workspace <path>              Path to .xcworkspace
  --project <path>                Path to .xcodeproj

Recommended:
  --test-plan <name>              .xctestplan name (without extension)
  --destination <string>          xcodebuild -destination string
  --artifacts-dir <dir>           Output root (default: ./.artifacts/ui)

Optional:
  --package-root <dir>            SwiftPM package root (default: repo root)
  --derived-data <dir>            DerivedData path (default: <run-dir>/DerivedData when --reuse-build)
  --configuration <name>          e.g. Debug / Release
  --only-testing <id>             Repeatable. TestTarget[/TestClass[/TestMethod]]
  --skip-testing <id>             Repeatable.
  --only-test-configuration <name> Repeatable. Test plan configuration name
  --skip-test-configuration <name> Repeatable.
  --reuse-build                   Run build-for-testing then test-without-building (faster reruns)
  --xctestrun <path>              Use existing .xctestrun (implies test-without-building; cannot use --workspace/--project)
  --only-failures-attachments     Export only failing attachments
  --parallel-testing-enabled <YES|NO>  Force parallel test execution on/off (default: NO)
  --maximum-parallel-testing-workers <n>  Limit spawned test runners when parallel is enabled
  --parallel-testing-worker-count <n>    Spawn exactly n test runners when parallel is enabled
  --adhoc-signing                 Apply ad-hoc signing overrides for macOS runner reliability
  --run-id <id>                   Override run id

Examples:
  scripts/ui/ui_loop.sh --workspace App.xcworkspace --scheme App --test-plan Smoke \
    --destination 'platform=macOS'

  scripts/ui/ui_loop.sh --workspace App.xcworkspace --scheme App --test-plan Smoke \
    --destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0'

  scripts/ui/ui_loop.sh --workspace App.xcworkspace --scheme App --test-plan Smoke \
    --destination 'platform=macOS' --reuse-build --derived-data /tmp/ui-loop/DerivedData
EOF
}

WORKSPACE=""
PROJECT=""
SCHEME=""
TEST_PLAN=""
DESTINATION="platform=macOS"
ARTIFACTS_DIR="$REPO_ROOT/.artifacts/ui"
PACKAGE_ROOT="$REPO_ROOT"
DERIVED_DATA=""
CONFIGURATION=""
REUSE_BUILD=0
XCTESTRUN=""
ONLY_FAIL_ATTACH=0
RUN_ID=""
ADHOC_SIGNING=0
VERBOSE="${VERBOSE:-0}"

PARALLEL_TESTING_ENABLED="NO"
MAX_PARALLEL_WORKERS=""
PARALLEL_WORKER_COUNT=""

ONLY_TESTING=()
SKIP_TESTING=()
ONLY_TEST_CONFIG=()
SKIP_TEST_CONFIG=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2;;
    --project) PROJECT="$2"; shift 2;;
    --scheme) SCHEME="$2"; shift 2;;
    --test-plan) TEST_PLAN="$2"; shift 2;;
    --destination) DESTINATION="$2"; shift 2;;
    --artifacts-dir) ARTIFACTS_DIR="$2"; shift 2;;
    --package-root) PACKAGE_ROOT="$2"; shift 2;;
    --derived-data) DERIVED_DATA="$2"; shift 2;;
    --configuration) CONFIGURATION="$2"; shift 2;;
    --only-testing) ONLY_TESTING+=("$2"); shift 2;;
    --skip-testing) SKIP_TESTING+=("$2"); shift 2;;
    --only-test-configuration) ONLY_TEST_CONFIG+=("$2"); shift 2;;
    --skip-test-configuration) SKIP_TEST_CONFIG+=("$2"); shift 2;;
    --reuse-build) REUSE_BUILD=1; shift 1;;
    --xctestrun) XCTESTRUN="$2"; shift 2;;
    --only-failures-attachments) ONLY_FAIL_ATTACH=1; shift 1;;
    --parallel-testing-enabled) PARALLEL_TESTING_ENABLED="$2"; shift 2;;
    --maximum-parallel-testing-workers) MAX_PARALLEL_WORKERS="$2"; shift 2;;
    --parallel-testing-worker-count) PARALLEL_WORKER_COUNT="$2"; shift 2;;
    --adhoc-signing) ADHOC_SIGNING=1; shift 1;;
    --run-id) RUN_ID="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2;;
  esac
done

case "$PARALLEL_TESTING_ENABLED" in
  YES|NO) ;;
  *) echo "--parallel-testing-enabled must be YES or NO (got: $PARALLEL_TESTING_ENABLED)" >&2; exit 2;;
esac

if [[ -z "$SCHEME" ]]; then
  echo "Missing --scheme" >&2
  usage
  exit 2
fi

discover_xcode_container() {
  local root="$1"
  local workspaces=()
  local projects=()
  local path=""

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    workspaces+=("$path")
  done < <(find "$root" -maxdepth 1 -type d -name '*.xcworkspace' -print | LC_ALL=C sort)

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    projects+=("$path")
  done < <(find "$root" -maxdepth 1 -type d -name '*.xcodeproj' -print | LC_ALL=C sort)

  if [[ ${#workspaces[@]} -gt 1 ]]; then
    echo $'Multiple .xcworkspace entries found. Pass --workspace to choose one:\n'"${workspaces[*]}" >&2
    exit 2
  fi
  if [[ ${#workspaces[@]} -eq 1 ]]; then
    printf '%s' "${workspaces[0]}"
    return 0
  fi

  if [[ ${#projects[@]} -gt 1 ]]; then
    echo $'Multiple .xcodeproj entries found. Pass --project to choose one:\n'"${projects[*]}" >&2
    exit 2
  fi
  if [[ ${#projects[@]} -eq 1 ]]; then
    printf '%s' "${projects[0]}"
    return 0
  fi

  return 1
}

if [[ -z "$XCTESTRUN" && -z "$WORKSPACE" && -z "$PROJECT" ]]; then
  if container="$(discover_xcode_container "$PACKAGE_ROOT")"; then
    case "$container" in
      *.xcworkspace) WORKSPACE="$container" ;;
      *.xcodeproj) PROJECT="$container" ;;
      *) ;;
    esac
  fi
fi

if [[ -n "$XCTESTRUN" ]]; then
  if [[ -n "$WORKSPACE" || -n "$PROJECT" ]]; then
    echo "--xctestrun cannot be used with --workspace/--project (xcodebuild restriction)" >&2
    exit 2
  fi
else
  if [[ -z "$WORKSPACE" && -z "$PROJECT" ]]; then
    if [[ ! -f "$PACKAGE_ROOT/Package.swift" ]]; then
      echo "SwiftPM mode requires Package.swift under --package-root: $PACKAGE_ROOT" >&2
      exit 2
    fi
  fi
  if [[ -n "$WORKSPACE" && -n "$PROJECT" ]]; then
    echo "Provide only one of --workspace/--project" >&2
    exit 2
  fi
fi

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")"
fi

RUN_DIR="$ARTIFACTS_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"

if [[ -z "${SEATBELT_SANDBOX_WORKSPACE_ROOT:-}" ]]; then
  export SEATBELT_SANDBOX_WORKSPACE_ROOT="$(cd "$PACKAGE_ROOT" && pwd -P)"
fi

RESULT_BUNDLE="$RUN_DIR/results.xcresult"
SUMMARY_JSON="$RUN_DIR/summary.json"
TOOLCHAIN_TXT="$RUN_DIR/toolchain.txt"

"$SCRIPT_DIR/toolchain_fingerprint.sh" > "$TOOLCHAIN_TXT"

if [[ -z "$DERIVED_DATA" ]]; then
  DERIVED_DATA="$RUN_DIR/DerivedData"
fi

clean_result_bundle() {
  if [[ -e "$RESULT_BUNDLE" ]]; then
    rm -rf "$RESULT_BUNDLE"
  fi
}

append_signing_overrides() {
  if [[ "$ADHOC_SIGNING" -eq 1 ]]; then
    # UI test runners modify a base runner app and must be re-signed.
    # Ad-hoc signing avoids requiring a local developer cert while still producing a runnable bundle.
    cmd+=("CODE_SIGN_STYLE=Manual" "CODE_SIGN_IDENTITY=-" "CODE_SIGNING_REQUIRED=NO")
  fi
}

run_xcodebuild_test() {
  local action="$1"; shift
  cmd=("xcodebuild")

  if [[ -n "$WORKSPACE" ]]; then cmd+=("-workspace" "$WORKSPACE"); fi
  if [[ -n "$PROJECT" ]]; then cmd+=("-project" "$PROJECT"); fi

  cmd+=("-scheme" "$SCHEME")

  if [[ -n "$CONFIGURATION" ]]; then cmd+=("-configuration" "$CONFIGURATION"); fi
  if [[ -n "$TEST_PLAN" ]]; then cmd+=("-testPlan" "$TEST_PLAN"); fi
  if [[ -n "$DESTINATION" ]]; then cmd+=("-destination" "$DESTINATION"); fi
  if [[ -n "$DERIVED_DATA" ]]; then cmd+=("-derivedDataPath" "$DERIVED_DATA"); fi

  local item
  for item in "${ONLY_TESTING[@]}"; do cmd+=("-only-testing" "$item"); done
  for item in "${SKIP_TESTING[@]}"; do cmd+=("-skip-testing" "$item"); done
  for item in "${ONLY_TEST_CONFIG[@]}"; do cmd+=("-only-test-configuration" "$item"); done
  for item in "${SKIP_TEST_CONFIG[@]}"; do cmd+=("-skip-test-configuration" "$item"); done

  if [[ "$action" != "build-for-testing" ]]; then
    clean_result_bundle
    cmd+=("-resultBundlePath" "$RESULT_BUNDLE")
  fi

  cmd+=("-parallel-testing-enabled" "$PARALLEL_TESTING_ENABLED")
  if [[ -n "$PARALLEL_WORKER_COUNT" ]]; then
    cmd+=("-parallel-testing-worker-count" "$PARALLEL_WORKER_COUNT")
  elif [[ -n "$MAX_PARALLEL_WORKERS" ]]; then
    cmd+=("-maximum-parallel-testing-workers" "$MAX_PARALLEL_WORKERS")
  fi

  cmd+=("$action")
  append_signing_overrides

  local log_file="$RUN_DIR/xcodebuild-${action}.log"
  : >"$log_file"

  echo "==> Running: ${cmd[*]}" >&2
  if [[ "$VERBOSE" == "1" ]]; then
    (cd "$PACKAGE_ROOT" && "${cmd[@]}")
    return $?
  fi

  if (cd "$PACKAGE_ROOT" && "${cmd[@]}") >"$log_file" 2>&1; then
    return 0
  else
    local status=$?
    echo "==> xcodebuild failed (log: $log_file)" >&2
    tail -n 200 "$log_file" >&2 || true
    return "$status"
  fi
}

run_test_without_building() {
  cmd=("xcodebuild" "-xctestrun" "$XCTESTRUN")

  if [[ -n "$DESTINATION" ]]; then cmd+=("-destination" "$DESTINATION"); fi
  clean_result_bundle
  cmd+=("-resultBundlePath" "$RESULT_BUNDLE")
  cmd+=("-parallel-testing-enabled" "$PARALLEL_TESTING_ENABLED")
  if [[ -n "$PARALLEL_WORKER_COUNT" ]]; then
    cmd+=("-parallel-testing-worker-count" "$PARALLEL_WORKER_COUNT")
  elif [[ -n "$MAX_PARALLEL_WORKERS" ]]; then
    cmd+=("-maximum-parallel-testing-workers" "$MAX_PARALLEL_WORKERS")
  fi
  cmd+=("test-without-building")
  append_signing_overrides

  local log_file="$RUN_DIR/xcodebuild-test-without-building.log"
  : >"$log_file"

  echo "==> Running: ${cmd[*]}" >&2
  if [[ "$VERBOSE" == "1" ]]; then
    (cd "$PACKAGE_ROOT" && "${cmd[@]}")
    return $?
  fi

  if (cd "$PACKAGE_ROOT" && "${cmd[@]}") >"$log_file" 2>&1; then
    return 0
  else
    local status=$?
    echo "==> xcodebuild failed (log: $log_file)" >&2
    tail -n 200 "$log_file" >&2 || true
    return "$status"
  fi
}

xcodebuild_status=0
if [[ -n "$XCTESTRUN" ]]; then
  if ! run_test_without_building; then
    xcodebuild_status=$?
  fi
elif [[ "$REUSE_BUILD" -eq 1 ]]; then
  if [[ -z "$DERIVED_DATA" ]]; then
    DERIVED_DATA="$RUN_DIR/DerivedData"
  fi

  # build-for-testing embeds test-plan/test-config into the generated .xctestrun.
  # (Do not rely on -testPlan being honored by test-without-building.)
  if ! run_xcodebuild_test "build-for-testing"; then
    xcodebuild_status=$?
  else
    mtime_of() {
      local p="$1"
      if stat -f %m "$p" >/dev/null 2>&1; then
        stat -f %m "$p"
      else
        stat -c %Y "$p"
      fi
    }

    xctestruns=()
    f=""
    while IFS= read -r -d '' f; do
      xctestruns+=("$f")
    done < <(find "$DERIVED_DATA" -name '*.xctestrun' -print0 2>/dev/null || true)

    newest=""
    newest_m=0
    m=""
    for f in "${xctestruns[@]}"; do
      m="$(mtime_of "$f" || echo 0)"
      if [[ -z "$newest" || "$m" -gt "$newest_m" ]]; then
        newest="$f"
        newest_m="$m"
      fi
    done

    XCTESTRUN="$newest"
    if [[ -z "$XCTESTRUN" ]]; then
      echo "Could not locate .xctestrun under derived data: $DERIVED_DATA" >&2
      xcodebuild_status=3
    elif ! run_test_without_building; then
      xcodebuild_status=$?
    fi
  fi
else
  if ! run_xcodebuild_test "test"; then
    xcodebuild_status=$?
  fi
fi

if [[ -d "$RESULT_BUNDLE" ]]; then
  "$SCRIPT_DIR/xcresult_summary.sh" "$RESULT_BUNDLE" "$SUMMARY_JSON" || true
else
  echo "{}" > "$SUMMARY_JSON"
fi

if [[ "$xcodebuild_status" -eq 0 && -f "$SUMMARY_JSON" ]]; then
  summary_result="$(
    python3 - "$SUMMARY_JSON" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    print("")
    raise SystemExit(0)

print(str(data.get("result", "")))
PY
  )"
  if [[ -n "$summary_result" && "$summary_result" != "Succeeded" && "$summary_result" != "Passed" ]]; then
    echo "==> xcresult summary reported non-success result: $summary_result" >&2
    xcodebuild_status=4
  fi
fi

if [[ -d "$RESULT_BUNDLE" ]]; then
  EXPORT_ARGS=()
  if [[ "$ONLY_FAIL_ATTACH" -eq 1 ]]; then
    EXPORT_ARGS+=("--only-failures")
  fi
  "$SCRIPT_DIR/xcresult_export.sh" "$RESULT_BUNDLE" "$RUN_DIR" "${EXPORT_ARGS[@]}" || true
fi

echo "==> Done."
echo "Run dir: $RUN_DIR"
echo "Result bundle: $RESULT_BUNDLE"
echo "Summary: $SUMMARY_JSON"

exit "$xcodebuild_status"
