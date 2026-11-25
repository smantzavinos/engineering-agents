# Shared non-dry launcher contracts for the pipeline and PR sweep specs.
# Requirement: FR-001
# Callers provide t3_tick (invoke the dispatcher), t3_seed_session (in-flight
# ledger), t3_seed_result (one deliverable result), and t3_expected_title.

t3_run() {
  local PY="$PY"
  if [[ -n "${T3_TEST_NOW:-}" ]]; then PY="$T3_FIXTURE/tick-at"; fi
  t3_tick PIPELINE_LAUNCHER=t3 T3_BIN="$T3_FIXTURE/t3" PATH="$T3_FIXTURE:$PATH" \
    HERMES_BIN="$TMP/not-hermes" PIPELINE_FORCE=1 PIPELINE_GIT_NAME= PIPELINE_GIT_EMAIL= \
    T3_TEST_TRACE="$T3_TRACE" T3_TEST_MUTATIONS="$T3_MUTATIONS" T3_TEST_DUE="${T3_TEST_DUE:-1}" \
    T3_TEST_STATE=live T3_TEST_SERVER=up "$@"
}

t3_prepare() {
  T3_STATE="$TMP/t3-flow-$1"
  T3_TRACE="$TMP/t3-flow-$1.calls"
  T3_MUTATIONS="$TMP/t3-flow-$1.mutations"
  mkdir -p "$T3_STATE/results" "$T3_STATE/logs"
  : > "$T3_TRACE"; : > "$T3_MUTATIONS"
}

t3_snapshot() {
  (cd "$T3_STATE" && { find . -type d; find . -type f -exec sha256sum {} +; } | LC_ALL=C sort)
}

