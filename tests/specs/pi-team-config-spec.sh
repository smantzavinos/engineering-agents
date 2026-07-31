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
team_profile="$REPO_ROOT/config/pi-team/team-profile.json"
project_config="$REPO_ROOT/.pi/messenger/crew/config.json"
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

config_ignore_rule="$(git check-ignore -v --no-index "$project_config" || true)"
if git check-ignore -q --no-index "$REPO_ROOT/.pi/messenger/crew/plan.json" &&
   git check-ignore -q --no-index "$REPO_ROOT/.pi/messenger/team/activity.json" &&
   [[ "$config_ignore_rule" == *':!.pi/messenger/crew/config.json'* ]]; then
  pass 'Runtime board and team state remain ignored while stable config is admitted'
else
  fail 'Runtime board and team state remain ignored while stable config is admitted'
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
