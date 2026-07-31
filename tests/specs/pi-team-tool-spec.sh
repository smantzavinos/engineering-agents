#!/usr/bin/env bash
# Verify the deterministic Pi team plan compiler, board initializer, and review bundler.
# Requirement: FR-002, OPR-001
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
require_commands node jq git cmp >/dev/null

ROOT="$(repo_root)"
TOOL="$ROOT/tools/pi-team.mjs"
FIXTURES="$(tests_dir)/spec-fixtures/pi-team"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
run_status() { local expected="$1"; shift; set +e; "$@" >"$TMP/out" 2>"$TMP/err"; local got=$?; set -e; [[ "$got" == "$expected" ]] || { cat "$TMP/out" "$TMP/err" >&2; fail "expected exit $expected, got $got: $*"; }; }

run_status 0 node "$TOOL" check "$FIXTURES/valid-diamond.md" --json
cp "$TMP/out" "$TMP/valid-1.json"
run_status 0 node "$TOOL" check "$FIXTURES/valid-diamond.md" --json
cmp -s "$TMP/valid-1.json" "$TMP/out" || fail 'JSON output is not byte deterministic'
node - "$FIXTURES/valid-diamond.md" "$TMP/reordered.md" <<'NODE'
const fs=require('fs');const lines=fs.readFileSync(process.argv[2],'utf8').trimEnd().split('\n');const start=lines.findIndex(l=>l.startsWith('| T'));const rows=lines.splice(start).sort().reverse();fs.writeFileSync(process.argv[3],[...lines,...rows,''].join('\n'));
NODE
run_status 0 node "$TOOL" check "$TMP/reordered.md" --json
cmp -s "$TMP/valid-1.json" "$TMP/out" || fail 'shuffled task rows changed compiled JSON'
jq -e '
  .schemaVersion == 1 and .valid == true and .diagnostics == [] and
  .metrics == {serialEstimateMin:10,criticalPathMin:6,criticalPathRatio:0.6,largestCriticalTask:{id:"T1",estimateMin:1,criticalPathShare:(1/6)}} and
  (.tasks | map(.id)) == ["T1","T2","T3","T4","T5","T6","T7","T8","T9","T10"] and
  (.waves | map(.taskIds)) == [["T1","T9","T10"],["T2"],["T3","T5"],["T4","T6"],["T7"],["T8"]] and
  (.waves[-1].integrationGroups == ["G1"]) and
  (.tasks[0].deps == [] and .tasks[0].riskLabels == ["api-contract"])
' "$TMP/valid-1.json" >/dev/null || fail 'valid diamond metrics/waves/task schema mismatch'
pass 'valid diamond emits deterministic metrics, waves, and natural task order'

node -e 'const x=JSON.parse(require("fs").readFileSync(process.argv[1]));process.stdout.write(x.tasks.find(t=>t.id==="T1").content)' "$TMP/valid-1.json" >"$TMP/packet"
cat >"$TMP/expected-packet" <<'PACKET'
# Plan task T1

Lane: complex
Estimate min: 1
Integration: G1

## Deliverable
Establish the root behavior

## Write set
- sandbox/t1.txt

## Contracts
- C1: Preserve the contract | Evidence: Targeted spec

## Decisions
- D1: Use deterministic order | Resolution: Numeric task IDs

## Minimal check
K1: node --check tools/pi-team.mjs

## Worker rules
- Modify only the declared write set.
- Use structured edit/write tools; do not mutate files through bash.
- Run only the minimal check above.
- Do not commit or run broad gates.
- Record concise progress and complete the Crew task with evidence.
PACKET
cmp -s "$TMP/packet" "$TMP/expected-packet" || { diff -u "$TMP/expected-packet" "$TMP/packet" >&2 || true; fail 'packet bytes differ'; }
[[ "$(node -e 'const x=JSON.parse(require("fs").readFileSync(process.argv[1]));process.stdout.write(String(x.tasks.find(t=>t.id==="T1").content.endsWith("\n")))' "$TMP/valid-1.json")" == true ]] || fail 'packet lacks LF termination'
pass 'task content matches the reviewed packet byte-for-byte'

