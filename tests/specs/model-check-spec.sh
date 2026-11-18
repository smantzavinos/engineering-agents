#!/usr/bin/env bash
# Verify tools/model-check.mjs: the model-to-code and approved-versus-shipped checks.
# The cases that run the diagram tool are skipped when `c4ish` is not on PATH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node git >/dev/null

REPO_ROOT="$(repo_root)"

if output="$(node --test "$REPO_ROOT/tools/model-check.test.mjs" 2>&1)"; then
  printf '  PASS: model-check tests (%s)\n' "$(printf '%s\n' "$output" | grep -E '^# pass ' | tr -d '#' | xargs)"
  if printf '%s\n' "$output" | grep -Eq '^# skipped [1-9]'; then
    printf '  NOTE: cases against a real repository were skipped (c4ish is not on PATH)\n'
  fi
else
  printf '%s\n' "$output" | grep -E '^\s*not ok|^# (pass|fail)' >&2 || true
  printf '  FAIL: model-check tests\n' >&2
  exit 1
fi
