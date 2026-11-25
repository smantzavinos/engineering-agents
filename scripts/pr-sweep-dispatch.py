#!/usr/bin/env python3
"""PR sweep dispatcher: a scheduled tick for PR automation (no LLM).

Each tick reads GitHub state for the owned repos, applies the rules in
docs/hermes/pr-automation.md, and launches one session per job: an independent
Reviewer, or one author-side babysit round. The sessions
outlive the tick. Their verdicts land on GitHub, and a later tick delivers their
result files. stdout is the delivery to the human; empty stdout means a silent,
zero-token tick.

Install: copy this file, commands.py, comment_style.py, post-comment.py, pipeline_runtime.py,
session_launcher.py and pr-sweep-prompts/ into $HERMES_HOME/scripts/, then
  hermes cron create "every 2m" --no-agent --script pr-sweep-dispatch.py --name pr-sweep
Without Hermes: docs/t3/README.md (systemd timers, PIPELINE_LAUNCHER=t3).

Environment:
  PR_SWEEP_REPOS          space-separated owner/repo list (PR_SWEEP_REPO also accepted); default: the board's
                          repositories (PIPELINE_REPOSITORIES or "repositories" in GH_PROJECT_CONFIG, else PIPELINE_REPO),
                          whose "checkout" settings are used, and whose pipeline states count toward PIPELINE_WIP
  PR_AGENT_HANDLE         handles whose mentions trigger: `<h> review`, `<h> fix` / `<h> babysit` (<h> is a full token: /devbot, @name)
                          (space/comma-separated list: the account handle AND its natural aliases)
  PR_SWEEP_CHECKOUT_ROOT  directory holding local checkouts named by repo (default ~/repos)
  PR_REVIEW_MODEL, PR_REVIEW_REASONING (medium), PR_REVIEW_SKILLS (pull-request)
  PR_BABYSIT_MODEL, PR_BABYSIT_SKILLS (babysit-pr)
  PR_SESSION_PROVIDER     session provider (T3 provider instance id when using t3)
  PIPELINE_LAUNCHER       hermes (default) | t3
  T3_BIN, T3CODE_HOME     T3 executable (default t3) and data directory selecting the server
  PIPELINE_GIT_NAME, PIPELINE_GIT_EMAIL  optional local git commit identity, set before launching
  PR_SWEEP_UNLABELED      ignore (default: opt-in) | review (drift: unlabeled = awaiting review)
  PR_BABYSIT_STALE_MIN    (60; chat-started claims only)   PR_REVIEW_STUCK_MIN (90)
  PIPELINE_OWNERS         owner logins (required): they command the bots on any PR and their comments keep
                          their hidden markers
  PIPELINE_RESPONDERS     extra logins who may command the bots on any PR (with the PR's assignees and the
                          assignees of the issues it closes)
  PIPELINE_BOT_LOGINS     logins the bots post as: their hidden markers count and their thread replies answer a
                          review thread (default: the '@' handles, else the account `gh` is logged in as)
  PR_BOT_REVIEWERS        bot logins whose reviews trigger sweep-owned babysit rounds
                          (default copilot-pull-request-reviewer[bot])
  PR_BOT_REVIEW_CAP       max bot-review rounds per PR (default 5)
  PR_REQUIRE_VERIFICATION_LOGS  1 (default) | 0: a result that published a commit or verdict must list non-empty logs
  PR_SWEEP_STATE          state dir (default $HERMES_HOME/state/pr-automation)
  HERMES_BIN, GH_BIN, GH_TOKEN_FILE (token file used when GH_TOKEN is unset)
  PR_SWEEP_DRY=1          print the intended actions; mutate nothing, record nothing
  PR_FIX_LOOP_CAP         FIX verdicts answered automatically before a human decides (default 2)
  PR_HUMAN_CHECKS         comma-separated check names only a person can satisfy (e.g. a merge-label check);
                          never treated as a code failure and never awaited
  PIPELINE_WIP            author sessions at once, shared with the pipeline's work sessions (default 2);
                          PIPELINE_STATE names the pipeline's state dir (default $HERMES_HOME/state/pipeline)
  PIPELINE_QUIET_HOURS, PIPELINE_QUIET_WEEKENDS, PIPELINE_QUIET_MODES (default "work pr"), PIPELINE_FORCE:
                          quiet hours, as in pipeline-dispatch.py; job name `pr`

Labels: `review-bot:*` / `fix-bot:*` mean a bot acts next; `needs-human:*` means a person acts next.
A PR carries at most one state label, and it always names who acts next: a bot state that no bot
will act on is converted to `needs-human:decision` with a message saying what to do.
"""
import contextlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse
from datetime import datetime
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import commands  # noqa: E402  (shared command parser, scripts/commands.py)
import pipeline_runtime  # noqa: E402  (quiet hours, shared WIP, stopped alerts: scripts/pipeline_runtime.py)
import session_launcher  # noqa: E402

ENV = os.environ
REPOS = (ENV.get("PR_SWEEP_REPOS") or ENV.get("PR_SWEEP_REPO") or "").split()
def parse_handles(raw):
    """PR_AGENT_HANDLE vocabulary (one rule for every script: commands.normalize_handles)."""
    return commands.normalize_handles(raw or "")


HANDLES = parse_handles(ENV.get("PR_AGENT_HANDLE", ""))
HANDLE = HANDLES[0]  # primary command token, for prompt templates and hints
# Logins the bots post as (their thread replies answer a thread): PIPELINE_BOT_LOGINS and the '@' handles;
# when neither names one (the default `/devbot`), agent_logins() falls back to the account `gh` uses.
LOGINS = set(commands.bot_logins(ENV.get("PIPELINE_BOT_LOGINS", ""), HANDLES))
OWNERS = frozenset(o.lstrip("@").lower() for o in ENV.get("PIPELINE_OWNERS", "").replace(",", " ").split())
RESPONDERS = frozenset(o.lstrip("@").lower() for o in ENV.get("PIPELINE_RESPONDERS", "").replace(",", " ").split())
CHECKOUT_ROOT = pathlib.Path(ENV.get("PR_SWEEP_CHECKOUT_ROOT", str(pathlib.Path.home() / "repos")))
CHECKOUTS: dict = {}  # owner/repo -> checkout, from the board's repositories map (main fills it)
BOARD_STATES: list = []  # every repository's pipeline state dir (main fills it): their work sessions share PIPELINE_WIP


def checkout_of(repo):
    return str(CHECKOUTS.get(repo) or CHECKOUT_ROOT / repo.split("/")[-1])
REVIEW_MODEL = ENV.get("PR_REVIEW_MODEL", "")
REVIEW_REASONING = ENV.get("PR_REVIEW_REASONING", "medium")
REVIEW_SKILLS = ENV.get("PR_REVIEW_SKILLS", "pull-request")
BABYSIT_MODEL = ENV.get("PR_BABYSIT_MODEL", "")
BABYSIT_SKILLS = ENV.get("PR_BABYSIT_SKILLS", "babysit-pr")
PROVIDER = ENV.get("PR_SESSION_PROVIDER", "")
UNLABELED = ENV.get("PR_SWEEP_UNLABELED", "ignore")
STALE_MIN = int(ENV.get("PR_BABYSIT_STALE_MIN", "60"))
BOT_REVIEWERS = tuple(ENV.get("PR_BOT_REVIEWERS", "copilot-pull-request-reviewer[bot]").split())
BOT_CAP = int(ENV.get("PR_BOT_REVIEW_CAP", "5"))
# Fix-bot rounds and the delivery pipeline's work sessions share one limit of live author sessions.
WIP = int(ENV.get("PIPELINE_WIP", "2"))
REQUIRE_LOGS = ENV.get("PR_REQUIRE_VERIFICATION_LOGS", "1") not in ("0", "false", "no")
RETRY_COOLDOWN_SECS = 30 * 60  # wait before retrying a round that failed or hit a passing blocker
CONFLICT_CAP = 2  # automatic merge-conflict rounds per PR since the owner last asked for a fix
STUCK_MIN = int(ENV.get("PR_REVIEW_STUCK_MIN", "90"))
STALL_MIN = int(ENV.get("PR_STALL_NOTIFY_MIN", "60"))
DRY = bool(ENV.get("PR_SWEEP_DRY"))
HERMES = ENV.get("HERMES_BIN", "hermes")
GH = ENV.get("GH_BIN", "gh")
TOKEN_FILE = pathlib.Path(ENV.get("GH_TOKEN_FILE", "/nonexistent"))
HOME = pathlib.Path(ENV.get("HERMES_HOME", str(pathlib.Path.home())))
STATE = pathlib.Path(ENV.get("PR_SWEEP_STATE", str(HOME / "state" / "pr-automation")))
PIPELINE_STATE = pathlib.Path(ENV.get("PIPELINE_STATE", str(HOME / "state" / "pipeline")))
DISPATCH, RESULTS, REPORTED, LOGS = STATE / "dispatches.jsonl", STATE / "results", STATE / "reported.json", STATE / "logs"
PROMPTS = pathlib.Path(__file__).resolve().parent / "pr-sweep-prompts"
_SIGNING = {}  # (repo, branch) -> "required" | "optional" | "unknown", for one tick

