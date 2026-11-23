# Bot Comment Style

Every comment, review reply and PR description a board bot posts follows this reference. Readers are engineers who
do not follow AI tooling: say who acts next, keep it short, and keep the machinery out of sight. Hidden HTML markers
(`<!-- ... -->`), JSON result fields and command syntax keep their exact machine form.

`<handle>` below is the configured command handle (`PR_AGENT_HANDLE`, default `/devbot`). Bot text always shows the
first configured handle in its canonical form.

## Posting

Post every issue or PR comment through the comment helper, which checks it first:

```
python3 <scripts>/post-comment.py --repo <owner/repo> --number <N> --body-file <file> [--kind <kind>]
```

- The helper infers `--kind` from the hidden marker and adds the `🤖 ` prefix when it is missing.
- Until `COMMENT_STYLE_ENFORCE_FROM` (an ISO date) it only warns; from that date on it refuses a comment that breaks
  the rules (exit 2). Shorten the comment and post again.
- Never fall back to `gh issue comment` or `gh pr comment`.
- Some rules apply even in warn mode: a "still waiting" notice must link an existing comment on the same issue, and a
  duplicate waiting notice is skipped.

The checker lives in `scripts/comment_style.py`; its kinds and budgets are the ones below.

## The Rules

- **Bot prefix.** Comments, reviews, review-thread replies and PR descriptions a bot posts start with `🤖 `. A
  person's own comments never do. Commit messages never do.
- **First line:** `🤖 **<who acts>: <what>**`, at most 12 words after the colon. Who acts is one of `Needs your
  decision`, `Needs your approval`, `Needs your help`, `Ready to schedule`, `No action needed`, `Review passed`,
  `Changes needed`, `Waiting for checks`, `Still waiting`, `Paused`, `Possibly done`, `Closed`, `Back to you`. Never
  write "Gate", the issue title, the commit or the branch.
- **Sections:** only these, in this order, and only when they have entries: `## Done` · `## Waiting on` ·
  `## Blockers` · `## Decisions made` · `## Questions` · `## Proposed new issues`. PR reviews use `## Must fix` ·
  `## Should fix` in place of `## Done`. Never write "None.".
  - `## Waiting on` is for things that finish by themselves (running or queued CI, a job waiting for a free bot).
  - `## Blockers` is only for a problem someone must act on.
  - After the sections comes the collapsed reply menu, then the hidden marker on the last line.
- **Bullets, not paragraphs.** One fact per bullet, in the past tense or as a short noun phrase.
- **Every bullet stands alone.** No bare IDs (T3, F6, D17 outside its own list); name the thing. Leave out passing
  checks, test counts and process steps. Mention a failing check only when it blocks this item.
- **Decision lines:** `- D<n>. <what was done>: <one reason>.` Sources go into the design or plan file, not the
  comment.
- **Questions:** at most 3, each with its options and a ⭐ recommendation:

  ```md
  1. <question>?
     - _Option A_: <option>. _[⭐ <reason, ≤ 10 words>]_
     - _Option B_: <option>.
  ```

  A yes/no question ends with `_[⭐ yes]_` or `_[⭐ no]_`.
- **Links:** `[PR #656](url)`, `[issue #652](url)`, `[design](url)`, `[plan](url)`. No bare URLs or file paths; list a
  file only when the reader should open it.
- **Hide in `<!-- -->`:** field changes, decisions triage filled in, commit, branch, plan directory, session ids, log
  paths, test counts.
- **Collapse in `<details>`:** reply menus, review checklists, check results, earlier history and test output.

### Budgets

Visible words, excluding `<details>` and `<!-- -->`:

| Kind | Marker | Budget |
|---|---|---|
| Approval step (gate) | `gate` | 200 |
| Blocked | `blocked` | 120 |
| Triage ready | `triage outcome=ready` | 40 |
| Triage clarify | `triage outcome=clarify` | 160 |
| Close proposal | `close-proposal` | 40 |
| PR review result | `pr-review` | 150 |
| Fix-bot summary | `babysit-round` | 60 |
| Notice | (none) | 60 |
| Claim, link, sync line | `work:`, `fix-bot:`, `pr-link`, `sync` | one line |

Per section: Done ≤ 6 bullets, Blockers ≤ 3, Decisions made ≤ 8, Questions ≤ 3.

## Plain Language

1. **Say who acts next in the first line.**
2. **Keep commits, branches and paths out of visible text.** They go into the hidden marker; links carry them. If a
   commit must be named, write "latest commit (`abc1234`)", never "head".
3. **Keep internal field names and mechanisms out of visible text**: no `owner_decision`, `PENDING_CI`,
   `mergeStateStatus`, dispatch, tick, sweep, worker, harness or adapter.
4. **Replace jargon; don't explain it in brackets.** A fact must make sense without context.
5. **Present every decision the owner must make as a question, the options and a recommendation.** Decisions the
   bot made itself go under `## Decisions made` with their source, never as questions.