for fixture in cycle dangling invalid-lane invalid-risk invalid-path zero-estimate missing-worker-check missing-integration-check missing-final-check unsupported-schema malformed-table; do
  run_status 2 node "$TOOL" check "$FIXTURES/$fixture.md" --json
  jq -e '.valid == false and .metrics == null and .waves == [] and .tasks == [] and (.diagnostics | length > 0) and all(.diagnostics[]; (.code|startswith("PLAN_")) and (.location.row|type)=="number")' "$TMP/out" >/dev/null || fail "$fixture malformed diagnostic contract"
done
for fixture in write-overlap threshold-failure; do
  run_status 1 node "$TOOL" check "$FIXTURES/$fixture.md" --json
  jq -e '.valid == false and .metrics != null and (.waves|length)>0 and (.tasks|length)>0 and all(.diagnostics[]; .code|startswith("GATE_"))' "$TMP/out" >/dev/null || fail "$fixture gate diagnostic contract"
done
pass 'malformed plans exit 2 and gate-only plans exit 1 with stable JSON shapes'

cp "$FIXTURES/valid-diamond.md" "$TMP/trailing-text.md"; printf 'trailing text\n' >>"$TMP/trailing-text.md"; run_status 2 node "$TOOL" check "$TMP/trailing-text.md" --json
sed 's/Preserve the contract/Preserve \\| the contract/' "$FIXTURES/valid-diamond.md" >"$TMP/escaped-pipe.md"; run_status 2 node "$TOOL" check "$TMP/escaped-pipe.md" --json
sed '/## Decisions/i ## Contracts' "$FIXTURES/valid-diamond.md" >"$TMP/duplicate-section.md"; run_status 2 node "$TOOL" check "$TMP/duplicate-section.md" --json
pass 'trailing task text, embedded pipes, and duplicate sections are rejected'

sed -e 's/| T3 | T2 | std |/| T3 | T2 | bogus |/' -e 's/| T5 | T2 | visual-complex | 1 | auth |/| T5 | T2 | visual-complex | 1 | bogus |/' "$FIXTURES/cycle.md" >"$TMP/multiple-diagnostics.md"
run_status 2 node "$TOOL" check "$TMP/multiple-diagnostics.md" --json
node - "$TMP/out" <<'NODE' || fail 'multiple diagnostics are not contract-sorted'
const fs=require('fs'); const d=JSON.parse(fs.readFileSync(process.argv[2])).diagnostics;
const sorted=[...d].sort((a,b)=>a.code.localeCompare(b.code)||a.location.section.localeCompare(b.location.section)||a.location.row-b.location.row||a.location.field.localeCompare(b.location.field)||a.message.localeCompare(b.message));
if(d.length < 2 || JSON.stringify(d)!==JSON.stringify(sorted)) process.exit(1);
NODE
[[ ! -s "$TMP/err" ]] || fail '--json wrote stderr'
run_status 2 node "$TOOL" check "$FIXTURES/cycle.md"
grep -Eq '^PLAN_[A-Z_]+: .+ \(.+\)$' "$TMP/err" || fail 'human diagnostic format missing'
run_status 2 node "$TOOL" check "$FIXTURES/missing-worker-check.md" --json
jq -e '(.diagnostics|length)>0 and (.diagnostics|map(.code)|unique) == ["PLAN_WORKER_CHECK"]' "$TMP/out" >/dev/null || fail 'missing-worker-check is not isolated'
run_status 1 node "$TOOL" check "$FIXTURES/threshold-failure.md" --json
jq -e '(.diagnostics|map(.code)) == ["GATE_CRITICAL_PATH_RATIO","GATE_CRITICAL_TASK_SHARE"]' "$TMP/out" >/dev/null || fail 'threshold fixture does not cover both threshold gates'
pass 'multiple diagnostics are sorted and isolated compiler gates are covered'

