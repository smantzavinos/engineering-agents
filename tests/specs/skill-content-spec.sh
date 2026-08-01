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

# The additive Pi team flow is isolated from the shared/OpenCode pipeline and carries
# its reviewed plan, transaction, review, and worker-safety contracts directly.
for pi_skill in pi-team-plan pi-team-lead pi-team-worker; do
  skill_path="$REPO_ROOT/skills/$pi_skill/SKILL.md"
  if [[ -f "$skill_path" ]] && grep -Fq 'harnesses: [pi]' "$skill_path"; then
    pass "${pi_skill} is a Pi-only canonical skill"
  else
    fail "${pi_skill} is missing or not restricted to Pi"
  fi
done

if grep -Fq 'disable-model-invocation: true' "$REPO_ROOT/skills/pi-team-plan/SKILL.md" \
  && grep -Fq 'human-triggered' "$REPO_ROOT/skills/pi-team-plan/SKILL.md" \
  && ! grep -Fq 'do not invoke a model to write, review, or approve the plan' "$REPO_ROOT/skills/pi-team-plan/SKILL.md" \
  && grep -Fq 'Plan schema: 1' "$REPO_ROOT/skills/pi-team-plan/SKILL.md" \
  && grep -Fq 'pi-team check <plan-path> --json' "$REPO_ROOT/skills/pi-team-plan/SKILL.md" \
  && grep -Fq 'fresh semantic review' "$REPO_ROOT/skills/pi-team-plan/SKILL.md" \
  && grep -Fq 'Never waive risk approval' "$REPO_ROOT/skills/pi-team-plan/SKILL.md"; then
  pass "pi-team-plan preserves human-triggered planning and semantic/risk-review gates"
else
  fail "pi-team-plan is missing its human-triggered, semantic-review, or risk gate"
fi

if grep -Fq 'pi_messenger({ action: "join" })' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'pi_messenger({ action: "team.profile.use", name: "pi-team" })' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'team.profile.use' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'stable topological order' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'plan-ID→Crew-ID map' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'task.approve' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'PI_MESSENGER_TEAM_PROFILE_DIR' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'config/pi-team/pi-team.json' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq '.pi/messenger/crew/agents/crew-worker.md' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'config/pi-team/crew-worker.md' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'before dispatch' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'no `tools` frontmatter' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq '**SUB-12**' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'HEAD == BASE' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'pi-team init-board' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'pi-team review-wave' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'fresh `pi-team-reviewer`' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'two remediation revisions' "$REPO_ROOT/skills/pi-team-lead/SKILL.md" \
  && grep -Fq 'telemetry.md' "$REPO_ROOT/skills/pi-team-lead/SKILL.md"; then
  pass "pi-team-lead encodes Messenger join, profile, transaction, review, remediation, and closure protocol"
else
  fail "pi-team-lead is missing required Messenger join or execution protocol anchors"
fi

lead="$REPO_ROOT/skills/pi-team-lead/SKILL.md"
if [[ "$(grep -nF 'pi_messenger({ action: "join" })' "$lead" | head -n1 | cut -d: -f1)" \
    -lt "$(grep -nF 'pi_messenger({ action: "team.profile.use", name: "pi-team" })' "$lead" | head -n1 | cut -d: -f1)" ]]; then
  pass "pi-team-lead joins Messenger before activating the team profile"
else
  fail "pi-team-lead must join Messenger before activating the team profile"
fi
if grep -Fq 'PLAN="$REPO/plans/YYYY_MM_DD_<slug>/plan.md"' "$lead" \
  && grep -Fq 'CREW="$REPO/.pi/messenger/crew"' "$lead" \
  && grep -Fq 'BASE="$(git -C "$REPO" rev-parse HEAD)"' "$lead" \
  && grep -Fq 'WAVE_IDS="T1,T2"' "$lead" \
  && grep -Fq 'RETRY_IDS="T1"' "$lead" \
  && grep -Fq 'pi-team check "$PLAN" --json' "$lead" \
  && grep -Fq 'pi-team init-board "$PLAN" --crew-dir "$CREW" --repo-root "$REPO"' "$lead" \
  && grep -Fq -- '--scope "$WAVE_IDS" --bundle "$WAVE_IDS" --repo-root "$REPO" --base "$BASE" --output-dir "$WAVE_OUTPUT_DIR"' "$lead" \
  && grep -Fq -- '--scope "$WAVE_IDS" --bundle "$RETRY_IDS" --repo-root "$REPO" --base "$BASE" --output-dir "$RETRY_OUTPUT_DIR"' "$lead" \
  && grep -Fq 'before.get(id) !== sha256' "$lead" \
  && grep -Fq 'task IDs, never paths' "$lead"; then
  pass "pi-team-lead supplies executable check, board, wave, retry, and remediation commands"