| Don't write | Write instead |
|---|---|
| gate / gated / re-gated | "waiting for your approval (design)" / "revised, waiting for your approval again" |
| owner ruling / escalate / ESCALATE | "needs your decision" |
| owner-only | "only you can do this" |
| fail-closed | "when in doubt, refuse" |
| reconcile / superseded | "already done in #N; close or reduce this issue" |
| round / maintenance round | "fix attempt" / "fix attempt for failing checks" |
| FIX-loop cap / bot cap | "after 2 automatic fixes, it's your call" |
| claim / released / heartbeat | "the bot is working on this branch" / "the bot stopped working on this" / "last active" |
| trigger | "started because: …" |
| WIP / slot | "waiting for a free bot (2 run at once)" |
| cooldown / retry budget | "retries automatically in 30 minutes" |
| companion PR | "related PR in `<repo>`" |
| deviation | "change from the approved plan" |
| head / current head / at this head | leave it out (the marker has it) |
| stale (about a review) | "outdated: new commits arrived" |
| delta | "changes since the last review" |
| verdict READY / FIX / BLOCKED (visible) | "Review passed" / "Changes needed: the fix bot will make them" / "Needs your decision" |
| BLOCKER / MAJOR / MINOR / Nit | "Must fix" / "Should fix" / "Optional" |
| evidence / artifact | "test results" / "log" / "file" |
| failing-first / RED → GREEN | "a test that failed before the fix and passes after" |
| DIRTY / CONFLICTING | "has merge conflicts with main" |
| rollup / check run | "CI results" |
| Gate: … / What is done / What went wrong | the sections `## Done`, `## Waiting on`, `## Blockers` |
| Fields set … / Decided for you … (visible) | hidden marker attributes |
| all tests green / N passed | leave it out |
| note that / as expected / re-checked / I did not touch | leave it out |
| reply with a plain comment | `<handle> answer: …` or the reply menu |

Keep product and domain terms, CI job and check names, command-line flags, file names and code identifiers exactly as
spelled.

## Board Names

The board shows these names; the tools and markers use the internal ones and accept both.

| Internal | Board |
|---|---|
| Track | **Size**: `fast-path` → `small fix`, `standard-implementation` → `needs design`, `analysis-spike` → `investigation`, `docs-process` → `docs` |
| Origin | **Source**: `human-request` → `requested`, `plan-follow-up` → `from a plan`, `review-finding` → `from a review`, `agent-observation` → `bot noticed`, `external-issue` → `external` |
| Autonomy | **Bot approvals**: `gated` → `ask at each step`, `auto` → `proceed alone` |
| Status | `Backlog` → `🧑 Backlog`, `Inbox` → `🤖 Inbox`, `Ready` → `🧑 📋 Ready to schedule`, `Up next` → `🤖 Up next`, `In progress` → `🤖 In progress`, `Your turn` → `🧑 Your turn`, `In review` → `🤖 In review`, `Icebox` → `Later`; `Done` and `Canceled` unchanged |
| Waiting for | `💬 answer`, `👍 approve`, `🛠️ unblock`, `⚖️ decide on PR`, `🔀 merge PR`, `⏳ Bot's turn` |

The Status prefix says who acts next: 🧑 a person, 🤖 a bot, none = nobody. Your turn is the one person column; the
card's Waiting for field names the action. In comments, write board names without the emoji ("moved to Your turn,
waiting for your approval").

## Commands

An instruction to a bot is a comment whose **first line** is `<handle> <command>`. A plain comment is never a command,
and a first line ending in `?` is a question, not a command. Other spellings are accepted (`\devbot approved`,
`/DevBot: approve`, `fixed`, `re-review`) through one shared parser (`scripts/commands.py`); bot text shows the
canonical form.

| Command | Where | Effect |
|---|---|---|
| `approve` | approval step | accept the decisions and recommended answers; continue |
| `revise: <answers or vetoes by number>` | approval step | redo the step with your changes |
| `discuss` | approval step | pause the bots for a live discussion |
| `reject` | approval step | cancel the item |
| `unblock: <what changed>` | blocked item | continue |
| `answer: <answers by number>` | clarification questions | triage reads the answers; `answer: approve` accepts every recommendation |
| `close` / `keep` | close proposal | close the issue / keep it open |
| `fix` / `review` | pull request | fix bot / review bot runs again (instructions below the first line) |
| `fix rebase` / `fix merge` | pull request with conflicts or behind its base | the fix bot brings the base in first: `merge` (default) adds a merge commit; `rebase` replays the PR commits and pushes with a lease |

## Reply Menus

Copy these; they stay collapsed.

Approval step:

```md
<details>
<summary><b>Reply with</b> <code><handle> approve|revise|discuss|reject</code></summary>

| Reply | Effect |
|---|---|
| `<handle> approve` | Accept every decision and recommended answer; continue |
| `<handle> revise: <answers or vetoes by number>` | Update this step and ask again |
| `<handle> discuss` | Pause the bots for a live discussion |
| `<handle> reject` | Cancel the item |
</details>
```

- Blocked: summary `<b>Reply with</b> <code><handle> unblock: &lt;what changed&gt;</code>`, one row `<handle> unblock:
  <what changed>` → Continue.
