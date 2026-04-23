#!/usr/bin/env bash
set -euo pipefail

# Tier 0: mandatory fast verifier after every edit.
#
# Supports two build/test modes:
# - Xcode mode (default when an .xcodeproj/.xcworkspace exists at repo root): uses `xcodebuild`.
# - SwiftPM mode: uses `swift build` / `swift test`.
#
# Mode selection:
#   VERIFY_FAST_MODE=auto|xcode|swiftpm (default: auto)
#   PROJECT_OR_WORKSPACE=<path>   (optional override in xcode/auto mode)
#   SCHEME=<name>                 (optional; defaults to the container basename)
#   VERIFY_FAST_XCODE_SEARCH_DEPTH=<int> (optional; max find depth for Xcode container lookup, defaults to 4)
#   XCODE_CODE_SIGNING_ALLOWED=YES|NO (optional; default: NO for local verification)
#   RUN_TESTS=0|1                 (optional; defaults to 1)
#
# Artifacts (repo root, ignored):
#   .artifacts/verify-fast/logs/build.log
#   .artifacts/verify-fast/logs/test.log (when tests run)
#   .artifacts/verify-fast/TestResults.xcresult (Xcode mode)
#
# Verbosity:
#   VERBOSE=1   stream tool output (default is low-noise)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVOKE_DIR="$(pwd)"

cd "${ROOT}"

# If invoked outside the repo, default package resolution to the repo root.
if [[ "${INVOKE_DIR}" != "${ROOT}" && "${INVOKE_DIR}" != "${ROOT}/"* ]]; then
  INVOKE_DIR="${ROOT}"
fi

ARTIFACTS_DIR="${VERIFY_FAST_ARTIFACTS_DIR:-$ROOT/.artifacts/verify-fast}"
LOG_DIR="${ARTIFACTS_DIR}/logs"

mkdir -p "${LOG_DIR}"

VERIFY_FAST_MODE="${VERIFY_FAST_MODE:-auto}"
PROJECT_OR_WORKSPACE="${PROJECT_OR_WORKSPACE:-}"
SCHEME="${SCHEME:-}"
DESTINATION="${DESTINATION:-platform=macOS}"
CONFIGURATION="${CONFIGURATION:-Debug}"
VERBOSE="${VERBOSE:-0}"
SWIFTPM_PACKAGE_DIR="${SWIFTPM_PACKAGE_DIR:-}"
XCODE_CODE_SIGNING_ALLOWED="${XCODE_CODE_SIGNING_ALLOWED:-NO}"
RUN_TESTS="${RUN_TESTS:-1}"

BUILD_LOG="${LOG_DIR}/build.log"
TEST_LOG="${LOG_DIR}/test.log"

: >"${BUILD_LOG}"
[[ "${RUN_TESTS}" == "1" ]] && : >"${TEST_LOG}"

append_log_cmd() {
  local log_file="${1}"
  shift
  printf '$ ' >>"${log_file}"
  for arg in "$@"; do
    printf "%q " "${arg}" >>"${log_file}"
  done
  printf "\n" >>"${log_file}"
}

run_logged() {
  local log_file="${1}"
  shift

  if [[ "${VERBOSE}" == "1" ]]; then
    "$@" 2>&1 | tee -a "${log_file}"
    return "${PIPESTATUS[0]}"
  fi

  "$@" >>"${log_file}" 2>&1
}

append_log_header() {
  local log_file="${1}"
  local header="${2}"
  printf "\n===== %s =====\n" "${header}" >>"${log_file}"
}

dump_log_tail() {
  local log_file="${1}"
  local lines="${2:-200}"

  [[ -f "${log_file}" ]] || return 0
  echo "[verify_fast] --- ${log_file} (tail) ---"
  tail -n "${lines}" "${log_file}" || true
}

