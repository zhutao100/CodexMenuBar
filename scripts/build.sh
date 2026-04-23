#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

usage() {
  cat <<'USAGE'
Release-build wrapper for building the Swift package via xcodebuild.

Usage:
  scripts/build.sh [xcodebuild args...]

Defaults:
  CONFIGURATION=Release
  DERIVED_DATA_PATH=.build/xcode
  DESTINATION='platform=macOS,arch=<host>'
  SCHEMES=(auto-detected)

This script ensures that the Xcode toolchain and Metal compiler tools are available.
If the Metal toolchain is missing, it will attempt to install it with:

  xcodebuild -downloadComponent MetalToolchain

Environment:
  CONFIGURATION                 Xcode configuration (Release or Debug)
  DERIVED_DATA_PATH             DerivedData output directory
  DESTINATION                   xcodebuild destination (default: platform=macOS,arch=<host>)
  SCHEMES                        Space-separated list of schemes to build (defaults to all discovered schemes; skips "*-Package" only when other schemes exist)
  XCODE_PROJECT                  Path to the .xcodeproj to use (optional; auto-detected when unambiguous)
  XCODE_WORKSPACE                Path to the .xcworkspace to use (optional; auto-detected when unambiguous; takes precedence over XCODE_PROJECT)
  LOG_DIR                        Directory to write xcodebuild logs into (default: artifacts/logs)
  VERBOSE                        Set to 1 to stream xcodebuild output (default: low-noise + logs only)
  SKIP_METAL_TOOLCHAIN_DOWNLOAD Set to 1 to disable auto-download attempts
  SKIP_XCODE_PLUGIN_FINGERPRINT_BYPASS Set to 1 to avoid writing the Xcode defaults used for non-interactive package plugin builds

Examples:
  scripts/build.sh
  CONFIGURATION=Debug scripts/build.sh
  DERIVED_DATA_PATH=./dist scripts/build.sh
  DESTINATION='platform=macOS,arch=arm64' scripts/build.sh
  XCODE_PROJECT=MyApp.xcodeproj scripts/build.sh
  scripts/build.sh -project MyApp.xcodeproj
USAGE
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

sanitize_filename_fragment() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

ensure_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    die "scripts/build.sh only supports macOS (xcodebuild + Metal toolchain required)"
  fi
}

ensure_xcode_tools() {
  command_exists xcodebuild || die "xcodebuild not found. Install Xcode (preferred) or Xcode Command Line Tools."
  command_exists xcrun || die "xcrun not found. Install Xcode Command Line Tools."
  command_exists xcode-select || die "xcode-select not found. Install Xcode Command Line Tools."

  local developer_dir=""
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ -z "$developer_dir" || ! -d "$developer_dir" ]]; then
    die "Xcode toolchain is not configured. Run 'xcode-select --install', or switch to Xcode via 'sudo xcode-select --switch /Applications/Xcode.app'."
  fi

  if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    warn "Xcode first-launch tasks are incomplete. If builds fail, run: sudo xcodebuild -runFirstLaunch"
  fi
}

ensure_xcode_package_plugin_settings() {
  if [[ "${SKIP_XCODE_PLUGIN_FINGERPRINT_BYPASS:-0}" == "1" ]]; then
    return 0
  fi
  if ! command_exists defaults; then
    warn "defaults not found; skipping Xcode package plugin fingerprint bypass"
    return 0
  fi

  local current=""
  current="$(defaults read com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidation 2>/dev/null || true)"
  case "$current" in
    1|YES|true|TRUE) return 0 ;;
    *) ;;
  esac

  warn "Enabling non-interactive SwiftPM build tool plugins for xcodebuild (Xcode default: IDESkipPackagePluginFingerprintValidation=YES)"
  defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidation -bool YES >/dev/null 2>&1 || true
}

ensure_metal_toolchain() {
  local metal_path=""
  local metallib_path=""

  metal_path="$(xcrun -sdk macosx -f metal 2>/dev/null || true)"
  metallib_path="$(xcrun -sdk macosx -f metallib 2>/dev/null || true)"
  if [[ -n "$metal_path" && -n "$metallib_path" ]]; then
    return 0
  fi

  if [[ "${SKIP_METAL_TOOLCHAIN_DOWNLOAD:-0}" == "1" ]]; then
    die "Metal toolchain tools (metal/metallib) not found. Install the Metal toolchain component (see 'xcodebuild -downloadComponent MetalToolchain')."
  fi

  warn "Metal toolchain tools (metal/metallib) not found; attempting to download MetalToolchain component..."
  if ! xcodebuild -downloadComponent MetalToolchain; then
    die "Failed to download MetalToolchain. Ensure Xcode 15+ is installed, Xcode license is accepted, and try again."
  fi

  metal_path="$(xcrun -sdk macosx -f metal 2>/dev/null || true)"
  metallib_path="$(xcrun -sdk macosx -f metallib 2>/dev/null || true)"
  if [[ -z "$metal_path" || -z "$metallib_path" ]]; then
    die "MetalToolchain download did not make metal/metallib available via xcrun. Try selecting Xcode via 'sudo xcode-select --switch /Applications/Xcode.app' and retry."
  fi
}

