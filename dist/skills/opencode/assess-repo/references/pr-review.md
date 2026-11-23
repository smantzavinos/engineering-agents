# PR Review Process

Canonical process for creating and reviewing pull requests across repos that
follow this workflow. Mirrors task tracking and requirements handling: this doc
defines common concepts, rules, and required hooks; each repo implements the
hooks via a single `pr-review-hooks.md` manifest at its root.

One skill executes the process in two roles:

- `pull-request` — as **Author**: prepares the PR body, evidence, and
  self-review before the PR opens. As **Reviewer**: executes the review
  rules, posts the findings table and verdict, and stamps the reviewed SHA.

The process exists to make PR review automatic: the human reviewer reads one
digest and merges, or gets pulled in only for escalations.

---

## Roles

| Role | Who | Rule |
|------|-----|------|
| Author | Implementing agent | Runs `pull-request` (Author role); fixes findings |
| Reviewer | A different agent than the author | Runs `pull-request` (Reviewer role); never the same agent/session as the author |
| Human | Repo owner | Escalations, backwards-compat calls, merge. Humans are never the first pass |

The reviewer-must-differ rule extends the contract-first principle: tests and
reviews come from a different agent than the implementer.

---

## Required Repo Hooks

Every repo using this process maintains a `pr-review-hooks.md` file at its
root, routed from `AGENTS.md`. One file, fixed sections, pointers plus facts.
The authoritative rule detail (typing rules, UI rules, capture guides) stays in
the files where it already lives; the manifest points to them.

| Hook | Required question answered | Manifest section |
|------|----------------------------|------------------|
| Review inputs | Which files must a reviewer load before reviewing? | `## review-inputs` |
| Local review rules | What repo-specific rules apply beyond the common set? | `## review-rules` |
| Verification commands | Which commands verify the change, per slot? | `## verification-commands` |
| Evidence captures | What visual proof is expected for which change types, and how is it produced? | `## evidence-captures` |
| PR tracking | Where does review state live, and what triggers autonomous follow-up? | `## pr-tracking` |
| Merge gate | What gates a merge and who merges? | `## merge-gate` |

### Manifest shape

Each section is a fixed-shape table so skills can parse it deterministically.

```markdown
## review-inputs
| file | why a reviewer needs it |
|------|-------------------------|

## review-rules
| rule | severity | detection |
|------|----------|-----------|

## verification-commands
| slot | command | pass condition |
|------|---------|----------------|

## evidence-captures
| change type | method | command | artifact home |
|-------------|--------|---------|---------------|

## pr-tracking
| field | value |
|-------|-------|

## merge-gate
| gate | requirement |
|------|-------------|
```

Severity vocabulary for `review-rules`: `BLOCKER` (cannot merge), `MAJOR`
(fix before merge), `MINOR` (fix now or list under `Considered and not done`;
never backlog — see "Finish in task"), `ESCALATE` (human decision
required, always).

New repos: `assess-repo` drafts the manifest as part of repo setup.

---

## PR body contract

PR bodies use these sections, in this order. Leave out a section that has no
content; never write `None.`. `Intent and scope` and `What changed / What did
not change` are always present. Bot-written bodies start with `🤖 ` and follow
the [comment style](comment-style.md) for wording.

```markdown
## Intent and scope
One paragraph: the problem, the chosen approach, what is explicitly NOT in
this PR.

## What changed / What did not change
Behavior level, not file level. "What did not change" lists adjacent things a
nervous reviewer might suspect were touched.

## Diagrams
Mermaid. Required when the diff adds/modifies/removes: a component, an API
surface, a data flow, or a schema. Show the pieces of the system that exist
and mark the new/modified/removed data flows. Skip only for pure-text or
pure-config diffs.

## Evidence
Per the repo's evidence-captures table. UI changes: before/after captures.
See evidence tiers below.

## Testing overview
| test | layer | what it actually proves |
Automation first; manual steps listed separately with exact steps.

## Review rules
The filled table: rule → evidence/link → pass/fail/N-A. Pre-filled by the
author; confirmed by the reviewer.

## Decisions made
Numbered list, each with its source in brackets (`software-development`
"Decide, don't ask"). The owner vetoes with `revise: D<n>` in a comment.

## Considered and not done
One line each: review Minors and nice-to-haves deliberately left out.

## Proposed new issues (need your OK)
Genuine defects outside this PR that cannot be fixed here, each with the
duplicate search done. Never filed without the owner's approval.

## Follow-ups
Only issues that already exist, with numbers.
```

