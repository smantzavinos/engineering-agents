---
name: software-development
description: "Use when starting or continuing ANY software development work, when the human says 'follow the dev process' (or similar), or when unsure which development stage comes next. The top-level entry: loads the process, locates the current stage via the stage-gate table, and routes to the stage skill."
harnesses: [hermes]
---

# Software Development — process entry and stage routing

This is the ENTRY skill for the engineering-agents development process. It
owns the stage-gate table (below) and routing; it owns NO stage content —
each stage's skill does that. The pipeline is sequential-first:

```
intake → BRIEF → RESEARCH → APPROACH → APPROACH REVIEW → PLAN → PLAN REVIEW
       → (human approval) → WORKLOG → EXECUTE (per-task) → CODE REVIEW → PR REVIEW
```

There are two ways to arrive at BRIEF: talking
(`discovery`/`discover-and-design*`) or building-to-learn
(`prototype-first` — a human-paired throwaway prototype whose branch +
`PROTOTYPE.md` feed the brief as primary evidence). The prototype is an
entry variant only; everything from BRIEF onward is identical.

Stage skills (universal — the same pipeline for every harness):

| Stage | Skill |
| --- | --- |
| Brief | `discovery` (vague idea) / `discover-and-design` (already discussed; also the unattended pipeline mode) / `discover-and-design-simple` (small, obvious) |
| Research | `research` |
| Approach | `design` |
| Approach review | `review-approach` |
| Plan | `create-plan` |
| Plan review | `review-plan` |
| Worklog | `create-worklog` |
| Execute | `execute-task` / `execution-orchestrator` |
| Code review | `review-code` |
| PR | `pull-request` |
| Epic layer | `review-epic` |
| Live PR fix loop | `babysit-pr` |

## Precedence and repo overlays

Order of authority: the human's instruction > the target repo's own docs
(`AGENTS.md` and what it links) > the agent's **repo overlay** skill > the
stage skills > this skill. A repo overlay is a local, repo-specific skill
(e.g. `<repo>-dev-overlay`) that holds the repo's path map (plan directory,
test-command catalog, backlog), and every deliberate deviation from this
process as a row: ID, deviation, justification, exit condition. Load it
together with this skill whenever one exists. Paths in the stage skills
(e.g. `plans/YYYY_MM_DD_<slug>/`) are defaults the overlay may remap. When
repo docs and this process conflict, follow the repo and report the
conflict; never fix it silently. Overlays are always `keep-local` in
`skill-sync`.

## Pick the plan level

| Signal | Level | Stages |
| --- | --- | --- |
| Obvious, < ~30 min, no design choice | Simple | brief → implement → verify |
| Clear bug, obvious root cause | Simple bug fix | as Simple; regression test first, mandatory |
| One coherent feature/fix | Standard | full pipeline below |
| Multi-feature / cross-component | Epic | brief → research → approach → `epic.md` → `review-epic` → child plans (each Standard) |
| Unsure | Standard | research may downgrade |

The stage-gate table applies in full to Standard and Epic. Simple levels
still need a `brief.md`; chat context is not a brief.

## The stage-gate table (NORMATIVE)

A stage may not START until its gate artifacts exist. This table is the
single authority; the per-stage skills do not re-litigate it.

| Stage you want to start | Gate (must already exist) | If the gate is missing |
| --- | --- | --- |
| Research | `brief.md` (goals/non-goals/constraints/success criteria) | Run `discovery` first. CHAT CONTEXT IS NOT A BRIEF — formalize it. |
| Approach (`design`) | `brief.md` + research findings on disk | `discovery`/`research` first |
| Approach review | `approach.md` | `design` first |
| Planning (`create-plan`) | APPROVED `approach.md` (review clean) | `review-approach` first |
| Plan review | `plan.md` complete per template | `create-plan` first |
| Worklog / execution | plan review CLEAN (zero Blocker/Critical/Major) + **human approval** | Stop. Present the plan for approval. |
| Code review | task(s) executed, commits landed | `execute-task` first |
| PR review | code review clean | `review-code` first |

**Artifact precedence:** briefs, approaches, and plans are reviewable
artifacts — decisions recorded in conversation are CONTENT for those
artifacts, never a substitute for them. An agent asked to plan work
verifies the gate artifacts exist on disk first and creates whichever are
missing, in pipeline order, before any plan is written.

## Execution mode selection (NORMATIVE — required before execution starts)

