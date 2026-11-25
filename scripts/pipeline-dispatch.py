#!/usr/bin/env python3
"""Delivery-pipeline dispatcher: scheduled ticks for backlog items (no LLM).

One script, three jobs (docs/references/delivery-pipeline.md §5, §7):

  pipeline-dispatch.py triage    every ~15 min: Inbox / answered Your turn questions -> one triage session
  pipeline-dispatch.py work      every ~3 min: gate/unblock replies, dead sessions, Up next pickups
                                 under the WIP limit, worktree cleanup -> one work session per item
  pipeline-dispatch.py hygiene   weekly: report stale waiting states and unlabeled PRs (no sessions)

The tick decides WHO works on WHICH item, never how. Sessions run the `triage-backlog` and
`work-item` skills. stdout is the delivery to the human; empty stdout is a silent tick.

Install: copy this file, commands.py, comment_style.py, post-comment.py, pipeline_runtime.py,
session_launcher.py and pipeline-prompts/ into $HERMES_HOME/scripts/, then e.g.
  hermes cron create "every 15m" --no-agent --script "pipeline-dispatch.py triage" --name pipeline-triage
  hermes cron create "every 3m"  --no-agent --script "pipeline-dispatch.py work"   --name pipeline-work
  hermes cron create "every 7d"  --no-agent --script "pipeline-dispatch.py hygiene" --name pipeline-hygiene
Without Hermes: docs/t3/README.md (systemd timers, PIPELINE_LAUNCHER=t3).

Environment:
  PIPELINE_REPO           owner/repo whose issues are the backlog (required)
  PIPELINE_CHECKOUT       local checkout of that repo (required; tracker commands run here)
  PIPELINE_LIST_CMD       prints the backlog as a JSON array (required), each item:
                          {"number", "title", "status", "stage", "track", "priority", "autonomy", "updatedAt"}
                          plus "state" (OPEN/CLOSED): closed items still In review are included so the
                          work tick can complete T17 (merged PR closed the issue -> Done)
  PIPELINE_MOVE_CMD       moves an item (required); tokens {number} {status}. The dispatcher appends
                          `--comment <text>` (every move into Your turn carries one), `--expect <status>`
                          (compare-and-set: the tracker must fail with a message containing "is no longer"
                          when the card moved meanwhile) and `--ack-reply <comment id>` (the reply that
                          releases a card from Your turn). The same command with `move` replaced by `set`
                          sets a field: `... set <number> "Waiting for" <value>` (empty value clears).
                          Example: "python3 scripts/gh-project.py move {number} {status}"
  PIPELINE_OWNERS         logins whose comments count as replies (required; only owners approve gates)
  PIPELINE_RESPONDERS     extra logins whose `answer:` replies answer triage questions (assignees count too)
  PIPELINE_BRANCH_TEMPLATE  branch of a new item (default item/{n})
  PIPELINE_BOARD_NAMES    JSON map internal status -> board column name, for messages (default: internal names)
  PR_AGENT_HANDLE         agent handles replies start with (default /devbot; same vocabulary as the PR sweep)
  PIPELINE_BOT_LOGINS     logins the bot posts as, whose markers are trusted (default: the '@' handles,
                          the owners on a shared account, else the account `gh` is logged in as)
  PIPELINE_SHARED_ACCOUNT=1  the owner and the agent post from the same login. Replies are then
                          recognised by format alone: an owner-login comment counts only if it
                          carries no pipeline marker (`<!-- ... -->`, `work:`/`babysit:` claim lines).
                          Sessions must never start a comment with `<handle> <verb>`.
  PIPELINE_BASE           base branch for new item branches (default main)
  PIPELINE_WORKTREE_ROOT  where item worktrees live (default <checkout>-worktrees)
  PIPELINE_WIP            author sessions at once: work sessions plus the PR sweep's fix-bot rounds (default 2)
  PIPELINE_WIP_CODING     of those, new items started from Up next (default = PIPELINE_WIP); the rest is kept
                          for resumes after a reply and fix rounds
  PIPELINE_QUIET_HOURS    e.g. 22:00-07:00 (local time): no new sessions then; PIPELINE_QUIET_WEEKENDS=1 adds
                          weekends; PIPELINE_QUIET_MODES the jobs it applies to (default "work pr");
                          PIPELINE_FORCE=1 runs anyway
  PIPELINE_TRACKS         tracks eligible for pickup (default: all four)
  PIPELINE_PARK_LABEL     label that parks a `discuss` reply (default needs-human:discussion;
                          the pre-rename `pipeline:discuss` is still honoured)
  PIPELINE_TRIAGE_BATCH   max items per triage session (default 8; oldest first)
  PIPELINE_TRIAGE_MODEL, PIPELINE_TRIAGE_SKILLS (backlog,triage-backlog)
  PIPELINE_WORK_MODEL, PIPELINE_WORK_SKILLS (backlog,work-item), PIPELINE_REASONING (medium)
  PIPELINE_SESSION_PROVIDER  session provider (T3 provider instance id when using t3)
  PIPELINE_STALE_DAYS     hygiene threshold (default 3)
  PIPELINE_LAUNCHER       hermes (default) | t3
  T3_BIN, T3CODE_HOME     T3 executable (default t3) and data directory selecting the server
  PIPELINE_GIT_NAME, PIPELINE_GIT_EMAIL  optional local git commit identity, set before launching
  PIPELINE_STATE          state dir (default $HERMES_HOME/state/pipeline); PR_SWEEP_STATE (the PR sweep's, for WIP)
  PIPELINE_REPOSITORIES   one board, several repositories: a JSON object (or "repositories" in GH_PROJECT_CONFIG)
                          {"owner/repo": {"checkout": "/path", "base": "main", "branch_template": "item/{n}",
                          "worktree_root": "/path"}}. With more than one (or one with settings), each tick runs this
                          script once per repository, in turn, with that repository's PIPELINE_REPO, PIPELINE_CHECKOUT,
                          base and branch template (unset: PIPELINE_BASE / PIPELINE_BRANCH_TEMPLATE), worktree root and
                          state dir (PIPELINE_REPO, the primary, keeps PIPELINE_STATE and PIPELINE_WORKTREE_ROOT; the
                          others use PIPELINE_STATE/repositories/<owner>__<name> and <checkout>-worktrees), and prefixes
                          its output with [owner/repo]. Every job needs the same PIPELINE_REPO and board config.
                          PIPELINE_WIP and PIPELINE_WIP_CODING then hold across the board: live sessions of the other
                          repositories count. (PIPELINE_ONE_REPO and PIPELINE_BOARD_STATES are set for those runs.)
  HERMES_BIN, GH_BIN, GH_TOKEN_FILE (token file used when GH_TOKEN is unset)
  PIPELINE_DRY=1          print intended actions; mutate nothing, record nothing
"""
import fcntl
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import commands  # noqa: E402  (shared command parser, scripts/commands.py)
import pipeline_runtime  # noqa: E402  (quiet hours, shared WIP, stopped alerts: scripts/pipeline_runtime.py)
import session_launcher  # noqa: E402

ENV = os.environ


def _handles(raw):
    return tuple(h for h in (p.strip().lstrip("@").lower() for p in (raw or "").replace(",", " ").split()) if h)


def _tokens(raw):
    """Command handles are full tokens with their sigil (one rule for every script: commands.normalize_handles)."""
    return commands.normalize_handles(raw or "")


def _command_rest(line, handles):
    """The text after the command token when the line starts with one as a whole word followed by space, else None."""
    low = line.lower()
    for t in handles:
        if low.startswith(t) and len(line) > len(t) and line[len(t)].isspace():
            return line[len(t):]
    return None


_WHOAMI: list = []


def _whoami():
    """The login `gh` is logged in as (resolved once; '' when it cannot be read)."""
    if not _WHOAMI:
        try:
            _WHOAMI.append((gh("api", "user") or {}).get("login") or "")
        except (RuntimeError, OSError, ValueError, AttributeError):
            _WHOAMI.append("")
    return _WHOAMI[0]


def _logins(handles):
    """Logins whose comments are the bot's own: PIPELINE_BOT_LOGINS, the '@' handles, the owners on a
    shared account; otherwise the account `gh` is logged in as (a '/' handle names no account)."""
    return commands.bot_logins(BOT_LOGINS, handles, OWNERS, SHARED, whoami=_whoami)


