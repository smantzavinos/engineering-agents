#!/usr/bin/env bash
# Dry-run smoke test for scripts/pr-sweep-dispatch.py against a fake `gh`.
# Proves the PR label flow in docs/hermes/pr-automation.md: opt-in ignores unlabeled PRs;
# review-bot:queued dispatches a review; a push after a passed review re-queues it; legacy pr:* labels
# are renamed; Copilot-review rounds, CI gate, owner commands, resolve-only re-review, prompt rendering.
# Finer decisions are unit-tested in tests/scripts/.
# Requirement: FR-001
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
ROOT="$(repo_root)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "pr list"*) cat <<'J'
[{"number":1,"title":"unlabeled","headRefName":"a","headRefOid":"1111111111111111111111111111111111111111","labels":[],"isDraft":false},
 {"number":2,"title":"wants review","headRefName":"b","headRefOid":"2222222222222222222222222222222222222222","labels":[{"name":"review-bot:queued"}],"isDraft":false},
 {"number":3,"title":"moved after READY","headRefName":"c","headRefOid":"3333333333333333333333333333333333333333","labels":[{"name":"needs-human:merge"}],"isDraft":false},
 {"number":4,"title":"legacy label","headRefName":"d","headRefOid":"4444444444444444444444444444444444444444","labels":[{"name":"pr:ready-review"}],"isDraft":false},
 {"number":5,"title":"from a fork","headRefName":"e","headRefOid":"5555555555555555555555555555555555555555","labels":[{"name":"review-bot:queued"}],"isDraft":false,"isCrossRepository":true}]
J
  ;;
  *"issues/3/comments"*) echo '[{"id":9,"user":{"login":"agent"},"body":"<!-- pr-review verdict=READY head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -->"}]' ;;
  *"/comments"*) echo '[]' ;;
  *) echo '[]' ;;
esac
EOF
chmod +x "$TMP/gh"
PY="$(command -v python3 || true)"
if [[ -z "$PY" ]]; then echo "  FAIL: python3 not on PATH (run inside nix develop)" >&2; exit 1; fi
run() { env -u GH_TOKEN PR_SWEEP_DRY=1 PR_SWEEP_REPOS=o/r PIPELINE_OWNERS=owner PIPELINE_BOT_LOGINS=agent PR_SWEEP_STATE="$TMP/state" GH_BIN="$TMP/gh" HERMES_HOME="$TMP" "$@" "$PY" "$ROOT/scripts/pr-sweep-dispatch.py"; }
PASS=0 FAIL=0
check() {
  if grep -Fq "$2" <<<"$1"; then
    PASS=$((PASS+1)); echo "  PASS: $3"
  else
    FAIL=$((FAIL+1)); echo "  FAIL: $3 (missing: $2)" >&2
    if [[ -n "${SPEC_DEBUG:-}" ]]; then printf '%s\n' "$1" >&2; fi
  fi
}
refute() { if grep -Fq "$2" <<<"$1"; then FAIL=$((FAIL+1)); echo "  FAIL: $3 (unexpected: $2)" >&2; else PASS=$((PASS+1)); echo "  PASS: $3"; fi; }

OUT="$(run)"
refute "$OUT" "spawn review for o/r#1" "opt-in: unlabeled PR is ignored"
check  "$OUT" "would spawn review for o/r#2" "review-bot:queued dispatches a detached review"
check  "$OUT" "would set o/r#2 label review-bot:running" "dispatch marks the PR in-review"
check  "$OUT" "would set o/r#3 label review-bot:queued" "push after a passed review queues a new review"
check  "$OUT" "new commits after the passed review" "stale READY is reported to the human"
check  "$OUT" "would rename o/r#4 label pr:ready-review -> review-bot:queued" "legacy pr:* labels are renamed"
check  "$OUT" "would spawn review for o/r#4" "a renamed legacy label is acted on in the same tick"
refute "$OUT" "o/r#5" "trust: a PR from a fork is never reviewed or fixed"
OUT="$(run PIPELINE_OWNERS= || true)"
check  "$OUT" "set PIPELINE_OWNERS" "trust: the sweep refuses to run without owners"
OUT="$(PR_SWEEP_UNLABELED=review run)"
check  "$OUT" "would spawn review for o/r#1" "drift mode: unlabeled PR is reviewed"