The pipeline is invariant; what varies is the vehicle that drives the
stages. Confirm the mode with the human when the plan is approved (unless
one is already agreed for the repo), record it in the worklog header, and
keep it for the whole plan.

| Situation | Mode |
| --- | --- |
| Default; multi-task plans; parallel tasks likely; isolation needed | **Pi subprocesses** |
| Simple plans (≤ ~3 small tasks), one domain, no parallelism worth isolating | **Hermes subagents** |
| Trivial change, single sitting, single domain, no review loop expected | **Single Hermes session** |

Invariants in every mode: the pipeline, artifacts, verification classes,
and gates are identical; verification runs on the host (never delegated to
the context that did the work); the reviewer's context is never the
implementer's; human gates are unchanged. Mode mechanics — pi session-ID
conventions, session-reuse exceptions, per-mode evidence shapes — live in
`references/execution-modes.md` (packaged with this skill), which is the deep-dive reference for
this table. When in doubt between two modes, pick the more isolated one;
escalating mid-execution is cheap, de-escalating is not.

## Locating yourself

- **New work item** (no brief): start at `discovery`, or the combined
  `discover-and-design` / `discover-and-design-simple` variants per the
  Brief row above. When requirements are discovery-shaped for a
  user-facing surface — the fastest way to specify the work is to see
  it working — the human may choose the `prototype-first` entry instead:
  a human-paired throwaway prototype ends with `PROTOTYPE.md`, which
  enters the brief as primary evidence.
- **"Implement this prototype"** (a pushed `prototype/<slug>` branch with
  `PROTOTYPE.md`, usually via a linked item): follow Prototype handoff
  below.

## Prototype handoff (prototype → clean PR)

An accepted prototype (verdict `build` or `build-with-changes`) already did
the brief's job of fixing *what* to build, with the human in the loop. When
the human asks to implement it (live, or by dispatching an item whose
handoff comment names the branch), run the rest of the pipeline end to end:

1. **Locate** the item, the `prototype/<slug>` branch and its
   `PROTOTYPE.md`. Missing pushed branch, `PROTOTYPE.md`, or a verdict →
   stop and say what is missing. `don't build` → stop.
2. **Design** with `discover-and-design` in unattended mode, the prototype
   as the conversation: `findings/prototype.md` = PROTOTYPE.md; the brief
   records `Path: prototype-first`; each change in "What was prototyped"
   becomes a goal (its objective, not its hack); **every acceptance scenario (and every
   build-with-changes change) is a success criterion**, worded as accepted.
   The overlooked-needs scan adds error paths, lifecycle and safety the
   prototype skipped — additions only, never dropping or reinterpreting a
   scenario. Approach records disposal (wipe-and-rebuild default), branch
   topology, and test freshness; approach review runs as usual.
3. **Gate or continue.** The accepted prototype plus the human's
   instruction to implement (or `Autonomy: auto` on the item) is the
   Design-gate and Plan-gate approval — *unless a stop trigger fires*.
   Commit the design, then continue to plan, plan review, worklog,
   execution and final code review (`execution-orchestrator`, detached).
   Contract freezes proceed without approval; changing a frozen test
   later still needs it. With `Autonomy: gated` (or unset on a dispatched
   item), gate as usual.
4. **Stop triggers** — post one gate (live: ask) with options and a
   recommendation, then continue on the answer:
   - the approach chooses refine-in-place;
   - a scenario cannot be met as demonstrated, or two scenarios conflict;
   - schema or data migration, auth/permissions or security posture,
     a new external service or dependency, a public API/contract
     change, spend, or anything irreversible;
   - a design fork that changes user-visible behavior beyond the demo,
     or a PROTOTYPE.md open question marked **[owner]**;
   - the work is epic-sized.
   Everything else is decided by the agent, recorded in the approach's
   decisions table, and surfaced in the PR body.
5. **PR** via `pull-request`: `Closes #N`; a **Prototype parity** section
   mapping each acceptance scenario to its test(s) and, for UI, evidence
   of the real build next to the prototype's; additions beyond the demo
   listed separately. Merge stays human. After merge the prototype branch
   is deleted (wipe path) with the owner's OK.
- **Epic-scale work**: the brief/approach become an epic skeleton
  (`epic.md`, numbered child plans); use `review-epic` at the epic layer.
  Child plans enter at PLAN in the table above, gated by the epic approach.
- **Existing plan approved**: `create-worklog`, then `execute-task`.
- **"Review this"**: identify the artifact (approach/plan/code/PR) → the
  matching `review-*` skill.