REPO = ENV.get("PIPELINE_REPO", "")
CHECKOUT = pathlib.Path(ENV.get("PIPELINE_CHECKOUT", "."))
LIST_CMD = ENV.get("PIPELINE_LIST_CMD", "")
MOVE_CMD = ENV.get("PIPELINE_MOVE_CMD", "")
OWNERS = tuple(o.lower() for o in _handles(ENV.get("PIPELINE_OWNERS", "")))
# Extra logins whose `/devbot answer:` comments answer triage questions (the item's assignees always count too).
RESPONDERS = tuple(o.lower() for o in _handles(ENV.get("PIPELINE_RESPONDERS", "")))
HANDLES = _tokens(ENV.get("PR_AGENT_HANDLE", ""))
SHARED = (ENV.get("PIPELINE_SHARED_ACCOUNT") or "").strip().lower() not in ("", "0", "false", "no")
BOT_LOGINS = ENV.get("PIPELINE_BOT_LOGINS", "")
# Automation text on the shared owner account: an HTML marker, a 🤖 first line, or a claim line.
AGENT_MARK = re.compile(r"<!--|\A\s*🤖|^\s*(?:🤖\s*)?(work|babysit|fix-bot):\s", re.M)
BOT_PREFIX = "🤖 "


def bot_body(body):
    """Every comment the automation posts in the owner's name starts with the bot emoji."""
    return body if body.lstrip().startswith("🤖") else BOT_PREFIX + body
BASE = ENV.get("PIPELINE_BASE", "main")
WT_ROOT = pathlib.Path(ENV.get("PIPELINE_WORKTREE_ROOT", str(CHECKOUT) + "-worktrees"))
WIP = int(ENV.get("PIPELINE_WIP", "2"))
# New Up next pickups stop at this many live new-item sessions; the rest of WIP stays free for resumes and fix rounds.
WIP_CODING = min(WIP, int(ENV.get("PIPELINE_WIP_CODING") or WIP))
BRANCH_TEMPLATE = ENV.get("PIPELINE_BRANCH_TEMPLATE", "item/{n}")
TRACKS = tuple(ENV.get("PIPELINE_TRACKS", "fast-path standard-implementation analysis-spike docs-process").split())
PARK = ENV.get("PIPELINE_PARK_LABEL", "needs-human:discussion")
LEGACY_PARK = "pipeline:discuss"
TRIAGE_BATCH = int(ENV.get("PIPELINE_TRIAGE_BATCH", "8"))
TRIAGE_MODEL = ENV.get("PIPELINE_TRIAGE_MODEL", "")
TRIAGE_SKILLS = ENV.get("PIPELINE_TRIAGE_SKILLS", "backlog,triage-backlog")
WORK_MODEL = ENV.get("PIPELINE_WORK_MODEL", "")
WORK_SKILLS = ENV.get("PIPELINE_WORK_SKILLS", "backlog,work-item")
REASONING = ENV.get("PIPELINE_REASONING", "medium")
PROVIDER = ENV.get("PIPELINE_SESSION_PROVIDER", "")
STALE_DAYS = float(ENV.get("PIPELINE_STALE_DAYS", "3"))
DRY = bool(ENV.get("PIPELINE_DRY"))
HERMES = ENV.get("HERMES_BIN", "hermes")
GH = ENV.get("GH_BIN", "gh")
TOKEN_FILE = pathlib.Path(ENV.get("GH_TOKEN_FILE", "/nonexistent"))
HOME = pathlib.Path(ENV.get("HERMES_HOME", str(pathlib.Path.home())))
STATE = pathlib.Path(ENV.get("PIPELINE_STATE", str(HOME / "state" / "pipeline")))
# The PR sweep's state: its live fix-bot rounds share the PIPELINE_WIP limit with work sessions.
PR_STATE = pathlib.Path(ENV.get("PR_SWEEP_STATE", str(HOME / "state" / "pr-automation")))
DISPATCH, RESULTS, REPORTED, LOGS = STATE / "dispatches.jsonl", STATE / "results", STATE / "reported.json", STATE / "logs"
PROMPTS = pathlib.Path(__file__).resolve().parent / "pipeline-prompts"

MAX_FAILS = 3
PRIORITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
VERBS = ("approve", "revise:", "discuss", "reject", "unblock:", "answer:", "close", "keep")
GATE_RE = re.compile(r"<!--\s*gate stage=(\w+)((?:\s+\w+=\S+)*)\s*-->")
# What a bot's marker says it is waiting for; the newest marker wins. Close proposals are deliberately absent.
WAIT_MARKERS = [
    (GATE_RE, "approve"),
    (re.compile(r"<!--\s*(?:dispatcher )?blocked\b"), "unblock"),
    (re.compile(r"<!--\s*triage outcome=clarify\b[^>]*-->"), "answer"),
]
TRIAGE_RE = re.compile(r"<!--\s*triage outcome=(ready|clarify|left)\b[^>]*-->")
UNREAD_RE = re.compile(r"<!--\s*reply-unreadable comment=(\d+)\s*-->")

# A card sits in `Your turn` only while it is really a person's turn: a reply the bot can act on moves it to a bot
# column at once (even when no bot is free), and a card a person drags from `Your turn` to a bot column without
# such a reply is moved back with an explanation. What the person does is the kind of wait (see wait_kind).
# Reply verbs by kind of wait (see wait_kind); disjoint, so a reply fits exactly one question. `close`/`keep` answer
# close proposals only and are never here. decide/merge are answered on the PR (`fix`/`review`), not on the issue.
REPLY_VERBS = {"answer": ("answer",), "approve": ("approve", "revise", "discuss", "reject"), "unblock": ("unblock",)}
try:  # internal status -> board column name
    BOARD_NAMES = json.loads(ENV.get("PIPELINE_BOARD_NAMES") or "{}")
except ValueError:
    BOARD_NAMES = {}  # a broken display map must not stop the dispatcher; internal names are shown instead
WAITING_FOR = {"answer": "💬 answer", "approve": "👍 approve", "unblock": "🛠️ unblock",
               "decide": "⚖️ decide on PR", "merge": "🔀 merge PR"}  # kind -> board option (display only)
LAST_STATUS = STATE / "last-status.json"
MOVED = {}  # item -> status this tick moved it to (the next tick's baseline)

out = []  # lines delivered to the human
err_out = []  # failure lines: delivered once per pipeline_runtime.DEDUPE_TTL while they repeat
probe_errors: dict[session_launcher.Handle, str] = {}  # stopped reasons, reported after the tick's work


# ---------------------------------------------------------------- pure decisions

def parse_reply(comment, handles=HANDLES, owners=OWNERS, shared=None):
    """(verb, body) if the comment is an owner reply per the dispatch contract, else None.

    With a shared account (owner login == agent login), a comment from that login is a
    reply only if it carries no agent marker; agent sessions never write reply lines."""
    shared = SHARED if shared is None else shared
    login = ((comment.get("user") or {}).get("login") or "").lower()
    if login not in owners:
        return None
    if login in _logins(handles) and not (shared and not AGENT_MARK.search(comment.get("body") or "")):
        return None
    lines = [ln.strip() for ln in (comment.get("body") or "").splitlines() if ln.strip()]
    if not lines:
        return None
    found = commands.parse(lines[0], handles)  # spelling variants (`\devbot approved`) are normalised there
    if found is None or found[1] not in {v.rstrip(":") for v in VERBS}:
        return None
    body = "\n".join([found[2], *lines[1:]]).strip()
    return found[1], body


SAFE_PATH = re.compile(r"^[A-Za-z0-9._/-]+$")


def by_agent(comment, handles=HANDLES):
    return ((comment.get("user") or {}).get("login") or "").lower() in _logins(handles)


def latest_gate(comments, handles=HANDLES) -> Any:
    """(comment, stage, attrs) of the newest gate marker posted by the agent itself, or None.

    Markers from anyone else are ignored, so a commenter cannot forge a gate; `plan`
    must be a plain relative path."""
    for c in reversed(comments):
        m = GATE_RE.search(c.get("body") or "") if by_agent(c, handles) else None
        if m:
            attrs = dict(kv.split("=", 1) for kv in m.group(2).split())
            plan = attrs.get("plan", "")
            if plan and (not SAFE_PATH.match(plan) or ".." in plan.split("/") or plan.startswith("/")):
                attrs["plan"] = ""
            return c, m.group(1), attrs
    return None


def pending_reply(comments, after_id, consumed, allowed, owners=OWNERS) -> Any:
    """The first unconsumed owner reply with an allowed verb posted after comment `after_id`.

    `consumed` holds comment IDs already acted on for this item."""
    for c in comments:
        if c["id"] <= after_id or c["id"] in consumed:
            continue
        r = parse_reply(c, owners=owners)
        if r and r[0] in allowed:
            return c, r[0], r[1]
    return None


