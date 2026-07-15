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
SKILLS_WITH_REFS=(discovery design create-plan create-team-plan create-worklog create-team-worklog review-plan review-team-plan review-approach review-code assess-repo)
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

if grep -Fq '`team_plan.md`' "$REPO_ROOT/skills/review-code/SKILL.md" \
  && grep -Fq 'Team mode' "$REPO_ROOT/skills/review-code/SKILL.md" \
  && grep -Fq 'do not require per-packet break-it evidence' "$REPO_ROOT/skills/review-code/SKILL.md"; then
  pass "review-code supports independent final review for team plans"
else
  fail "review-code is missing team-plan final review semantics"
fi

# Template files in create-new-repo-docs
TEMPLATE_DIR="$REPO_ROOT/skills/create-new-repo-docs/templates"
if [[ -d "$TEMPLATE_DIR" ]]; then
  for tmpl in README.md docs/architecture.md docs/testing-strategy.md; do
    if [[ -f "$TEMPLATE_DIR/$tmpl" ]]; then
      pass "Template exists: $tmpl"
    else
      fail "Template missing: $tmpl"
    fi
  done
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

if [[ -f "$REPO_ROOT/skills/create-team-plan/references/team-plan-template.md" ]]; then
  pass "Team plan template exists"
else
  fail "Team plan template missing"
fi
if [[ -f "$REPO_ROOT/skills/review-team-plan/references/review-template.md" ]]; then
  pass "Team plan review template exists"
else
  fail "Team plan review template missing"
fi

if grep -Fq 'Acceptance Contract Packets' "$REPO_ROOT/skills/create-team-plan/SKILL.md" \
  && grep -Fq 'Strong rescue implementer' "$REPO_ROOT/skills/create-team-plan/references/team-plan-template.md"; then
  pass "Team planning skill defines contract-first execution and rescue capacity"
else
  fail "Team planning skill is missing contract-first or rescue-role requirements"
fi

if grep -Fq 'Do not poll' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md" \
  && grep -Fq 'Final reviewer' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md"; then
  pass "Team orchestrator is event-driven and includes fresh final review"
else
  fail "Team orchestrator is missing no-polling or final-review rules"
fi

if grep -Fq 'direct `subagent_type="hephaestus"`' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md" \
  && grep -Fq 'category="ultrabrain"' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md"; then
  pass "Team orchestrator separates direct rescue from external strong final review"
else
  fail "Team orchestrator role routing is incomplete"
fi

if grep -Fq 'Resume from the first missing stage artifact' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md" \
  && grep -Fq 'Do not push; all commits remain local' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md"; then
  pass "Team orchestrator has resumable prerequisites and a local-only git boundary"
else
  fail "Team orchestrator prerequisites or git boundary are incomplete"
fi

if grep -Fq 'Visual implementer replaces one fast implementer' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md" \
  && grep -Fq 'Member Prompt Contracts' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md" \
  && grep -Fq 'Contract/verifier prompt contract' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md"; then
  pass "Team orchestrator defines adaptive UI staffing and self-contained member prompts"
else
  fail "Team orchestrator is missing adaptive UI staffing or member prompt contracts"
fi

if ! grep -Fq 'GitHub Copilot suggestion' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md" \
  && ! grep -Fq 'Suggested Models' "$REPO_ROOT/skills/execution-orchestrator-team/SKILL.md"; then
  pass "Team orchestrator does not duplicate model recommendations that live in orchestration docs"
else
  fail "Team orchestrator should not duplicate docs/orchestration.md's model suggestion table"
fi

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