# Babysit on open: a sweep-owned claim gets a round on a new bot review, never ages,
# and stops at the bot-review cap.
BOT="$TMP/gh-bot"
cat > "$BOT" <<'EOF'
#!/usr/bin/env bash
old='{"number":7,"title":"owned","headRefName":"item/7","headRefOid":"7777777777777777777777777777777777777777","labels":[{"name":"fix-bot:owns-branch"}],"isDraft":false}'
# PR 8: READY stamped at its head; rollup controlled by CI_ROLLUP (red|green|pending|none)
mk8() {
  case "${CI_ROLLUP:-red}" in
    red)     R='[{"name":"E2E","status":"COMPLETED","conclusion":"FAILURE"},{"name":"CI","status":"COMPLETED","conclusion":"SUCCESS"}]';;
    green)   R='[{"name":"CI","status":"COMPLETED","conclusion":"SUCCESS"}]';;
    pending) R='[{"name":"CI","status":"IN_PROGRESS","conclusion":null}]';;
    none)    R='[]';;
  esac
  if [ "${PR8_LABEL:-needs-human:merge}" = "fix-bot:owns-branch" ]; then
    L='[{"name":"fix-bot:owns-branch"},{"name":"review-bot:running"}]'
  else
    L="[{\"name\":\"${PR8_LABEL:-needs-human:merge}\"}]"
  fi
  printf '{"number":8,"title":"ready+ci","headRefName":"item/8","headRefOid":"8888888888888888888888888888888888888888","labels":%s,"isDraft":false,"statusCheckRollup":%s}' "$L" "$R"
}
case "$*" in
  "pr list"*) echo "[$old, $(mk8)]" ;;
  *"issues/7/comments"*) echo '[{"id":70,"user":{"login":"agent"},"body":"babysit: session=babysit-pr-item7-x heartbeat=2000-01-01T00:00:00Z"}]' ;;
  *"issues/8/comments"*)
    C='[{"id":80,"user":{"login":"agent"},"body":"<!-- pr-review verdict=READY head=8888888888888888888888888888888888888888 -->"}'
    if [ "${PR8_LABEL:-}" = "fix-bot:owns-branch" ]; then
      C="$C,{\"id\":81,\"user\":{\"login\":\"agent\"},\"body\":\"babysit: session=${PR8_SESSION:-babysit-pr-item8-x} heartbeat=${PR8_HEARTBEAT:-2000-01-01T00:00:00Z}\"}"
    fi
    echo "$C]" ;;
  *"pulls/7/reviews"*)
    n="${BOT_REVIEWS:-1}"; printf '['
    for i in $(seq 1 "$n"); do [[ $i -gt 1 ]] && printf ','; printf '{"id":%d,"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z"}' "$((700+i))"; done
    printf ']\n' ;;
  *) echo '[]' ;;
esac
EOF
chmod +x "$BOT"
OUT="$(run GH_BIN="$BOT")"
check  "$OUT" "would spawn babysit for o/r#7" "sweep-owned claim: new bot review dispatches a babysit round"
refute "$OUT" "claim went stale" "sweep-owned claim does not age by heartbeat"
OUT="$(run BOT_REVIEWS=6 GH_BIN="$BOT")"
refute "$OUT" "would spawn babysit for o/r#7" "bot-review cap: no round past 5 bot reviews"
check  "$OUT" "Copilot has reviewed this PR 5 times" "bot-review cap is reported once"
OUT="$(run BOT_REVIEWS=5 GH_BIN="$BOT")"
check  "$OUT" "would spawn babysit for o/r#7" "bot-review cap: the 5th bot review still gets a round"