PROPOSE_LABEL = "needs-human:approve-close"
CLOSE_PROPOSAL_RE = re.compile(r"<!--\s*close-proposal\b(?!\s+dismissed)")
PROPOSAL_MARKER_RE = re.compile(r"<!--\s*(?:gate|triage|close-proposal|sync)")


def live_close_proposal(comments):
    """True when the newest marker comment of the agent is a close proposal that is not dismissed (a triage close
    proposal also carries `triage outcome=clarify`). Board sync answers close/keep for cards carrying the label."""
    for c in reversed(comments):
        if by_agent(c) and PROPOSAL_MARKER_RE.search(c.get("body") or ""):
            return bool(CLOSE_PROPOSAL_RE.search(c["body"]))
    return False


def open_questions(comments):
    """The comments holding the questions the card is waiting on: the newest triage clarify comment, only while it is
    still the current wait anchor (wait_kind == 'answer'). Empty when nothing is asked (an approval, a block, no
    triage yet): then no bot text may say it is waiting for answers. Reads ALL comments, like wait_kind."""
    kind, anchor = wait_kind(comments)
    return [anchor] if kind == "answer" and anchor else []


def open_questions_text(comments):
    """`<url>` of each open question comment, or `none` (the triage prompt text)."""
    return ", ".join(c.get("html_url") or f"comment {c['id']}" for c in open_questions(comments)) or "none"


def needs_triage(item, comments, owners=OWNERS):
    """Inbox with no triage marker yet, or Your turn waiting for an answer (kind answer) with a `<handle> answer:`
    reply after the question (every instruction is a command; a plain comment is context, not an answer)."""
    marks = [c["id"] for c in comments if by_agent(c) and TRIAGE_RE.search(c.get("body") or "")]
    if item["status"] == "Inbox":
        return not marks
    if item["status"] == "Your turn" and not in_pr_stage(item):
        kind, anchor = wait_kind(comments)
        if kind != "answer":
            return False
        return any(c["id"] > anchor["id"] and (parse_reply(c, owners=owners) or ("",))[0] == "answer" for c in comments)
    return False


def pickup_order(items, tracks=TRACKS):
    """Up next items eligible for pickup: Priority, then oldest (lowest number) first."""
    ups = [i for i in items if i["status"] == "Up next" and (i.get("track") or "") in tracks]
    return sorted(ups, key=lambda i: (PRIORITY_ORDER.get(i.get("priority") or "", 9), i["number"]))


def free_slots(items, wip=WIP):
    return max(0, wip - sum(1 for i in items if i["status"] == "In progress"))


def next_step(stage, verb):
    """Human-readable step for the session prompt (the work-item skill holds the full table)."""
    if verb == "unblock":
        return f"continue the blocked {stage or 'current'} stage with the reply"
    if verb == "revise":
        return f"rerun the {stage} stage with the reply, then gate again"
    return {"Design": "Plan", "Plan": "Execute",
            "Findings": "capture the approved follow-ups, then close the item as Done",
            "Escalation": "continue the stage that escalated, using the recommended answers"}.get(stage, stage)


def board_name(status):
    """The column name people see on the board (internal names stay in code, skills and markers)."""
    return BOARD_NAMES.get(status, status)


def in_pr_stage(item):
    """The PR stage: status In review, or Your turn with a linked open PR (same rule as gem-project.py)."""
    if "pr_stage" in item:
        return bool(item["pr_stage"])
    return item.get("status") == "In review" or (item.get("status") == "Your turn" and bool(item.get("prs")))


def review_status(label_sets):
    """What an issue in the PR stage waits for, from the labels of its open PRs: 'decide' or 'merge' (a person's
    turn, decide wins) or 'In review' (the review and fix bots')."""
    names = {name for labels in label_sets for name in labels}
    if any(n.startswith("needs-human:") and n != "needs-human:merge" for n in names) or "pr:escalated" in names:
        return "decide"
    if names & {"needs-human:merge", "pr:ready-merge"}:
        return "merge"
    return "In review"


def wait_kind(comments, label_sets=()) -> tuple[Any, Any]:
    """(kind, anchor comment or None) for a card waiting on a person.

    kind is 'approve' | 'unblock' | 'answer' | 'decide' | 'merge' | None. PR labels win (as review_status does);
    otherwise the newest marker posted by the agent itself decides, so a person cannot forge one. A newer triage
    outcome ready/left ends an older clarify question (nobody is waiting).
    Only the PR labels carry no anchor comment."""
    if label_sets:
        status = review_status(label_sets)
        if status in ("decide", "merge"):
            return status, None
    for c in reversed(comments):
        if not by_agent(c):
            continue
        t = TRIAGE_RE.search(c.get("body") or "")
        if t and t.group(1) != "clarify":
            return None, None  # triage moved on (ready/left): an older question is answered
        for rx, kind in WAIT_MARKERS:
            if rx.search(c.get("body") or ""):
                return kind, c
    return None, None


def owner_comment(comment, owners=OWNERS):
    """Written by a person: an owner login and (shared account) no automation marker."""
    return (((comment.get("user") or {}).get("login") or "").lower() in owners
            and not AGENT_MARK.search(comment.get("body") or ""))


def unreadable_reply(comments, kind, anchor, consumed, owners=OWNERS):
    """The newest owner comment after `anchor`, when it is not a reply the bot can act on here and has no notice yet."""
    if anchor is None:
        return None
    newest = next((c for c in reversed(comments) if c["id"] > anchor and owner_comment(c, owners=owners)), None)
    if newest is None or newest["id"] in consumed:
        return None
    if any(m and int(m.group(1)) == newest["id"] for c in comments if by_agent(c)
           for m in [UNREAD_RE.search(c.get("body") or "")]):
        return None
    r = parse_reply(newest, owners=owners)
    if r and r[0] in ("close", "keep"):
        return None  # board sync acts on replies to a close proposal
    return None if r and r[0] in REPLY_VERBS[kind] else newest


def reply_menu(kind):
    h = HANDLES[0]
    if kind == "unblock":
        return f"`{h} unblock: <what changed>`"
    if kind == "answer":
        return f"`{h} answer: <your answers>`"
    return f"`{h} approve`, `{h} revise: <changes>`, `{h} discuss` or `{h} reject`"


# ---------------------------------------------------------------- side effects

def env_clean():
    env = {k: v for k, v in ENV.items() if not k.startswith(("HERMES_CRON", "HERMES_SESSION"))}
    if "GH_TOKEN" not in env and TOKEN_FILE.exists():
        env["GH_TOKEN"] = TOKEN_FILE.read_text().strip()
    return env


def run(argv, cwd=None, parse=False) -> Any:
    # UTF-8 explicitly: comments and board names carry emoji; never rely on the platform default encoding.
    r = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env_clean(),
                       cwd=cwd, timeout=300)
    if r.returncode != 0:
        text = (r.stderr or r.stdout).strip()  # keep the end: a traceback names its error on the last line
        raise RuntimeError(f"{' '.join(argv[:4])} failed: {text if len(text) <= 600 else text[:120] + ' ... ' + text[-475:]}")
    if not (parse and r.stdout.strip()):
        return r.stdout
    try:
        return json.loads(r.stdout)
    except ValueError as e:
        raise RuntimeError(f"{' '.join(argv[:4])} printed invalid JSON: {e}") from e


def gh(*args, parse=True) -> Any:
    return run([GH, *args], parse=parse)


def list_items():
    items = run(shlex.split(LIST_CMD), cwd=str(CHECKOUT), parse=True)
    for i in items:
        i["number"] = int(i["number"])
    return items


def comments_of(n):
    pages = gh("api", "--paginate", "--slurp", f"repos/{REPO}/issues/{n}/comments?per_page=100")
    return [c for page in pages for c in page] if pages and isinstance(pages[0], list) else (pages or [])


_ASSIGNEES = {}


def assignees_of(n):
    """Lowercase assignee logins of issue n (cached per tick; empty on a read failure)."""
    if n not in _ASSIGNEES:
        try:
            data = gh("api", f"repos/{REPO}/issues/{n}")
            _ASSIGNEES[n] = tuple(((a or {}).get("login") or "").lower() for a in (data.get("assignees") or []))
        except Exception:  # noqa: BLE001 — the owner and configured responders still count
            _ASSIGNEES[n] = ()
    return _ASSIGNEES[n]


def responders_of(n):
    """Logins whose `answer:` comments answer triage questions on item n: owner, configured responders, assignees."""
    return tuple(dict.fromkeys((*OWNERS, *RESPONDERS, *assignees_of(n))))