sed 's/$/\r/' "$FIXTURES/valid-diamond.md" >"$TMP/crlf.md"
run_status 0 node "$TOOL" check "$TMP/crlf.md" --json
cmp -s "$TMP/valid-1.json" "$TMP/out" || fail 'CRLF normalization changed output'
sed 's/T10/T100000000000000000000000/g' "$FIXTURES/valid-diamond.md" >"$TMP/huge-id.md"
run_status 0 node "$TOOL" check "$TMP/huge-id.md" --json
jq -e '.tasks[-1].id == "T100000000000000000000000"' "$TMP/out" >/dev/null || fail 'arbitrary-size numeric order failed'
pass 'CRLF and arbitrary-size numeric IDs are deterministic'

for bad in '../x' 'sandbox/*.txt' 'sandbox\\x' 'sandbox//x'; do
  sed "s#sandbox/t3.txt#$bad#" "$FIXTURES/valid-diamond.md" >"$TMP/bad-path.md"
  run_status 2 node "$TOOL" check "$TMP/bad-path.md" --json
done
mkdir -p "$TMP/path-root/sandbox"; ln -s real "$TMP/path-root/sandbox/link"; sed 's#sandbox/t3.txt#sandbox/link/file#' "$FIXTURES/valid-diamond.md" >"$TMP/path-root/plan.md"
(cd "$TMP/path-root" && run_status 2 node "$TOOL" check plan.md --json)
mkdir -p "$TMP/notdir-root"; printf 'not a directory\n' >"$TMP/notdir-root/sandbox"; sed 's#sandbox/t3.txt#sandbox/child#' "$FIXTURES/valid-diamond.md" >"$TMP/notdir-root/plan.md"
(cd "$TMP/notdir-root" && run_status 2 node "$TOOL" check plan.md --json)
[[ ! -s "$TMP/err" ]] || fail 'filesystem failure under --json wrote stderr'
jq -e '.schemaVersion==1 and .valid==false and (.diagnostics|map(.code))==["PLAN_IO"] and .metrics==null and .waves==[] and .tasks==[]' "$TMP/out" >/dev/null || fail 'filesystem failure did not emit one compiler schema object'
[[ "$(wc -l <"$TMP/out")" == 1 ]] || fail 'filesystem failure emitted more than one JSON object'
pass 'unsafe paths, symlinks, and public-boundary filesystem errors fail closed'

BOARD_REPO="$TMP/board-repo"; mkdir -p "$BOARD_REPO/plans" "$BOARD_REPO/.crew/agents"; cp "$FIXTURES/valid-diamond.md" "$BOARD_REPO/plans/plan.md"; printf '{}\n' >"$BOARD_REPO/.crew/config.json"; printf 'stable\n' >"$BOARD_REPO/.crew/agents/keep"
run_status 0 node "$TOOL" init-board "$BOARD_REPO/plans/plan.md" --crew-dir "$BOARD_REPO/.crew" --repo-root "$BOARD_REPO"
jq -e '.prd == "plans/plan.md" and .task_count == 0 and .completed_count == 0 and (.created_at == .updated_at) and (.created_at|test("Z$")) and (keys|sort)==["completed_count","created_at","prd","task_count","updated_at"]' "$BOARD_REPO/.crew/plan.json" >/dev/null || fail 'board record shape mismatch'
cmp -s "$BOARD_REPO/plans/plan.md" "$BOARD_REPO/.crew/plan.md" || fail 'runtime plan snapshot differs'
[[ -f "$BOARD_REPO/.crew/config.json" && -f "$BOARD_REPO/.crew/agents/keep" && ! -e "$BOARD_REPO/.crew/tasks" ]] || fail 'stable config changed or tasks created'
run_status 1 node "$TOOL" init-board "$BOARD_REPO/plans/plan.md" --crew-dir "$BOARD_REPO/.crew" --repo-root "$BOARD_REPO"
ISOLATED_CREW="$BOARD_REPO/isolated-crew"; mkdir "$ISOLATED_CREW"; printf 'sentinel\n' >"$ISOLATED_CREW/plan.json"
run_status 1 node "$TOOL" init-board "$BOARD_REPO/plans/plan.md" --crew-dir "$ISOLATED_CREW" --repo-root "$BOARD_REPO"
grep -qx sentinel "$ISOLATED_CREW/plan.json" || fail 'isolated plan.json runtime state overwritten'
[[ ! -e "$ISOLATED_CREW/plan.md" ]] || fail 'isolated plan.json refusal published plan.md'
cat >"$TMP/inject-init-collision.mjs" <<'NODE'
import fs from 'node:fs';
const link = fs.linkSync.bind(fs);
fs.linkSync = (source, target) => {
  if (target.endsWith('/plan.md')) {
    const record = target.slice(0, -'plan.md'.length) + 'plan.json';
    fs.unlinkSync(record);
    fs.writeFileSync(record, 'record-racer\n', { flag: 'wx' });
    fs.writeFileSync(target, 'plan-racer\n', { flag: 'wx' });
  }
  return link(source, target);
};
NODE
RACE_CREW="$BOARD_REPO/race-crew"
run_status 2 env NODE_OPTIONS="--import=$TMP/inject-init-collision.mjs" node "$TOOL" init-board "$BOARD_REPO/plans/plan.md" --crew-dir "$RACE_CREW" --repo-root "$BOARD_REPO"
grep -qx record-racer "$RACE_CREW/plan.json" || fail 'collision rollback removed or replaced racer plan.json inode'
grep -qx plan-racer "$RACE_CREW/plan.md" || fail 'collision publication removed or replaced racer plan.md inode'
run_status 2 node "$TOOL" init-board "$FIXTURES/valid-diamond.md" --crew-dir "$TMP/outside-board" --repo-root "$BOARD_REPO"
pass 'board init is no-clobber, rolls back only owned publications, and refuses unsafe state'