xcode_container_args=()
xcodebuild_forwarded_args=()

format_shell_command() {
  local formatted=()
  local arg=""
  for arg in "$@"; do
    formatted+=("$(printf '%q' "$arg")")
  done
  (IFS=' '; printf '%s' "${formatted[*]}")
}

run_logged() {
  local log_file="${1}"
  shift

  if [[ "${VERBOSE:-0}" == "1" ]]; then
    "$@" 2>&1 | tee "${log_file}"
    return "${PIPESTATUS[0]}"
  fi

  "$@" >"${log_file}" 2>&1
}

extract_relevant_errors() {
  local log_file="${1}"
  awk '
    /^[^:]+:[0-9]+:[0-9]+:[[:space:]]+(fatal[[:space:]]+error|error|note):/ { print; next }
    /^[^:]+:[0-9]+:[[:space:]]+(fatal[[:space:]]+error|error|note):/ { print; next }
    /^xcodebuild: error:/ { print; next }
    /^clang: error:/ { print; next }
    /^ld: / { print; next }
    /^Undefined symbols for architecture / { print; next }
    /^duplicate symbol / { print; next }
    /^Command (PhaseScriptExecution|SwiftCompile) failed/ { print; next }
    /^error: / { print; next }
    /^fatal error: / { print; next }
  ' "${log_file}"
}