t3_flow_cases() {
  local T3_STATE T3_TRACE T3_MUTATIONS T3_CHECKOUT T3_OTHER
  local out rc before trace alert tag entry now lines
  local show=$'thread\tshow\t--json\tthread-test\t' start=$'thread\tstart\t' list=$'thread\tlist\t'
  T3_CHECKOUT="$TMP/T3 repository"
  T3_OTHER="$TMP/Other repository"
  git init -q --template= "$T3_CHECKOUT"
  git init -q --template= "$T3_OTHER"

  t3_prepare outage
  t3_seed_result
  before="$(<"$T3_STATE/dispatches.jsonl")"
  rc=0; out="$(t3_run T3_TEST_SERVER=down 2>&1)" || rc=$?
  check "rc=$rc;" 'rc=1;' 'T3 outage: a due tick exits 1'
  alert="$(grep -F '🛑' <<<"$out" | grep -F 'stopped' || true)"
  check "$alert" 'No running T3 Code server uses the test home' 'T3 outage: stopped alert names T3 and keeps its failure reason'
  check "$out" 'finished before outage' 'T3 outage: finished results still arrive'
  trace="$(<"$T3_TRACE")"
  check "$trace" "${list}"$'--json\t--project\t'"$T3_CHECKOUT"$'\t' 'T3 outage: checks readiness for the checkout'
  check "checks=$(grep -Fc "$list" <<<"$trace" || true);" 'checks=1;' 'T3 outage: checks the repository exactly once'
  refute "$trace" "$start" 'T3 outage: does not attempt a start'
  check "unchanged=$([[ "$(<"$T3_STATE/dispatches.jsonl")" == "$before" ]] && echo yes);" \
    'unchanged=yes;' 'T3 outage: ledger contains only the pre-existing result record'
  check "mutations=$(<"$T3_MUTATIONS");" 'mutations=;' 'T3 outage: no label, reaction, or tracker move'
  : > "$T3_TRACE"
  rc=0; out="$(t3_run 2>&1)" || rc=$?
  check "rc=$rc;" 'rc=0;' 'T3 outage: healthy next tick exits 0'
  check "$(grep -F '✅' <<<"$out" || true)" 'runs again' 'T3 outage: restored readiness reports recovery'
  check "$(<"$T3_TRACE")" "$start" 'T3 outage: restored readiness starts due work'

  t3_prepare unknown
  t3_seed_session
  before="$(<"$T3_STATE/dispatches.jsonl")"
  rc=0; out="$(t3_run T3_TEST_STATE=unknown 2>&1)" || rc=$?
  check "rc=$rc;" 'rc=1;' 'T3 unknown (non-dry): exits 1'
  alert="$(grep -F '🛑' <<<"$out" | grep -F 'stopped' | grep -Fi T3 || true)"
  check "$alert" 'connection refused' 'T3 unknown (non-dry): emits the stopped alert'
  rc=0; out="$(t3_run 2>&1)" || rc=$?
  check "rc=$rc;" 'rc=0;' 'T3 unknown (non-dry): live next tick exits 0'
  check "$(grep -F '✅' <<<"$out" || true)" 'runs again' 'T3 unknown (non-dry): live next tick reports recovery'
  refute "$(<"$T3_TRACE")" "$start" 'T3 unknown (non-dry): no retry while unknown or live'
  check "unchanged=$([[ "$(<"$T3_STATE/dispatches.jsonl")" == "$before" ]] && echo yes);" \
    'unchanged=yes;' 'T3 unknown (non-dry): no new record while unknown or live'

  # Isolate notice persistence from B1: waiting + pending was already classified as asked.
  t3_prepare asked
  t3_seed_session
  before="$(t3_snapshot)"
  for _ in 1 2; do
    out="$(T3_DRY=1 T3_TEST_DUE=0 t3_run T3_TEST_STATE=asked-waiting 2>&1)" || true
    lines="$(grep -F 'waiting for an answer' <<<"$out" || true)"
    check "$lines" 't3:thread-test' 'T3 asked (dry): prints the waiting notice on each tick'
  done
  check "unchanged=$([[ "$(t3_snapshot)" == "$before" ]] && echo yes);" \
    'unchanged=yes;' 'T3 asked (dry): does not change state'
  refute "$(<"$T3_TRACE")" "$list" 'T3 asked (dry): does not check readiness'
  now="$(date +%s)"
  rc=0; out="$(T3_TEST_NOW="$now" T3_TEST_DUE=0 t3_run T3_TEST_STATE=asked-waiting 2>&1)" || rc=$?
  check "rc=$rc;" 'rc=0;' 'T3 asked (non-dry): first tick succeeds'
  lines="$(grep -F 'waiting for an answer' <<<"$out" || true)"
  check "$lines" 't3:thread-test' 'T3 asked (non-dry): prints the first waiting notice'
  : > "$T3_TRACE"
  rc=0; out="$(T3_TEST_NOW="$((now + 86400))" T3_TEST_DUE=0 t3_run T3_TEST_STATE=asked-waiting 2>&1)" || rc=$?
  check "rc=$rc;" 'rc=0;' 'T3 asked (non-dry): later tick succeeds'
  check "$(<"$T3_TRACE")" "$show" 'T3 asked (non-dry): later tick still probes the handle'
  refute "$out" 'waiting for an answer' 'T3 asked (non-dry): stays silent after the old dedupe TTL'

  t3_prepare dead
  t3_seed_session
  before="$(t3_snapshot)"
  rc=0; out="$(T3_DRY=1 T3_TEST_DUE=0 t3_run T3_TEST_STATE=dead 2>&1)" || rc=$?
  check "rc=$rc;" 'rc=0;' 'T3 dead (dry): tick succeeds'
  check "$(<"$T3_TRACE")" "$show" 'T3 dead (dry): probes the handle'
  check "unchanged=$([[ "$(t3_snapshot)" == "$before" ]] && echo yes);" \
    'unchanged=yes;' 'T3 dead (dry): no cache or other state write'
  : > "$T3_TRACE"
  rc=0; out="$(T3_TEST_DUE=0 t3_run T3_TEST_STATE=dead 2>&1)" || rc=$?
  check "rc=$rc;" 'rc=0;' 'T3 dead (non-dry): first tick succeeds'
  check "$(<"$T3_TRACE")" "$show" 'T3 dead (non-dry): still probes after the dry tick'
  : > "$T3_TRACE"
  rc=0; out="$(T3_TEST_DUE=0 t3_run T3_TEST_STATE=dead 2>&1)" || rc=$?
  check "rc=$rc;" 'rc=0;' 'T3 dead (non-dry): later tick succeeds'
  refute "$(<"$T3_TRACE")" "$show" 'T3 dead (non-dry): remembers the dead handle across ticks'

  t3_prepare spawn
  rc=0; out="$(t3_run PIPELINE_GIT_NAME='T3 Test Bot' PIPELINE_GIT_EMAIL=t3-bot@example.test 2>&1)" || rc=$?
  check "rc=$rc;" 'rc=0;' 'T3 start: tick succeeds'
  trace="$(grep -F "$start" "$T3_TRACE" || true)"
  check "starts=$(grep -c . <<<"$trace" || true);" 'starts=1;' 'T3 start: exactly one CLI start'
  entry="$("$PY" - "$T3_STATE/dispatches.jsonl" <<'PY' || true
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
for line in path.read_text().splitlines() if path.exists() else ():
    record = json.loads(line)
    print(record.get('pid', '<no handle>'), record.get('tag', '<no tag>'))
PY
)"
  check "$entry" 't3:thread-started ' 'T3 start: ledger records the returned handle'
  tag="${entry#* }"
  check "$trace" $'\t--title\t'"$(t3_expected_title "$tag")"$'\t'"$T3_CHECKOUT"$'\t-\t' \
    'T3 start: session title and project checkout are passed to the CLI'
  check "$(git -C "$T3_CHECKOUT" config --local --get user.name || true)" 'T3 Test Bot' 'T3 start: author name goes to the checkout'
  check "$(git -C "$T3_CHECKOUT" config --local --get user.email || true)" 't3-bot@example.test' 'T3 start: author email goes to the checkout'
  check "author=$(git -C "$T3_OTHER" config --local --get-regexp '^user\.(name|email)$' || true);" \
    'author=;' 'T3 start: other checkout author is untouched'
}
