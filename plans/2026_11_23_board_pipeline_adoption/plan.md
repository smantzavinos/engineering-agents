# Adopt the board-pipeline improvements from gm-agent-pipeline

|                 |  |
|-----------------|--|
| **Created**     | 2026-11-23 |
| **Source**      | https://github.com/globusmedical/gm-agent-pipeline (Daniel Gehriger), clone at `/tmp/daniel/gm-agent-pipeline` |
| **Approved**    | Owner, 2026-11-23 ("adopt all its improvements as you suggested") |
| **Branch**      | `pilot/arch-plans` |

## Goal

Take every generic improvement Daniel made to our backlog / delivery pipeline / PR
process, leave out what is specific to his company (Sonar, Windows path
workarounds, GitHub-API-only publishing, `ready for merge` label, GM shared
repositories, patient-safety wording, Confluence/development-kb, Pi disabled in
favour of Hermes profiles, model failover, Jira, instance auto-onboarding).

## Contract (every doc, skill, prompt and script follows this)

**Statuses (internal → board name):** `Backlog` → `🧑 Backlog`, `Inbox` → `🤖 Inbox`,
`Ready` → `🧑 📋 Ready to schedule`, `Up next` → `🤖 Up next`, `In progress` →
`🤖 In progress`, `Your turn` → `🧑 Your turn`, `In review` → `🤖 In review`,
`Icebox` → `Later`, `Done`, `Canceled`. Removed: `Clarification needed`,
`Awaiting approval`, `Blocked`. `Backlog`: no bot reads or moves it; a person
moves a card to Inbox. Off-board issues land in Backlog; issues a bot created
(with approval) carry `<!-- bot-created source=<owner/repo#N> -->` and go to Inbox.

**Waiting for** (display only, never read by a bot): `💬 answer`, `👍 approve`,
`🛠️ unblock`, `⚖️ decide on PR`, `🔀 merge PR`; board sync may show `⏳ Bot's turn`
once a valid reply waits for the dispatcher. The kind of wait comes from the
newest bot marker (gate → approve, `blocked` → unblock, `triage outcome=clarify`
→ answer) or, for a PR, its labels (`needs-human:merge` → merge, other
`needs-human:*` → decide). Close proposals never count. Every move into
`Your turn` carries a comment.

**Fields (internal → board name):** Track → Size (`fast-path`→`small fix`,
`standard-implementation`→`needs design`, `analysis-spike`→`investigation`,
`docs-process`→`docs`); Origin → Source (`human-request`→`requested`,
`plan-follow-up`→`from a plan`, `review-finding`→`from a review`,
`agent-observation`→`bot noticed`, `external-issue`→`external`); Autonomy →
Bot approvals (`gated`→`ask at each step`, `auto`→`proceed alone`). Tools
accept both names.

**Markers:** `<!-- gate stage=<S> head=<sha> branch=<b> plan=<dir> -->`;
`<!-- triage outcome=ready|clarify fields="…" decided="…" -->` (no `left`;
historical `left` read only); `<!-- blocked reason=<key> -->`;
`<!-- close-proposal reason=duplicate|fixed dup=<N|-> pr=<N|-> auto_close_after=<UTC ISO> -->`;
`<!-- bot-created source=… -->`; `<!-- reply-unreadable comment=<id> -->`;
`<!-- pr-review verdict=READY|FIX|BLOCKED head=<sha> -->`, `<!-- reviewed@<sha> -->`.

**Commands:** first line `<handle> <verb>`; handle default `/devbot`, `@name`
also accepted; one tolerant parser (case, `\` sigil, optional colon,
inflections such as approved/fixed/re-review); a trailing `?` is a question,
never a command. Issue verbs by kind of wait: `answer:` (incl. `answer: approve`),
`approve` / `revise:` / `discuss` / `reject`, `unblock:`, `close` / `keep`
(close proposals only). PR verbs: `fix`, `fix rebase`, `fix merge`, `review`.
Who may answer: owner, the item's assignees, configured responders; gate
approvals are owner-only. 👀 reaction marks a reply as read and accepted.

**PR labels (old → new):** `pr:ready-review` → `review-bot:queued`;
`pr:in-review` → `review-bot:running`; `pr:re-review` → `fix-bot:queued` after
a FIX verdict, `review-bot:queued` after a push; `pr:ready-merge` →
`needs-human:merge`; `pr:escalated` → `needs-human:decision`; `pr:babysat` →
`fix-bot:owns-branch`; `pipeline:discuss` → `needs-human:discussion`. The sweep
still reads and renames the old names.

**Tracker CLI** (`PIPELINE_MOVE_CMD` / list command): `list` prints JSON items;
`move N STATUS [--comment T] [--expect S] [--ack-reply ID]` (compare-and-set:
fails with a message containing `is no longer` when the card moved);
`set N FIELD VALUE` (used for `Waiting for`).

**Comment style:** `docs/references/comment-style.md` (merged from his
`comment-templates.md` + `plain-language.md`, handle as `<handle>`): first line
`🤖 **<who acts>: <what>**`; sections in order Done · Waiting on · Blockers ·
Decisions made · Questions · Proposed new issues (reviews: Must fix · Should
fix); empty sections omitted; word budgets; ⭐ recommended options; collapsed
reply menus; bookkeeping in hidden markers; checked by `scripts/post-comment.py`.

**Policies:** "Decide, don't ask" (owner list: unresolved contradiction,
irreversible/external action, spend, security posture, FROZEN change, safety
behaviour the spec does not fix, creating a backlog item); "Finish in task"
(do item work in the item; Minors fixed now or dropped under "Considered and
not done"; only genuine out-of-scope defects proposed under "Proposed new
issues (need your OK)" after a duplicate search; no new TODOs); Plan gate only
when the plan departs from the approved design; PR body omits empty sections
and adds Decisions made / Considered and not done / Proposed new issues.

## Work

1. Worker A (worktree): `scripts/commands.py`, `comment_style.py`,
   `post-comment.py`, port `pipeline-dispatch.py` + `pr-sweep-dispatch.py` from
   his `pipeline/upstream/`, generic prompts, ported unit tests, spec wiring.
2. Worker B (worktree): `scripts/gh-project.py` (generic port of
   `gem-project.py`), `scripts/board-sync.py` (subset: closed → Done,
   close-proposal auto-close, PR links, Waiting-for reconcile, Backlog/Inbox
   intake, fields, migrate-your-turn), tests.
3. Parent: contract docs, ADR 0008, skills, `skill-resources.json`, render
   `dist/`, AGENTS.md/backlog capture policy.
4. Parent: merge, `./tests/run-tests.sh fast`, fresh review, fixes, commit, push.
5. Notify the "Pi Delegation and Extension Review" thread (use ADR 0009).