require_swift_6() {
  local -a swiftc_cmd=()
  if command -v swiftc >/dev/null 2>&1; then
    swiftc_cmd=(swiftc)
  elif command -v xcrun >/dev/null 2>&1; then
    swiftc_cmd=(xcrun swiftc)
  else
    echo "error: swiftc not found (no swiftc in PATH, and xcrun unavailable)." >&2
    exit 2
  fi

  local version_line
  version_line="$("${swiftc_cmd[@]}" -version 2>/dev/null | head -n 1 || true)"
  if [[ -z "${version_line}" ]]; then
    echo "error: swiftc -version returned no output." >&2
    exit 2
  fi

  local major
  if [[ "${version_line}" =~ ([Aa]pple[[:space:]]+)?Swift[[:space:]]+version[[:space:]]+([0-9]+)\. ]]; then
    major="${BASH_REMATCH[2]}"
  else
    echo "error: could not parse Swift version from: ${version_line}" >&2
    exit 2
  fi

  if ((major < 6)); then
    echo "error: Swift 6+ required. Found: ${version_line}" >&2
    exit 2
  fi

  echo "[verify_fast] Toolchain: ${version_line}"
}

require_swift_6

case "${VERIFY_FAST_MODE}" in
  auto|xcode|swiftpm) ;;
  *)
    echo "error: VERIFY_FAST_MODE must be auto, xcode, or swiftpm (got: ${VERIFY_FAST_MODE})" >&2
    exit 2
    ;;
esac

