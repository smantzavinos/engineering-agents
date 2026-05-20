#!/usr/bin/env bash

set -euo pipefail

log_path="${FAKE_REAL_PI_LOG:?FAKE_REAL_PI_LOG is required}"

{
  printf 'argc=%s\n' "$#"
  printf 'argv=%s\n' "$*"
  if [[ -n "${PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH+x}" ]]; then
    printf 'startup_status_path=%s\n' "$PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH"
  else
    printf 'startup_status_path=<unset>\n'
  fi
} >"$log_path"

exit "${FAKE_REAL_PI_EXIT_CODE:-0}"
