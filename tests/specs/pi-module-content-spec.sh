#!/usr/bin/env bash
# Verify Pi module content: keybindings, models, MCP, skills, agents all declared
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands nix jq >/dev/null

REPO_ROOT="$(repo_root)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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

PI_MODULE="$REPO_ROOT/nix/modules/pi/default.nix"
PI_CONFIG="$REPO_ROOT/nix/modules/pi/config.nix"
if grep -Fq 'pi-messenger = {' "$PI_CONFIG" &&
   grep -Fq 'packageName = "pi-messenger";' "$PI_CONFIG" &&
   grep -Fq 'spec = "pi-messenger@0.15.0";' "$PI_CONFIG" &&
   grep -Fq 'installSpec = "pi-messenger@0.15.0";' "$PI_CONFIG" &&
   grep -Fq 'extensions = [ "./index.ts" ];' "$PI_CONFIG" &&
   grep -Fq 'skills = [ "pi-messenger-crew" ];' "$PI_CONFIG" &&
   grep -Fq '".pi/agent/messenger/team-profiles/pi-team.json"' "$PI_MODULE" &&
   grep -Fq 'config/pi-team/team-profile.json $out/agent/messenger/team-profiles/pi-team.json' "$PI_CONFIG"; then
  pass "Pi module declares pi-messenger resources and the canonical pi-team profile"
else
  fail "Pi module declares pi-messenger resources and the canonical pi-team profile"
fi

# The global Pi team skills invoke pi-team, so the module must install a real PATH
# command backed by the checked-in tool and its Node/git runtime dependencies.
# Inspect only the home.packages list: a declaration elsewhere must not satisfy this gate.
home_packages_contains_pi_team_pkg() {
  local module="$1" packages
  packages="$(awk '
    /^[[:space:]]*home\.packages[[:space:]]*=[[:space:]]*\[/ { collecting = 1 }
    collecting { print }
    collecting && /^[[:space:]]*\][[:space:]]*\+\+/ { exit }
  ' "$module")"
  grep -Eq '^[[:space:]]*piTeamPkg[[:space:]]*$' <<<"$packages"
}

if grep -Fq 'piTeamPkg = pkgs.writeShellApplication {' "$PI_MODULE" \
  && grep -Fq 'name = "pi-team";' "$PI_MODULE" \
  && grep -Fq 'runtimeInputs = [ pkgs.nodejs pkgs.git ];' "$PI_MODULE" \
  && grep -Fq 'exec node ${repoRoot}/tools/pi-team.mjs "$@"' "$PI_MODULE" \
  && home_packages_contains_pi_team_pkg "$PI_MODULE"; then
  pass "Pi module installs pi-team from the repo tool with Node and git runtime"
else
  fail "Pi module is missing the pi-team PATH command or its home.packages wiring"
fi

# Prove the previous assertion cannot be satisfied by the piTeamPkg declaration alone.
MODULE_WITHOUT_PACKAGE="$TMP/default-without-pi-team-package.nix"
sed '/^[[:space:]]*piTeamPkg[[:space:]]*$/d' "$PI_MODULE" >"$MODULE_WITHOUT_PACKAGE"
if home_packages_contains_pi_team_pkg "$MODULE_WITHOUT_PACKAGE"; then
  fail "Pi module home.packages assertion passed after piTeamPkg was removed from the package list"
else
  pass "Pi module pi-team assertion rejects a declaration without home.packages installation"
fi

# Verify the module references skills that actually exist
SKILL_REFS=(
  "skills/discovery" "skills/design" "skills/research"
  "skills/create-plan" "skills/review-plan" "skills/create-worklog"
  "skills/execute-task" "skills/execution-orchestrator"
  "skills/review-code" "skills/review-approach" "skills/assess-repo"
  "skills/create-skills" "skills/configure-pi" "skills/create-new-repo-docs"
  "skills/pi-team-plan" "skills/pi-team-lead" "skills/pi-team-worker"
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
  "agents/vision.md" "agents/oracle.md" "agents/pi-team-reviewer.md"
)
for ref in "${AGENT_REFS[@]}"; do
  agent_name="$(basename "$ref" .md)"
  if [[ -f "$REPO_ROOT/${ref}" ]]; then
    pass "Module agent ref '${agent_name}' resolves to existing file"
  else
    fail "Module agent ref '${agent_name}' does not resolve (missing $REPO_ROOT/${ref})"
  fi
done

# Pi team skills and reviewer must be installed from their generated/canonical
# surfaces: config.nix declares the rosters and links them into the agent
# tree; default.nix links the tree entries into ~/.pi/agent by roster.
if grep -Fq '"pi-team-plan"' "$PI_CONFIG" \
  && grep -Fq '"pi-team-lead"' "$PI_CONFIG" \
  && grep -Fq '"pi-team-worker"' "$PI_CONFIG" \
  && grep -Fq '"pi-team-reviewer"' "$PI_CONFIG" \
  && grep -Fq 'piAgentNames' "$PI_MODULE" \
  && grep -Fq 'piSkillNames' "$PI_MODULE"; then
  pass "Pi module installs the Pi team skills and task reviewer"
else
  fail "Pi module is missing Pi team skill or reviewer wiring"
fi

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