REVIEW="$TMP/review"; mkdir -p "$REVIEW/sandbox"; cp "$FIXTURES/valid-diamond.md" "$REVIEW/plan.md"; git -C "$REVIEW" init -q; git -C "$REVIEW" config user.email test@example.invalid; git -C "$REVIEW" config user.name Test
for n in {1..8} 10; do printf 'base-%s\n' "$n" >"$REVIEW/sandbox/t$n.txt"; done
git -C "$REVIEW" add .; git -C "$REVIEW" commit -qm base; BASE="$(git -C "$REVIEW" rev-parse HEAD)"; export BASE
printf 'tracked-change\n' >>"$REVIEW/sandbox/t1.txt"; printf '\000\001untracked\377' >"$REVIEW/sandbox/t9.txt"
[[ "$(git -C "$REVIEW" status --porcelain=v1 -- sandbox/t9.txt)" == '?? sandbox/t9.txt' ]] || fail 'binary review fixture is not truly untracked'
run_status 0 node "$TOOL" review-wave "$REVIEW/plan.md" --scope T1,T9,T10 --bundle T1,T9 --repo-root "$REVIEW" --base "$BASE" --output-dir "$TMP/evidence-1"
run_status 0 node "$TOOL" review-wave "$REVIEW/plan.md" --scope T1,T9,T10 --bundle T1,T9 --repo-root "$REVIEW" --base "$BASE" --output-dir "$TMP/evidence-2"
cmp -s "$TMP/evidence-1/manifest.json" "$TMP/evidence-2/manifest.json" || fail 'manifest not deterministic'
jq -e '.schemaVersion==1 and .base==env.BASE and (.tasks|map(.id))==["T1","T9"] and .tasks[0].changedPaths==["sandbox/t1.txt"] and .tasks[1].changedPaths==["sandbox/t9.txt"] and all(.tasks[]; .bytes>0 and (.sha256|test("^[0-9a-f]{64}$"))) and (.affectedGroups|map(.id))==["G1"] and (.affectedGroups[0].revision|test("^[0-9a-f]{64}$"))' "$TMP/evidence-1/manifest.json" >/dev/null || fail 'review manifest shape/content mismatch'
grep -q 'tracked-change' "$TMP/evidence-1/T1.diff" || fail 'tracked diff absent'; grep -q 'sandbox/t9.txt' "$TMP/evidence-1/T9.diff" || fail 'untracked binary diff absent'; grep -q '^new file mode ' "$TMP/evidence-1/T9.diff" || fail 'untracked binary did not use no-index evidence'; ! grep -q 'sandbox/t9.txt' "$TMP/evidence-1/T1.diff" || fail 'peer write set leaked into bundle'
pass 'review bundles tracked and truly untracked no-index binary changes with deterministic isolated evidence'