# Finished rounds are read back from the dispatch log plus an accepted result file. `round` writes both:
# round TAG KIND PR HEAD OUTCOME [extra record JSON] [extra result JSON] — the result lists one non-empty log.
round() {
  local tag="$1" kind="$2" pr="$3" head="$4" outcome="$5" extra="${6:-}" rextra="${7:-}" key=status
  [[ "$kind" == review ]] && key=verdict
  mkdir -p "$TMP/state/results" "$TMP/state/logs/$tag"
  echo ok > "$TMP/state/logs/$tag/test.log"
  printf '{"ts":%s,"kind":"%s","repo":"o/r","pr":%s,"head":"%s","tag":"%s"%s}\n' \
    "$(date +%s)" "$kind" "$pr" "$head" "$tag" "${extra:+,$extra}" >> "$TMP/state/dispatches.jsonl"
  printf '{"repo":"o/r","pr":%s,"kind":"%s","%s":"%s","head":"%s","verification_artifacts":["%s"]%s}\n' \
    "$pr" "$kind" "$key" "$outcome" "$head" "$TMP/state/logs/$tag/test.log" "${rextra:+,$rextra}" > "$TMP/state/results/$tag.json"
}
H7=7777777777777777777777777777777777777777
H8=8888888888888888888888888888888888888888

# A finished round consumes EVERY Copilot review it saw (bot_review_ids), so two reviews between
# ticks cost one round, not two; a record naming only the first leaves the second due.
rm -rf "$TMP/state"
round b7 babysit 7 "$H7" RELEASED '"bot_review_ids":[701,702]'
OUT="$(run BOT_REVIEWS=2 GH_BIN="$BOT")"
refute "$OUT" "would spawn babysit for o/r#7" "bot-review batching: a round that saw both reviews suppresses the follow-up round"
rm -rf "$TMP/state"
round b7 babysit 7 "$H7" RELEASED '"bot_review_id":701'
OUT="$(run BOT_REVIEWS=2 GH_BIN="$BOT")"
check  "$OUT" "would spawn babysit for o/r#7" "bot-review batching: a round that saw only the first review leaves the second due"
rm -rf "$TMP/state"

# CI gate: red at the reviewed head sends the PR back to the fix bot; green restores needs-human:merge;
# pending checks or no checks are not red.
OUT="$(run GH_BIN="$BOT")"
check  "$OUT" "would spawn babysit for o/r#8" "CI gate: red at the reviewed head dispatches a fix round"
check  "$OUT" "would set o/r#8 label fix-bot:queued" "CI gate: red at the reviewed head re-queues the fix bot"
check  "$OUT" "CI red on the reviewed commit (E2E (FAILURE)); back to fix-bot:queued" "CI gate: the owner is told"
# tick 2: a finished round already handled this red set -> no second round, no second line.
round c8 babysit 8 "$H8" FIXED '"ci_key":"888888888888:E2E (FAILURE)"'
OUT="$(run PR8_LABEL=fix-bot:queued GH_BIN="$BOT")"
refute "$OUT" "would spawn babysit for o/r#8" "CI gate: the CI round fires once per red set"
refute "$OUT" "CI red" "CI gate: no second line for the same red set"
rm -rf "$TMP/state"
OUT="$(run PR8_LABEL=review-bot:running GH_BIN="$BOT")"
check  "$OUT" "CI red (E2E (FAILURE)); the fix bot will fix it." "CI gate: red while a review runs is handed to the fix bot"
OUT="$(run PR8_LABEL=fix-bot:queued CI_ROLLUP=green GH_BIN="$BOT")"
check  "$OUT" "CI green on the reviewed commit; back to needs-human:merge" "CI gate: green restores needs-human:merge"
OUT="$(run CI_ROLLUP=green GH_BIN="$BOT")"
refute "$OUT" "back to needs-human:merge" "CI gate: green at needs-human:merge is silent"
OUT="$(run CI_ROLLUP=pending GH_BIN="$BOT")"
refute "$OUT" "CI red" "CI gate: pending checks are ignored"
OUT="$(run CI_ROLLUP=none GH_BIN="$BOT")"
refute "$OUT" "CI red" "CI gate: no checks yet is not a red"

