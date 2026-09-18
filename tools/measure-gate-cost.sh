#!/usr/bin/env bash
# Measure the startup overhead of a verification profile.
#
# Compares wall-clock time against the runner's self-reported test duration to expose
# per-invocation startup cost (shell entry, dependency resolution, transform/collect).
# Produces the "Startup cost" column required by the proposed Verification Profiles table.
#
# Usage:
#   ./measure-gate-cost.sh "<label>" "<command>" [...more label/command pairs]
#
# Example:
#   ./measure-gate-cost.sh \
#     "single-file"  "<targeted test command for one test file>" \
#     "full-suite"   "<full test suite command>" \
#     "build"        "<build command>"

set -uo pipefail

if [ $# -lt 2 ] || [ $(( $# % 2 )) -ne 0 ]; then
  sed -n '2,16p' "$0"
  exit 64
fi

printf '%-18s %10s %14s %12s\n' "PROFILE" "WALL(s)" "REPORTED" "OVERHEAD"
printf '%-18s %10s %14s %12s\n' "------------------" "----------" "--------------" "------------"

while [ $# -gt 0 ]; do
  label="$1"; cmd="$2"; shift 2

  start=$(date +%s)
  output=$(eval "$cmd" 2>&1)
  status=$?
  end=$(date +%s)
  wall=$(( end - start ))

  # Vitest prints e.g. "Duration  13.13s (transform 21.36s, ...)"
  reported=$(printf '%s\n' "$output" | grep -oE 'Duration[[:space:]]+[0-9.]+m?s' | head -1 | grep -oE '[0-9.]+m?s' || true)
  [ -z "$reported" ] && reported="n/a"

  if [ "$reported" != "n/a" ]; then
    num=${reported%s}
    case "$reported" in
      *ms) secs=$(awk -v v="${num%m}" 'BEGIN{printf "%.3f", v/1000}') ;;
      *)   secs="$num" ;;
    esac
    overhead=$(awk -v w="$wall" -v t="$secs" 'BEGIN{ if (w>0) printf "%.0f%%", (w-t)/w*100; else print "n/a" }')
  else
    overhead="n/a"
  fi

  printf '%-18s %10s %14s %12s' "$label" "$wall" "$reported" "$overhead"
  [ $status -ne 0 ] && printf '   (exit %d)' "$status"
  printf '\n'
done

cat <<'NOTE'

Interpretation:
  WALL      total elapsed time an implementer actually pays per invocation
  REPORTED  the runner's own test-execution time
  OVERHEAD  share of wall-clock spent on startup rather than testing

High overhead on a frequently-invoked profile is the strongest argument for a
warm runner (persistent watch process or pre-entered dev shell). Multiply the
overhead by the plan's expected invocations-per-packet to size the total cost.
NOTE