Rules for the body:

- Pseudocode or plain-language description of tricky logic beats raw diffs.
- Evidence links are durable GitHub URLs (comments, review captures), not
  ephemeral attachments.
- No plan-internal artifacts leak into the body (task IDs internal to a plan,
  scratch notes).

---

## Evidence tiers

| Tier | When | Content |
|------|------|---------|
| 0 — always | Every PR | Body contract, Mermaid diagrams, testing table |
| 1 — UI diff | Any PR touching user-visible UI | Before/after captures per the repo's evidence-captures method |
| 2 — opt-in | Requested by the human, or large feature work | Narrated demo video (captured scenes + TTS narration stitched to MP4), built by a background subagent; linked in the PR |

Tier 2 is never a default. Proof artifacts never substitute for the tests
named in the testing table.

---

## Common review rules

These apply in every repo. The manifest adds repo-specific rules; it never
repeats these.

| # | Rule | Severity | Detection guidance |
|---|------|----------|--------------------|
| R1 | **Schema review first.** Schemas/data models are the single source of truth. No hardcoded task-type or category literal enums where the repo's registry pattern applies; new types must be data, not migrations. Reviewer reads the schema layer before any logic. | BLOCKER | Read schema/migration diff first; grep for literal unions duplicating registry values |
| R2 | **Types follow the repo's typing rules.** No `any`/`unknown`-smuggling, no double casts (`as unknown as X`), no hand-rolled context/db interfaces where the framework provides generics. | BLOCKER | Grep the diff for `any`, `unknown as`, `as any` |
| R3 | **Comments earn their place.** Comments explain why, for future readers, especially where code is intentional but looks unusual. No implementation narration, no references to plan-internal task IDs. | MINOR→MAJOR | Read every added/modified comment in the diff |
| R4 | **Backwards compatibility / legacy code is a human decision.** Any code kept "for compatibility", any deprecated-path retention, any dual-write/shim is flagged for the human reviewer. This is where cruft sneaks in. The author must declare it in the body; the reviewer must verify nothing was added silently. | ESCALATE | Grep diff for `deprecated`, `legacy`, `compat`, `shim`, `fallback`; author declaration cross-check |
| R5 | **Consistency.** Patterns, UI, APIs, and tests match the repo's existing exemplars. | MAJOR | Diff against neighboring code; manifest review-inputs name the exemplars |
| R6 | **Tests catch bugs, not mirror implementation.** Each behavioral change has a test that would fail on a real regression; assertions check behavior, not internal call patterns; no tautological tests. | BLOCKER | Invert each new test mentally: would plausible bugs pass it? |

Severity calibration and finding format reuse the `review-code` conventions
(Blocker/Critical/Major/Minor/Nit). Common-rule severities above are floors,
not ceilings.

---

## Review loop rules

1. **Author self-review before opening.** The Author role runs the common rules
   and the manifest rules against the author's own diff and pre-fills the
   review-rules table. A PR that fails its own table does not open.
2. **Reviewer independence.** The Reviewer role runs in a fresh session/agent that
   is not the author's session.
3. **First pass is full.** The reviewer verifies every common rule and every
   manifest rule, runs the manifest verification commands, and posts:
   - the filled review-rules table with evidence links,
   - findings as a severity-ordered list,
   - a verdict: `READY`, `FIX` (findings below Blocker), or `BLOCKED`,
     closed by the machine-readable marker
     `<!-- pr-review verdict=<VERDICT> head=<full sha> -->` so the verdict
     history (and with it the fix-loop bound below) is countable.
4. **Re-review is incremental.** The reviewer stamps the reviewed SHA in a PR
   comment (`reviewed@<sha>`). Subsequent passes review only the delta since
   the stamp plus verification that prior findings are resolved. Unchanged,
   already-approved code is not re-reviewed.
5. **Review threads gate READY.** The Reviewer posts READY only when every
   review thread on the PR is resolved. An unresolved thread whose last
   comment is not the PR author's is `FIX` (the author resolves it by fixing
   or by answering with evidence), or an ESCALATE finding when it needs a
   human decision. The Reviewer never resolves threads
   itself. The author side (babysit) resolves the threads it addresses.
6. **Fix loops are bounded.** The author fixes and pushes; after **two** fix
   loops without a `READY` verdict, the PR escalates to the human with the
   findings history summarized. An explicit owner `fix` command is a ruling
   for that round and is not counted against the bound. Agents do not loop indefinitely, and the
   human never reviews an intermediate state.
