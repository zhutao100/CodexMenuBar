#!/usr/bin/env bash
# Shared Xcode build destinations and artifact paths for repo scripts.

xcode_host_arch() {
  uname -m
}

xcode_default_destination() {
  local include_arch="${1:-0}"
  if [[ "${include_arch}" == "1" ]]; then
    printf 'platform=macOS,arch=%s' "$(xcode_host_arch)"
  else
    printf 'platform=macOS'
  fi
}

xcode_sanitize_path_fragment() {
  local value="${1:-default}"
  local sanitized=""
  sanitized="$(printf '%s' "${value}" | tr -c 'A-Za-z0-9._-' '_' | sed -E 's/_+/_/g; s/^_//; s/_$//')"
  if [[ -z "${sanitized}" ]]; then
    sanitized="default"
  fi
  printf '%s' "${sanitized}"
}

xcode_shared_derived_data_path() {
  local repo_root="${1:?repo root required}"
  local destination="${2:?destination required}"
  local configuration="${3:-Debug}"
  local configuration_slug=""
  local destination_slug=""

  configuration_slug="$(xcode_sanitize_path_fragment "${configuration}")"
  destination_slug="$(xcode_sanitize_path_fragment "${destination}")"
  printf '%s/.build/xcode/DerivedData/%s/%s' "${repo_root}" "${configuration_slug}" "${destination_slug}"
}