MAX_FAILS = 3
INERT_CONCLUSIONS = {"CANCELLED", "STALE"}   # runner/infra outcomes: nothing a fix round can change
CI_SETTLE_SECS = 6 * 3600                     # a BLOCKED/RELEASED round on a ci_key is not repeated for this long
WAIT_RECHECK_SECS = 20 * 60                   # minimum gap between waiting-for-checks reviews of one head
WAIT_REVIEW_CAP = 3                           # waiting-for-checks reviews per head before the owner is asked
FIX_LOOP_CAP = int(ENV.get("PR_FIX_LOOP_CAP", "2"))
# Checks only a person can turn green (e.g. a merge-label check): never a code failure, never awaited.
HUMAN_CHECKS = {c.strip().casefold() for c in ENV.get("PR_HUMAN_CHECKS", "").split(",") if c.strip()}
# Label vocabulary: `review-bot:` / `fix-bot:` = a bot acts next; `needs-human:` = a person acts next.
REVIEW_QUEUED, REVIEW_RUNNING = "review-bot:queued", "review-bot:running"
FIX_QUEUED, FIX_OWNS = "fix-bot:queued", "fix-bot:owns-branch"
HUMAN_MERGE, HUMAN_DECISION = "needs-human:merge", "needs-human:decision"
STATE_LABELS = [REVIEW_QUEUED, REVIEW_RUNNING, FIX_QUEUED, HUMAN_MERGE, HUMAN_DECISION]
LABEL_PRIORITY = [REVIEW_RUNNING, FIX_QUEUED, HUMAN_MERGE, HUMAN_DECISION, REVIEW_QUEUED]
BOT_STATES = (REVIEW_QUEUED, REVIEW_RUNNING, FIX_QUEUED)
HUMAN_STATES = (HUMAN_MERGE, HUMAN_DECISION)
# Pre-rename names: still read (a skill or person may add one), rewritten to the new name on sight.
LEGACY_LABELS = {"pr:ready-review": REVIEW_QUEUED, "pr:in-review": REVIEW_RUNNING, "pr:re-review": FIX_QUEUED,
                 "pr:ready-merge": HUMAN_MERGE, "pr:escalated": HUMAN_DECISION, "pr:babysat": FIX_OWNS}
SWEEP_CLAIM_PREFIX = "babysit-pr"  # session ids of sweep-started fix-bot rounds (see Babysit coexistence rule 7)
VERDICT_RE = re.compile(r"<!--\s*pr-review verdict=(READY|FIX|BLOCKED) head=([0-9a-f]{7,40})\s*-->")
# Claim comment: `fix-bot: owns this branch; session=<id> last-active=<UTC ISO>` (legacy: `babysit: session=<id> heartbeat=<t>`).
HEARTBEAT_RE = re.compile(r"(?:fix-bot: owns this branch;|babysit:) session=(\S+) (?:last-active|heartbeat)=(\S+)")

out = []  # lines delivered to the human
asked_lines: dict[session_launcher.Handle, str] = {}  # one diagnostic per waiting session
probe_errors: dict[session_launcher.Handle, str] = {}  # stopped reasons, reported after the sweep


# ---------------------------------------------------------------- pure decisions

def state_label(labels, unlabeled=UNLABELED):
    """The PR's one state label, or None. Drift mode reads 'no label' as awaiting review."""
    label = next((name for name in LABEL_PRIORITY if name in labels), None)
    if label is None and unlabeled == "review" and FIX_OWNS not in labels:
        return REVIEW_QUEUED
    return label


def migrate_labels(repo, n, labels):
    """Rewrite pre-rename workflow labels on one PR to the current names; returns the current label list."""
    current = list(dict.fromkeys(LEGACY_LABELS.get(name, name) for name in labels))
    for old in (name for name in labels if name in LEGACY_LABELS):
        if DRY:
            out.append(f"DRY: would rename {repo}#{n} label {old} -> {LEGACY_LABELS[old]}")
            continue
        if LEGACY_LABELS[old] not in labels:
            gh("api", "-X", "POST", f"repos/{repo}/issues/{n}/labels", "-f", f"labels[]={LEGACY_LABELS[old]}", parse=False)
        gh("api", "-X", "DELETE", f"repos/{repo}/issues/{n}/labels/{old}", parse=False)
    return current


def verdicts(comments):
    """[(verdict, head, comment)] in comment order, from the machine-readable marker."""
    return [(m.group(1), m.group(2), c) for c in comments
            for m in [VERDICT_RE.search(c.get("body") or "")] if m]