- Clarification questions: summary `<b>Reply with</b> <code><handle> answer: 1A, 2 yes, …</code>`, rows
  `<handle> answer: <answers by number>` → Triage reads your answers, and `<handle> answer: approve` → Accept every
  recommended answer.
- Close proposal: summary `<b>Reply with</b> <code><handle> close|keep</code>`, rows `close` (close as completed) and
  `keep` (keep open; not proposed again).
- Pull request: summary `<b>Commands</b> <code><handle> fix|review</code>`, rows `fix`, `fix rebase` / `fix merge`,
  `review`, and "Merge (only you)".

## Templates

### Approval Step

```md
🤖 **Needs your approval: plan for the per-joint speed limits**

## Done
- schema v8 with per-joint planning limits

Files: [design](url) · [plan](url)

## Decisions made
- D1. Kept each robot's own calibration: dropping it silently is unsafe.

## Questions
1. Release both limits together?
   - _Option A_: yes, one PR. _[⭐ smaller change]_
   - _Option B_: two PRs.

<details>…approval-step menu…</details>
<!-- gate stage=<Stage> head=<full sha> branch=<branch> plan=<plan dir> -->
```

- First line: `Needs your approval: <what>` for design, plan and findings steps; `Needs your decision: <the conflict>`
  for escalations; `Needs your approval: nothing to decide, approve to continue` when there are no questions.
- `## Done` is left out on design steps; `## Blockers` appears on escalations only; `## Proposed new issues` (at most
  3 one-liners, each after a duplicate search) appears on findings steps and epic splits only.

### Blocked

The card moves to Your turn (Waiting for: unblock); this comment is the comment that move needs.

```md
🤖 **Needs your help: the test bench is offline**

## Blockers
- the bench does not answer; the bot cannot run the hardware test
- power it on, or reply `<handle> unblock: skip the bench test`

<details>…blocked menu…</details>
<!-- blocked reason=<short-key> -->
```

### Triage: Ready

```md
🤖 **Ready to schedule: move the card to Up next when a bot should start.**

- each caller that starts a move names its speed limit
<!-- triage outcome=ready fields="Size=needs design Priority=P1" decided="…" -->
```

At most 2 bullets. Fields set and decisions filled in go in the marker attributes.

### Triage: Clarify

```md
🤖 **Needs your decision: which part of this item should the bots take?**

## Questions
1. Scope?
   - _Option A_: phase 1 only. _[⭐ phase 2 needs its own design]_
   - _Option B_: the whole item.

<details>…clarification menu…</details>
<!-- triage outcome=clarify fields="…" -->
```

Optional `## Done` (at most 2 bullets, only facts that change the questions) and `## Blockers`.

### Close Proposal

```md
🤖 **Possibly done: duplicate of [issue #612](url). Close this issue?**

- closes automatically after 48 h (2026-10-10 14:00 UTC) unless you reply

<details>…close-proposal menu…</details>
<!-- close-proposal reason=duplicate dup=612 pr=- auto_close_after=2026-10-10T14:00:00Z -->
<!-- triage outcome=clarify -->
```

The proposal also carries the `needs-human:approve-close` label so board sync can find it.

### Notices

At most 60 words, no sections.

- `🤖 **Still waiting for your answers: [questions](<url of the question comment>).** Reply with `<handle> answer:
  …`.` Only when open questions exist; the link to an existing comment of this issue is mandatory.
- `🤖 **Paused for a live discussion.** …` (posted by the dispatcher).

### PR Review Result

```md
🤖 **Changes needed: the fix bot acts next**

## Must fix
- `src/planner.rs:212` — the speed limit is skipped when the segment is empty

## Should fix
- `docs/motion.md` — the new stop cause is not listed

## Waiting on
- CI: `tests` and 2 more jobs still running

<details><summary>Review checklist (8 checks: 7 pass, 1 waiting)</summary>…</details>
<details>…pull-request menu…</details>

**Result: Changes needed (the fix bot will make them)**
<!-- pr-review verdict=FIX head=<sha> -->
```

- Never restate what the PR does or summarise earlier reviews.
- BLOCKED results add `## Questions` in the standard format.
- **Waiting for checks** (the only open item is CI still running, no open owner question): first line
  `🤖 **Waiting for checks: the review bot runs again when they finish**`, one `## Waiting on` line, checklist and
  commands in `<details>`, result line `**Result: Waiting for checks (no action needed)**`, marker `verdict=BLOCKED`,
  label `review-bot:queued`. If an earlier bot comment on the same commit asked the owner something unanswered, repeat
  that question under `## Questions` and end with Needs your decision instead.

### Fix-Bot Summary

```md
🤖 **No action needed: the review bot checks the new commit next.**

## Done
- fixed the empty-segment speed limit (`src/planner.rs`)

<details><summary>Checks run</summary>…</details>
<!-- babysit-round … -->
```

### Claims, Links and Status Lines

Claims (`🤖 work: …`, `🤖 fix-bot: owns this branch; …`), related-PR links and board-sync notes stay one line.
Session ids and timestamps go inside the marker.