- **Bug fix**: see the plan-level table — Simple bug fix when the root cause
  is obvious (regression test first), otherwise Standard.

## Artifact formatting (NORMATIVE)

Every process artifact (`brief.md`, `approach.md`, `plan.md`, `worklog.md`,
findings, all `*_review*.md`, result files) writes its metadata header as a
two-column table, never as consecutive `**Key:** value` lines, which
Markdown joins into one paragraph:

```md
|                         |  |
|-------------------------|--|
| **Created**             | YYYY-MM-DD |
| **Item**                | <owner/repo#N> |
| **Task review default** | each |
```

Pad the key column so the source stays aligned; escape a literal `|` in a
value as `\|`. The same applies to any other run of two or more key/value
lines (task metadata blocks, review summaries); separate them by blank lines
or use a table or a list.

## Process choices (each has a point, a mechanism, and a record)

Every choice in the process happens at a defined point, by a defined
mechanism, documented in a defined place:

| Choice | When it happens | Mechanism | Documented in |
| --- | --- | --- | --- |
| Execution mode (pi subprocesses / Hermes subagents / single session) | At plan approval | Confirm with the human (default: pi subprocesses) | Worklog header |
| Parallel reviews (`dual` — default: two independent reviewers, distinct from each other and the author — vs `multi-model`: 2–3 reviewers on distinct model families) | At plan creation | Agent proposes per plan risk; human confirms at plan approval | plan.md "Parallel reviews" choice row; if multi-model, the review files carry a merged findings table with per-reviewer attribution |
| Per-task review (yes/no per task) | At plan creation | Agent proposes per task risk (a `no` on schema/auth/migration tasks is a review finding); human confirms at plan approval | plan.md task graph |
| Approval gates (approval-gate / auto-continue / detached) | At execution start | Human decides (default: approval-gate) | Worklog header |
| Contract freezes | When a contract-task's tests are frozen | Agent-determines; changing frozen tests afterward requires human approval | plan.md freeze schedule + worklog |
| Prototype disposal (wipe-and-rebuild vs refine-in-place; wipe is the default) | At approach review, for `Path: prototype-first` briefs | `design` records it with rationale; `review-approach` checks it | approach.md decisions table |

## Autonomy defaults (harness/human may override per plan)

- **Auto**: everything WITHIN an approved plan's execution (task order,
  internal fixes, gate re-runs).
- **Human gates**: (1) plan approval before execution (in unattended board
  mode the approved Design gate covers it; a separate Plan gate is posted
  only when the plan departs from the approved approach, see
  `execution-orchestrator` detached mode); (2) contract
  freezes — the point where a contract task's tests are declared frozen;
  changing them afterward requires human approval; (3) owner-ruling
  classes — contradictions in the spec or plan, contract-level questions the repo cannot answer, irreversible actions, external contact, spend, security
  posture; (4) PR merge (agents never merge).
- Reviews are always delegated to a DIFFERENT agent than the author, in a
  fresh session (never the author's session id).
- **Filling pi delegation placeholders:** `<skills-dir>/<skill>` is the
  installed skill's directory (find it in your store; it may sit under a
  category folder). `<model-for-ROLE>` comes from the repo's role->model
  mapping (`AGENTS.md` roles table, `.pi/settings.json` agentOverrides); if
  the repo has none, use `references/agent-roles.md` tiers and ask once.
  `--name` is a display name only and selects nothing.
- Verification runs on the orchestrator's host after every delegated step; a
  worker's report is not evidence.
- **Commit signing is never a precondition.** If `git commit` fails only
  because signing fails, rerun it as `git -c commit.gpgsign=false commit ...`
  and continue. Exception: a repository that requires signed commits (the
  push is rejected for unverified signatures). Then re-sign the unsigned
  outgoing commits with content unchanged
  (`git rebase --exec "git commit --amend --no-edit -S" <base>`) and push; if
  signing still fails, block with reason `commit-signing`.
- **Investigation continuity:** while one task's root cause is unproven, the
  same implementer session may be resumed across rounds. Record
  `session: <id> — continuity: <reason>` in the worklog, gate on the host
  every round, review in fresh sessions, and end it once the cause is proven
  (details: `references/execution-modes.md`).

## Decide, don't ask (NORMATIVE; owner policy)

