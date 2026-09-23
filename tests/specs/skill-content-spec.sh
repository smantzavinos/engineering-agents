#!/usr/bin/env bash
# Verify skill content quality: templates exist, skills have required sections
# Requirement: FR-007
# Requirement: FR-008
# Requirement: NFR-003
# Requirement: OPR-003
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(repo_root)"
PASS=0 FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

assert_skill_has_section() {
  local skill_path="$1" section="$2" desc="$3"
  if grep -qi "^## *${section}" "$skill_path" 2>/dev/null || grep -qi "^# *${section}" "$skill_path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (missing '## ${section}' in $(basename "$(dirname "$skill_path")"))"
  fi
}

assert_references_valid() {
  local skill_dir="$1" skill_name="$2"
  local ref_dir="$skill_dir/references"
  if [[ ! -d "$ref_dir" ]]; then
    return 0  # References are optional
  fi
  local count
  count=$(find "$ref_dir" -type f | wc -l)
  if [[ "$count" -gt 0 ]]; then
    pass "Skill '${skill_name}' has ${count} reference file(s)"
    for ref in "$ref_dir"/*; do
      if [[ -s "$ref" ]]; then
        pass "Skill '${skill_name}' reference $(basename "$ref") is non-empty"
      else
        fail "Skill '${skill_name}' reference $(basename "$ref") is empty"
      fi
    done
  fi
}

# ============================================================
printf 'Skill content verification\n'
printf '==========================\n\n'

# Skills that should have references
SKILLS_WITH_REFS=(discovery design create-plan create-worklog review-plan review-approach review-code assess-repo)
for skill in "${SKILLS_WITH_REFS[@]}"; do
  assert_references_valid "$REPO_ROOT/skills/$skill" "$skill"
done

# Verify key skills have essential sections
# Discovery should reference brief (case-insensitive, anywhere in file)
if grep -qi 'brief' "$REPO_ROOT/skills/discovery/SKILL.md"; then
  pass "discovery references brief"
else
  fail "discovery does not reference brief"
fi

# Design should reference approach (case-insensitive, anywhere in file)
if grep -qi 'approach' "$REPO_ROOT/skills/design/SKILL.md"; then
  pass "design references approach"
else
  fail "design does not reference approach"
fi

# Execute-task should mention "TDD" or "test"
if grep -qi "tdd\|test" "$REPO_ROOT/skills/execute-task/SKILL.md"; then
  pass "execute-task references TDD/testing"
else
  fail "execute-task does not reference TDD/testing"
fi

# Review-code should mention "plan"
if grep -qi "plan" "$REPO_ROOT/skills/review-code/SKILL.md"; then
  pass "review-code references plan"
else
  fail "review-code does not reference plan"
fi

if grep -Fq 'Team mode' "$REPO_ROOT/skills/review-code/SKILL.md" \
  && grep -Fq 'per-task verification evidence' "$REPO_ROOT/skills/review-code/SKILL.md"; then
  pass "review-code distinguishes execution modes and checks per-task verification evidence"
else
  fail "review-code is missing execution-mode distinction or verification-evidence semantics"
fi


# Verify approach template has expected structure
if [[ -f "$REPO_ROOT/skills/design/references/approach-template.md" ]]; then
  pass "Design approach template exists"
else
  fail "Design approach template missing"
fi

# Verify plan template has expected structure
if [[ -f "$REPO_ROOT/skills/create-plan/references/plan-template.md" ]]; then
  pass "Plan template exists"
else
  fail "Plan template missing"
fi

# Team mode was replaced by code-mode execution: the Pi-only team skills and the
# team task reviewer are removed, and the retired orchestration skills are kept
# for OpenCode only so the Pi surface stays small.
for gone in pi-team-plan pi-team-lead pi-team-worker; do
  if [[ ! -e "$REPO_ROOT/skills/$gone" ]]; then
    pass "${gone} is removed with team mode"
  else
    fail "${gone} is removed with team mode"
  fi
done
if [[ ! -e "$REPO_ROOT/agents/pi-team-reviewer.md" ]]; then
  pass "pi-team-reviewer agent is removed with team mode"
else
  fail "pi-team-reviewer agent is removed with team mode"
fi
for oc_only in execution-orchestrator execute-task create-worklog \
                create-plan review-plan review-code; do
  if grep -Fq 'harnesses: [opencode]' "$REPO_ROOT/skills/$oc_only/SKILL.md"; then
    pass "${oc_only} is retained for OpenCode only"
  else
    fail "${oc_only} must be restricted to OpenCode after the Pi code-mode switch"
  fi
done

if grep -Fq 'General model suggestion' "$REPO_ROOT/docs/orchestration.md" \
  && grep -Fq 'GitHub Copilot suggestion' "$REPO_ROOT/docs/orchestration.md" \
  && grep -Fq 'Role-to-runtime mapping' "$REPO_ROOT/docs/orchestration.md"; then
  pass "Orchestration docs separate role routing from general and Copilot model suggestions"
else
  fail "Orchestration docs are missing role or model recommendation tables"
fi

# Verify worklog template exists
if [[ -f "$REPO_ROOT/skills/create-worklog/references/worklog-template.md" ]]; then
  pass "Worklog template exists"
else
  fail "Worklog template missing"
fi

# ============================================================
printf '\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
