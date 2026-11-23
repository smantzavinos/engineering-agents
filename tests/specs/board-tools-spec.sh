#!/usr/bin/env bash
# Board tools: scripts/gh-project.py (GitHub Project v2 tracker adapter), scripts/board-sync.py (script-only
# board hygiene) and scripts/commands.py (owner command parser). No network: unit tests patch gh/graphql with an
# in-memory fake, and the CLI checks drive the scripts end to end through the same fake as GH_BIN.
# Proves: the tracker CLI contract (list JSON with internal names; move compare-and-set fails with "is no longer";
# a move into Your turn needs a comment; set Waiting for), board names accepted, Up next/Canceled guards, fields,
# labels, migrate-your-turn, intake (bot-created -> Inbox, others -> Backlog), closed -> Done/Canceled,
# close-proposal close/keep/auto-close, PR links, PR cards and labels, PR assignment, Waiting for reconciliation,
# the owner digest, unheard replies (scripts/unheard.py), and every bot comment starting 🤖.
# Requirement: FR-001
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PY="$(command -v python3 || true)"
if [[ -z "$PY" ]]; then echo "  FAIL: python3 not on PATH (run inside nix develop)" >&2; exit 1; fi
PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1" >&2; }
check() { if grep -Fq -- "$2" <<<"$1"; then ok "$3"; else bad "$3 (missing: $2)"; fi; }

if "$PY" -m py_compile "$ROOT/scripts/gh-project.py" "$ROOT/scripts/board-sync.py" "$ROOT/scripts/commands.py" \
    "$ROOT/scripts/unheard.py" "$ROOT/scripts/pipeline_runtime.py"; then
  ok "scripts compile"
else
  bad "scripts do not compile"
fi

for t in test_gh_project test_board_sync test_unheard; do
  if OUT="$(cd "$ROOT/tests/scripts" && "$PY" -m unittest -q "$t" 2>&1)"; then
    ok "unit tests: $t ($(grep -Eo 'Ran [0-9]+ tests' <<<"$OUT"))"
  else
    bad "unit tests: $t"; printf '%s\n' "$OUT" >&2
  fi
done

# ---- CLI end to end through a fake gh (state in a JSON file)
export FAKE_GH_STATE="$TMP/board.json"
"$PY" - "$ROOT/tests/scripts" "$FAKE_GH_STATE" <<'PYEOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from fake_github import FakeBoard
b = FakeBoard()
b.add_issue(5, '🤖 In progress', title='five')
b.add_issue(6, '🧑 Your turn', title='six')
b.comment(6, 'bot', '🤖 **Needs your approval: plan**\n<!-- gate stage=Plan head=a branch=b plan=p -->')
b.add_issue(7, on_board=False, body='<!-- bot-created source=o/r#1 -->')
json.dump(b.__dict__, open(sys.argv[2], 'w'), ensure_ascii=False)
PYEOF
printf '#!/usr/bin/env bash\nexec %q %q "$@"\n' "$PY" "$ROOT/tests/scripts/fake_github.py" > "$TMP/gh"
chmod +x "$TMP/gh"
gp() { env PIPELINE_REPO=o/r GH_PROJECT_NUMBER=1 GH_BIN="$TMP/gh" PIPELINE_OWNERS=owner PIPELINE_BOT_LOGINS=bot \
         BOARD_SYNC_STATE="$TMP/state" "$PY" "$ROOT/scripts/$1" "${@:2}"; }

OUT="$(gp gh-project.py list)"
check "$OUT" '"status": "In progress"' "list prints internal status names"
check "$OUT" '"autonomy": "gated"' "list carries the item fields"

if OUT="$(gp gh-project.py move 5 'Your turn' --comment why --expect Inbox 2>&1)"; then
  bad "move with a stale --expect must fail"
else
  check "$OUT" "is no longer" "move --expect is compare-and-set (message says 'is no longer')"
fi
if OUT="$(gp gh-project.py move 5 'Your turn' 2>&1)"; then
  bad "move into Your turn without --comment must fail"
else
  check "$OUT" "requires an audit comment" "move into Your turn needs --comment"
fi
if OUT="$(gp gh-project.py move 5 'Up next' 2>&1)"; then
  bad "move into Up next without --ack-reply must fail"
else
  check "$OUT" "owner-controlled" "Up next needs --ack-reply"
fi
OUT="$(gp gh-project.py move 5 '🧑 Your turn' --comment 'Needs your help: blocked' --expect '🤖 In progress')"
check "$OUT" '"value": "Your turn"' "move accepts board names for the status and --expect"
gp gh-project.py set 5 'Waiting for' unblock >/dev/null
OUT="$(gp gh-project.py list)"
check "$OUT" '"waiting_for": "🛠️ unblock"' "set N 'Waiting for' VALUE writes the display field"
gp gh-project.py set 5 'Waiting for' '' >/dev/null
check "$(gp gh-project.py list)" '"waiting_for": ""' "set with an empty value clears it"
check "$(grep -o '🤖 Needs your help: blocked' "$FAKE_GH_STATE" || true)" "🤖 Needs your help" "the audit comment is posted with the 🤖 prefix"

BEFORE="$(cat "$FAKE_GH_STATE")"
OUT="$(gp gh-project.py fields --dry)"
check "$OUT" "Status: colours, descriptions or order (DRY)" "fields --dry plans the Status colours and descriptions"
if [[ "$(cat "$FAKE_GH_STATE")" == "$BEFORE" ]]; then ok "fields --dry writes nothing"; else bad "fields --dry wrote to the board"; fi
gp gh-project.py fields >/dev/null
check "$(gp gh-project.py fields)" "Status: up to date" "fields applies, reads back, and a second run is up to date"
OUT="$(gp gh-project.py labels --dry)"
check "$OUT" "create review-bot:queued" "labels --dry plans the workflow labels"

OUT="$(gp board-sync.py --dry)"
check "$OUT" "1 to 🤖 Inbox" "board-sync --dry: a bot-created issue goes to Inbox"
check "$OUT" "#6: Waiting for empty -> 👍 approve" "board-sync --dry: Waiting for follows the newest bot marker"
gp board-sync.py >/dev/null
OUT="$(gp gh-project.py list)"
check "$OUT" '"waiting_for": "👍 approve"' "board-sync sets Waiting for on a Your turn card"
check "$OUT" '"number": 7' "board-sync adds the bot-created issue to the board"
OUT="$(gp board-sync.py --digest)"
check "$OUT" "item(s) waiting on you" "board-sync --digest lists what waits on a person"
check "$OUT" "#6 " "board-sync --digest names the waiting card"
OUT="$(gp unheard.py --dry)"
if [[ "$OUT" != *Traceback* && "$OUT" != *FAILED* ]]; then ok "unheard.py --dry runs end to end"; else bad "unheard.py --dry crashed"; printf '%s\n' "$OUT" >&2; fi

if OUT="$(env -u PIPELINE_REPO -u GH_PROJECT_CONFIG "$PY" "$ROOT/scripts/gh-project.py" list 2>&1)"; then
  bad "gh-project.py without configuration must fail"
else
  check "$OUT" "gh-project: PIPELINE_REPO" "missing configuration fails with a clear message"
fi

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