# A sweep-owned fix bot takes the CI round; so does a PR nobody owns. A chat-started claim with a
# fresh last-active stamp gets no sweep twin.
OUT="$(run PR8_LABEL=fix-bot:owns-branch CI_ROLLUP=red GH_BIN="$BOT")"
check  "$OUT" "would spawn babysit for o/r#8" "CI gate: sweep-owned claim gets a CI-fix round"
OUT="$(run PR8_LABEL=needs-human:merge CI_ROLLUP=red GH_BIN="$BOT")"
check  "$OUT" "would spawn babysit for o/r#8" "CI gate: red with no claim dispatches the round"
OUT="$(run PR8_LABEL=fix-bot:owns-branch PR8_SESSION=20260101_chat PR8_HEARTBEAT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" CI_ROLLUP=red GH_BIN="$BOT")"
refute "$OUT" "would spawn babysit for o/r#8" "CI gate: chat-started claim gets no sweep twin"


# Owner commands: `<handle> review` -> review bot; `<handle> fix` -> fix bot; free text and the bot's
# own comments never trigger anything.
MEN="$TMP/gh-men"
cat > "$MEN" <<'EOF'
#!/usr/bin/env bash
pr='{"number":9,"title":"mention","headRefName":"item/9","headRefOid":"9999999999999999999999999999999999999999","labels":[{"name":"needs-human:merge"}%s],"isDraft":false}'
case "${M_CLAIM:-none}" in
  owned) L=',{"name":"fix-bot:owns-branch"}' ;;
  *) L='' ;;
esac
case "$*" in
  "pr list"*) printf "[$pr]" "$L" ;;
  *"issues/9/comments"*)
    C='[{"id":90,"user":{"login":"agent"},"body":"<!-- pr-review verdict=READY head=9999999999999999999999999999999999999999 -->"}'
    [ "${M_CLAIM:-none}" = owned ] && C="$C,{\"id\":91,\"user\":{\"login\":\"agent\"},\"body\":\"babysit: session=babysit-pr-x heartbeat=2000-01-01T00:00:00Z\"}"
    [ -n "${M_BODY:-}" ] && C="$C,{\"id\":92,\"user\":{\"login\":\"${M_USER:-owner}\"},\"body\":\"$M_BODY\"}"
    echo "$C]" ;;
  *closingIssuesReferences*)
    printf '{"data":{"repository":{"pullRequest":{"assignees":{"nodes":[]},"closingIssuesReferences":{"nodes":[{"repository":{"nameWithOwner":"%s"},"assignees":{"nodes":[{"login":"%s"}]}}]}}}}}' "${M_CLOSES_REPO:-o/r}" "${M_ASSIGNEE:-dev}" ;;
  *reviewThreads*)
    if [ -n "${M_THREAD:-}" ]; then
      printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"start":{"nodes":[{"author":{"login":"%s"}}]},"comments":{"nodes":[{"databaseId":5,"author":{"login":"%s"}}]}}]}}}}}' "$M_THREAD" "$M_THREAD"
    else echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}'; fi ;;
  *) echo '[]' ;;