def repliers(n, kind):
    """Logins whose reply to a `kind` wait counts: gate decisions (approve, revise, discuss, reject) are the
    owners' alone; answers and unblocks also come from configured responders and the item's assignees."""
    return OWNERS if kind == "approve" else responders_of(n)


def labels_of(n):
    # The pre-rename park label still parks (read as the current name).
    return [PARK if lbl["name"] == LEGACY_PARK else lbl["name"] for lbl in gh("api", f"repos/{REPO}/issues/{n}/labels")]


def move(n, status, comment=None, expect=None, ack=None):
    """Move item n. `expect`: only if it is still in that status (a person or a session may have moved it).
    `ack`: id of the owner reply that queues it in Up next (the tracker refuses Up next otherwise)."""
    if DRY:
        out.append(f"DRY: would move #{n} to {status}" + (" with comment" if comment else "")
                   + (f" (only if still {expect})" if expect else ""))
        return
    argv = [t.format(number=n, status=status) for t in shlex.split(MOVE_CMD)]
    run(argv + (["--comment", comment] if comment else []) + (["--expect", expect] if expect else [])
        + (["--ack-reply", str(ack)] if ack else []), cwd=str(CHECKOUT))
    MOVED[n] = status


def set_waiting_for(n, kind):
    """Best-effort display of what a person does in `Your turn` (the `Waiting for` field); kind None clears it.
    Never raises: errors go to `out`. Bots never read the field."""
    value = WAITING_FOR.get(kind, "") if kind else ""
    if DRY:
        out.append(f"DRY: would set Waiting for on #{n} to {value or 'empty'}")
        return
    try:
        argv = shlex.split(MOVE_CMD)
        argv = argv[:argv.index("move")] + ["set", str(n), "Waiting for", value]
        run(argv, cwd=str(CHECKOUT))
    except Exception as e:  # noqa: BLE001 — display only; board sync reconciles it
        out.append(f"#{n}: could not update 'Waiting for': {e}")


def try_move(n, status, comment=None, expect=None, ack=None, waiting=None):
    """move(), but a compare-and-set conflict (the item moved meanwhile) is a quiet no-op; returns whether it moved.
    Into `Your turn`: sets `Waiting for` to `waiting`; out of it (expect == `Your turn`): clears it."""
    try:
        move(n, status, comment=comment, expect=expect, ack=ack)
        if status == "Your turn":
            set_waiting_for(n, waiting)
        elif expect == "Your turn":
            set_waiting_for(n, None)
        return True
    except RuntimeError as e:
        if "is no longer" in str(e):
            return False
        raise


def discuss_note(n):
    """The comment that confirms a `discuss` reply and says how to talk it through (plain language)."""
    h = HANDLES[0]
    return (f"**Paused for a live discussion.** No bot works on this item while it has the `{PARK}` label.\n\n"
            f"- to talk: say `discuss {REPO}#{n}` in a Hermes chat\n"
            f"- to resume without a chat: remove the `{PARK}` label, then reply `{h} approve` or "
            f"`{h} revise: …`\n\n"
            f"<!-- dispatcher parked -->")


def comment_on(n, body):
    if DRY:
        out.append(f"DRY: would comment on #{n}: {body.splitlines()[0][:120]}")
        return
    gh("api", "-X", "POST", f"repos/{REPO}/issues/{n}/comments", "-f", f"body={bot_body(body)}", parse=False)


def react(comment_id):
    """Mark an owner reply as read (an eyes reaction GitHub shows right away)."""
    if DRY:
        out.append(f"DRY: would mark reply {comment_id} as read")
        return
    try:
        gh("api", "-X", "POST", f"repos/{REPO}/issues/comments/{comment_id}/reactions", "-f", "content=eyes", parse=False)
    except Exception as e:  # noqa: BLE001 — a missing reaction must never stop the reply from being handled
        err_out.append(f"could not mark reply {comment_id} as read: {e}")


def react_issue(n):
    """Eyes reaction on the issue description itself: visible on the issue page the moment a bot picks it up."""
    if DRY:
        out.append(f"DRY: would mark #{n} as picked up (eyes on the issue)")
        return
    try:
        gh("api", "-X", "POST", f"repos/{REPO}/issues/{n}/reactions", "-f", "content=eyes", parse=False)
    except Exception as e:  # noqa: BLE001 — a missing reaction must never stop triage from proceeding
        err_out.append(f"could not mark #{n} as picked up: {e}")


def load_last_status():
    """Each item's status at the end of the previous work tick: tells a person's drag from a bot's move."""
    try:
        return {int(k): v for k, v in json.loads(LAST_STATUS.read_text()).items()}
    except (OSError, ValueError, AttributeError):
        return {}


def save_last_status(items):
    if DRY:
        return
    data = {str(i["number"]): MOVED.get(i["number"], i["status"]) for i in items}
    tmp = LAST_STATUS.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, sort_keys=True))
    os.replace(tmp, LAST_STATUS)


def add_label(n, label):
    if DRY:
        out.append(f"DRY: would label #{n} {label}")
        return
    gh("api", "-X", "POST", f"repos/{REPO}/issues/{n}/labels", "-f", f"labels[]={label}", parse=False)


def alive(pid):
    reply = session_launcher.probe(ENV, pid, None if DRY else STATE)
    if reply["state"] == "asked":
        line = f"⚠️ Session {pid} is waiting for an answer, so it counts as failed: {reply['link']}".rstrip(": ")
        if line not in err_out:
            err_out.append(line)
    elif reply["state"] == "unknown":
        probe_errors[pid] = f"T3 could not check {pid}: {reply['detail']}"
    return reply["state"] in ("live", "unknown")


def branch_for(n):
    """Branch of item n. New items use PIPELINE_BRANCH_TEMPLATE (e.g. feature/item-{n}); an item that already has work on
    the legacy item/<n> branch (live worktree or pushed branch) keeps it, so in-flight items resume untouched."""
    new = BRANCH_TEMPLATE.format(n=n)
    legacy = f"item/{n}"
    if DRY:
        return new
    path = WT_ROOT / f"item-{n}"
    if path.exists():
        try:
            current = run(["git", "-C", str(path), "branch", "--show-current"]).strip()
        except Exception:  # noqa: BLE001
            current = ""
        if current:
            return current
    git = ["git", "-C", str(CHECKOUT)]
    if run(git + ["ls-remote", "--heads", "origin", new]).strip():
        return new
    if run(git + ["ls-remote", "--heads", "origin", legacy]).strip():
        return legacy
    return new


def sync_worktree(n, path, branch):
    """Fast-forward item n's worktree to origin/<branch>. A diverged worktree never blocks the item for good: when the
    local-only commits carry nothing origin lacks (same content, only line endings differ) and the tree is clean, HEAD is
    saved to refs/backup/item-<n>-<sha> and the branch is reset to origin; anything else is kept and explained."""
    wt = ["git", "-C", str(path)]
    remote = f"origin/{branch}"
    try:
        run(wt + ["merge", "--ff-only", "--quiet", remote])
        return
    except RuntimeError:
        pass
    head = run(wt + ["rev-parse", "HEAD"]).strip()
    backup = f"refs/backup/item-{n}-{head[:7]}"
    run(wt + ["update-ref", backup, head])
    dirty = bool(run(wt + ["status", "--porcelain", "--untracked-files=all"]).strip())
    same = not run(wt + ["diff", "--ignore-cr-at-eol", "HEAD", remote]).strip()
    if same and not dirty:
        run(wt + ["reset", "--hard", "--quiet", remote])
        out.append(f"#{n}: local {branch} diverged from origin by line endings only; reset to origin, old commit kept at {backup}")
        return
    local = run(wt + ["log", "--format=%h %s", f"{remote}..HEAD"]).strip().replace("\n", "; ")
    theirs = run(wt + ["log", "--format=%h %s", f"HEAD..{remote}"]).strip().replace("\n", "; ")
    behind_only = subprocess.run(wt + ["merge-base", "--is-ancestor", "HEAD", remote], capture_output=True).returncode == 0
    if behind_only:
        state = f"the local work copy of branch {branch} is behind the pushed branch, but uncommitted changes block the update"
    else:
        why = "it has uncommitted changes" if dirty else "its commits hold work that is not on origin"
        state = f"the local work copy of branch {branch} and the pushed branch have diverged and {why}"
    raise RuntimeError(
        f"{state}, so nothing was discarded "
        f"(local-only: {local or 'none'}; origin-only: {theirs or 'none'}; local HEAD saved at {backup}). "
        f"Publish or drop the local work in {path}, then rerun.")