LITERAL="$TMP/literal-path-repo"; mkdir -p "$LITERAL"; sed 's#sandbox/t1.txt#:foo#' "$FIXTURES/valid-diamond.md" >"$LITERAL/plan.md"
printf 'base\n' >"$LITERAL/:foo"; git -C "$LITERAL" init -q; git -C "$LITERAL" config user.email test@example.invalid; git -C "$LITERAL" config user.name Test
git -C "$LITERAL" add .; git -C "$LITERAL" commit -qm base; LITERAL_BASE="$(git -C "$LITERAL" rev-parse HEAD)"; printf 'literal-change\n' >>"$LITERAL/:foo"
run_status 0 node "$TOOL" review-wave "$LITERAL/plan.md" --scope T1,T9,T10 --bundle T1 --repo-root "$LITERAL" --base "$LITERAL_BASE" --output-dir "$TMP/literal-evidence"
jq -e '.tasks[0].changedPaths==[":foo"] and .tasks[0].bytes>0' "$TMP/literal-evidence/manifest.json" >/dev/null || fail 'literal path evidence is empty or malformed'
grep -q 'literal-change' "$TMP/literal-evidence/T1.diff" || fail 'colon-prefixed path was interpreted as pathspec magic'
pass 'git path arguments are literal and changed paths cannot produce empty evidence'

DIGEST="$TMP/digest-repo"; mkdir -p "$DIGEST/sandbox/tree" "$DIGEST/sandbox/empty-dir"
sed -e 's#sandbox/t1.txt#sandbox/tree/#' -e 's#sandbox/t2.txt#sandbox/tree/file.txt#' -e 's#sandbox/t9.txt#sandbox/missing.txt#' -e 's#sandbox/t10.txt#sandbox/empty-dir/#' "$FIXTURES/valid-diamond.md" >"$DIGEST/plan.md"
printf 'tree-base\n' >"$DIGEST/sandbox/tree/file.txt"
for n in {3..8}; do printf 'digest-%s\n' "$n" >"$DIGEST/sandbox/t$n.txt"; done
git -C "$DIGEST" init -q; git -C "$DIGEST" config user.email test@example.invalid; git -C "$DIGEST" config user.name Test; git -C "$DIGEST" add .; git -C "$DIGEST" commit -qm base
DIGEST_BASE="$(git -C "$DIGEST" rev-parse HEAD)"; printf 'tree-change\n' >>"$DIGEST/sandbox/tree/file.txt"
run_status 0 node "$TOOL" review-wave "$DIGEST/plan.md" --scope T1,T9,T10 --bundle T1 --repo-root "$DIGEST" --base "$DIGEST_BASE" --output-dir "$TMP/digest-evidence"
EXPECTED_DIGEST="$(node - "$DIGEST" <<'NODE'
const crypto=require('crypto'),fs=require('fs'),path=require('path');
const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
const empty=hash(Buffer.alloc(0));
const records=[
  ['sandbox/empty-dir','directory',empty],
  ['sandbox/missing.txt','missing',empty],
  ...[3,4,5,6,7,8].map(n=>[`sandbox/t${n}.txt`,'file',hash(fs.readFileSync(path.join(process.argv[2],`sandbox/t${n}.txt`)))]),
  ['sandbox/tree','directory',empty],
  ['sandbox/tree/file.txt','file',hash(fs.readFileSync(path.join(process.argv[2],'sandbox/tree/file.txt')))],
].sort((a,b)=>a[0]<b[0]?-1:a[0]>b[0]?1:0);
process.stdout.write(hash(Buffer.concat(records.map(([name,type,digest])=>Buffer.from(`${name}\0${type}\0${digest}`)))));
NODE
)"
[[ "$(jq -r '.affectedGroups[0].revision' "$TMP/digest-evidence/manifest.json")" == "$EXPECTED_DIGEST" ]] || fail 'integration digest construction/content/missing/directory/dedup contract mismatch'
pass 'integration digest exactly covers content, missing paths, directories, and deduplicated records'

