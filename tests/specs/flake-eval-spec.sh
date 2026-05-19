#!/usr/bin/env bash
# Verify flake evaluation: modules load, packages build, schema is correct
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands nix jq >/dev/null

REPO_ROOT="$(repo_root)"
PASS=0 FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# ============================================================
printf 'Flake evaluation verification\n'
printf '=============================\n\n'

# Flake metadata
if nix flake metadata "$REPO_ROOT" --json 2>/dev/null | jq -e '.description' >/dev/null; then
  pass "Flake metadata is readable"
else
  fail "Flake metadata is not readable"
fi

# Module evaluation
for module in pi opencode default; do
  if nix eval "$REPO_ROOT#homeManagerModules.${module}" --json 2>/dev/null | jq -e '.' >/dev/null; then
    pass "Module '${module}' evaluates successfully"
  else
    fail "Module '${module}' fails to evaluate"
  fi
done

# Packages build (docs bundle)
if nix build "$REPO_ROOT#engineering-agents-docs" --no-link --print-out-paths 2>/dev/null; then
  pass "engineering-agents-docs package builds"
else
  fail "engineering-agents-docs package fails to build"
fi

# Dev shell evaluates
if nix eval "$REPO_ROOT#devShells.x86_64-linux.default" 2>/dev/null; then
  pass "Default dev shell evaluates"
else
  fail "Default dev shell fails to evaluate"
fi

# Template exists
if nix eval "$REPO_ROOT#templates.default" 2>/dev/null; then
  pass "Default template evaluates"
else
  fail "Default template fails to evaluate"
fi

# ============================================================
printf '\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
