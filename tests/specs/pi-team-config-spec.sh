#!/usr/bin/env bash
# Verify reproducible Pi Messenger Crew configuration and profile policy.
# Requirement: FR-002, OPR-001
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands git jq >/dev/null

REPO_ROOT="$(repo_root)"
PASS=0 FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

assert_equals() {
  local actual="$1" expected="$2" desc="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc (expected: $expected, actual: $actual)"
  fi
}

validate_profile() {
  jq -e '
    .name == "pi-team" and
    .roles == {
      "worker-cheap": {"model":"github-copilot/gpt-5.6-terra","thinking":"low","skills":["pi-team-worker"]},
      "worker-std": {"model":"github-copilot/gpt-5.6-terra","thinking":"medium","skills":["pi-team-worker"]},
      "worker-complex": {"model":"github-copilot/gpt-5.6-sol","thinking":"high","skills":["pi-team-worker"]},
      "worker-visual": {"model":"github-copilot/gpt-5.6-terra","thinking":"high","skills":["pi-team-worker"]},
      "worker-visual-complex": {"model":"github-copilot/gpt-5.6-sol","thinking":"high","skills":["pi-team-worker"]}
    } and
    .approval == {"mode":"risk-labels","labels":["migration","destructive","auth","api-contract"]} and
    .memory == {"inject":["decision","interface","risk"],"maxCharsPerType":4000}
  ' "$1" >/dev/null
}

printf 'Pi team configuration verification\n'
printf '==================================\n\n'

crew_config="$REPO_ROOT/config/pi-team/crew-config.json"
crew_worker="$REPO_ROOT/config/pi-team/crew-worker.md"
team_profile="$REPO_ROOT/config/pi-team/team-profile.json"
project_config="$REPO_ROOT/.pi/messenger/crew/config.json"
project_worker="$REPO_ROOT/.pi/messenger/crew/agents/crew-worker.md"
expected_crew='{"concurrency":{"workers":4},"artifacts":{"enabled":true},"review":{"enabled":false,"maxIterations":2},"work":{"maxAttemptsPerTask":2,"maxWaves":1,"stopOnBlock":true},"dependencies":"strict","coordination":"minimal"}'

if [[ -f "$crew_config" ]] && [[ "$(jq -cS . "$crew_config")" == "$(printf '%s\n' "$expected_crew" | jq -cS .)" ]]; then
  pass 'Canonical Crew config exactly matches the reviewed design'
else
  fail 'Canonical Crew config exactly matches the reviewed design'
fi

if [[ -f "$team_profile" ]] && validate_profile "$team_profile"; then
  pass 'Canonical pi-team profile exactly enforces models, skills, and risk approval'
else
  fail 'Canonical pi-team profile exactly enforces models, skills, and risk approval'
fi

if [[ -L "$project_config" ]]; then
  assert_equals "$(readlink "$project_config")" '../../../config/pi-team/crew-config.json' 'Project Crew config is a relative canonical-config symlink'
else
  fail 'Project Crew config is a relative canonical-config symlink'
fi

if [[ -L "$project_worker" ]]; then
  assert_equals "$(readlink "$project_worker")" '../../../../config/pi-team/crew-worker.md' 'Project Crew worker is a relative canonical override symlink'
else
  fail 'Project Crew worker is a relative canonical override symlink'
fi

if [[ -f "$crew_worker" ]] \
  && grep -Fq 'name: crew-worker' "$crew_worker" \
  && grep -Fq 'tools: read, write, edit, bash, pi_messenger' "$crew_worker" \
  && grep -Fq 'crewRole: worker' "$crew_worker" \
  && grep -Fq 'pi_messenger({ action: "task.show", id: "<TASK_ID>" })' "$crew_worker" \
  && grep -Fq 'Use structured `edit` and `write` tools for every file mutation.' "$crew_worker" \
  && grep -Fq 'Run only the task packet’s minimal check.' "$crew_worker" \
  && grep -Fq 'tests: ["<minimal-check-command>"]' "$crew_worker"; then
  pass 'Canonical Crew worker override has the bounded worker protocol and tools'