The owner's attention is the scarcest resource in the pipeline. Ask only
about items on the **owner list** below; decide everything else yourself,
record it, and move on. This section overrides any wording in the stage
skills ("ask", "stop and ask", "ambiguous", "confirm", "open question")
that would send a non-owner-list question to the human.

**Sources, in this order:** the item text and owner comments; the
repository (code, tests, `AGENTS.md`, docs, git history, open and merged
PRs, earlier plan directories); the specs/requirements the repo cites; documentation the repo links;
conventions in sibling repositories. When two
answers are defensible, pick the one the sources support best; if they are
silent, pick the smaller, reversible option.

**Record every non-trivial decision** in a numbered **Decisions made** list
with its source in brackets, e.g.
`D3. Nightly run at 02:17 UTC [convention: other nightly workflows in .github/workflows]`.
The list lives in the brief/approach, the plan (new decisions only), and
the PR body (one merged list). The owner vetoes with `revise: D3 …` at a
gate or in a PR comment; a veto is cheap, a question is not. A decision
with a source is never phrased as a question.

**Owner list (ask; never decide):**

1. A contradiction between the item and the specs/requirements, or between
   two requirements, that the sources do not resolve.
2. An irreversible or externally visible action: data migration, public API
   or wire-format change, release, anything that touches production or a
   customer.
3. Spend: anything that adds cost — a new paid service or licence, or a
   bigger or paid CI machine (e.g. GitHub "larger runners").
4. Security posture: permissions, secrets, trust boundaries.
5. Changing a FROZEN decision or a frozen contract test.
6. Safety behaviour (stop conditions, interlocks, limits) that the spec
   does not already fix.
7. Creating a new backlog item (see "Finish in task").

Plus the human gates under "Autonomy defaults". **Not** on the list:
"scope" (follow "Finish in task"), "ambiguous" (resolve it from the
sources), file placement, naming, test selection, schedules, defaults,
version bumps that follow repo convention, and anything already answered
by an approved gate. A diagnostic only a person can run (bench logs,
hardware access) is a request for information, phrased as one, not a
decision.

**Questions sections** (gates, triage, result files) hold owner-list items
only, at most three. When there are none, write
`Questions: none — see Decisions made.`

## Finish in task (NORMATIVE; owner policy)

The goal is a backlog that **shrinks**. An item is done when the problem
it states is solved for every case the repository can reach, including the
gaps found by the design scan and the review findings of every severity.

- **Default: do it here**, in this item's branch and PR. A file the work
  needs outside the plan's Scope/Touched-files list is added and recorded
  under Decisions made; it is never a question.
- **New backlog items: zero without the owner's explicit approval.** Propose
  one only for (a) a genuine defect outside this item's problem that cannot
  be fixed in this PR without changing an unrelated module's behaviour, or
  (b) an epic-sized item, where the Design gate proposes a split into 2–3
  items with one-line goals (more than three means an umbrella; recommend
  closing it after the split). Before proposing, search open issues
  (`gh issue list --search <key words>`) and propose extending a matching
  one instead. Proposals go in the next gate, or in the PR body under
  `## Proposed new issues (need your OK)`; nothing is filed until the
  owner approves.
- **Review Minors** are fixed in the same round when small (rename, doc,
  test, roughly under 30 lines); otherwise dropped with one line under
  `## Considered and not done` in the PR body. Minors are never filed and
  never listed as follow-ups.
- **Related repositories.** A change the item needs in another repository
  (dependency, consumer, shared library, schema or API) is made as a
  companion PR there, cross-linked with this item's PR and never merged by
  an agent, when the approved plan or design names it. Otherwise it is an
  owner-list question (an externally visible action), asked at the next
  gate; it is never filed as a follow-up.
- **Nice-to-haves** outside the item's problem are dropped and listed under
  "Considered and not done", not filed.
- The PR body's follow-ups section lists only issues that already exist
  with numbers, or says `None — finished in task.`

## Review bar

A plan/code review passes at zero **Blocker/Critical/Major** findings;
Minors follow "Finish in task" (fixed in the same round, or dropped and
listed under "Considered and not done"; never filed as issues). Approach/plan/code reviews run as a
loop: each round re-reviews the fixed artifact until the bar is met. Every
plan and code review round uses at least TWO reviewers, distinct from each
other and from the author (`dual`, the default); the round passes only when
both meet the bar — one clean pass is not enough. When the plan selects
`multi-model`, 2–3 reviewers on distinct model families run the round. In
both cases findings merge into one review file with per-reviewer
attribution.