discover_xcode_container() {
  local workspaces=()
  local projects=()
  local path=""
  local max_depth="${VERIFY_FAST_XCODE_SEARCH_DEPTH:-4}"

  if ! [[ "${max_depth}" =~ ^[0-9]+$ ]] || ((max_depth < 1)); then
    max_depth=4
  fi

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    workspaces+=("$path")
  done < <(
    # Ignore Xcode-generated internal workspaces inside `.xcodeproj` bundles.
    find . \
      -maxdepth "${max_depth}" \
      -type d \
      -name '*.xcworkspace' \
      ! -path '*/.build/*' \
      ! -path '*/.artifacts/*' \
      ! -path '*/.swiftpm/*' \
      ! -path '*.xcodeproj/*' \
      -print \
    | LC_ALL=C sort
  )

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    projects+=("$path")
  done < <(
    find . \
      -maxdepth "${max_depth}" \
      -type d \
      -name '*.xcodeproj' \
      ! -path '*/.build/*' \
      ! -path '*/.artifacts/*' \
      ! -path '*/.swiftpm/*' \
      -print \
    | LC_ALL=C sort
  )

  if [[ ${#workspaces[@]} -gt 1 ]]; then
    echo $'error: Multiple .xcworkspace entries found. Set PROJECT_OR_WORKSPACE to choose one:\n'"${workspaces[*]}" >&2
    exit 2
  fi
  if [[ ${#workspaces[@]} -eq 1 ]]; then
    printf '%s' "${workspaces[0]}"
    return 0
  fi

  if [[ ${#projects[@]} -gt 1 ]]; then
    echo $'error: Multiple .xcodeproj entries found. Set PROJECT_OR_WORKSPACE to choose one:\n'"${projects[*]}" >&2
    exit 2
  fi
  if [[ ${#projects[@]} -eq 1 ]]; then
    printf '%s' "${projects[0]}"
    return 0
  fi

  return 1
}

if [[ "${VERIFY_FAST_MODE}" != "swiftpm" ]]; then
  if [[ -n "${PROJECT_OR_WORKSPACE}" && ! -e "${PROJECT_OR_WORKSPACE}" ]]; then
    echo "error: PROJECT_OR_WORKSPACE not found: ${PROJECT_OR_WORKSPACE}" >&2
    exit 2
  fi

  if [[ -z "${PROJECT_OR_WORKSPACE}" ]]; then
    PROJECT_OR_WORKSPACE="$(discover_xcode_container || true)"
  fi

  if [[ "${VERIFY_FAST_MODE}" == "xcode" && -z "${PROJECT_OR_WORKSPACE}" ]]; then
    echo "error: VERIFY_FAST_MODE=xcode but no .xcodeproj/.xcworkspace found in repo (or via PROJECT_OR_WORKSPACE)." >&2
    exit 2
  fi
fi

if [[ -n "${PROJECT_OR_WORKSPACE}" && "${VERIFY_FAST_MODE}" != "swiftpm" ]]; then
  # Xcode mode
  echo "[verify_fast] Xcode mode: ${PROJECT_OR_WORKSPACE}"

  if [[ -z "${SCHEME}" ]]; then
    SCHEME="$(basename "${PROJECT_OR_WORKSPACE}")"
    SCHEME="${SCHEME%.xcworkspace}"
    SCHEME="${SCHEME%.xcodeproj}"
  fi

  local_build_args=()
  if [[ "${PROJECT_OR_WORKSPACE}" == *.xcworkspace ]]; then
    local_build_args+=( -workspace "${PROJECT_OR_WORKSPACE}" )
  else
    local_build_args+=( -project "${PROJECT_OR_WORKSPACE}" )
  fi

  DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ARTIFACTS_DIR}/DerivedData}"

  if [[ -z "${SEATBELT_SANDBOX_WORKSPACE_ROOT:-}" ]]; then
    export SEATBELT_SANDBOX_WORKSPACE_ROOT="${ROOT}"
  fi

  echo "[verify_fast] Building (log: ${BUILD_LOG})..."
  append_log_header "${BUILD_LOG}" "xcodebuild build (${PROJECT_OR_WORKSPACE} :: ${SCHEME})"
  if ! run_logged "${BUILD_LOG}" \
    xcodebuild \
      "${local_build_args[@]}" \
      -scheme "${SCHEME}" \
      -configuration "${CONFIGURATION}" \
      -destination "${DESTINATION}" \
      CODE_SIGNING_ALLOWED="${XCODE_CODE_SIGNING_ALLOWED}" \
      -derivedDataPath "${DERIVED_DATA_PATH}" \
      build; then
    echo "[verify_fast] Build failed (log: ${BUILD_LOG})." >&2
    if [[ "${VERBOSE}" != "1" ]]; then
      dump_log_tail "${BUILD_LOG}"
    fi
    exit 1
  fi

  echo "[verify_fast] Running unit tests (optional; disable via RUN_TESTS=0)..."
  if [[ "${RUN_TESTS}" == "1" ]]; then
    echo "[verify_fast] Testing (log: ${TEST_LOG})..."
    append_log_header "${TEST_LOG}" "xcodebuild test (${PROJECT_OR_WORKSPACE} :: ${SCHEME})"
    rm -rf "${ARTIFACTS_DIR}/TestResults.xcresult"
    if ! run_logged "${TEST_LOG}" \
      xcodebuild \
        "${local_build_args[@]}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -destination "${DESTINATION}" \
        CODE_SIGNING_ALLOWED="${XCODE_CODE_SIGNING_ALLOWED}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        test \
      -resultBundlePath "${ARTIFACTS_DIR}/TestResults.xcresult"; then
      echo "[verify_fast] Tests failed (log: ${TEST_LOG})." >&2
      if [[ "${VERBOSE}" != "1" ]]; then
        dump_log_tail "${TEST_LOG}"
      fi
      exit 1
    fi
  fi

  echo "[verify_fast] PASS"
  exit 0
fi

# SwiftPM mode
# SwiftPM argument forwarding:
# - Forward all script args to `swift test`.
# - Forward a small, safe subset to `swift build` so `--skip-build` runs match the build configuration.
declare -a SWIFTPM_TEST_ARGS=("$@")
declare -a SWIFTPM_BUILD_ARGS=()

i=0
while [[ "${i}" -lt "${#SWIFTPM_TEST_ARGS[@]}" ]]; do
  arg="${SWIFTPM_TEST_ARGS[${i}]}"
  case "${arg}" in
  -c | --configuration | --scratch-path | --build-path | -Xswiftc | -Xcc | -Xlinker | -Xcxx)
    if ((i + 1 >= ${#SWIFTPM_TEST_ARGS[@]})); then
      echo "error: missing value for ${arg}" >&2
      exit 2
    fi
    SWIFTPM_BUILD_ARGS+=("${arg}" "${SWIFTPM_TEST_ARGS[$((i + 1))]}")
    i=$((i + 2))
    ;;
  --configuration=* | --scratch-path=* | --build-path=*)
    key="${arg%%=*}"
    value="${arg#*=}"
    SWIFTPM_BUILD_ARGS+=("${key}" "${value}")
    i=$((i + 1))
    ;;
  *)
    i=$((i + 1))
    ;;
  esac
done

swiftpm_should_add_skip_build=1
for arg in "${SWIFTPM_TEST_ARGS[@]}"; do
  if [[ "${arg}" == "--skip-build" ]]; then
    swiftpm_should_add_skip_build=0
    break
  fi
done

resolve_abs_dir() {
  local path="${1}"
  if [[ "${path}" == /* ]]; then
    (cd "${path}" >/dev/null 2>&1 && pwd) || return 1
  else
    (cd "${ROOT}/${path}" >/dev/null 2>&1 && pwd) || return 1
  fi
}

find_swiftpm_package_root() {
  local start_dir="${1}"
  local dir="${start_dir}"

  while [[ "${dir}" != "/" ]]; do
    if [[ -f "${dir}/Package.swift" ]]; then
      echo "${dir}"
      return 0
    fi

    if [[ "${dir}" == "${ROOT}" ]]; then
      break
    fi

    dir="$(dirname "${dir}")"
  done

  return 1
}

# SwiftPM mode
echo "[verify_fast] SwiftPM mode"

declare -a swiftpm_dirs=()
if [[ -n "${SWIFTPM_PACKAGE_DIR}" ]]; then
  if ! swiftpm_dir="$(resolve_abs_dir "${SWIFTPM_PACKAGE_DIR}")"; then
    echo "error: SWIFTPM_PACKAGE_DIR not found: ${SWIFTPM_PACKAGE_DIR}" >&2
    exit 2
  fi
  swiftpm_dirs+=("${swiftpm_dir}")
else
  if swiftpm_dir="$(find_swiftpm_package_root "${INVOKE_DIR}")"; then
    swiftpm_dirs+=("${swiftpm_dir}")
  else
    echo "error: no Package.swift found from ${INVOKE_DIR} (set SWIFTPM_PACKAGE_DIR to override)." >&2
    exit 2
  fi
fi

for dir in "${swiftpm_dirs[@]}"; do
  if [[ ! -f "${dir}/Package.swift" ]]; then
    echo "error: Package.swift not found in: ${dir}" >&2
    exit 2
  fi

  package_name="$(basename "${dir}")"
  echo "[verify_fast] Package: ${package_name}"

  if [[ "${RUN_TESTS}" == "1" ]]; then
    echo "[verify_fast] swift build --build-tests (${package_name}) (log: ${BUILD_LOG})..."
    append_log_header "${BUILD_LOG}" "${package_name} :: swift build --build-tests"
    append_log_cmd "${BUILD_LOG}" swift build --build-tests "${SWIFTPM_BUILD_ARGS[@]}"
    if ! (cd "${dir}" && run_logged "${BUILD_LOG}" swift build --build-tests "${SWIFTPM_BUILD_ARGS[@]}"); then
      echo "[verify_fast] Build failed (log: ${BUILD_LOG})." >&2
      if [[ "${VERBOSE}" != "1" ]]; then
        dump_log_tail "${BUILD_LOG}"
      fi
      exit 1
    fi

    echo "[verify_fast] swift test --skip-build (${package_name}) (log: ${TEST_LOG})..."
    append_log_header "${TEST_LOG}" "${package_name} :: swift test --skip-build"
    test_cmd=(swift test)
    if [[ "${swiftpm_should_add_skip_build}" == "1" ]]; then
      test_cmd+=(--skip-build)
    fi
    test_cmd+=("${SWIFTPM_TEST_ARGS[@]}")
    append_log_cmd "${TEST_LOG}" "${test_cmd[@]}"
    if ! (cd "${dir}" && run_logged "${TEST_LOG}" "${test_cmd[@]}"); then
      echo "[verify_fast] Tests failed (log: ${TEST_LOG})." >&2
      if [[ "${VERBOSE}" != "1" ]]; then
        dump_log_tail "${TEST_LOG}"
      fi
      exit 1
    fi
  else
    echo "[verify_fast] swift build (${package_name}) (log: ${BUILD_LOG})..."
    append_log_header "${BUILD_LOG}" "${package_name} :: swift build"
    append_log_cmd "${BUILD_LOG}" swift build "${SWIFTPM_BUILD_ARGS[@]}"
    if ! (cd "${dir}" && run_logged "${BUILD_LOG}" swift build "${SWIFTPM_BUILD_ARGS[@]}"); then
      echo "[verify_fast] Build failed (log: ${BUILD_LOG})." >&2
      if [[ "${VERBOSE}" != "1" ]]; then
        dump_log_tail "${BUILD_LOG}"
      fi
      exit 1
    fi
  fi
done

echo "[verify_fast] PASS"
