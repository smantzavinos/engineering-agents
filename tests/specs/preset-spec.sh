#!/usr/bin/env bash
# Verify preset.jsonc structure: has discovery, design, execute modes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node jq >/dev/null

REPO_ROOT="$(repo_root)"
PASS=0 FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# Parse JSONC by stripping comments and trailing commas
PRESET_JSON=$(node -e "
  const raw = require('fs').readFileSync('$REPO_ROOT/agents/preset.jsonc', 'utf8');
  const cleaned = raw.replace(/\/\/.*$/gm, '').replace(/,\s*([}\]])/g, '\$1');
  console.log(cleaned);
")

# ============================================================
printf 'Preset configuration verification\n'
printf '=================================\n\n'

# Verify all three modes exist
for mode in discovery design execute; do
  if echo "$PRESET_JSON" | jq -e --arg mode "$mode" '.presets[$mode]' >/dev/null 2>&1; then
    pass "Preset mode '${mode}' exists"
  else
    fail "Preset mode '${mode}' missing"
  fi
done

# Verify each mode has essential fields
for mode in discovery design execute; do
  if echo "$PRESET_JSON" | jq -e --arg mode "$mode" '.presets[$mode].model // .presets[$mode].systemPrompt' >/dev/null 2>&1; then
    pass "Mode '${mode}' has model or systemPrompt"
  else
    fail "Mode '${mode}' missing model and systemPrompt"
  fi
done

# Verify agent definition files exist (agents are separate .md files)
for agent in planner plan-reviewer code-reviewer worker ui-worker researcher vision oracle; do
  if [[ -f "$REPO_ROOT/agents/${agent}.md" ]]; then
    pass "Agent '${agent}' definition file exists"
  else
    fail "Agent '${agent}' definition file missing"
  fi
done

# ============================================================
printf '\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