printf 'late-change\n' >>"$REVIEW/sandbox/t8.txt"
run_status 0 node "$TOOL" review-wave "$REVIEW/plan.md" --scope T1,T2,T3,T4,T5,T6,T7,T8,T9,T10 --bundle T8 --repo-root "$REVIEW" --base "$BASE" --output-dir "$TMP/remediation"
jq -e '(.tasks|length)==1 and .tasks[0].id=="T8" and .tasks[0].changedPaths==["sandbox/t8.txt"]' "$TMP/remediation/manifest.json" >/dev/null || fail 'scope/bundle remediation behavior mismatch'
[[ "$(jq -r '.affectedGroups[0].revision' "$TMP/evidence-1/manifest.json")" != "$(jq -r '.affectedGroups[0].revision' "$TMP/remediation/manifest.json")" ]] || fail 'integration digest ignored changed group content'
pass 'scope/bundle semantics and affected integration content digests support remediation'

ALL_TASKS=T1,T2,T3,T4,T5,T6,T7,T8,T9,T10
run_status 1 node "$TOOL" review-wave "$REVIEW/plan.md" --scope "$ALL_TASKS" --bundle T10 --repo-root "$REVIEW" --base "$BASE" --output-dir "$TMP/no-change"
grep -q 'REVIEW_NO_CHANGE' "$TMP/err" || fail 'no-change rejection used the wrong gate'
printf 'outside\n' >"$REVIEW/outside.txt"; run_status 1 node "$TOOL" review-wave "$REVIEW/plan.md" --scope "$ALL_TASKS" --bundle T1 --repo-root "$REVIEW" --base "$BASE" --output-dir "$TMP/out-of-set"; grep -q 'REVIEW_OUT_OF_SCOPE' "$TMP/err" || fail 'out-of-set rejection used the wrong gate'; rm "$REVIEW/outside.txt"
node -e 'const fs=require("fs"),c=require("crypto"),chunks=[];for(let i=0,n=0;n<150000;i++){const b=c.createHash("sha256").update(String(i)).digest();chunks.push(b);n+=b.length}fs.writeFileSync(process.argv[1],Buffer.concat(chunks).subarray(0,150000))' "$REVIEW/sandbox/t9.txt"; run_status 1 node "$TOOL" review-wave "$REVIEW/plan.md" --scope "$ALL_TASKS" --bundle T9 --repo-root "$REVIEW" --base "$BASE" --output-dir "$TMP/oversize"
grep -q 'REVIEW_OVERSIZE' "$TMP/err" || fail 'oversize rejection used the wrong gate'
git -C "$REVIEW" add sandbox/t1.txt; git -C "$REVIEW" commit -qm worker-commit; run_status 1 node "$TOOL" review-wave "$REVIEW/plan.md" --scope "$ALL_TASKS" --bundle T9 --repo-root "$REVIEW" --base "$BASE" --output-dir "$TMP/head-drift"
grep -q 'REVIEW_HEAD_MISMATCH' "$TMP/err" || fail 'HEAD drift rejection used the wrong gate'
run_status 1 node "$TOOL" review-wave "$REVIEW/plan.md" --scope "$ALL_TASKS" --bundle T9 --repo-root "$REVIEW" --base "$(git -C "$REVIEW" rev-parse HEAD)" --output-dir "$TMP/evidence-1"
grep -q 'REVIEW_OUTPUT_EXISTS' "$TMP/err" || fail 'existing-output rejection used the wrong gate'
pass 'review rejects no-change, out-of-set, oversize, HEAD drift, and existing output'

printf '\nPi team tool results: %d passed\n' "$PASS"
