#!/usr/bin/env bash
# Enforces the single-source rule for substrate facts in this directory.
#
#   notes/README.md defines the SUB-n constraints (mechanism + file:line citations).
#   Every other doc states only the consequence and cites [SUB-n].
#
# Two invariants, both cheap:
#   1. No source file:line citations outside notes/ — mechanism lives in one place.
#   2. Every cited [SUB-n] is defined, and every defined SUB-n is cited.
#
# Run from this directory. Exits non-zero on violation.

set -uo pipefail
cd "$(dirname "$0")"

stale_claims=(
  "review-on-handoff"
  "every handoff"
  "Phase 1b"
  "plans/<date>-<slug>"
)

scan_stale_claims() {
  local target label claim found=0
  local -a targets=("$@")

  for target in "${targets[@]}"; do
    label=$(basename "$target")
    for claim in "${stale_claims[@]}"; do
      if grep -Fq -- "$claim" "$target"; then
        echo "STALE_CLAIM: $claim in $label"
        found=1
      fi
    done
  done

  return "$found"
}

self_test() {
  local fixture target claim output expected
  fixture=$(mktemp -d) || return 1
  trap "rm -rf -- $(printf '%q' "$fixture")" EXIT

  for target in README.md pi-team-execution-plan.html; do
    printf '%s\n' 'Current promoted summary.' > "$fixture/$target"
  done

  if output=$(scan_stale_claims "$fixture/README.md" "$fixture/pi-team-execution-plan.html"); then
    [ -z "$output" ] || {
      echo "SELF_TEST_FAIL: clean fixtures produced diagnostics"
      return 1
    }
  else
    echo "SELF_TEST_FAIL: clean fixtures failed stale scan"
    return 1
  fi

  for target in README.md pi-team-execution-plan.html; do
    for claim in "${stale_claims[@]}"; do
      printf '%s\n%s\n' 'Current promoted summary.' "$claim" > "$fixture/$target"
      expected="STALE_CLAIM: $claim in $target"
      if output=$(scan_stale_claims "$fixture/$target"); then
        echo "SELF_TEST_FAIL: missing $expected"
        return 1
      elif [ "$output" != "$expected" ]; then
        echo "SELF_TEST_FAIL: expected $expected"
        return 1
      fi
      printf '%s\n' 'Current promoted summary.' > "$fixture/$target"
    done
  done

  echo "PASS"
}

if [ "$#" -eq 1 ] && [ "$1" = "--self-test" ]; then
  self_test
  exit "$?"
elif [ "$#" -ne 0 ]; then
  echo "usage: $0 [--self-test]" >&2
  exit 2
fi

fail=0

echo "== 1. source citations outside notes/"
if hits=$(grep -noE "crew/[a-z/-]+\.ts:[0-9-]+|index\.ts:[0-9-]+" \
            README.md pi-team-execution.md implementation-plan.md \
            pi-team-execution-plan.html 2>/dev/null); then
  echo "$hits" | sed 's/^/   FAIL restates mechanism: /'
  echo "   -> move the detail into notes/README.md and cite [SUB-n] instead"
  fail=1
else
  echo "   ok"
fi

echo "== 2. SUB-n reference integrity"
defined=$(grep -oE '\*\*SUB-[0-9a-b]+\*\*' notes/README.md | tr -d '*' | sort -u)
cited=$(cat ./*.md ./*.html 2>/dev/null | grep -ohE '\[SUB-[0-9a-b]+\]' | tr -d '[]' | sort -u)

if undef=$(comm -13 <(echo "$defined") <(echo "$cited")) && [ -n "$undef" ]; then
  echo "$undef" | sed 's/^/   FAIL cited but undefined: /'
  fail=1
fi
if unused=$(comm -23 <(echo "$defined") <(echo "$cited")) && [ -n "$unused" ]; then
  echo "$unused" | sed 's/^/   WARN defined but never cited: /'
fi
[ -z "${undef:-}" ] && echo "   ok"

echo "== 3. stale claims in promoted summaries"
if scan_stale_claims README.md pi-team-execution-plan.html; then
  echo "   ok"
else
  fail=1
fi

[ "$fail" -eq 0 ] && echo "PASS" || echo "FAIL"
exit "$fail"