def claim_state(labels, comments, now_s, stale_min=STALE_MIN):
    """Babysit claim: 'none' | 'active' | 'stale'. A label with no readable heartbeat is stale.

    Sweep-owned claims never age: between rounds nobody runs by design, and the
    sweep tracks their sessions through its own dispatch records."""
    if FIX_OWNS not in labels:
        return "none"
    beats = [m for c in comments for m in [HEARTBEAT_RE.search(c.get("body") or "")] if m]
    if not beats:
        return "stale"
    if beats[-1].group(1).startswith(SWEEP_CLAIM_PREFIX):
        return "active"
    try:
        t = datetime.fromisoformat(beats[-1].group(2).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return "stale"
    return "stale" if now_s - t > stale_min * 60 else "active"


def sweep_owned(comments):
    beats = [m for c in comments for m in [HEARTBEAT_RE.search(c.get("body") or "")] if m]
    return bool(beats) and beats[-1].group(1).startswith(SWEEP_CLAIM_PREFIX)


def bot_reviews(reviews, bots=BOT_REVIEWERS):
    """Completed reviews by configured bot accounts, oldest first."""
    return sorted((r for r in reviews if (r.get("user") or {}).get("login") in bots
                   and r.get("state") not in (None, "PENDING") and r.get("submitted_at")),
                  key=lambda r: r["id"])


THREADS_QUERY = ("query($o:String!,$r:String!,$p:Int!){repository(owner:$o,name:$r){pullRequest(number:$p){"
                 "reviewThreads(first:100){nodes{isResolved start:comments(first:1){nodes{author{login}}} "
                 "comments(last:30){nodes{databaseId author{login}}}}}}}}")


def unanswered_threads(threads, authors, voices=None):
    """Ids of the last comment of every unresolved review thread whose last word is not the PR author's
    (the owner account the fix bot replies from). Such a thread was neither fixed nor answered.

    `voices`: a callable returning everyone else the sweep listens to on this PR (owners, the PR's people,
    PR_BOT_REVIEWERS). With it, a thread counts only when one of them (or the bot) started it, and a later
    comment from anyone else neither opens nor reopens it. None: every author counts (unit tests)."""
    def norm(who):  # GraphQL names a bot `copilot-pull-request-reviewer`, REST `copilot-pull-request-reviewer[bot]`
        return (who or "").lower().removesuffix("[bot]")

    def author(node):
        return norm((node.get("author") or {}).get("login"))
    mine = {norm(a) for a in authors}
    out = []
    for t in threads:
        nodes = (t.get("comments") or {}).get("nodes") or []
        if t.get("isResolved") or not nodes:
            continue
        if voices is not None:
            heard = mine | {norm(v) for v in voices()}
            if author(((t.get("start") or {}).get("nodes") or [{}])[0]) not in heard:
                continue
            nodes = [c for c in nodes if author(c) in heard]
            if not nodes:
                continue
        last = nodes[-1]
        if author(last) not in mine:
            out.append(last["databaseId"])
    return out


def bot_round_due(bot_revs, handled_ids, cap=BOT_CAP):
    """(review, capped, seen_ids): the newest unhandled bot review if a round is due,
    whether the cap is hit, and ALL unhandled ids to record with the round.

    GitHub's review list is the counter: the cap counts completed bot reviews on the
    PR. The dispatch record carries every unhandled review id, not just the dispatched
    one, so several bot reviews landing between ticks are all consumed by the single
    round they trigger instead of queuing one no-op round each."""
    capped = len(bot_revs) > cap
    pending = [r for r in bot_revs if r["id"] not in handled_ids]
    if not pending or capped:
        return None, capped, []
    return pending[-1], False, [r["id"] for r in pending]


def inert_checks(rollup):
    """Sorted 'name (CONCLUSION)' for completed checks that were cancelled/stale; a person must re-run them."""
    return sorted(f"{c.get('name')} ({c.get('conclusion')})" for c in (rollup or [])
                  if (c.get("name") or "").strip().casefold() not in HUMAN_CHECKS
                  and c.get("status") == "COMPLETED" and c.get("conclusion") in INERT_CONCLUSIONS)


def ci_round_due(rollup, handled_keys, stamp_head, head):
    """(fires, key, ok): CI conclusions at the stamped READY head.

    key identifies (head, conclusion-set); None when out of scope — no READY
    verdict at this head, or the head moved past the stamp (push demotion owns
    that). fires is non-empty only when key is new AND some completed check
    failed. ok is overall health, used to restore a CI demotion once green.

    Checks named in PR_HUMAN_CHECKS are intentional human gates (for example a
    merge-label check): their red state must not block READY advice or trigger an
    author-side fix round.
    Every other completed failing check remains an engine-level fact. The
    required-vs-advisory split lives in each repo's merge-gate manifest row
    and binds the Reviewer's verdict (docs/references/pr-review.md, Merge),
    not this demotion. Only check-run rollups (name/status/conclusion) are
    read; classic commit statuses (context/state) are ignored.
    """
    if not stamp_head or not head.startswith(stamp_head):
        return [], None, False
    checks = [c for c in (rollup or [])
              if (c.get("name") or "").strip().casefold() not in HUMAN_CHECKS]
    bad = sorted(f"{c.get('name')} ({c.get('conclusion')})" for c in checks
                 if c.get("status") == "COMPLETED"
                 and c.get("conclusion") not in {"SUCCESS", "NEUTRAL", "SKIPPED"} | INERT_CONCLUSIONS)
    inert = [c for c in checks if c.get("status") == "COMPLETED" and c.get("conclusion") in INERT_CONCLUSIONS]
    # cancelled checks are not healthy: the PR must never return to needs-human:merge on a cancelled run
    complete = bool(checks) and all(c.get("status") == "COMPLETED" for c in checks) and not inert
    key = f"{head[:12]}:" + (",".join(bad) if bad else ("inert" if inert else "green"))
    if key in handled_keys:
        return [], None, not bad and complete
    if bad:
        return bad, key, False
    return [], key, complete



# Comments that look like automation (a hidden marker, the bot emoji, a claim line) are never requests.
AUTOMATION_RE = re.compile(r"<!--|\A\s*\U0001F916|^\s*(?:\U0001F916\s*)?(?:work|babysit|fix-bot):\s", re.M)
AUTOMATION_START_RE = re.compile(r"\s*(?:\U0001F916|(?:work|babysit|fix-bot):)")


def login_of(record):
    return ((record.get("user") or {}).get("login") or "").lower()


def trusted_comments(comments, bots, people):
    """The PR comments the sweep reads, filtered by author (docs/hermes/pr-automation.md, Who the bots listen to).

    Owners and bot logins: kept as they are (their hidden markers carry verdicts and claims).
    People who may command the bots (`people()`: responders, the PR's assignees, the assignees of the issues
    it closes): kept only when nothing in the comment looks like automation (no hidden-marker delimiter, no
    🤖 first line, no claim, heartbeat or verdict text anywhere), so they cannot pose as a bot. Anyone else:
    dropped, so a stranger can neither start a bot round nor forge a verdict.
    `people` is a callable, asked only when a comment comes from someone outside the first group."""
    trusted = OWNERS | set(bots)
    kept = []
    for c in comments:
        who = login_of(c)
        if who in trusted:
            kept.append(c)
        elif who and who in people() and not looks_automated(c.get("body") or ""):
            kept.append(c)
    return kept


def trusted_logins(people):
    """The logins a session may take instructions from on this PR, for its prompt. Bots are listed with and
    without `[bot]`: GraphQL review threads name them without it."""
    logins = OWNERS | people() | set(BOT_REVIEWERS) | set(agent_logins())
    return ", ".join(sorted(logins | {x.removesuffix("[bot]") for x in logins})) or "none"


def looks_automated(body):
    """True when a comment carries anything only automation may write (commands.looks_automated; unheard.py
    applies the same rule when it explains why no bot acted)."""
    return (commands.looks_automated(body) or bool(AUTOMATION_RE.search(body)) or bool(HEARTBEAT_RE.search(body))
            or bool(VERDICT_RE.search(body)))


def mentions(comments, handles, seen_ids):
    """Newest unprocessed (review_comment, babysit_comment) across the handle vocabulary.

    `fix` and `babysit` both mean an author round. A comment is ignored when the
    author IS one of the configured handles (self-mention) — not just the primary —
    or when it looks like automation (a worker's comment posted from a shared account).
    Callers pass trusted_comments(), so only owners and the PR's people reach this.
    """
    review = babysit = None
    if not handles:
        return None, None
    for c in comments:
        if c["id"] in seen_ids or c["user"]["login"].lower() in {h[1:] for h in handles if h.startswith("@")}:
            continue
        if commands.automation_start(c.get("body")):  # a claim line further down is an owner's instruction
            continue
        found = commands.parse(c.get("body"), handles)
        if found is None or found[1] not in ("review", "fix", "babysit"):
            continue
        if found[1] in ("babysit", "fix"):
            babysit = c
        else:
            review = c
    return review, babysit


def integrate_strategy(comment, handles):
    """How the fix bot brings the base branch in: `rebase` only when the owner's mention names it as the first
    word after `fix`/`babysit` on its first line; `merge` otherwise (default, also with no mention).
    The comment already came through mentions(), which drops the bot's own comments."""
    if not comment or not handles:
        return "merge"
    found = commands.parse(comment.get("body"), handles)
    if found is None or found[1] not in ("fix", "babysit"):
        return "merge"
    words = found[2].split()
    return "rebase" if words and commands.strategy(words[0].rstrip(".!,;:?")) == "rebase" else "merge"


# ---------------------------------------------------------------- side effects

_WHOAMI_TRIED: list = []


def agent_logins():
    """LOGINS, or the login `gh` is logged in as when none is configured (asked once per run, even on failure)."""
    if not LOGINS and not _WHOAMI_TRIED:
        _WHOAMI_TRIED.append(True)
        try:
            me = ((gh("api", "user") or {}).get("login") or "").lower()
        except (RuntimeError, OSError, ValueError, AttributeError):
            me = ""
        if me:
            LOGINS.add(me)
    return LOGINS


def gh(*args, parse=True) -> Any:
    env = {k: v for k, v in ENV.items() if not k.startswith(("HERMES_CRON", "HERMES_SESSION"))}
    if "GH_TOKEN" not in env and TOKEN_FILE.exists():
        env["GH_TOKEN"] = TOKEN_FILE.read_text().strip()
    r = subprocess.run([GH, *args], capture_output=True, text=True, env=env, timeout=60)
    if r.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args[:3])} failed: {r.stderr.strip()[:300]}")
    if not (parse and r.stdout.strip()):
        return r.stdout
    try:
        return json.loads(r.stdout)
    except ValueError as e:
        raise RuntimeError(f"gh {' '.join(args[:3])} printed invalid JSON: {e}") from e


def react(repo, comment_id):
    """Mark an owner trigger comment as read (an eyes reaction GitHub shows right away)."""
    if DRY or not comment_id:
        return
    with contextlib.suppress(Exception):  # a missing reaction must never stop the dispatch
        gh("api", "-X", "POST", f"repos/{repo}/issues/comments/{comment_id}/reactions", "-f", "content=eyes", parse=False)


def alive(pid):
    reply = session_launcher.probe(ENV, pid, None if DRY else STATE)
    if reply["state"] == "asked":
        asked_lines[pid] = (f"⚠️ Session {pid} is waiting for an answer, so it counts as failed: "
                            f"{reply['link']}").rstrip(": ")
    elif reply["state"] == "unknown":
        probe_errors[pid] = f"T3 could not check {pid}: {reply['detail']}"
    return reply["state"] in ("live", "unknown")


def result_problem(rec):
    """None when the dispatch wrote an acceptable result; else the reason it does not count.
    'no result file' means nothing was written; any other reason means a file exists but was rejected."""
    try:
        path = RESULTS / f"{rec.get('tag')}.json"
        if not path.is_file():
            return 'no result file'
        result = json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(result, dict) or result.get('pr') != rec.get('pr'):
            return 'result is for another PR'
        if result.get('repo', rec.get('repo')) != rec.get('repo') or result.get('kind', rec['kind']) != rec['kind']:
            return 'result is for another repository or kind'
        outcome = result.get('verdict') if rec['kind'] == 'review' else result.get('status')
        allowed = ('READY', 'FIX', 'BLOCKED', 'STALE') if rec['kind'] == 'review' else ('FIXED', 'RELEASED', 'ESCALATE', 'BLOCKED')
        if outcome not in allowed or not re.fullmatch(r'[0-9a-f]{40}', result.get('head', '')):
            return 'result has no valid verdict or head'
        if rec['kind'] == 'review' and result['head'] != rec['head']:
            return 'result is for another commit'
        if result.get('input_head', rec['head']) != rec['head']:
            return 'result is for another commit'
        # Real test logs, not a claim: a review, or a fix round that published a commit, lists the log files
        # it wrote under its artifacts directory. A STALE review or a round that published nothing needs none.
        artifacts = result.get('verification_artifacts')
        nothing_published = (rec['kind'] == 'babysit' and result.get('input_head', rec['head']) == result['head']
                             and outcome in ('RELEASED', 'BLOCKED', 'ESCALATE'))
        if REQUIRE_LOGS and not nothing_published and outcome != 'STALE':
            if not isinstance(artifacts, list) or not artifacts or not all(isinstance(p, str) for p in artifacts):
                return 'verification log list missing'
            own = (LOGS / str(rec.get('tag'))).resolve()
            for p in artifacts:  # every listed log must exist; an empty log is fine (clean tools print nothing)
                if not pathlib.Path(p).is_file():
                    return f'verification log missing: {p}'
                if not pathlib.Path(p).resolve().is_relative_to(own):  # a log the round wrote, not any file
                    return f'verification log outside the artifacts directory: {p}'
            if not any(pathlib.Path(p).stat().st_size > 0 for p in artifacts):
                return f'verification logs all empty: {", ".join(artifacts)}'
        return None
    except (OSError, ValueError, TypeError, KeyError) as e:
        return f'result unreadable: {type(e).__name__}'