else
  fail "pi-team-lead is missing executable commands or retry/remediation bundle semantics"
fi

if grep -Fq 'task.unblock' "$lead" \
  && grep -Fq 'task.start' "$lead" \
  && grep -Fq 'task.done' "$lead" \
  && grep -Fq 'summary and review evidence' "$lead" \
  && grep -Fq 'rescue failure remains blocked' "$lead" \
  && grep -Fq 'github-copilot/gpt-5.6-sol' "$lead" \
  && grep -Fq 'fresh full-diff review' "$lead" \
  && grep -Fq 'same new HEAD commit' "$lead" \
  && grep -Fq 'at most two fresh remediation passes' "$lead"; then
  pass "pi-team-lead closes rescue state and requires a fresh clean final review on the new HEAD"
else
  fail "pi-team-lead is missing rescue closure or final same-commit review requirements"
fi

plan_skill="$REPO_ROOT/skills/pi-team-plan/SKILL.md"
plan_contract="$REPO_ROOT/skills/pi-team-plan/references/plan-contract.md"
if grep -Fq 'Read `references/plan-contract.md` before authoring or validating a plan.' "$plan_skill" \
  && [[ -s "$plan_contract" ]] \
  && grep -Fq 'Exact v1 grammar' "$plan_contract" \
  && grep -Fq 'T[1-9][0-9]*' "$plan_contract" \
  && grep -Fq 'cheap, std, complex, visual, visual-complex' "$plan_contract" \
  && grep -Fq 'migration, destructive, auth, api-contract' "$plan_contract" \
  && grep -Fq 'integration:G<n>' "$plan_contract" \
  && grep -Fq 'Wave = dependency depth' "$plan_contract" \
  && grep -Fq 'critical path <= 60% of serial estimate' "$plan_contract" \
  && grep -Fq 'estimate <= max(20 minutes, 20% of critical path)' "$plan_contract" \
  && grep -Fq 'do not add artificial dependency' "$plan_contract" \
  && grep -Fq '# <title>' "$plan_contract"; then
  pass "pi-team-plan loads a self-contained v1 grammar, rules, and template reference"
else
  fail "pi-team-plan is missing its installed self-contained plan-contract reference or exact critical-path thresholds"
fi

if grep -Fq 'Modify only the declared write set' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'minimal check' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'Do not commit' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'broad gates' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'do not mutate files through bash' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'handoff' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'declared write set remains the authority' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'even if a malformed packet lists them' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'authored `plan.md`' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'generated board/runtime state' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'Crew/project config' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'telemetry' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'review records' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && grep -Fq 'Stop and report the invalid packet' "$REPO_ROOT/skills/pi-team-worker/SKILL.md" \
  && ! grep -Fq 'durable policy documents' "$REPO_ROOT/skills/pi-team-worker/SKILL.md"; then
  pass "pi-team-worker preserves write-set authority, immutable control artifacts, and bounded handoff"
else
  fail "pi-team-worker is missing immutable control-artifact protection or retains a blanket durable-policy prohibition"
fi

reviewer="$REPO_ROOT/agents/pi-team-reviewer.md"
if [[ -f "$reviewer" ]] \
  && grep -Fq 'model: github-copilot/gpt-5.6-terra' "$reviewer" \
  && grep -Fq 'read-only' "$reviewer" \
  && grep -Fq 'SHIP|NEEDS_WORK|MAJOR_RETHINK' "$reviewer" \
  && grep -Fq 'Do not inspect peer write sets' "$reviewer"; then
  pass "pi-team-reviewer is read-only with the exact task-review verdict contract"
else
  fail "pi-team-reviewer is missing model, read-only, verdict, or scope boundaries"
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
