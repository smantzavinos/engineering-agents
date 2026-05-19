#!/usr/bin/env bash
set -euo pipefail

# Common test utilities for engineering-agents verification
# Adapted from dotfiles/nix/tests/pi/lib/common.sh

tests_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

repo_root() {
  cd "$(tests_dir)/.." && pwd
}

require_commands() {
  local missing=()
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Missing required command(s): %s\n' "${missing[*]}" >&2
    return 2
  fi
  return 0
}

settings_path() {
  printf '%s\n' "${PI_SETTINGS_PATH:-${HOME}/.pi/agent/settings.json}"
}

hostname_val() {
  printf '%s\n' "${PI_HOSTNAME_OVERRIDE:-$(hostname)}"
}

nix_bin() {
  printf '%s\n' "${PI_NIX_BIN:-nix}"
}

home_manager_bin() {
  printf '%s\n' "${PI_HOME_MANAGER_BIN:-home-manager}"
}

pi_bin() {
  printf '%s\n' "${PI_BIN:-pi}"
}

assert_writable_regular_file() {
  local path="$1" label="${2:-File}"
  if [[ -L "$path" ]]; then
    printf '%s must not be a symlink: %s\n' "$label" "$path" >&2; return 2
  fi
  if [[ ! -e "$path" ]]; then
    printf '%s does not exist: %s\n' "$label" "$path" >&2; return 2
  fi
  if [[ ! -f "$path" ]]; then
    printf '%s must be a regular file: %s\n' "$label" "$path" >&2; return 2
  fi
  if [[ ! -w "$path" ]]; then
    printf '%s must be writable: %s\n' "$label" "$path" >&2; return 2
  fi
  return 0
}