def read_result(rec):
    """The dispatch's result JSON, or {} when it is missing or unreadable (callers check has_result first)."""
    try:
        data = json.loads((RESULTS / f"{rec.get('tag')}.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def has_result(rec):
    return result_problem(rec) is None


def settled_ci_keys(recs, now=None):
    """ci_keys whose babysit round already ended BLOCKED/RELEASED (owner_decision not true) within CI_SETTLE_SECS.
    Same head + same failing set will not start another paid round until the window passes."""
    now = time.time() if now is None else now
    keys = set()
    for r in recs:
        if r.get("kind") != "babysit" or not r.get("ci_key") or now - r.get("ts", 0) >= CI_SETTLE_SECS:
            continue
        if not has_result(r):
            continue
        res = read_result(r)
        if res.get("status") in ("BLOCKED", "RELEASED") and res.get("owner_decision") is not True:
            keys.add(r["ci_key"])
    return keys


def handled_dispatch(rec):
    """Only successful/owner-decision results consume author triggers, never launch records."""
    if not has_result(rec):
        return False
    result = read_result(rec)
    if rec['kind'] == 'review':
        # A BLOCKED verdict that asks the owner is final for this commit: re-reviewing cannot answer it.
        return result.get('verdict') in ('READY', 'FIX') or (
            result.get('verdict') == 'BLOCKED' and result.get('owner_decision') is True)
    return result.get('status') == 'FIXED' or (result.get('status') == 'ESCALATE' and result.get('owner_decision') is True)


def unfinished(rec):
    """A round that neither pushed nor needs the owner: it failed, or ended BLOCKED on a passing blocker
    (owner_decision not true). Such a round is retried and does not use up CONFLICT_CAP; an owner request
    it carried stays pending."""
    if failed_dispatch(rec):
        return True
    if not has_result(rec):
        return False  # still running
    result = read_result(rec)
    outcome = result.get('verdict') if rec.get('kind') == 'review' else result.get('status')
    return outcome == 'BLOCKED' and result.get('owner_decision') is not True


def owner_requests(mine, running, now=None):
    """(answered, exhausted) comment ids among this PR's dispatch records.
    answered: a run is live, or ended with a real outcome, or the last unfinished run is inside the
    cooldown, or MAX_FAILS unfinished runs are used up. exhausted: id -> newest unfinished record, for the
    ids whose retries are used up (the caller reports them once)."""
    now = time.time() if now is None else now
    by_id = {}
    for r in mine:
        if r.get("comment_id"):
            by_id.setdefault(r["comment_id"], []).append(r)
    answered, exhausted = set(), {}
    for cid, rs in by_id.items():
        bad = [r for r in rs if unfinished(r)]
        if any(r in running for r in rs) or any(not unfinished(r) and has_result(r) for r in rs):
            answered.add(cid)
        elif len(bad) >= MAX_FAILS:
            answered.add(cid)
            exhausted[cid] = max(bad, key=lambda r: r.get("ts", 0))
        elif any(has_result(r) for r in bad) and \
                now - max(r.get("ts", 0) for r in bad if has_result(r)) < RETRY_COOLDOWN_SECS:
            # Only a run that reported a passing blocker waits; one that died without a result (e.g. the
            # gateway did not answer session.create under load) is retried on the next tick.
            answered.add(cid)
    return answered, exhausted


def why_unfinished(rec):
    """First sentence of the unfinished run's summary (or its error) for the digest line."""
    text = rec.get("error") or ""
    if has_result(rec):
        text = read_result(rec).get("summary") or text
    text = " ".join(str(text).split()) or "the session ended without a result"
    m = re.match(r".*?[.!?](?=\s|$)", text)
    return (m.group(0) if m else text)[:300]


def failed_dispatch(rec):
    """A launch error, or a dead session that left no accepted result. A valid result of any status
    (RELEASED, BLOCKED, ...) is a finished round, never a failure."""
    return bool(rec.get('error') or (rec.get('pid') and not alive(rec['pid']) and not has_result(rec)))


def handled_bot_reviews(mine):
    """Bot reviews a babysit round with a valid result of any status already looked at and decided."""
    handled = set()
    for r in mine:
        if r.get("kind") != "babysit" or not has_result(r):
            continue
        result = read_result(r)
        if result.get("status") == "BLOCKED" and result.get("owner_decision") is not True:
            continue  # a transient block: leave the review due so a later round retries it
        if r.get("bot_review_id"):
            handled.add(r["bot_review_id"])
        handled.update(r.get("bot_review_ids") or [])
    return handled


def retry_budget(recs, now=None):
    """Three failed attempts per six-hour window; recover automatically after transient blockers."""
    now = time.time() if now is None else now
    recent = [r for r in recs if now - r.get('ts', 0) < 6 * 3600]
    failures = [r for r in recent if failed_dispatch(r)]
    return len(failures) < MAX_FAILS


def is_waiting_result(result):
    """A review result whose only blocker is pending checks: nobody has anything to do."""
    return (result.get('verdict') == 'BLOCKED' and result.get('owner_decision') is False
            and result.get('blocked_reason') == 'PENDING_CI')


def waiting_for_checks(recs, last_verdict, head):
    """True when the newest review of this exact head is a machine-classified waiting-for-checks result."""
    if not recs or not last_verdict or last_verdict[0] != 'BLOCKED' or last_verdict[1] != head:
        return False
    latest = max(recs, key=lambda rec: rec.get('ts', 0))
    if not has_result(latest):
        return False
    result = read_result(latest)
    # The url match preserves owner rulings posted after this result.
    return bool(is_waiting_result(result) and result.get('url') and result['url'] == last_verdict[2].get('html_url'))


def transient_review_due(recs, rollup, last_verdict, head):
    """Resume machine-classified pending checks, never guess from human finding text."""
    if not waiting_for_checks(recs, last_verdict, head):
        return False
    # Never re-review pending CI.
    return ci_round_due(rollup, set(), head, head)[2]


def verdict_label(verdict):
    """State label for a finished review verdict whose label write was lost."""
    return {"READY": HUMAN_MERGE, "FIX": FIX_QUEUED}.get(verdict, HUMAN_DECISION)


def checks_complete(rollup):
    """Every check except the human gates in PR_HUMAN_CHECKS has finished, with any conclusion."""
    checks = [c for c in (rollup or []) if (c.get('name') or '').strip().casefold()
              not in HUMAN_CHECKS]
    # Classic commit statuses (context/state, no status) are finished unless PENDING/EXPECTED.
    return bool(checks) and all(
        (c.get('state') not in ('PENDING', 'EXPECTED') if 'status' not in c and 'state' in c
         else c.get('status') == 'COMPLETED') for c in checks)


def waiting_results(recs):
    return [r for r in recs if has_result(r) and is_waiting_result(
        read_result(r))]


def latest_waiting_ts(recs):
    return max((r.get('ts', 0) for r in waiting_results(recs)), default=0)


def waiting_exhausted(recs, last_verdict, head):
    """True when this head already had WAIT_REVIEW_CAP waiting reviews and still waits."""
    return (waiting_for_checks(recs, last_verdict, head)
            and len(waiting_results(recs)) >= WAIT_REVIEW_CAP)


def review_wanted(label, labels, done_at_head, mention_review, at_head, rollup, last_v, head, now=None):
    """Whether a review should start now (before the drift checks).

    A review that is waiting for checks keeps review-bot:queued and starts only when the checks finish."""
    now = time.time() if now is None else now
    want = (label == REVIEW_QUEUED and not done_at_head) or bool(mention_review)
    if (label == REVIEW_QUEUED and want and not mention_review
            and waiting_for_checks(at_head, last_v, head)):
        # Any finished outcome re-runs it (the fresh review reports red or cancelled checks), but not
        # every tick and not forever.
        want = (checks_complete(rollup) and not waiting_exhausted(at_head, last_v, head)
                and now - latest_waiting_ts(at_head) >= WAIT_RECHECK_SECS)
    if (label == HUMAN_DECISION and not done_at_head
            and not waiting_exhausted(at_head, last_v, head)
            and transient_review_due(at_head, rollup, last_v, head)):
        want = True  # legacy: a pending-check result that was labelled for the owner
    return want


def author_pushed_head(recs, head):
    """True when a handled author round published exactly the current head.

    Such a push needs a fresh independent review even when the PR never carried
    a state label (sweep-owned bot maintenance claims a PR with only
    `fix-bot:owns-branch`). Without this, the round's own push leaves nothing due."""
    for rec in recs:
        if rec.get('kind') != 'babysit' or not handled_dispatch(rec):
            continue
        try:
            result = read_result(rec)
        except (OSError, ValueError, KeyError):
            continue
        if result.get('head') == head and result.get('input_head', rec.get('head')) != head:
            return True
    return False


def set_state_label(repo, n, label):
    if DRY:
        out.append(f"DRY: would set {repo}#{n} label {label}")
        return
    cur = [lbl["name"] for lbl in gh("api", f"repos/{repo}/issues/{n}/labels")]
    for name in cur:
        if name in STATE_LABELS and name != label:
            gh("api", "-X", "DELETE", f"repos/{repo}/issues/{n}/labels/{name}", parse=False)
    if label and label not in cur:
        gh("api", "-X", "POST", f"repos/{repo}/issues/{n}/labels", "-f", f"labels[]={label}", parse=False)


def remove_label(repo, n, label):
    if not DRY:
        gh("api", "-X", "DELETE", f"repos/{repo}/issues/{n}/labels/{label}", parse=False)


def signing_for(repo, branch):
    """Whether the branch rules require signed commits: required | optional | unknown (cached per tick)."""
    key = (repo, branch)
    if key not in _SIGNING:
        try:
            rules = gh("api", f"repos/{repo}/rules/branches/{urllib.parse.quote(branch, safe='')}")
            _SIGNING[key] = "required" if any(
                isinstance(x, dict) and x.get("type") == "required_signatures" for x in rules or []) else "optional"
        except Exception:  # noqa: BLE001
            _SIGNING[key] = "unknown"
    return _SIGNING[key]


def spawn(kind, repo, pr, head, model, reasoning, skills, extra=None):
    """Launch a session that outlives this tick."""
    n = pr["number"]
    tag = f"{kind}-pr{n}-{head[:8]}-{time.time_ns()}"
    if DRY:
        out.append(f"DRY: would spawn {kind} for {repo}#{n} at {head[:8]}")
        return 0, tag
    artifacts_dir = LOGS / tag  # pipeline-owned and durable: the session writes its verification logs here
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    extra = {"merge_state": "UNKNOWN", "merge_status": "UNKNOWN", "base_branch": "", "base_sha": "",
             "integrate_strategy": "merge", "signing": "unknown", "fix_loops": 0, "fix_loop_cap": FIX_LOOP_CAP,
             "trusted_logins": ", ".join(sorted(OWNERS)) or "none", "comment_id": "none", **(extra or {})}
    checkout = checkout_of(repo)
    short_head = head[:7]
    rename = session_launcher.rename_step(ENV, hermes_bin=HERMES, number=n, short_head=short_head)
    prompt = (PROMPTS / f"{kind}.md").read_text().format(
        repo=repo, number=n, head=head, short_head=short_head, title=pr["title"], branch=pr["headRefName"],
        checkout=checkout, rename_step=f"{rename} " if rename else "", handle=HANDLE,
        result_file=(RESULTS / f"{tag}.json").as_posix(), tag=tag, artifacts_dir=artifacts_dir.as_posix(),
        scripts_dir=str(pathlib.Path(__file__).resolve().parent), **extra)
    pfile = LOGS / f"{tag}.prompt.md"
    pfile.write_text(prompt)
    env = {k: v for k, v in ENV.items() if not k.startswith(("HERMES_CRON", "HERMES_SESSION"))}
    pid = session_launcher.launch(
        ENV, hermes_argv=[HERMES, "chat", "-Q", "--oneshot", "--query-file", str(pfile), "--source", "tool",
                          "--reasoning", reasoning, "-s", skills,
                          *(["-m", model] if model else []), *(["--provider", PROVIDER] if PROVIDER else [])],
        prompt_file=pfile, title=f"PR #{n} {kind} @{short_head} {repo}", checkout=checkout,
        log_file=LOGS / f"{tag}.log", model=model, provider=PROVIDER, child_env=env)
    return pid, tag


def record(recs, rec):
    recs.append(rec)
    if not DRY:
        with DISPATCH.open("a") as f:
            f.write(json.dumps(rec, sort_keys=True) + "\n")


# ---------------------------------------------------------------- the tick

def addressed_without_code(mine, head, verdict_id):
    """Newest handled fix round for this verdict that resolved the review without publishing code
    (it edited the PR body, answered threads) and says so in its result; else None."""
    found = None
    for r in sorted(mine, key=lambda x: x.get("ts", 0)):
        if (r.get("kind") != "babysit" or r.get("head") != head or not verdict_id
                or r.get("verdict_id") != verdict_id or not handled_dispatch(r)):
            continue
        result = read_result(r)
        if (result.get("status") == "FIXED" and result.get("addressed_without_code") is True
                and result.get("head", head) == result.get("input_head", head)):
            found = r
    return found


def human_comment(repo, n, head, key, headline, why, how, comments, reported):
    """One PR comment when the sweep itself hands a PR to a person (house style, docs/references/comment-style.md).

    Deduped per PR + head + reason by `reported` and by a hidden marker in the PR's own comments."""
    marker = f"<!-- pr-sweep needs-human head={head[:12]} reason={key} -->"
    rkey = f"human:{repo}#{n}:{head}:{key}"
    if rkey in reported or any(marker in (c.get("body") or "") for c in comments):
        return
    # The newest comment is already a bot comment for this head that asks for the person's decision
    # (typically the review that reached the FIX-loop cap): a second one would only bury it.
    last = comments[-1] if comments else {}
    last_body = last.get("body") or ""
    if "\U0001F916" in last_body and "Needs your decision" in last_body and head[:7] in last_body:
        return
    body = (f"\U0001F916 **Needs your decision: {headline}**\n\n{why[:1].upper() + why[1:]}\n\n"
            f"<details>\n<summary>What to reply</summary>\n\n{how}\n\n</details>\n{marker}")
    if DRY:
        out.append(f"DRY: would comment on {repo}#{n}: {headline}")
        return
    try:
        gh("api", "-X", "POST", f"repos/{repo}/issues/{n}/comments", "-f", f"body={body}", parse=False)
        reported.add(rkey)
    except Exception as e:  # noqa: BLE001 — the digest line still reaches the owner
        out.append(f"{repo}#{n}: could not post the hand-over comment: {e}")


PEOPLE_QUERY = ("query($o:String!,$r:String!,$p:Int!){repository(owner:$o,name:$r){pullRequest(number:$p){"
                "assignees(first:20){nodes{login}} closingIssuesReferences(first:10){nodes{repository{nameWithOwner} "
                "assignees(first:10){nodes{login}}}}}}}")


def pr_people(repo, n):
    """Logins who may command the bots on PR n (lower case): the responders, the PR's assignees and the
    assignees of the issues it closes (the people responsible for the work). Owners always may.
    A failed read falls back to the responders alone."""
    found = set(RESPONDERS)
    owner, name = repo.split("/")
    try:
        pull = gh("api", "graphql", "-f", f"query={PEOPLE_QUERY}", "-f", f"o={owner}", "-f", f"r={name}",
                  "-F", f"p={n}")["data"]["repository"]["pullRequest"] or {}
    except Exception:  # noqa: BLE001 — unknown assignees: owners and responders still count
        return found
    nodes = list((pull.get("assignees") or {}).get("nodes") or [])
    for issue in (pull.get("closingIssuesReferences") or {}).get("nodes") or []:
        # Only issues of this repository: "Closes someone/else#1" must not make its assignees people of the PR.
        if ((issue.get("repository") or {}).get("nameWithOwner") or "").lower() == repo.lower():
            nodes += (issue.get("assignees") or {}).get("nodes") or []
    return found | {(a.get("login") or "").lower() for a in nodes if a and a.get("login")}


def sweep_repo(repo, recs, reported):
    pulls = gh("pr", "list", "-R", repo, "--state", "open", "--limit", "100",
               "--json", "number,title,headRefName,headRefOid,labels,isDraft,statusCheckRollup,mergeable,mergeStateStatus,"
               "baseRefName,isCrossRepository")
    for pr in sorted(pulls, key=lambda p: p["number"]):
        n, head = pr["number"], pr["headRefOid"]
        if pr.get("isCrossRepository"):
            # A fork's branch: the bots never check it out, run its code or push to it (a person reviews it).
            continue
        labels = [lbl["name"] for lbl in pr["labels"]]
        if any(name in LEGACY_LABELS for name in labels):
            labels = migrate_labels(repo, n, labels)
        label = state_label(labels)
        people_cache = []

        def people(number=n, cache=people_cache):
            if not cache:
                cache.append(pr_people(repo, number))
            return cache[0]
        comments = trusted_comments(gh("api", f"repos/{repo}/issues/{n}/comments?per_page=100"), agent_logins(), people)
        reviews = gh("api", f"repos/{repo}/pulls/{n}/reviews?per_page=100")
        owner_name, repo_name = repo.split("/")
        try:
            threads = gh("api", "graphql", "-f", f"query={THREADS_QUERY}", "-f", f"o={owner_name}",
                         "-f", f"r={repo_name}", "-F", f"p={n}")["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]
            open_threads = unanswered_threads(threads, agent_logins(), lambda: OWNERS | people() | set(BOT_REVIEWERS))
        except Exception:  # noqa: BLE001 — unknown thread state never blocks the rest of the sweep
            open_threads = []
        vs = verdicts(comments)
        last_v = vs[-1] if vs else None
        mine = [r for r in recs if r.get("repo") == repo and r["pr"] == n]
        running = [r for r in mine if r.get("pid") and alive(r["pid"])]
        dispatched_before = len(recs)

        for r in running:  # stuck: a live session past its budget, reported once
            age = (time.time() - r["ts"]) / 60
            key = f"stuck:{r['tag']}"
            if age > STUCK_MIN and key not in reported:
                reported.add(key)
                bot = "review bot" if r["kind"] == "review" else "fix bot"
                out.append(f"{repo}#{n}: the {bot} has been running for {int(age)} min, longer than expected. "
                           f"No action needed unless it is still running later (log {LOGS / (r['tag'] + '.log')}).")

        # Author-push demotion: a sweep-owned author round published this head on a PR
        # without a state label (maintenance-only claim). Re-review it instead of stalling.
        if (label is None and sweep_owned(comments) and author_pushed_head(mine, head)
                and not any(r["kind"] == "review" and r["head"] == head for r in mine)):
            set_state_label(repo, n, REVIEW_QUEUED)
            label = REVIEW_QUEUED
            out.append(f"{repo}#{n}: the fix bot pushed {head[:8]}; the review bot will check it.")

        if label == HUMAN_MERGE and open_threads:
            set_state_label(repo, n, FIX_QUEUED)
            label = FIX_QUEUED
            out.append(f"{repo}#{n}: not ready to merge yet: {len(open_threads)} review comment(s) have no answer. "
                       f"The fix bot will fix or answer them, then the review runs again.")

        # Push demotion: a verdict whose head is not the PR head is stale.
        ready_at_head = bool(last_v) and last_v[0] == "READY" and head.startswith(last_v[1])
        fix_at_head = bool(last_v) and last_v[0] == "FIX" and head.startswith(last_v[1])
        if label in HUMAN_STATES and last_v and not head.startswith(last_v[1]):
            set_state_label(repo, n, REVIEW_QUEUED)
            label = REVIEW_QUEUED
            if last_v[0] == "READY":
                out.append(f"{repo}#{n}: new commits after the passed review at {last_v[1][:8]}; "
                           f"back to {REVIEW_QUEUED}.")
        # fix-bot:queued only stands for a FIX verdict or red CI at this exact commit; after new
        # commits the review bot must check them first.
        if label == FIX_QUEUED and not fix_at_head and not ready_at_head:
            set_state_label(repo, n, REVIEW_QUEUED)
            label = REVIEW_QUEUED

        # CI gate (merge contract): required checks red at the stamped READY head
        # invalidate mergeable advice; the babysitting author owns the fix; green
        # restores. A CI fix round is maintenance, not a verdict response.
        handled_ci = {r.get("ci_key") for r in mine if r["kind"] == "babysit" and handled_dispatch(r)} | settled_ci_keys(mine)
        ci_fires, ci_key, ci_ok = ci_round_due(pr.get("statusCheckRollup"), handled_ci,
                                               last_v[1] if last_v else None, head)
        if ci_fires:
            if label == HUMAN_MERGE:
                set_state_label(repo, n, FIX_QUEUED)
                label = FIX_QUEUED
                reported.add(f"ci:{repo}#{n}:{ci_key}")
                out.append(f"{repo}#{n}: CI red on the reviewed commit ({'; '.join(ci_fires)}); "
                           f"back to {FIX_QUEUED} until green.")
            elif label in BOT_STATES:
                rkey = f"ci:{repo}#{n}:{ci_key}"
                if rkey not in reported:
                    reported.add(rkey)
                    out.append(f"{repo}#{n}: CI red ({'; '.join(ci_fires)}); the fix bot will fix it.")
        elif ci_ok and ci_key and label == FIX_QUEUED and ready_at_head and not open_threads:
            set_state_label(repo, n, HUMAN_MERGE)
            label = HUMAN_MERGE
            out.append(f"{repo}#{n}: CI green on the reviewed commit; back to {HUMAN_MERGE}.")
        cancelled = inert_checks(pr.get("statusCheckRollup"))
        if cancelled:
            ckey = f"cancelled:{repo}#{n}:{head[:12]}"
            if ckey not in reported:
                reported.add(ckey)
                out.append(f"{repo}#{n}: needs a person: these checks were cancelled on the latest commit "
                           f"({'; '.join(cancelled)}). Re-run them in GitHub Actions. No fix bot was started.")

        # A request is answered only by a real outcome; a failed or transiently blocked run leaves it
        # pending (retried after the cooldown, at most MAX_FAILS times, then reported once).
        answered, exhausted = owner_requests(mine, running)
        for cid, rec in exhausted.items():
            rkey = f"ownerreq:{repo}#{n}:{cid}"
            if rkey not in reported:
                reported.add(rkey)
                out.append(f"{repo}#{n}: the fix bot could not carry out your request after {MAX_FAILS} tries: "
                           f"{why_unfinished(rec)} Reply with a new request once that is resolved.")
        mention_review, mention_babysit = mentions(comments, HANDLES, answered)

        claim = claim_state(labels, comments, time.time())
        babysitter_running = any(r["kind"] == "babysit" for r in running)
        if claim == "stale" and not babysitter_running:
            remove_label(repo, n, FIX_OWNS)
            out.append(f"{repo}#{n}: the chat session working on this branch was inactive for over {STALE_MIN} min; "
                       f"removed {FIX_OWNS}, so the bots take over again. No action needed.")
            claim = "none"

        # A fix round that resolved the review without pushing code (PR body edit, answered threads) hands
        # back to the review bot for a fresh review of the same head. A review that repeats the FIX counts
        # toward FIX_LOOP_CAP like any other, so this cannot ping-pong forever.
        fix_loops = sum(1 for v in vs if v[0] == "FIX")
        over_cap = fix_loops > FIX_LOOP_CAP
        verdict_id = last_v[2]["id"] if last_v else None
        no_code_rec = (addressed_without_code(mine, head, verdict_id)
                       if fix_at_head and not over_cap else None)
        if no_code_rec and label == FIX_QUEUED:
            set_state_label(repo, n, REVIEW_QUEUED)
            label = REVIEW_QUEUED
            out.append(f"{repo}#{n}: the fix bot resolved the review without changing code; "
                       f"the review bot checks {head[:8]} again.")

        # Reviewer side: runs regardless of any babysit claim. A dispatch is done only when it wrote a
        # result file; a dead session without one is a failed dispatch, retried up to MAX_FAILS per head.
        reviewer_running = any(r["kind"] == "review" for r in running)
        at_head = [r for r in mine if r["kind"] == "review" and r["head"] == head]
        # Reviews that predate a description-only fix round do not count: that round changed what they judged.
        done_at_head = any(handled_dispatch(r) for r in at_head
                           if not no_code_rec or r.get("ts", 0) > no_code_rec.get("ts", 0))
        last_reason = ''
        for r in sorted(mine, key=lambda x: x.get('ts', 0)):
            why = result_problem(r) if r.get('pid') and not alive(r['pid']) else None
            if why and why != 'no result file':
                last_reason = why if r in at_head else last_reason
                rk = f"rejected:{r.get('tag')}"
                if rk not in reported:
                    reported.add(rk)
                    out.append(f"{repo}#{n}: {r['kind']} result for #{n} rejected: {why}")
            elif r.get('error') and r in at_head:
                last_reason = f"could not start: {r['error']}"
        fails = sum(1 for r in at_head if time.time() - r['ts'] < 6 * 3600 and failed_dispatch(r))
        # A waiting-for-checks review keeps review-bot:queued and starts again once the checks finish.
        want_review = review_wanted(label, labels, done_at_head, mention_review, at_head,
                                    pr.get('statusCheckRollup'), last_v, head)
        if (label == REVIEW_QUEUED and not reviewer_running and not mention_review
                and waiting_exhausted(at_head, last_v, head)):
            set_state_label(repo, n, HUMAN_DECISION)
            label = HUMAN_DECISION
            want_review = False
            key = f"waitcap:{repo}#{n}:{head}"
            if key not in reported:
                reported.add(key)
                out.append(f"{repo}#{n}: needs your decision: the checks never settled after {WAIT_REVIEW_CAP} "
                           f"reviews on {head[:8]}. Look at the checks, then re-run the review.")
            human_comment(repo, n, head, "waitcap", "the checks never settled",
                          f"the checks never settled after {WAIT_REVIEW_CAP} reviews on {head[:8]}.",
                          f"Look at the checks, then reply `{HANDLE} review` to run the review again.",
                          comments, reported)
        if label == REVIEW_RUNNING and not reviewer_running and not done_at_head:
            want_review = True  # drift: review-bot:running with nobody working it
        if (label in (REVIEW_QUEUED, REVIEW_RUNNING) and not reviewer_running and done_at_head
                and not mention_review and last_v and head.startswith(last_v[1])):
            # This commit is already reviewed (or its label write was lost): the verdict decides who acts.
            label = verdict_label(last_v[0])
            set_state_label(repo, n, label)
            want_review = False
        owned = claim == "active" and sweep_owned(comments)
        chat_claim = claim == "active" and not owned  # a person's chat session holds the branch
        # Merge conflicts come first: a conflicting head cannot be merged, so no review starts on it.
        conflicting = pr.get("mergeable") == "CONFLICTING"
        base_branch = pr.get("baseRefName") or ""
        base_sha = ""
        if conflicting and base_branch:
            try:
                base_info = gh("api", f"repos/{repo}/branches/{base_branch}")
                base_sha = ((base_info or {}).get("commit") or {}).get("sha", "") if isinstance(base_info, dict) else ""
            except Exception:  # noqa: BLE001 — the round still runs; the prompt re-reads the base tip
                base_sha = ""
        conflict_label = label in (HUMAN_MERGE, FIX_QUEUED, REVIEW_QUEUED, REVIEW_RUNNING)
        # A conflict round is done for this head once it pushed, or stopped for an owner decision. A round
        # that failed or stopped on a passing blocker (e.g. a GitHub rate limit while pushing) is retried
        # after RETRY_COOLDOWN_SECS, at most MAX_FAILS times per head, and never counts toward CONFLICT_CAP.
        head_rounds = [r for r in mine if r.get("conflict_key") == head]
        retries_spent = sum(1 for r in head_rounds if unfinished(r)) >= MAX_FAILS
        conflict_done = retries_spent or any(
            not r.get("error") and not (unfinished(r) and time.time() - r.get("ts", 0) >= RETRY_COOLDOWN_SECS)
            for r in head_rounds)
        # Automatic rounds since the owner last asked for a fix are capped; owner rounds are not.
        last_owner = max([r.get("ts", 0) for r in mine if r["kind"] == "babysit" and r.get("comment_id")] or [0])
        conflict_auto = sum(1 for r in mine if r["kind"] == "babysit" and r.get("conflict_auto")
                            and r.get("ts", 0) > last_owner and not unfinished(r))
        conflict_capped = conflict_auto >= CONFLICT_CAP
        # Under a needs-human decision the round is conflict-only: it merges the base in,
        # leaves the findings and the label alone, and stays silent unless a choice is needed.
        conflict_only_label = label == HUMAN_DECISION
        conflict_open = (conflicting and (conflict_label or conflict_only_label) and not chat_claim
                         and not pr["isDraft"])
        conflict_round = conflict_open and not conflict_done and not conflict_capped
        if conflicting and not pr["isDraft"]:
            want_review = False
        if conflict_open and conflict_capped and not conflict_done and not mention_babysit and not babysitter_running:
            human_comment(repo, n, head, "conflictcap", "the fix bot could not bring the base branch in",
                          f"the fix bot tried {CONFLICT_CAP} times to bring {base_branch or 'the base branch'} into this "
                          f"branch and it still conflicts.",
                          f"Reply `{HANDLE} fix` (add `rebase` for a rebase) to try again, or merge the base branch in by hand.",
                          comments, reported)
        if conflicting and chat_claim:
            ckey = f"conflict:{repo}#{n}:{head}"
            if ckey not in reported:
                reported.add(ckey)
                out.append(f"{repo}#{n}: has merge conflicts with its base branch and cannot be merged. A chat session "
                           f"holds this branch, so the fix bot will not touch it: merge or rebase the base branch "
                           f"into it there, or remove {FIX_OWNS} to let the fix bot do it.")
        # An explicit owner request may launch past the cap, once per request: a failed run that
        # carried this comment already used it.
        retry_asked = bool(mention_review) and not any(r.get('comment_id') == mention_review['id'] for r in at_head
                                                         if r.get('error') or not has_result(r))
        review_exhausted = False
        if want_review and not reviewer_running and not pr["isDraft"]:
            if fails >= MAX_FAILS and not retry_asked:
                review_exhausted = True
                if label == REVIEW_RUNNING:
                    # Nothing is running: the review waits for the retry cooldown.
                    set_state_label(repo, n, REVIEW_QUEUED)
                    label = REVIEW_QUEUED
                key = f"fails:{repo}#{n}:{head}"
                if key not in reported:
                    reported.add(key)
                    out.append(f"{repo}#{n}: {fails} review runs on {head[:8]} failed"
                               f"{': ' + last_reason if last_reason else ''}; reply `{HANDLE} review` to retry now, "
                               f"or it retries automatically after a six-hour cooldown (logs {LOGS}).")
            else:
                rec = {"ts": time.time(), "kind": "review", "repo": repo, "pr": n, "head": head,
                       "comment_id": mention_review["id"] if mention_review else None}
                try:
                    set_state_label(repo, n, REVIEW_RUNNING)
                    rec["pid"], rec["tag"] = spawn("review", repo, pr, head, REVIEW_MODEL, REVIEW_REASONING, REVIEW_SKILLS,
                                                   {"fix_loops": fix_loops, "fix_loop_cap": FIX_LOOP_CAP,
                                                    "trusted_logins": trusted_logins(people)})
                    if mention_review:
                        react(repo, mention_review["id"])
                except Exception as e:  # noqa: BLE001 — recorded; retried next tick
                    rec["error"] = str(e)[:300]
                record(recs, rec)

        # Author side: one babysit round per session. Only continue sweep-owned claims; a chat-started
        # babysitter runs its own watcher and must not get a twin.
        round_done = any(r["kind"] == "babysit" and r["head"] == head and r.get("verdict_id") == verdict_id
                         and handled_dispatch(r) for r in mine)
        # A CI red is author-ownable maintenance even with nobody on the PR: a
        # READY-stamped head may not sit red unclaimed until green. The round
        # posts its own sweep-owned claim (prompt step 1); chat-started
        # claims still get no twin, and a stale claim recovers above.
        ci_round = (owned or claim == "none") and bool(ci_fires)
        handled_bots = handled_bot_reviews(mine)
        bot_rev, capped, bot_seen = bot_round_due(bot_reviews(reviews), handled_bots)
        if capped and (owned or claim == "none"):
            key = f"botcap:{repo}#{n}"
            if key not in reported:
                reported.add(key)
                out.append(f"{repo}#{n}: Copilot has reviewed this PR {BOT_CAP} times; the fix bot no longer "
                           f"answers new Copilot reviews. Reply `{HANDLE} fix` if you want another fix attempt.")
        # A FIX verdict starts the fix bot automatically (fix-bot:queued must never sit idle), unless a
        # person's chat session holds the branch or the review already asked for changes FIX_LOOP_CAP times.
        fix_round = fix_at_head and not round_done and not chat_claim and not over_cap
        # A Copilot review must be answered even when no fix round holds the branch (the claim is released
        # between rounds); only a person's chat session keeps the branch to itself.
        bot_round = (owned or claim == "none") and bot_rev is not None and not fix_round
        handled_threads = {i for r in mine if handled_dispatch(r) for i in (r.get("thread_ids") or [])}
        new_threads = [i for i in open_threads if i not in handled_threads]
        thread_round = ((owned or claim == "none") and bool(new_threads) and label == FIX_QUEUED
                        and not fix_round and not bot_round)
        # An owner fix request is honoured when nobody holds the branch or the sweep holds it between
        # rounds; only a person's chat session keeps exclusivity (no two authors on one branch).
        owner_round = bool(mention_babysit) and not chat_claim
        want_babysit = owner_round or fix_round or bot_round or thread_round or ci_round or conflict_round
        # A conflicting head is not reviewed; when no fix round will start either, say why once per head.
        decision_hold = label == HUMAN_DECISION and not owner_round
        # Conflicts that need no decision are merged in by a conflict-only round (no "held" notice); the
        # notice remains for the cases that get no round (capped, or already tried at this head).
        conflict_only = (conflict_round and decision_hold and not (fix_round or bot_round or thread_round
                         or ci_round or owner_round))
        if (conflicting and not pr["isDraft"] and not chat_claim and decision_hold
                and not conflict_open):
            why = "it is waiting on your decision"
            how = (f"Answer the open question, or reply `{HANDLE} fix` (add `rebase` for a rebase) and the fix bot "
                   f"brings {base_branch or 'the base branch'} in.")
            if label in (HUMAN_DECISION, HUMAN_MERGE):  # already a needs-human state with its own comment
                ckey = f"conflict:{repo}#{n}:{head}"
                if ckey not in reported:
                    reported.add(ckey)
                    out.append(f"{repo}#{n}: has merge conflicts with its base branch and cannot be merged; "
                               f"the fix bot is not fixing them because {why}. {how}")
            else:
                human_comment(repo, n, head, "conflictheld", "this pull request has merge conflicts",
                              f"the fix bot is not fixing them because {why}.", how, comments, reported)
        author_attempts = [r for r in mine if r['kind'] == 'babysit' and r['head'] == head]
        if want_babysit and not retry_budget(author_attempts):
            key = f"author-fails:{repo}#{n}:{head}:{int(time.time() // (6 * 3600))}"
            if key not in reported:
                reported.add(key)
                out.append(f"{repo}#{n}: the fix bot failed {MAX_FAILS} times on this commit; it retries "
                           f"automatically in 6 hours (logs {LOGS}).")
            want_babysit = False
        # Shared author limit: with PIPELINE_WIP author sessions live (fix rounds here plus the pipeline's work
        # sessions), the round waits for a free slot; the PR does not count as idle meanwhile.
        deferred = (want_babysit and not babysitter_running
                    and len(pipeline_runtime.live_authors([STATE, *(BOARD_STATES or [PIPELINE_STATE])], alive)) >= WIP)
        if deferred:
            want_babysit = False
            if mention_babysit and f"deferred:{mention_babysit['id']}" not in reported:
                reported.add(f"deferred:{mention_babysit['id']}")
                out.append(f"{repo}#{n}: your fix request waits for a free bot: all {WIP} author slots are busy "
                           f"(PIPELINE_WIP). It starts by itself when one frees up.")
        if want_babysit and not babysitter_running:
            rec = {"ts": time.time(), "kind": "babysit", "repo": repo, "pr": n, "head": head,
                   "comment_id": mention_babysit["id"] if mention_babysit else None,
                   "verdict_id": verdict_id if fix_round or owner_round else None,
                   "bot_review_id": bot_rev["id"] if bot_round and bot_rev else None,
                   "bot_review_ids": bot_seen if bot_round else [],
                   "thread_ids": open_threads,
                   "ci_key": ci_key if ci_round else None}
            if conflicting:
                rec["conflict_key"] = head
                rec["conflict_auto"] = conflict_round and not owner_round
            try:
                rec["pid"], rec["tag"] = spawn("babysit", repo, pr, head, BABYSIT_MODEL, "medium", BABYSIT_SKILLS,
                                               {"fix_loops": fix_loops, "signing": signing_for(repo, pr["headRefName"]),
                                                "bot_rounds": len(bot_reviews(reviews)), "bot_cap": BOT_CAP,
                                                "merge_state": pr.get("mergeable") or "UNKNOWN",
                                                "merge_status": pr.get("mergeStateStatus") or "UNKNOWN",
                                                "base_branch": base_branch, "base_sha": base_sha,
                                                "integrate_strategy": integrate_strategy(mention_babysit, HANDLES) if owner_round else "merge",
                                                "conflict_only": conflict_only,
                                                "trusted_logins": trusted_logins(people),
                                                "comment_id": mention_babysit["id"] if mention_babysit else "none",
                                                "trigger": "owner request" if owner_round else ("merge conflict only" if conflict_only else "merge conflict" if conflict_round and not (fix_round or bot_round) else ("CI red" if ci_round else ("bot review" if bot_round else ("open review threads" if thread_round else "verdict"))))})
                if mention_babysit:
                    react(repo, mention_babysit["id"])
            except Exception as e:  # noqa: BLE001
                rec["error"] = str(e)[:300]
            record(recs, rec)

        # Invariant: a bot state label must name a bot that will act. When none will, hand the PR to a
        # person with `needs-human:decision` and say exactly what to do.
        idle = (len(recs) == dispatched_before and not deferred
                and not any(r.get("pid") and alive(r["pid"]) for r in mine))
        url = f"https://github.com/{repo}/pull/{n}"
        if idle and label in BOT_STATES and not pr["isDraft"]:
            reason = key = headline = None
            why = how = ""
            last_fix = max((r for r in mine if r["kind"] == "babysit" and r["head"] == head and has_result(r)),
                           key=lambda r: r.get("ts", 0), default=None)
            fix_result = read_result(last_fix) if last_fix else {}
            if label == FIX_QUEUED and chat_claim:
                key, headline = "chat-claim", "a chat session holds this branch"
                why = f"a chat session holds this branch ({FIX_OWNS}), so the fix bot will not push."
                how = f"Fix it in that session, or remove {FIX_OWNS} to hand the branch back."
            elif label == FIX_QUEUED and fix_at_head and over_cap:
                key, headline = "fix-loop-cap", "the review keeps asking for changes"
                why = f"the review bot asked for changes {fix_loops} times."
                how = (f"Reply `{HANDLE} fix` (first line, optionally with instructions) for another fix round, "
                       "or fix it by hand.")
            elif fix_result.get("status") == "ESCALATE" and fix_result.get("owner_decision") is True:
                key, headline = "fix-escalated", "the fix bot needs a decision"
                why, how = "the fix bot needs a decision; see its latest comment on the PR.", ""
            elif label == FIX_QUEUED and not retry_budget(author_attempts):
                key, headline = "fix-failed", "the fix bot failed on this commit"
                why = f"the fix bot failed {MAX_FAILS} times on this commit (logs {LOGS})."
                how = f"Fix it by hand or reply `{HANDLE} fix` after the cause is resolved."
            elif label == FIX_QUEUED and open_threads and not new_threads:
                key, headline = "open-threads", "review comments have no answer"
                why = f"the fix bot left {len(open_threads)} review comment(s) without an answer."
                how = f"Answer or resolve them on the PR, or reply `{HANDLE} fix` with instructions."
            elif label == FIX_QUEUED and fix_at_head and round_done:
                key, headline = "fix-no-change", "the fix bot did not change anything"
                why = "the fix bot answered the review without changing code."
                how = f"Reply `{HANDLE} review` to re-check, or `{HANDLE} fix` with instructions."
            if key:
                reason = f"{why} {how}".strip()
                set_state_label(repo, n, HUMAN_DECISION)
                label = HUMAN_DECISION
                out.append(f"{repo}#{n}: {HUMAN_DECISION}: {reason} {url}")
                # The fix bot (fix-escalated) or the review itself (fix-loop-cap: its first line is
                # "Needs your decision") already posted the comment the person reads.
                if key not in ("fix-escalated", "fix-loop-cap"):
                    human_comment(repo, n, head, key, headline, why, how or f"Reply `{HANDLE} review` or `{HANDLE} fix`.",
                                  comments, reported)

        # Liveness: a PR the automation has engaged must never sit silently. When no worker runs,
        # nothing was dispatched this tick and the last activity is older than STALL_MIN, tell the
        # owner once per head what reply moves it. needs-human PRs are already notified + digested.
        engaged = label is not None or FIX_OWNS in labels
        if engaged and label not in HUMAN_STATES and not pr["isDraft"] and idle \
                and not review_exhausted:
            last = max((r.get("ts", 0) for r in mine), default=0)
            key = f"stall:{repo}#{n}:{head}"
            if time.time() - last > STALL_MIN * 60 and key not in reported:
                reported.add(key)
                state = label or f"{FIX_OWNS} only"
                out.append(f"{repo}#{n}: no bot is due to act on {head[:8]} (label: {state}). "
                           f"Reply on the PR, first line `{HANDLE} review` for a fresh review "
                           f"or `{HANDLE} fix` for a fix round. {url}")


def load_reported():
    """The delivered-results ledger. A missing file is empty; a damaged one (killed tick, disk full) must not stop
    the sweep or re-send old results: it is rebuilt from the result files on disk, which were all delivered.
    The synthetic one-shot keys (stuck:/ci:/fails:/...) cannot be recovered, so such a report may fire once more."""
    if not REPORTED.exists():
        return set()
    try:
        data = json.loads(REPORTED.read_text())
        if isinstance(data, list):
            return set(data)
    except (ValueError, OSError):
        pass
    out.append(f"PR bots: the list of already-sent messages ({REPORTED}) was damaged and has been rebuilt. "
               "No action needed.")
    return {f.name for f in RESULTS.glob("*.json")}


def save_reported(reported):
    """Atomic write: a killed tick never leaves the ledger truncated."""
    tmp = REPORTED.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(sorted(reported)))
    os.replace(tmp, REPORTED)


def load_dispatch():
    """The dispatch ledger; a torn or corrupt line (a crash mid-write) is skipped, never fatal."""
    recs = []
    for line in (DISPATCH.read_text().splitlines() if DISPATCH.exists() else []):
        try:
            rec = json.loads(line) if line.strip() else None
        except ValueError:
            rec = None
        if isinstance(rec, dict):
            recs.append(rec)
    return recs


def main():
    try:
        _, mapped = pipeline_runtime.repositories(ENV)
        BOARD_STATES[:] = pipeline_runtime.board_states(ENV, PIPELINE_STATE)
    except ValueError as e:
        print(f"PR sweep error: {e}")
        return 1
    CHECKOUTS.update({repo: settings["checkout"] for repo, settings in mapped.items() if settings.get("checkout")})
    if not REPOS:
        REPOS.extend(mapped)
    if not REPOS:
        print("PR sweep error: set PR_SWEEP_REPOS (or PIPELINE_REPOSITORIES / PIPELINE_REPO)")
        return 1
    if not OWNERS:
        # Without owners nobody may command the bots, and nothing tells a person's comment from a stranger's.
        print("PR sweep error: set PIPELINE_OWNERS (the logins who command the bots)")
        return 1
    if not agent_logins():
        # Without a bot login every bot-answered review thread looks open and READY PRs are demoted each tick.
        print("PR sweep error: no bot login: set PIPELINE_BOT_LOGINS (or an @ handle in PR_AGENT_HANDLE), "
              "or log gh in as the bot account")
        return 1
    for d in (STATE, RESULTS, LOGS):
        d.mkdir(parents=True, exist_ok=True)
    recs = load_dispatch()
    reported = load_reported()

    # Deliver finished sessions: READY / BLOCKED / ESCALATE / babysit exits. FIX stays silent.
    for f in sorted(RESULTS.glob("*.json")):
        if f.name in reported:
            continue
        dispatch = next((rec for rec in recs if rec.get('tag') == f.stem), None)
        if dispatch is None or not has_result(dispatch):
            continue
        try:
            r = json.loads(f.read_text())
        except ValueError:
            continue
        reported.add(f.name)
        if r.get("notify", True) and r.get("verdict") != "FIX" and not is_waiting_result(r):  # waiting needs no owner
            word = {"READY": "review passed", "BLOCKED": "needs your decision", "STALE": "review outdated",
                    "FIXED": "fix bot pushed changes", "ESCALATE": "needs your decision",
                    "RELEASED": "fix bot stopped", }.get(r.get("verdict") or r.get("status"), r.get("verdict") or r.get("status") or "?")
            out.append(f"{r.get('repo', '')}#{r.get('pr')} [{word}] "
                       f"{r.get('summary', '').strip()} {r.get('url', '')}".strip())

    errors = []
    asked_lines.clear()
    probe_errors.clear()
    config_error = False
    try:
        session_launcher.kind(ENV)
        quiet = pipeline_runtime.quiet_now(ENV, "pr")  # quiet hours: results still arrive, no session starts
    except ValueError as e:
        quiet = True
        errors.append(f"PR sweep error: {e}")
        config_error = True
    for repo in sorted(REPOS) if not quiet else ():
        try:
            sweep_repo(repo, recs, reported)
        except Exception as e:  # noqa: BLE001 — one repo failing must not starve the others
            errors.append(f"PR sweep error ({repo}): {e}")
    if not DRY:
        save_reported(reported)
    failures = errors + list(probe_errors.values())
    if DRY:
        lines = out + list(asked_lines.values()) + failures
    else:
        # Every repository failing: one plain alert, repeated hourly, then one line when it runs again. A single
        # failing repository repeats its line at most once per pipeline_runtime.DEDUPE_TTL.
        health = STATE / "health"
        # A configuration error stops every repository; a quiet tick ran nothing, so it proves no recovery.
        down = bool(probe_errors) or config_error or (bool(errors) and len(errors) == len(REPOS))
        status = (pipeline_runtime.job_down(health, "PR sweep", "; ".join(failures)) if down
                  else [] if quiet else pipeline_runtime.job_up(health, "PR sweep"))
        notices = list(asked_lines.values()) + ([] if down else errors)
        lines = status + out + (pipeline_runtime.fresh_lines(health, "errors", notices) if notices or not down else [])
    if lines:
        print("\n".join(lines))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