esac
EOF
chmod +x "$MEN"
mrun() { run PR_AGENT_HANDLE=@agent GH_BIN="$MEN" "$@"; }
OUT="$(M_BODY='@agent fix: please rename the helper' mrun)"
check  "$OUT" "would spawn babysit for o/r#9" "command: '<handle> fix' dispatches a fix round"
refute "$OUT" "would spawn review for o/r#9" "command: '<handle> fix' does not dispatch the review bot"
OUT="$(M_BODY='@agent review' mrun)"
check  "$OUT" "would spawn review for o/r#9" "command: '<handle> review' dispatches the review bot"
refute "$OUT" "would spawn babysit for o/r#9" "command: '<handle> review' does not dispatch a fix round"
OUT="$(M_BODY='@agent fix' M_CLAIM=owned mrun)"
check  "$OUT" "would spawn babysit for o/r#9" "command: runs under a sweep-owned claim"
OUT="$(M_BODY='@agent please rename the helper' mrun)"
refute "$OUT" "would spawn" "command: free text after the handle is not a command"
OUT="$(M_BODY='@agent fix?' mrun)"
refute "$OUT" "would spawn" "command: a question is not a command"
OUT="$(M_USER=agent M_BODY='@agent fix' mrun)"
refute "$OUT" "would spawn babysit for o/r#9" "command: the bot's own comment never triggers"
OUT="$(M_USER=stranger M_BODY='@agent fix' mrun)"
refute "$OUT" "would spawn" "trust: a stranger's command is ignored"
OUT="$(M_USER=dev M_BODY='@agent fix' mrun)"
check  "$OUT" "would spawn babysit for o/r#9" "trust: an assignee of the issue the PR closes may command the bots"
OUT="$(M_USER=dev M_ASSIGNEE=someone-else M_BODY='@agent fix' mrun)"
refute "$OUT" "would spawn" "trust: someone who is not assigned may not"
OUT="$(M_USER=dev M_CLOSES_REPO=x/y M_BODY='@agent fix' mrun)"
refute "$OUT" "would spawn" "trust: assignees of an issue in another repository are not people of the PR"
OUT="$(M_THREAD=owner mrun)"
check  "$OUT" "review comment(s) have no answer" "threads: an owner's open review thread sends a ready PR back to the fix bot"
OUT="$(M_THREAD=copilot-pull-request-reviewer mrun)"
check  "$OUT" "review comment(s) have no answer" "threads: a bot reviewer's thread counts (GraphQL drops the [bot] suffix)"
OUT="$(M_THREAD=stranger mrun)"
refute "$OUT" "review comment(s) have no answer" "threads: a stranger's review thread changes nothing"
refute "$OUT" "would spawn babysit" "threads: a stranger's review thread starts no fix round"

# Shared author limit and quiet hours (scripts/pipeline_runtime.py). A live "hermes" process stands in for a
# running work session of the delivery pipeline (alive() reads /proc/<pid>/cmdline).
"$PY" -c 'import time; time.sleep(60)' hermes-stand-in & LIVE=$!
mkdir -p "$TMP/pipe"; echo "{\"kind\":\"work\",\"item\":1,\"reason\":\"start\",\"ts\":0,\"pid\":$LIVE}" > "$TMP/pipe/dispatches.jsonl"
OUT="$(M_BODY='@agent fix' mrun PIPELINE_WIP=1 PIPELINE_STATE="$TMP/pipe")"
refute "$OUT" "would spawn babysit for o/r#9" "shared WIP: a live work session holds the only author slot"
check  "$OUT" "your fix request waits for a free bot" "shared WIP: a waiting owner command is told why"
OUT="$(run GH_BIN="$BOT" PIPELINE_WIP=1 PIPELINE_STATE="$TMP/pipe")"
refute "$OUT" "would spawn babysit for o/r#7" "shared WIP: a bot-review round waits for a free slot"
refute "$OUT" "no bot is due to act" "shared WIP: a waiting fix round is not reported as stalled"
OUT="$(M_BODY='@agent fix' mrun PIPELINE_WIP=2 PIPELINE_STATE="$TMP/pipe")"
check  "$OUT" "would spawn babysit for o/r#9" "shared WIP: a free slot starts the fix round"
kill "$LIVE" 2>/dev/null || true
OUT="$(M_BODY='@agent fix' mrun PIPELINE_QUIET_HOURS=00:00-00:00)"
refute "$OUT" "would spawn" "quiet hours: no session starts"
OUT="$(M_BODY='@agent fix' mrun PIPELINE_QUIET_HOURS=00:00-00:00 PIPELINE_FORCE=1)"
check  "$OUT" "would spawn babysit for o/r#9" "quiet hours: PIPELINE_FORCE=1 overrides"