def worktree(n, reason):
    """Path of item n's worktree on its branch (see branch_for), created from the pushed branch or the base."""
    path = WT_ROOT / f"item-{n}"
    if DRY:
        return path
    git = ["git", "-C", str(CHECKOUT)]
    branch = branch_for(n)
    if path.exists():  # bring it up to the pushed branch (a live discuss session may have pushed)
        run(git + ["fetch", "--quiet", "origin"])
        if run(git + ["ls-remote", "--heads", "origin", branch]).strip():
            sync_worktree(n, path, branch)
        return path
    run(git + ["fetch", "--quiet", "origin"])
    remote = run(git + ["ls-remote", "--heads", "origin", branch]).strip()
    if reason not in ("start", "unblock") and not remote:
        # An unblock may restart an item that never pushed anything (for example one that failed to start).
        raise RuntimeError(f"{branch} is not on origin; the gate should have pushed it")
    start = f"origin/{branch}" if remote else f"origin/{BASE}"
    WT_ROOT.mkdir(parents=True, exist_ok=True)
    run(git + ["worktree", "add", "-B", branch, str(path), start])
    return path


def spawn(kind, n, title, extra):
    tag = f"{kind}-item{n}-{int(time.time())}" if kind == "work" else f"triage-{int(time.time())}"
    if DRY:
        what = extra.get("reason") or extra.get("items")
        out.append(f"DRY: would spawn {kind} for #{n}" + (f" ({what})" if what else ""))
        return 0, tag
    if kind == "triage":  # who may answer; job_triage passes the per-item list
        extra = {"responders": ", ".join(f"@{o}" for o in OWNERS) or "the owner", "open_questions": "none", **extra}
    if "reply_body" in extra:  # keep untrusted text inside its fence
        extra = {**extra, "reply_body": re.sub(r"(?m)^\s*~{3,}", "", extra["reply_body"])}
    prompt = (PROMPTS / f"{kind}.md").read_text().format(
        repo=REPO, number=n, title=title, handle=HANDLES[0], tag=tag,
        result_file=str(RESULTS / f"{tag}.json"), checkout=str(CHECKOUT),
        scripts_dir=str(pathlib.Path(__file__).resolve().parent), **extra)
    pfile = LOGS / f"{tag}.prompt.md"
    pfile.write_text(prompt)
    # The repository is in the name: two repositories of one board may start a session in the same second.
    name = (f"{REPO} item #{n} {extra.get('reason', kind)} {tag} — {title[:50]}" if kind == "work"
            else f"Backlog triage {REPO} {tag}")
    model, skills = (WORK_MODEL, WORK_SKILLS) if kind == "work" else (TRIAGE_MODEL, TRIAGE_SKILLS)
    pid = session_launcher.launch(
        ENV, hermes_argv=[HERMES, "chat", "-Q", "--oneshot", "--query-file", str(pfile), "--source", "tool",
                          "--continue", name, "--create-if-missing", "--reasoning", REASONING, "-s", skills,
                          *(["-m", model] if model else []), *(["--provider", PROVIDER] if PROVIDER else [])],
        prompt_file=pfile, title=name, checkout=CHECKOUT, log_file=LOGS / f"{tag}.log",
        cwd=str(extra.get("worktree") or CHECKOUT), model=model, provider=PROVIDER, child_env=env_clean())
    return pid, tag


def load_records():
    """The dispatch log; a torn or corrupt line (e.g. a crash mid-write) is skipped, never fatal."""
    recs = []
    if DISPATCH.exists():
        for line in DISPATCH.read_text().splitlines():
            try:
                rec = json.loads(line) if line.strip() else None
            except ValueError:
                rec = None
            if isinstance(rec, dict):
                recs.append(rec)
    return recs


def record(recs, rec):
    recs.append(rec)
    if not DRY:
        with DISPATCH.open("a") as f:
            f.write(json.dumps(rec, sort_keys=True) + "\n")


def report_once(reported, key, line):
    if key not in reported:
        reported.add(key)
        out.append(line)


# ---------------------------------------------------------------- jobs

def job_triage(items, recs, reported):
    cache = {}

    def due_item(i):
        cache[i["number"]] = comments_of(i["number"])
        return needs_triage(i, cache[i["number"]], owners=responders_of(i["number"]))

    def answers_since_last_triage(n):
        marks = [c["id"] for c in cache[n] if by_agent(c) and TRIAGE_RE.search(c.get("body") or "")]
        last = marks[-1] if marks else 0
        who = responders_of(n)
        return [c for c in cache[n] if c["id"] > last and (parse_reply(c, owners=who) or ("",))[0] == "answer"]

    due = [i for i in items if i["status"] in ("Inbox", "Your turn") and due_item(i)]
    # A triage close proposal must carry the label board sync answers close/keep through: set here, not by the prompt.
    for i in items:
        n = i["number"]
        if n in cache and live_close_proposal(cache[n]):
            try:
                if PROPOSE_LABEL not in labels_of(n):
                    add_label(n, PROPOSE_LABEL)
            except Exception as e:  # noqa: BLE001 — board sync adds it too; never stop triage
                out.append(f"#{n}: could not label the close proposal: {e}")
    # The owner answered: it is the bot's turn now, even if a triage session is still busy with other items.
    # Mark the answer as read and take the card out of the person's column right away.
    for i in due:
        n = i["number"]
        if i["status"] != "Your turn":
            continue
        try:
            for c in answers_since_last_triage(n):
                react(c["id"])
            if try_move(n, "Inbox", expect="Your turn"):
                i["status"] = "Inbox"
        except Exception as e:  # noqa: BLE001 — the triage below still reads the answer
            out.append(f"#{n}: could not move it to {board_name('Inbox')} while a bot reads your answer: {e}")
    if any(r["kind"] == "triage" and r.get("pid") and alive(r["pid"]) for r in recs):
        return
    if not due:
        return
    nums = sorted(i["number"] for i in due)[:TRIAGE_BATCH]
    rec = {"ts": time.time(), "kind": "triage", "items": nums}
    try:
        rec["pid"], rec["tag"] = spawn("triage", nums[0], "triage", {
            "items": " ".join(f"#{n}" for n in nums),
            "responders": "; ".join(f"#{n}: " + ", ".join(f"@{w}" for w in responders_of(n)) for n in nums),
            "open_questions": "; ".join(f"#{n}: {open_questions_text(cache.get(n) or [])}" for n in nums)})
    except Exception as e:  # noqa: BLE001 — recorded; retried next tick
        rec["error"] = str(e)[:300]
    if not rec.get("error"):
        # Visible the instant it's picked up, even before the session posts its first comment.
        for n in nums:
            react_issue(n)
            for c in answers_since_last_triage(n):  # every answer this pass reads
                react(c["id"])
    record(recs, rec)


def dispatch_work(recs, item, reason, reply=None, reply_verb=None, stage=None, gate_attrs=None):
    """Start a work session; returns True when one was started (False: recorded as a failed dispatch)."""
    n = item["number"]
    rec = {"ts": time.time(), "kind": "work", "item": n, "reason": reason, "stage": stage or item.get("stage"),
           "reply_id": reply["id"] if reply else None, "verb": reply_verb,
           "reply_body": (reply or {}).get("_body", ""), "plan": (gate_attrs or {}).get("plan", "")}
    try:
        wt = worktree(n, reason)
        if item["status"] != "In progress":
            move(n, "In progress")
            if item["status"] == "Your turn":
                set_waiting_for(n, None)
        rec["pid"], rec["tag"] = spawn("work", n, item["title"], {
            "reason": reason, "worktree": str(wt), "branch": branch_for(n), "track": item.get("track") or "",
            "stage": stage or item.get("stage") or "", "autonomy": item.get("autonomy") or "gated",
            "reply_verb": reply_verb or "", "reply_body": (reply or {}).get("_body", ""),
            "plan_dir": (gate_attrs or {}).get("plan", ""),
            "next_step": next_step(stage, reply_verb) if reply_verb else "first step of the track"})
    except Exception as e:  # noqa: BLE001
        rec["error"] = str(e)[:300]
    record(recs, rec)
    return not rec.get("error")


def result_of(rec):
    try:
        return json.loads((RESULTS / f"{rec.get('tag')}.json").read_text())
    except (OSError, ValueError):
        return None


def failed(rec):
    """A dispatch failed: spawn error, or the session is gone with no result or an explicit failure."""
    if rec.get("error"):
        return True
    if rec.get("pid") and alive(rec["pid"]):
        return False
    res = result_of(rec)
    return res is None or res.get("outcome") == "failed"


