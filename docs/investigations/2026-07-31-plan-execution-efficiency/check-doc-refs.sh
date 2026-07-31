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

[ "$fail" -eq 0 ] && echo "PASS" || echo "FAIL"
exit "$fail"