7. **Notifications.** On `READY`, the author notifies the human with a short
   digest: what the PR does, evidence links, the verdict, and the merge-gate
   status. On `BLOCKED` or any ESCALATE finding, the human is notified
   immediately with the specific question. Humans are not notified about
   intermediate `FIX` states.
8. **State stays truthful.** PR/project status moves per the repo's
   pr-tracking manifest. Reviewers and authors update state to reflect
   reality; stale "in review" state is a process bug.

---

## Merge

The merge gate is the repo's `merge-gate` manifest section (required checks,
required verdict, who merges). Only the human merges; agents stage work for
merge. The agent's merge handoff (`needs-human:merge`) requires an independent
READY at the exact current head and completed, passing checks; pending,
absent or incomplete check evidence is not green. Checks only a person can
satisfy (for example a merge-label check; `PR_HUMAN_CHECKS`) are expected to
be absent at handoff and are never an agent failure. Required checks are a hard gate in both
directions: the Reviewer posts BLOCKED, never READY, when a required check is
red at the reviewed head; the author (usually the babysitting session) keeps
them green and fixes reds — CI maintenance rounds do not consume the
fix-loop bound. Division of labor: the manifest row binds the Reviewer's
verdict; the sweep's mechanical demotion treats every completed failing
check as red (its CI red→round transition fires once per head+conclusion
set, tracked in `ci_key`); classic commit statuses (context/state) are not
read.

### A change across several repositories

For a change whose code is in git submodules of a root repository, pinned by
commits of the root.

- **The set.** One PR per changed submodule, and one PR in the root. The root
  PR holds the pointer moves and whatever the root itself changes (plan
  record, docs). Every repository in the set needs its own
  `pr-review-hooks.md`; each PR follows this contract in its own repository.
- **Links.** The root PR's body lists every PR of the set, with the commit
  of each submodule that the root pins. Each submodule PR's body links the
  root PR. The plan record and the evidence that spans repositories go in the
  root PR; a submodule PR carries what its own diff needs.
- **Opened together.** Push every branch, then open the submodule PRs, then
  the root PR. A set with one changed submodule is still two PRs.
- **Merge order.** Submodule PRs first, each by the method its repository's
  `merge-gate` names: a merge commit, a squash or a rebase. The root PR is
  `BLOCKED` until every submodule PR of the set is merged.
- **The merged commit.** A merge leaves one commit for the PR at the tip of
  the submodule's target branch (on GitHub:
  `gh pr view <n> --json mergeCommit`). After a squash or a rebase it is a
  new commit and does not descend from the reviewed head. No step may assume
  that it does.
- **The tree check.** Before a pointer moves, confirm that the merged commit
  holds exactly what was reviewed: its tree equals the tree of the reviewed
  head, the head the last `READY` verdict marker on that PR names.

  ```sh
  git -C <submodule> fetch origin <target branch> refs/pull/<n>/head
  git -C <submodule> rev-parse '<merged commit>^{tree}' '<reviewed head>^{tree}'   # the same id twice
  ```

  If the trees differ (the target branch moved and the merge took in other
  work, or the head moved after the verdict), escalate with
  `git diff --stat <reviewed head> <merged commit>`. Never move that pointer
  on your own; the human decides.
- **The last pointer move.** When every submodule PR is merged and every tree
  check has passed, the author side (the session that opened the set, or the
  one babysitting the root PR) adds one commit to the root PR that moves each
  pointer to its merged commit. The body then lists, per submodule, the merged
  commit beside the reviewed head. The move changes no file (the trees are
  equal), so it is not re-reviewed; the root's required checks run on it as on
  any push.
- **The review record keeps naming the reviewed commits.** The root's earlier
  commits pin them, and the ledger and the verdict markers name them. After a
  squash or a rebase they are not on the target branch. They stay reachable
  on the host under the PR's head ref (on GitHub `refs/pull/<n>/head`, fetched
  as above), which a default fetch does not bring.
- **A fix after review** in a submodule is a new commit there and a new root
  commit that pins it. Never rewrite a pinned commit before the merge.

---

## Orchestration (cron / hooks)

How this process is driven automatically — polling open PRs, dispatching
`pull-request` (Reviewer role), and routing notifications — is defined
separately and is
deliberately not part of this doc. The manual process above is the contract;
automation is an accelerator on top of it.

Where the PR sits in the item's lifecycle (opening the PR starts babysitting;
bot-review rounds are capped) is defined in the engineering-agents
`docs/references/delivery-pipeline.md` (§4 PR lifecycle).