else
  fail 'Canonical Crew worker override has the bounded worker protocol and tools'
fi

protocol_lines=()
for anchor in \
  'pi_messenger({ action: "join" })' \
  'pi_messenger({ action: "task.show", id: "<TASK_ID>" })' \
  'read({ path: ".pi/messenger/crew/tasks/<TASK_ID>.md" })' \
  'pi_messenger({ action: "task.start", id: "<TASK_ID>" })' \
  'pi_messenger({ action: "reserve", paths: ["<declared-write-set>"], reason: "<TASK_ID>" })' \
  'Use structured `edit` and `write` tools for every file mutation.' \
  'Run only the task packet’s minimal check.' \
  'pi_messenger({ action: "task.progress", id: "<TASK_ID>", message:' \
  'pi_messenger({ action: "release" })' \
  'action: "task.done"'; do
  protocol_lines+=("$(grep -nF "$anchor" "$crew_worker" | head -n1 | cut -d: -f1 || true)")
done
protocol_order_valid=true
for ((i = 0; i < ${#protocol_lines[@]}; i++)); do
  if [[ ! "${protocol_lines[$i]}" =~ ^[0-9]+$ ]] ||
     ((i > 0 && protocol_lines[i - 1] >= protocol_lines[i])); then
    protocol_order_valid=false
    break
  fi
done
if [[ "$protocol_order_valid" == true ]]; then
  pass 'Crew worker override orders join, re-anchor, start, reserve, edit, check, progress, release, and completion'
else
  fail 'Crew worker override orders join, re-anchor, start, reserve, edit, check, progress, release, and completion'
fi

if [[ -f "$crew_worker" ]] \
  && ! grep -Fq 'git add -A' "$crew_worker" \
  && ! grep -Eq 'git (add|commit|checkout|reset|restore|stash|merge|rebase|cherry-pick)' "$crew_worker" \
  && ! grep -Fq 'commits:' "$crew_worker" \
  && grep -Fq 'Do not commit, stage, or run any Git mutation command.' "$crew_worker" \
  && grep -Fq 'Do not run broad gates.' "$crew_worker" \
  && grep -Fq 'Do not mutate files through `bash`' "$crew_worker"; then
  pass 'Crew worker override removes bundled commit behavior and forbids unsafe mutation and broad gates'
else
  fail 'Crew worker override removes bundled commit behavior and forbids unsafe mutation and broad gates'
fi

config_ignore_rule="$(git check-ignore -v --no-index "$project_config" || true)"
worker_ignore_rule="$(git check-ignore -v --no-index "$project_worker" || true)"
if git check-ignore -q --no-index "$REPO_ROOT/.pi/messenger/crew/plan.json" &&
   git check-ignore -q --no-index "$REPO_ROOT/.pi/messenger/crew/agents/other-agent.md" &&
   git check-ignore -q --no-index "$REPO_ROOT/.pi/messenger/team/activity.json" &&
   [[ "$config_ignore_rule" == *':!.pi/messenger/crew/config.json'* ]] &&
   [[ "$worker_ignore_rule" == *':!.pi/messenger/crew/agents/crew-worker.md'* ]]; then
  pass 'Runtime state and other agents remain ignored while stable config and worker override are admitted'
else
  fail 'Runtime state and other agents remain ignored while stable config and worker override are admitted'
fi

invalid_profile="$(mktemp)"
trap 'rm -f "$invalid_profile"' EXIT
if [[ -f "$team_profile" ]]; then
  jq '.approval.labels[0] = "unsafe"' "$team_profile" >"$invalid_profile"
else
  printf '{"approval":{"labels":["unsafe"]}}\n' >"$invalid_profile"
fi
if ! validate_profile "$invalid_profile"; then
  pass 'Invalid profile risk policy fails validation'
else
  fail 'Invalid profile risk policy fails validation'
fi

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