discover_xcode_container() {
  local workspace_env="${XCODE_WORKSPACE:-}"
  local project_env="${XCODE_PROJECT:-}"

  if [[ -n "$workspace_env" && -n "$project_env" ]]; then
    die "Both XCODE_WORKSPACE and XCODE_PROJECT are set. Set only one."
  fi

  if [[ -n "$workspace_env" ]]; then
    [[ -d "$workspace_env" ]] || die "XCODE_WORKSPACE does not exist: $workspace_env"
    xcode_container_args=(-workspace "$workspace_env")
    return 0
  fi

  if [[ -n "$project_env" ]]; then
    [[ -d "$project_env" ]] || die "XCODE_PROJECT does not exist: $project_env"
    xcode_container_args=(-project "$project_env")
    return 0
  fi

  local workspaces=()
  local projects=()
  local path=""

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    workspaces+=("$path")
  done < <(find . -maxdepth 1 -type d -name '*.xcworkspace' -print | LC_ALL=C sort)

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    projects+=("$path")
  done < <(find . -maxdepth 1 -type d -name '*.xcodeproj' -print | LC_ALL=C sort)

  if [[ ${#workspaces[@]} -gt 1 ]]; then
    die $'Multiple .xcworkspace entries found. Set XCODE_WORKSPACE to choose one:\n'"${workspaces[*]}"
  fi
  if [[ ${#workspaces[@]} -eq 1 ]]; then
    xcode_container_args=(-workspace "${workspaces[0]}")
    return 0
  fi

  if [[ ${#projects[@]} -gt 1 ]]; then
    die $'Multiple .xcodeproj entries found. Set XCODE_PROJECT to choose one:\n'"${projects[*]}"
  fi
  if [[ ${#projects[@]} -eq 1 ]]; then
    xcode_container_args=(-project "${projects[0]}")
    return 0
  fi

  xcode_container_args=()
}

parse_xcode_container_args_from_cli() {
  local forwarded=()
  local container=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -workspace|-project)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        [[ ${#container[@]} -eq 0 ]] || die "Multiple Xcode container options provided. Use only one of -workspace/-project."
        container=("$1" "$2")
        shift 2
        ;;
      *)
        forwarded+=("$1")
        shift
        ;;
    esac
  done

  xcodebuild_forwarded_args=("${forwarded[@]}")

  if [[ ${#container[@]} -gt 0 ]]; then
    [[ -d "${container[1]}" ]] || die "Xcode container does not exist: ${container[1]}"
    xcode_container_args=("${container[@]}")
  fi
}

xcodebuild_list_json() {
  local stderr_file=""
  local out=""
  stderr_file="$(mktemp -t xcodebuild-list.XXXXXX)"
  if ! out="$(xcodebuild -list -json "${xcode_container_args[@]}" 2>"$stderr_file")"; then
    local err=""
    err="$(cat "$stderr_file" 2>/dev/null || true)"
    rm -f "$stderr_file" || true
    if [[ -n "$err" ]]; then
      die $'Failed to run xcodebuild -list -json for scheme discovery.\n'"$err"
    fi
    die "Failed to run xcodebuild -list -json for scheme discovery."
  fi
  rm -f "$stderr_file" || true
  printf '%s' "$out"
}

discover_schemes() {
  command_exists plutil || die "plutil not found; unable to discover xcodebuild schemes automatically"

  local list_json=""
  list_json="$(xcodebuild_list_json)"

  local schemes=""
  if schemes="$(printf '%s' "$list_json" \
    | plutil -extract workspace.schemes xml1 -o - - 2>/dev/null \
    | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"; then
    :
  else
    schemes=""
  fi

  if [[ -z "$schemes" ]]; then
    if schemes="$(printf '%s' "$list_json" \
      | plutil -extract project.schemes xml1 -o - - 2>/dev/null \
      | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"; then
      :
    else
      schemes=""
    fi
  fi

  if [[ -z "$schemes" ]]; then
    die "Failed to parse schemes from xcodebuild -list -json output. Try running: $(format_shell_command xcodebuild -list -json "${xcode_container_args[@]}")"
  fi

  printf '%s\n' "$schemes"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
configuration="${CONFIGURATION:-Release}"
derived_data_path="${DERIVED_DATA_PATH:-.build/xcode}"
host_arch="$(uname -m)"
destination="${DESTINATION:-platform=macOS,arch=$host_arch}"
log_dir="${LOG_DIR:-.artifacts/logs}"

cd "$root_dir"
ensure_macos

parse_xcode_container_args_from_cli "$@"
set -- "${xcodebuild_forwarded_args[@]}"

for arg in "$@"; do
  case "$arg" in
    -scheme|-configuration|-destination|-derivedDataPath)
      die "Do not pass '$arg' to scripts/build.sh. Use SCHEMES/CONFIGURATION/DESTINATION/DERIVED_DATA_PATH instead."
      ;;
    *)
      ;;
  esac
done

if [[ ${#xcode_container_args[@]} -eq 0 ]]; then
  discover_xcode_container
fi

ensure_xcode_tools
ensure_xcode_package_plugin_settings
ensure_metal_toolchain

mkdir -p "$log_dir"

schemes=()
if [[ -n "${SCHEMES:-}" ]]; then
  while IFS= read -r scheme; do
    [[ -n "$scheme" ]] || continue
    schemes+=("$scheme")
  done < <(printf '%s\n' "$SCHEMES" | tr -s '[:space:]' '\n')
else
  discovered_schemes="$(discover_schemes || true)"
  if [[ -z "$discovered_schemes" ]]; then
    die "Failed to auto-discover xcodebuild schemes. Try running: $(format_shell_command xcodebuild -list -json "${xcode_container_args[@]}")"
  fi
  all_schemes=()
  while IFS= read -r scheme; do
    [[ -n "$scheme" ]] || continue
    all_schemes+=("$scheme")
  done <<<"$discovered_schemes"

  for scheme in "${all_schemes[@]}"; do
    [[ "$scheme" == *"-Package" ]] && continue
    schemes+=("$scheme")
  done

  if [[ ${#schemes[@]} -eq 0 ]]; then
    schemes=("${all_schemes[@]}")
  fi
fi

if [[ ${#schemes[@]} -eq 0 ]]; then
  die "No schemes selected to build"
fi

container_desc="(auto)"
if [[ ${#xcode_container_args[@]} -gt 0 ]]; then
  container_desc="$(format_shell_command "${xcode_container_args[@]}")"
fi
log "==> Xcodebuild container: $container_desc"
log "==> Building ${#schemes[@]} scheme(s) (${configuration})"

quiet_args=()
if [[ "${VERBOSE:-0}" != "1" ]]; then
  saw_verbosity_flag=0
  for arg in "$@"; do
    case "$arg" in
      -quiet|-verbose)
        saw_verbosity_flag=1
        break
        ;;
      *)
        ;;
    esac
  done
  if [[ "$saw_verbosity_flag" == "0" ]]; then
    quiet_args=(-quiet)
  fi
fi

for scheme in "${schemes[@]}"; do
  log "==> Building $scheme"
  scheme_slug="$(sanitize_filename_fragment "$scheme")"
  log_file="${log_dir}/xcodebuild.${scheme_slug}.${configuration}.log"

  if ! run_logged "${log_file}" \
    xcodebuild build \
      "${xcode_container_args[@]}" \
      -scheme "$scheme" \
      -configuration "$configuration" \
      -destination "$destination" \
      -derivedDataPath "$derived_data_path" \
      -skipPackagePluginValidation \
      ENABLE_PLUGIN_PREPAREMLSHADERS=YES \
      CLANG_COVERAGE_MAPPING=NO \
      "${quiet_args[@]}" \
      "$@"; then
    printf 'error: Build failed for scheme %s\n' "$scheme" >&2
    printf 'error: Log: %s\n' "$log_file" >&2
    relevant_errors="$(extract_relevant_errors "$log_file" | sed '/^[[:space:]]*$/d' || true)"
    if [[ -n "$relevant_errors" ]]; then
      printf '%s\n' "$relevant_errors" >&2
    else
      printf 'error: No recognizable error lines found; showing log tail.\n' >&2
      tail -n 120 "$log_file" >&2 || true
    fi
    exit 1
  fi
done

log "==> PASS"
