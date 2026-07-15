#!/usr/bin/env bash
# Verify skill content quality: templates exist, skills have required sections
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
SKILLS_WITH_REFS=(discovery design create-plan create-worklog create-team-worklog review-plan review-approach review-code assess-repo)
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