# Every repository failing: one alert, silence within the hour, then one recovery line (not a dry run).
printf '#!/usr/bin/env bash\necho "[]"\n' > "$TMP/gh-empty"; chmod +x "$TMP/gh-empty"
real() { run PR_SWEEP_DRY= PR_SWEEP_STATE="$TMP/real" "$@"; }
OUT="$(real GH_BIN="$TMP/missing-gh" || true)"
check  "$OUT" "PR sweep stopped since" "stopped: the first failing tick alerts"
OUT="$(real GH_BIN="$TMP/missing-gh" || true)"
refute "$OUT" "stopped" "stopped: the next failing tick within the hour is silent"
OUT="$(real GH_BIN="$TMP/gh-empty" PIPELINE_QUIET_HOURS=00:00-00:00)"
refute "$OUT" "runs again" "stopped: a quiet tick ran nothing, so it reports no recovery"
OUT="$(real GH_BIN="$TMP/gh-empty")"
check  "$OUT" "PR sweep runs again" "stopped: the first good tick says it runs again"
OUT="$(real GH_BIN="$TMP/gh-empty" PR_SWEEP_REPOS="o/r o/s" PIPELINE_QUIET_HOURS=late PR_SWEEP_STATE="$TMP/real-cfg" || true)"
check  "$OUT" "PR sweep stopped since" "stopped: malformed quiet hours stop every repository, so they alert"
OUT="$(M_USER=helper M_BODY='@agent review' mrun PIPELINE_RESPONDERS=helper)"
check  "$OUT" "would spawn review for o/r#9" "trust: a configured responder may command the bots"


# A fix round that answered the review without changing code (FIXED, same head, addressed_without_code)
# gets one fresh review of that head; without such a round, a finished review at the head is not repeated.
RES="$TMP/gh-res"
cat > "$RES" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "pr list"*) echo '[{"number":10,"title":"resolved","headRefName":"item/10","headRefOid":"1010101010101010101010101010101010101010","labels":[{"name":"fix-bot:queued"}],"isDraft":false}]' ;;
  *"issues/10/comments"*) echo "[{\"id\":100,\"user\":{\"login\":\"${R_USER:-agent}\"},\"body\":\"<!-- pr-review verdict=FIX head=1010101010101010101010101010101010101010 -->\"}]" ;;
  *closingIssuesReferences*) echo '{"data":{"repository":{"pullRequest":{"assignees":{"nodes":[{"login":"dev"}]},"closingIssuesReferences":{"nodes":[]}}}}}' ;;
  *) echo '[]' ;;
esac
EOF
chmod +x "$RES"
H=1010101010101010101010101010101010101010
rm -rf "$TMP/state"
round rev1 review 10 "$H" FIX
OUT="$(run GH_BIN="$RES")"
refute "$OUT" "would spawn review for o/r#10" "resolve-only: a finished review at this head is not repeated"
round bab1 babysit 10 "$H" FIXED '"verdict_id":100' '"addressed_without_code":true'
OUT="$(run GH_BIN="$RES")"
check  "$OUT" "would set o/r#10 label review-bot:queued" "resolve-only: a FIXED round with no push queues one re-review of the same head"
rm -rf "$TMP/state"
OUT="$(R_USER=stranger run GH_BIN="$RES")"
check  "$OUT" "would set o/r#10 label review-bot:queued" "trust: a verdict marker posted by a stranger is not a verdict"
OUT="$(R_USER=dev run GH_BIN="$RES")"
check  "$OUT" "would set o/r#10 label review-bot:queued" "trust: a verdict marker posted by an assignee is not a verdict either"
OUT="$(run GH_BIN="$RES")"
refute "$OUT" "would set o/r#10 label review-bot:queued" "trust: the bot's own verdict marker counts"
round rev1 review 10 "$H" FIX
round bab1 babysit 10 "$H" RELEASED '"verdict_id":100'
OUT="$(run GH_BIN="$RES")"
refute "$OUT" "would spawn review for o/r#10" "resolve-only: a round that fixed nothing does not trigger a re-review"
refute "$OUT" "would set o/r#10 label review-bot:queued" "resolve-only: a round that fixed nothing does not queue a re-review"
rm -rf "$TMP/state"