def retry(recs, item, last):
    """Re-dispatch a failed session with everything it was given."""
    reply = {"id": last["reply_id"], "_body": last.get("reply_body", "")} if last.get("reply_id") else None
    dispatch_work(recs, item, last["reason"], reply=reply, reply_verb=last.get("verb"),
                  stage=last.get("stage"), gate_attrs={"plan": last.get("plan", "")})


def job_work(items, recs, reported):
    work = [r for r in recs if r["kind"] == "work"]
    running = {r["item"] for r in work if r.get("pid") and alive(r["pid"])}
    # An "ack" only records that a reply was read and queued; the reply is consumed when a bot starts on it.
    consumed = {(r["item"], r["reply_id"]) for r in recs if r.get("reply_id") and not r.get("error") and r["kind"] != "ack"}
    acks = {}
    for r in recs:
        if r["kind"] == "ack" and (r["item"], r["reply_id"]) not in consumed:
            acks[r["item"]] = r
    last = load_last_status()
    slots = free_slots(items)
    # Fix-bot rounds of the PR sweep share PIPELINE_WIP with work sessions (the In progress cards).
    # One board, several repositories: the other repositories' live sessions count too (their cards are not listed
    # here), and new-item sessions are counted across the board.
    board = pipeline_runtime.board_states(ENV, STATE)
    others = [d for d in board if pathlib.Path(d).resolve() != STATE.resolve()]
    slots = max(0, slots - len(pipeline_runtime.live_authors([PR_STATE, *others], alive)))
    coding = sum(1 for kind in pipeline_runtime.live_authors([STATE, *others], alive).values() if kind == "coding")
    errors = []
    h = HANDLES[0]

    def guarded(n, fn):
        try:
            return fn()
        except Exception as e:  # noqa: BLE001 — one item must not starve the rest of the tick
            errors.append(f"#{n}: {e}")
            return None

    def block(i, key, why):
        """A bot column item that no bot will move: hand it to the owner in Your turn, with what to do."""
        n = i["number"]
        body = (f"**Needs your help: a bot can't continue this item.**\n\n"
                f"- {why}\n"
                f"- reply `{h} unblock: <what to do>` to let a bot continue, or move the card to Later\n\n"
                f"<!-- dispatcher blocked reason={key.split(':')[0]} -->")
        if try_move(n, "Your turn", comment=body, expect=i["status"], waiting="unblock"):
            report_once(reported, key, f"#{n} moved to {board_name('Your turn')}: {why}")

    def resume_failed(i, ack):
        """True when resuming the queued reply `ack` failed MAX_FAILS times: the card goes to the owner (once; it
        leaves Up next). Counting is per reply, so a new owner reply starts at zero and a started session (the reply
        is consumed) ends the queue entry."""
        n = i["number"]
        fails = [r for r in recs if r["kind"] == "work" and r["item"] == n and r.get("reply_id") == ack["reply_id"] and r.get("error")]
        if len(fails) < MAX_FAILS:
            return False
        block(i, f"resumefail:{n}:{ack['reply_id']}", f"a bot failed {len(fails)} times to resume it after your reply "
              f"and stopped retrying (last error: `{(fails[-1]['error'] or 'unknown error')[:200].replace('`', "'")}`).")
        return True

    def act_on_reply(i, gate, c, verb, body, from_status, mark_read=True):
        """One owner reply the bot can act on: park, cancel, or start a bot. With no bot free, the card still
        leaves the person's column: it waits in Up next (the reply is marked as read either way)."""
        nonlocal slots
        n = i["number"]
        c["_body"] = body
        if mark_read:
            react(c["id"])
        if verb in ("discuss", "reject"):
            if verb == "discuss":
                add_label(n, PARK)
                if i["status"] != "Your turn":
                    try_move(n, "Your turn", comment=discuss_note(n), expect=i["status"], waiting="approve")
                else:
                    comment_on(n, discuss_note(n))
            else:
                move(n, "Canceled", body or "Rejected at the gate by the owner.")
                if i["status"] == "Your turn":
                    set_waiting_for(n, None)
            record(recs, {"ts": time.time(), "kind": "reply", "item": n, "reply_id": c["id"], "verb": verb})
            consumed.add((n, c["id"]))
            return
        stage = gate[1] if gate and verb != "unblock" else i.get("stage")
        if slots > 0 and dispatch_work(recs, i, "unblock" if verb == "unblock" else "resume", reply=c,
                                       reply_verb=verb, stage=stage, gate_attrs=gate[2] if gate else None):
            slots -= 1
            running.add(n)
            return
        if i["status"] != "Up next" and not try_move(n, "Up next", expect=i["status"], ack=c["id"]):
            return
        if not (n in acks and acks[n]["reply_id"] == c["id"]):
            acks[n] = {"ts": time.time(), "kind": "ack", "item": n, "reply_id": c["id"], "verb": verb, "from": from_status}
            record(recs, acks[n])

    def handoff(i, prev):
        """A person moved the card out of `Your turn` (`prev`) to a bot column: act on their reply, or move the card
        back and say why. Returns False when there is nothing to check (no question of ours to answer)."""
        n = i["number"]
        if i.get("prs") and i.get("state") == "OPEN":
            return False  # PR stage: the PR mirror below decides
        comments = comments_of(n)
        kind, anchor_c = wait_kind(comments)
        if kind not in REPLY_VERBS:
            return False
        gate = latest_gate(comments)
        mine = {rid for (item_n, rid) in consumed if item_n == n}
        hit = pending_reply(comments, anchor_c["id"], mine, REPLY_VERBS[kind], owners=repliers(n, kind))
        if hit and kind == "answer":
            # Triage reads the answer: back to Inbox, where the bot takes it from.
            react(hit[0]["id"])
            if try_move(n, "Inbox", expect=i["status"]):
                set_waiting_for(n, None)
                i["status"] = "Inbox"
            return True
        if hit:
            act_on_reply(i, gate, hit[0], hit[1], hit[2], prev)
            return True
        body = (f"**Back to you: moved back to {board_name(prev)}.** No reply I can act on after my last question.\n\n"
                f"- start a comment with {reply_menu(kind)}; a bot picks it up within minutes, no card move needed\n"
                f"\n<!-- handoff-bounced from={i['status'].replace(' ', '-')} to={prev.replace(' ', '-')} -->")
        if try_move(n, prev, comment=body, expect=i["status"], waiting=kind):
            out.append(f"#{n}: moved back to {board_name(prev)}; no reply to act on (explained on the issue)")
        return True

    # 1. In progress items nobody is working: a person's hand-off, a retry of a failed session (bounded),
    #    or a card that needs the owner (moved to Unblock with what to do).
    for i in (i for i in items if i["status"] == "In progress" and i["number"] not in running):
        n = i["number"]
        if last.get(n) == "Your turn" and guarded(n, lambda i=i, prev=last[n]: handoff(i, prev)) is not False:
            continue
        mine = [r for r in work if r["item"] == n]
        if not mine:
            guarded(n, lambda i=i, n=n: block(i, f"orphan:{n}", f"this item was in {board_name('In progress')}, "
                                              "but no bot is working on it and there is no record of a bot starting it."))
            continue
        last_rec = mine[-1]
        if not failed(last_rec):
            res = result_of(last_rec) or {}
            guarded(n, lambda i=i, res=res, last_rec=last_rec: block(
                i, f"stuck:{last_rec.get('tag')}", f"the bot finished (result: {res.get('outcome', 'unknown')}) "
                f"but left the card in {board_name('In progress')}. Its last comment on this issue says what it did."))
            continue
        fails = [r for r in mine if r.get("stage") == last_rec.get("stage") and r.get("reason") == last_rec.get("reason")
                 and failed(r)]
        if len(fails) >= MAX_FAILS:
            # A session that never started (launch error) has no tag and no log; name its error instead.
            where = (f"log on the bot's computer: `{LOGS / (last_rec['tag'] + '.log')}`" if last_rec.get("tag")
                     else f"the bot could not start: `{(last_rec.get('error') or 'unknown error')[:200]}`")
            guarded(n, lambda i=i, n=n, k=len(fails), last_rec=last_rec, where=where: block(
                i, f"fails:{n}:{last_rec.get('stage')}", f"the bot failed {k} times at the "
                f"{last_rec.get('stage') or 'first'} step and stopped retrying ({where})."))
            continue
        guarded(n, lambda i=i, last_rec=last_rec: retry(recs, i, last_rec))
        running.add(n)

    # 2. Replies on items waiting for the owner. Resumes come before pickups; with no free bot the card is queued
    #    in Up next. A comment the bot cannot act on gets one explanation, so the owner never waits in vain.
    for i in sorted(items, key=lambda i: i["number"]):
        n = i["number"]
        if n in running or i["status"] != "Your turn" or in_pr_stage(i):
            continue

        def handle(i=i, n=n):
            comments = comments_of(n)
            kind, anchor_c = wait_kind(comments)
            if kind is None:
                report_once(reported, f"nokind:{n}", f"#{n} is in {board_name('Your turn')} but no bot question is on the "
                            f"card, so no bot will act on it. Move it to {board_name('Inbox')} to have it triaged "
                            f"again, or to a bot column (for example {board_name('Up next')}) to have a bot pick it up.")
                return
            if kind not in REPLY_VERBS or kind == "answer":
                return  # answers are read by the triage job; PR kinds are answered on the PR
            gate = latest_gate(comments)
            mine = {rid for (item_n, rid) in consumed if item_n == n}
            if kind == "approve" and PARK in labels_of(n):
                return
            hit = pending_reply(comments, anchor_c["id"], mine, REPLY_VERBS[kind], owners=repliers(n, kind))
            if hit:
                act_on_reply(i, gate, hit[0], hit[1], hit[2], i["status"])
                return
            bad = unreadable_reply(comments, kind, anchor_c["id"], mine, owners=repliers(n, kind))
            if bad:
                comment_on(n, f"**Still waiting for you:** I can't act on [your comment]({bad.get('html_url', '')}). "
                              f"Start a new comment with {reply_menu(kind)}; the card stays in "
                              f"{board_name(i['status'])} until then.\n"
                              f"\n<!-- reply-unreadable comment={bad['id']} -->")
        guarded(n, handle)

    # 3. Up next: first the cards queued by a reply or handed off by a person, then new pickups. An item whose
    #    pickup keeps failing goes to the owner (Unblock) after MAX_FAILS.
    queued = sorted((i for i in items if i["status"] == "Up next" and i["number"] not in running),
                    key=lambda i: (PRIORITY_ORDER.get(i.get("priority") or "", 9), i["number"]))
    special = set()
    for i in queued:
        n = i["number"]
        ack = acks.get(n)
        if ack:
            special.add(n)

            def resume_queued(i=i, n=n, ack=ack):
                comments = comments_of(n)
                c = next((c for c in comments if c["id"] == ack["reply_id"]), None)
                r = parse_reply(c, owners=repliers(n, next((k for k, vs in REPLY_VERBS.items() if ack["verb"] in vs), ""))) if c else None
                if not r or r[0] != ack["verb"]:
                    special.discard(n)
                    report_once(reported, f"ackgone:{n}:{ack['reply_id']}", f"#{n}: the reply that queued it was "
                                "deleted or edited; a bot will start it as a new item.")
                    return
                if not resume_failed(i, ack):  # MAX_FAILS failed resumes of this reply: the owner decides
                    act_on_reply(i, latest_gate(comments), c, r[0], r[1], ack.get("from") or "Your turn",
                                 mark_read=False)
                    resume_failed(i, ack)
            guarded(n, resume_queued)
        elif last.get(n) == "Your turn":
            special.add(n)
            if guarded(n, lambda i=i, prev=last[n]: handoff(i, prev)) is False:
                special.discard(n)
    for i in pickup_order(items):
        if slots <= 0 or coding >= WIP_CODING:
            break
        n = i["number"]
        if n in running or n in special:
            continue
        starts = [r for r in work if r["item"] == n and r["reason"] == "start" and r.get("error")]
        if len(starts) >= MAX_FAILS:
            guarded(n, lambda i=i, starts=starts: block(
                i, f"pickfail:{i['number']}", f"a bot failed to start it {len(starts)} times "
                f"({starts[-1]['error'][:200]})."))
            continue
        if guarded(n, lambda i=i: dispatch_work(recs, i, "start")):
            slots -= 1
            coding += 1

    # 4. T17: a merged PR closed the issue (Closes #N) but the tracker still shows the PR stage.
    for i in items:
        if in_pr_stage(i) and i.get("state") == "CLOSED":
            was = i["status"]
            guarded(i["number"], lambda i=i: move(i["number"], "Done", "Closed by its merged PR."))
            if was == "Your turn":
                guarded(i["number"], lambda i=i: set_waiting_for(i["number"], None))
            i["status"] = "Done"

    # 4b. The PR stage follows the PR labels: a person's turn (decide, merge) or the review/fix bots'.
    for i in items:
        if not in_pr_stage(i) or i.get("state") != "OPEN" or not i.get("prs"):
            continue

        def mirror(i=i):
            n = i["number"]
            labels = {p: [lbl["name"] for lbl in gh("api", f"repos/{REPO}/issues/{p}/labels")] for p in i["prs"]}
            target = review_status(labels.values())
            if target == "In review":
                if i["status"] != "In review":
                    try_move(n, "In review", expect=i["status"])
                return
            if i["status"] == "Your turn":
                return
            waiting = [p for p, names in labels.items() if review_status([names]) == target]
            prs = ", ".join(f"PR #{p}" for p in waiting)
            what = ("answer the question in the latest bot comment on the PR" if target == "decide"
                    else "merge it")
            if last.get(n) == "Your turn" and i["status"] == "In review":
                # A person moved the card to the bots' column, but the PR still waits for them.
                body = (f"**Back to you: moved back to {board_name('Your turn')}.** "
                        f"{prs} still waits for you: {what}.\n\n"
                        f"<!-- handoff-bounced from=In-review to=Your-turn -->")
            else:
                head = (f"🤖 **Needs your decision: {prs}**" if target == "decide"
                        else f"🤖 **Review passed: merge {prs}**")
                body = f"{head}\n\n- {what}\n\n<!-- dispatcher pr-mirror -->"
            try_move(n, "Your turn", comment=body, expect=i["status"], waiting=target)
        guarded(i["number"], mirror)

    # 5. Worktree cleanup for finished items (never forced: a dirty tree is reported, not deleted).
    for i in items:
        path = WT_ROOT / f"item-{i['number']}"
        if i["status"] in ("Done", "Canceled") and path.exists() and i["number"] not in running:
            if DRY:
                out.append(f"DRY: would remove worktree {path}")
                continue
            try:
                run(["git", "-C", str(CHECKOUT), "worktree", "remove", str(path)])
            except Exception as e:  # noqa: BLE001
                report_once(reported, f"wt:{i['number']}", f"#{i['number']}: could not remove worktree {path}: {e}")

    # Surface dispatch errors once each.
    for r in recs:
        if r["kind"] == "work" and r.get("error"):
            report_once(reported, f"err:{r['item']}:{r['ts']}", f"#{r['item']}: the bot could not start: {r['error']}")
    for e in errors:
        err_out.append(f"Board bot error: {e}")


def job_hygiene(items, reported):
    now = datetime.now(timezone.utc).timestamp()

    def age(i):
        try:
            return (now - datetime.fromisoformat(i["updatedAt"].replace("Z", "+00:00")).timestamp()) / 86400
        except (KeyError, ValueError, AttributeError):
            return 0
    lines = []
    stale = [i for i in items if i["status"] == "Your turn" and age(i) > STALE_DAYS]
    if stale:
        lines.append(f"{board_name('Your turn')} for > {STALE_DAYS:g} days: " + ", ".join(f"#{i['number']}" for i in stale))
    parked = [i for i in items if i["status"] == "Your turn" and PARK in labels_of(i["number"])]
    if parked:
        lines.append("Paused for a live discussion (remove needs-human:discussion to resume): "
                     + ", ".join(f"#{i['number']}" for i in parked))
    prs = gh("pr", "list", "-R", REPO, "--state", "open", "--limit", "100", "--json", "number,labels,isDraft")
    flow = ("review-bot:", "fix-bot:", "needs-human:", "pr:")
    unlabeled = [p["number"] for p in prs if not p["isDraft"] and not any(lbl["name"].startswith(flow) for lbl in p["labels"])]
    if unlabeled:
        lines.append("Open PRs outside the review flow (no review-bot/fix-bot/needs-human label): "
                     + ", ".join(f"#{n}" for n in unlabeled))
    if lines:
        out.append("Weekly board check:\n- " + "\n- ".join(lines))


def deliver(reported):
    for f in sorted(RESULTS.glob("*.json")):
        if f.name in reported:
            continue
        try:
            r = json.loads(f.read_text())
        except ValueError:
            continue
        reported.add(f.name)
        outcomes = r.get("outcomes") or {}
        # A triage that asked a question or left an item for the owner always notifies: someone must answer.
        asks = r.get("kind") == "triage" and any(v in ("clarify", "left") for v in outcomes.values())
        if r.get("notify", True) or asks:
            who = " ".join(f"#{n}" for n in r.get("items", [])) or f.stem
            what = r.get("outcome") or json.dumps(outcomes)
            what = {"gated": "waiting for your approval", "escalated": "needs your decision", "blocked": "blocked",
                    "pr-opened": "PR opened", "done": "done", "failed": "bot failed"}.get(what, what)
            line = f"{who} [{what}] {r.get('summary', '').strip()} {r.get('url', '')}".strip()
            out.append(("Needs your answer: " if asks else "") + line)


def repo_env(repo, settings, primary, board):
    """The environment of one repository's run (one board, several repositories)."""
    checkout = settings.get("checkout") or (ENV.get("PIPELINE_CHECKOUT") if repo == primary else "")
    if not checkout:
        raise ValueError(f"repositories: {repo} needs a checkout")
    env = {**ENV, "PIPELINE_ONE_REPO": "1", "PIPELINE_REPO": repo, "PIPELINE_CHECKOUT": checkout,
           "PIPELINE_STATE": str(pipeline_runtime.repo_state(STATE, repo, primary)),
           "PIPELINE_BOARD_STATES": os.pathsep.join(str(d) for d in board)}
    # A repository without its own base or branch template uses PIPELINE_BASE / PIPELINE_BRANCH_TEMPLATE.
    for key, name in (("base", "PIPELINE_BASE"), ("branch_template", "PIPELINE_BRANCH_TEMPLATE")):
        if settings.get(key):
            env[name] = settings[key]
    # Worktrees are named item-<n>: a root shared by two repositories would mix their items. The primary keeps
    # PIPELINE_WORKTREE_ROOT (its items in progress live there); the others default to <checkout>-worktrees.
    if repo != primary:
        env.pop("PIPELINE_WORKTREE_ROOT", None)
    if settings.get("worktree_root"):
        env["PIPELINE_WORKTREE_ROOT"] = settings["worktree_root"]
    return env


def worktree_root(env):
    root = env.get("PIPELINE_WORKTREE_ROOT") or env["PIPELINE_CHECKOUT"] + "-worktrees"
    return os.path.normpath(os.path.expanduser(root))


CHILD_TIMEOUT = 900  # one repository's tick; a hung one must not hold the board for long
LOCK_STUCK = 1800


def lock_busy(job, path):
    """The previous tick still runs: silent, unless it has held the board for LOCK_STUCK (then once an hour)."""
    try:
        held = time.time() - float(path.read_text(encoding="utf-8") or time.time())
    except (OSError, ValueError):
        held = 0
    if held < LOCK_STUCK:
        return 0
    lines = pipeline_runtime.fresh_lines(STATE / "health" / job, "board-lock", [
        f"Pipeline dispatch ({job}): the previous run has held the board for {pipeline_runtime.duration(held)}; "
        f"nothing starts until it ends (lock {path})."], ttl=3600)
    if lines:
        print("\n".join(lines))
    return 1


def fan_out(job, primary, repos):
    """Run this job once per repository, in turn (so each run sees the sessions the previous ones started)."""
    try:
        board = pipeline_runtime.board_states(ENV, STATE)
        envs = [(repo, repo_env(repo, settings, primary, board)) for repo, settings in repos.items()]
        roots = [worktree_root(env) for _, env in envs]
        if len(set(roots)) != len(roots):
            raise ValueError("two repositories share a worktree root (set worktree_root for each)")
    except ValueError as e:
        print(f"Pipeline dispatch error: {e}")
        return 1
    code, lines = 0, []
    path = STATE / f"board-{job}.lock"
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        with open(path, "a+", encoding="utf-8") as lock:  # held for the whole run; holds the time it was taken
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                return lock_busy(job, path)
            lock.seek(0)
            lock.truncate()
            lock.write(str(time.time()))
            lock.flush()
            for repo, env in envs:
                try:
                    r = subprocess.run([sys.executable, str(pathlib.Path(__file__).resolve()), job], capture_output=True,
                                       text=True, encoding="utf-8", errors="replace", env=env, timeout=CHILD_TIMEOUT)
                    text, rc = r.stdout, r.returncode
                    if rc:  # a crash says why on stderr; a warning on a good run is not news
                        text = (text + "\n" + r.stderr.strip()[-600:]).strip() or f"exited with {rc}"
                except (OSError, ValueError, TypeError, subprocess.SubprocessError) as e:
                    text, rc = f"Pipeline dispatch error ({job}): {e}", 1
                code = code or (1 if rc else 0)
                lines += [f"[{repo}] {line}" for line in text.splitlines() if line.strip()]
    except OSError as e:  # the state dir is not writable: no run can record anything
        print(f"Pipeline dispatch error ({job}): {e}")
        return 1
    if lines:
        print("\n".join(lines))
    return code


def main(argv):
    job = argv[1] if len(argv) > 1 else ""
    if job not in ("triage", "work", "hygiene"):
        print("usage: pipeline-dispatch.py triage|work|hygiene")
        return 2
    if not ENV.get("PIPELINE_ONE_REPO"):
        try:
            primary, repos = pipeline_runtime.repositories(ENV)
        except ValueError as e:
            print(f"Pipeline dispatch error: {e}")
            return 1
        if len(repos) > 1 or repos.get(primary):  # a listed repository's own settings apply even alone
            return fan_out(job, primary, repos)
    missing = [k for k, v in (("PIPELINE_REPO", REPO), ("PIPELINE_CHECKOUT", ENV.get("PIPELINE_CHECKOUT")),
                              ("PIPELINE_LIST_CMD", LIST_CMD), ("PIPELINE_MOVE_CMD", MOVE_CMD),
                              ("PIPELINE_OWNERS", OWNERS)) if not v]
    if missing:
        print("Pipeline dispatch error: set " + ", ".join(missing))
        return 1
    if not _logins(HANDLES):
        # Without a bot login no gate, blocked or triage marker is trusted, and every reply looks unanswered.
        print("Pipeline dispatch error: no bot login: set PIPELINE_BOT_LOGINS (or an @ handle in "
              "PR_AGENT_HANDLE), or log gh in as the bot account")
        return 1
    if not SHARED and set(_logins(HANDLES)) & set(OWNERS):
        # The bot posts as an owner: without the shared-account rule every owner reply would be read as the bot's.
        print("Pipeline dispatch error: the bot posts as an owner login ("
              + ", ".join(sorted(set(_logins(HANDLES)) & set(OWNERS)))
              + "): set PIPELINE_SHARED_ACCOUNT=1, or give the bot its own account")
        return 1
    for d in (STATE, RESULTS, LOGS):
        d.mkdir(parents=True, exist_ok=True)
    recs = load_records()
    try:
        reported = set(json.loads(REPORTED.read_text())) if REPORTED.exists() else set()
    except ValueError:
        # A truncated file (e.g. disk full mid-write) must not stop the tick or re-send old results.
        reported = {f.name for f in RESULTS.glob("*.json")}
    health = STATE / "health" / job  # stopped record and repeat filter of this job
    stop = ""
    ran = False
    probe_errors.clear()
    try:
        session_launcher.kind(ENV)
        deliver(reported)
        if not pipeline_runtime.quiet_now(ENV, job):  # quiet hours: results still arrive, no session starts
            ran = True
            items = list_items()
            try:
                {"triage": lambda: job_triage(items, recs, reported),
                 "work": lambda: job_work(items, recs, reported),
                 "hygiene": lambda: job_hygiene(items, reported)}[job]()
            finally:
                if job == "work":
                    save_last_status(items)  # also after a failure: the bot's own moves must not look like a person's
        code = 0
    except Exception as e:  # noqa: BLE001 — surface the failure; never crash silently
        code = 1
        stop = f"Pipeline dispatch error ({job}): {e}"
    if probe_errors:
        code = 1
        stop = "; ".join(([stop] if stop else []) + list(probe_errors.values()))
    if not DRY:
        tmp = REPORTED.with_suffix(".tmp")
        tmp.write_text(json.dumps(sorted(reported)))
        os.replace(tmp, REPORTED)  # atomic: a failed write never truncates the record
    if DRY:
        lines = out + err_out + ([stop] if code else [])
    else:
        # Every tick failing: one plain alert, repeated hourly, then one line when it runs again.
        # A quiet tick ran nothing, so it proves no recovery.
        status = (pipeline_runtime.job_down(health, f"{job} dispatch", stop) if code
                  else pipeline_runtime.job_up(health, f"{job} dispatch") if ran else [])
        lines = status + out + pipeline_runtime.fresh_lines(health, "errors", err_out)
    if lines:
        print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
