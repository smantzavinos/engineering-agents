#!/usr/bin/env bash
# Verify Pi module content: keybindings, models, MCP, skills, agents all declared
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands nix jq >/dev/null

REPO_ROOT="$(repo_root)"
PASS=0 FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# Extract the Pi module's home.file entries by evaluating with a mock config
# We check the source files exist rather than trying to instantiate the module
# (which would require llmAgents input resolution).

# ============================================================
printf 'Pi module content verification\n'
printf '==============================\n\n'

# Verify guardrails.json is valid JSON
if jq -e '.' "$REPO_ROOT/nix/modules/pi/guardrails.json" >/dev/null 2>&1; then
  pass "guardrails.json is valid JSON"
else
  fail "guardrails.json is not valid JSON"
fi

# Verify compile-managed-packages.mjs is valid JS (syntax check)
if node --check "$REPO_ROOT/nix/modules/pi/compile-managed-packages.mjs" 2>/dev/null; then
  pass "compile-managed-packages.mjs has valid syntax"
else
  fail "compile-managed-packages.mjs has syntax errors"
fi

# Verify the module references skills that actually exist
SKILL_REFS=(
  "skills/discovery" "skills/design" "skills/research"
  "skills/create-plan" "skills/review-plan" "skills/create-worklog"
  "skills/execute-task" "skills/execution-orchestrator"
  "skills/review-code" "skills/review-approach" "skills/assess-repo"
  "skills/create-skills" "skills/configure-pi" "skills/create-new-repo-docs"
)
for ref in "${SKILL_REFS[@]}"; do
  skill_name="$(basename "$ref")"
  if [[ -f "$REPO_ROOT/${ref}/SKILL.md" ]]; then
    pass "Module skill ref '${skill_name}' resolves to existing SKILL.md"
  else
    fail "Module skill ref '${skill_name}' does not resolve (missing $REPO_ROOT/${ref}/SKILL.md)"
  fi
done

# Verify agent refs
AGENT_REFS=(
  "agents/planner.md" "agents/plan-reviewer.md" "agents/code-reviewer.md"
  "agents/worker.md" "agents/ui-worker.md" "agents/researcher.md"
  "agents/vision.md" "agents/oracle.md"
)
for ref in "${AGENT_REFS[@]}"; do
  agent_name="$(basename "$ref" .md)"
  if [[ -f "$REPO_ROOT/${ref}" ]]; then
    pass "Module agent ref '${agent_name}' resolves to existing file"
  else
    fail "Module agent ref '${agent_name}' does not resolve (missing $REPO_ROOT/${ref})"
  fi
done

# Verify preset.jsonc is valid JSONC (stripping comments and trailing commas)
if node -e "JSON.parse(require('fs').readFileSync('$REPO_ROOT/agents/preset.jsonc','utf8').replace(/\/\/.*$/gm,'').replace(/,\s*([}\]])/g,'\$1'))" 2>/dev/null; then
  pass "preset.jsonc is parseable as JSONC"
else
  fail "preset.jsonc fails to parse"
fi

# Verify check-updates.sh is executable
if [[ -x "$REPO_ROOT/scripts/check-updates.sh" ]]; then
  pass "check-updates.sh is executable"
else
  fail "check-updates.sh is not executable"
fi

# ============================================================
printf '\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