# PR #2 is queued, with an in-flight review record at this head; PR #4 is independently due later in the tick.
T3_FIXTURE="$ROOT/tests/spec-fixtures/session-launcher"
for state in live unknown asked; do
  STATE="$TMP/t3-$state"
  mkdir -p "$STATE"
  printf '{"ts":%s,"kind":"review","repo":"o/r","pr":2,"head":"2222222222222222222222222222222222222222","tag":"review-pr2-t3","pid":"t3:thread-test"}\n' \
    "$(date +%s)" > "$STATE/dispatches.jsonl"
  RC=0; OUT="$(run PR_SWEEP_STATE="$STATE" PIPELINE_STATE="$TMP/none" PIPELINE_FORCE=1 \
    PIPELINE_LAUNCHER=t3 T3_BIN="$T3_FIXTURE/t3" PATH="$T3_FIXTURE:$PATH" \
    HERMES_BIN="$TMP/not-hermes" T3_TEST_STATE="$state" 2>&1)" || RC=$?
  case "$state" in
    live|unknown) refute "$OUT" 'would spawn review for o/r#2' "T3 $state: running review is not retried" ;;
    asked) check "$OUT" 'would spawn review for o/r#2' 'T3 asked: the dispatch is eligible for retry' ;;
  esac
  case "$state" in
    live) check "rc=$RC;" 'rc=0;' 'T3 live: tick succeeds' ;;
    unknown)
      check "rc=$RC;" 'rc=1;' 'T3 unknown: tick exits 1'
      check "$(grep -Fi 'T3' <<<"$OUT" || true)" 'connection refused' 'T3 unknown: the reason names T3 and includes its diagnostic'
      check "$OUT" 'would spawn review for o/r#4' 'T3 unknown: another PR is still processed'
      ;;
    asked)
      WAIT_LINES="$(grep -F 'waiting for an answer' <<<"$OUT" || true)"
      check "lines=$(grep -c . <<<"$WAIT_LINES" || true);" 'lines=1;' 'T3 asked: prints one waiting line'
      check "$WAIT_LINES" 't3:thread-test' 'T3 asked: waiting line includes the handle'
      check "$WAIT_LINES" 'https://example.test/threads/thread-test' 'T3 asked: waiting line includes the link'
      ;;
  esac
done

# Both prompt templates must render with the placeholders spawn() supplies (a stray brace would
# crash every dispatch, and DRY mode never renders them).
if "$PY" - "$ROOT/scripts/pr-sweep-prompts" <<'PYEOF'
import sys, pathlib
kw = dict(repo="o/r", number=1, head="a" * 40, short_head="aaaaaaa", title="t", branch="b", checkout="/c",
          hermes="h", rename_step="", handle="@agent", result_file="/r", tag="t", artifacts_dir="/a", scripts_dir="/s",
          merge_state="CLEAN", merge_status="MERGEABLE", base_branch="main", base_sha="b" * 40,
          integrate_strategy="merge", signing="unknown", fix_loops=0, fix_loop_cap=3, bot_rounds=0, bot_cap=5,
          trigger="owner request", trusted_logins="owner, agent", comment_id=92)
for k in ("review", "babysit"):
    (pathlib.Path(sys.argv[1]) / f"{k}.md").read_text().format(**kw)
PYEOF
then PASS=$((PASS+1)); echo "  PASS: prompt templates render with spawn()'s placeholders"
else FAIL=$((FAIL+1)); echo "  FAIL: a prompt template does not render" >&2; fi

# Unit tests for the decisions behind this flow (tests/scripts/test_pr_sweep_*.py, the command parser and the comment checker).
for t in test_pr_sweep_dispatch test_pr_sweep_progress test_pr_sweep_transient_review test_pr_sweep_result_evidence test_pr_sweep_review_threads test_commands test_comment_style; do
  if UOUT="$(cd "$ROOT/tests/scripts" && "$PY" -m unittest -q "$t" 2>&1)"; then
    PASS=$((PASS+1)); echo "  PASS: unit tests: $t ($(grep -Eo 'Ran [0-9]+ tests' <<<"$UOUT"))"
  else
    FAIL=$((FAIL+1)); echo "  FAIL: unit tests: $t" >&2; printf '%s\n' "$UOUT" >&2
  fi
done

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
