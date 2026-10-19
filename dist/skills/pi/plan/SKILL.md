---
name: plan
description: Write a short, decisive implementation plan for one child of an epic (or for a single plan), revise it from review findings, and hand back. Used by the plan-author subagent.
compatibility: pi
---

# Plan

Write the plan a strong engineer needs to build this child in one session without guessing, and nothing more. You will be resumed with review findings, so this session owns the plan until it is approved.

## Inputs
- `epic.md` and this child's entry; the plans and ledgers of the children it depends on, for what they leave behind. A dependency that isn't built yet is represented by its approved plan: plan against that, and expect a scout to check the plan once the code is integrated;
- `PROTOTYPE.md` and the prototype diff;
- the repo's docs and rules;
- the code that will change.

Scout widely with subagents (`delegate`), and read the critical paths yourself.

## plan.md
- **Goal:** what this child delivers, the acceptance scenarios it owns, and an estimate in changed lines, with the implementer's hours for it. For a single plan there is no epic, so this section also carries what was agreed with the human:
  - scope in and out, and disposal;
  - the full-gate commands, the test map and the smoke set;
  - budget and autonomy limits.
- **Context:** links to the code, docs and earlier decisions that matter.
- **Design:** the key decisions and why. Name rejected alternatives when the choice isn't obvious.
- **Changes:** by area or module, what changes and where. Enough to start, not a script.
- **Tests:** the contracts each acceptance scenario and each risky piece of logic needs proven, and the owning layer for each (`test-quality`). This is not a test checklist. It is the test budget: code review rejects new tests that don't trace to it, so keep it complete and lean.
- **Gates (T1):** the commands, run once at the end of implementation:
  - typecheck and build for the touched packages;
  - lint and format on the changed files;
  - units selected against the base commit, plus a whole-package rerun when its config, test setup or a shared module changes;
  - E2E: this child's scenario specs, the test-map specs for the changed paths, and the smoke set. Without a test map, name the specs for the paths you expect to change.

  **Widen** T1 to the whole affected packages and all mapped specs when the child touches schema, migrations, seed data, authorization or visibility, the shared shell, dependencies or build config. **Escalate** to full gates when it touches test infrastructure. Say which applies, and why.
- **Claims** (every child, when the epic has a worktree pool): restate the child's claim from `epic.md`, refined to the files, routes, tables and shared components it will change. Stay inside it.
- **Done when:** observable criteria, and the **Deliverables**: the outcomes the build must contain (scenarios, specs, UI behaviours), not tasks. The implementer maps each to its evidence.
- **Risks:** what could go wrong, and how to handle it.
- **Handoff:** a few lines for the implementer, written last: what review settled, where you were unsure, what to watch.

Answer each of these where it applies, in a line or "n/a" (`references/plan-questions.md`):
- **Access and visibility** (Design, Tests): who can see and do what, including hidden or locked items; each guard's owning test.
- **Failure and concurrency** (Design, Tests): errors, retry, two users at once, live updates.
- **Assumptions checked against the code** (Context, Gates): what the plan relies on exists; specs and files outside the edit list that the change affects.
- **Limits and load** (Design, Risks), for read-heavy features: platform limits and fan-out.
- **Deviations** (Design): from the prototype or earlier decisions, with a reason.
- **Deliverables** (Done when).

Aim for under 150 lines.

## Judgment calls
- **Course-setting decisions**, the ones that shape most of the remaining children: consult the oracle first. Take a clearly better option and record it. If there is none, say so in your reply; the orchestrator stops for the human.
- **Sizing:** estimate first. If the estimate is above the epic's review-load signal, say whether the child mixes separable concerns. If it does and the pieces could run in parallel (every `scope` → Parallel groups rule), stop before writing the full plan and propose the split, each piece with its scenarios, estimate and claim (inside the child's own claim). Otherwise plan it whole. Propose merging this child with one it depends on only when their content belongs together. Don't silently plan half of it.
- **Scope:** plan only this child's entry. A fix or improvement outside it goes on a short Follow-ups line in `plan.md`, not into Changes.
- **Claims:** if the design needs to go outside the `epic.md` claim, say so in your reply. The orchestrator widens the claim or orders the child after the one that holds it.

## Refresh
A fresh session, started in the child's worktree (its lane, or the work-branch worktree without a pool) when the scout found integrated changes the plan relies on.
1. Read the `## refresh scout` note in the ledger, the plan and the ledger.
2. Check the plan against what the note names: the integrated code, `epic.md` changes and any checkpoint merge.
3. Update what changed, including the estimate, and commit it as one refresh commit. Its review covers only that commit.
4. Reply with the refresh commit, the old and new estimate in lines and hours, and whether claims or scenarios changed. Don't `self_compact`; refreshes are short.

## Revising
For each finding in `review.md`, either fix it, or reject it with a one-line reason under the finding. If the reviewer has already disputed a rejection, or you're unsure, ask the oracle; its ruling settles the finding. Your reply lists the findings you rejected, and says whether any fix changed a contract (an interface, data shape, access rule or scenario).

## Handoff
1. Commit `plan.md` and your `review.md` responses.
2. `self_compact` with a note: what you decided and why, what's open, and how to continue.
3. After compaction, reply in a few lines: a summary, sizing or course-setting flags, and the open risks.

Everything the next session needs is on disk, so you can be resumed or replaced.

## Do
- Make the decisions. A plan that defers design to the implementer is not done.
- Follow the repo's patterns. Say where you deliberately depart from them, and why.

## Don't
- Restate repo rules or docs. Link them.
- Write task tables, execution tiers or step-by-step checklists. The Deliverables list of outcomes is not one.
- Plan beyond this child. Flag cross-child issues to the orchestrator.
