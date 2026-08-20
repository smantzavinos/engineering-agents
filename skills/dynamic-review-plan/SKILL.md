---
name: dynamic-review-plan
description: Review a Parallel plan (plan.md + tasks.json) for correctness, honest verification, real dependency edges, and honest fence groups. Produces plan_review.md. Called iteratively until clean, before the human approval gate.
harnesses: [pi]
---

# Parallel: Review Plan

Find the problems in a plan *before* anything executes. A bad task graph does not fail
loudly — it produces confidently wrong work in parallel.

## Inputs

- Plan directory (required): `plan.md`, `tasks.json`, plus `approach.md` and `brief.md` for
  context.
- `plan_review.md` if a previous pass exists.
- Scope: `full` (default) or `delta` after fixes.

## Process

1. **Run the mechanical gate first.** `node tools/check-plan.mjs <plan-dir> --json`. If it
   fails, stop and report — there is no point reviewing semantics on a plan that cannot run.
   Everything it checks is off your list; do not re-derive it by hand.
2. **Read** the plan, the graph, the approach, and any prior review.
3. **Review against the criteria below.**
4. **Fix safe issues directly** in `plan.md` / `tasks.json` — those with one obviously correct
   fix. Re-run the gate after editing.
5. **Write findings** to `plan_review.md`.
6. **Commit** only the plan artifacts and the review.

When fixing, write the plan as if it had always been correct. No "we changed" commentary; the
review log is the audit trail.

## What the gate already covers

Unique IDs, unknown dependencies, cycles, missing `brief`, `contract` tasks without
`testPaths`, non-`none` tasks without `verify`, missing models, fence-group membership,
intra-group write-set collisions, and `plan.md` ↔ `tasks.json` drift. **Do not spend
review effort there.**

## Quality criteria

### Verification honesty — the highest-value check
For every task, ask the anti-tautology question: *can this task's verification fail because of
a change in the behaviour or artifact the task modifies, without someone editing the oracle?*

- If not, the class is wrong. Usually it should be `check`, or honestly `none`.
- A test asserting a document contains a sentence the same task just wrote is not a test.
- A `contract` task whose `testPaths` do not actually cover the named behaviour is worse than
  `none`, because it looks verified.
- Watch for `verify` commands so broad they cannot fail for this task's reason (a whole-repo
  suite as a single task's proof) or so narrow they prove nothing.

### Class assignment
- New or changed observable behaviour marked `characterization` or `check` — usually wrong.
- Refactors marked `contract` — usually means the "refactor" changes behaviour, which is a
  finding about the plan, not the class.
- Everything marked `none` — the plan is not executable.

### Decomposition, DAG edges, and fences
- Write-sets are declared honestly. A task that will obviously touch a file it does not
  declare is a latent race the gate cannot see.
- Globs are not widened to dodge collision detection.
- Dependencies reflect real coupling, not story order. A missing edge is a race; a
  spurious one serialises the DAG for nothing.
- Named anti-patterns, each a finding: a shared component bundled into its first
  consumer's integration task (serializes the other consumers); a trailing polish
  task re-touching all surface files after parallel surface tasks (merge the polish
  into each surface's ownership); edges between tasks with disjoint write-sets
  (serialize nothing but the clock); story-order fences (recreate the wave engine).
- A scheduling-only dependency (used because the write dialect cannot express a
  dynamic path segment) is legitimate **only** when labeled as such in `plan.md`;
  unlabeled, it looks exactly like accidental coupling.
- Fence groups cut where later work must not start on a lie. Extra groups that only
  recreate ready-set waves are a finding. Missing groups before a wide fan-out that is
  expensive to rewind are a finding.
- Task size is plausible against the 30-minute default child timeout.
- Total task count is plausible against the 64-spawn run ceiling (~16 tasks at four spawns
  each, including review and retries).

### Briefs
- Specific enough to execute without the plan: concrete files, behaviours, commands.
- Carry paths, not pasted file contents.
- No placeholder tokens left in.

### Completeness
- The baseline is recorded, so a pre-existing failure is not later blamed on this plan.
- Verification commands come from canonical repo docs, not invention.
- Requirement and backlog references follow repo policy.
- Risks have mitigations; open questions have owners.
- Compatibility and rollback are addressed where the change warrants it.

## Findings format

Write `plan_review.md` with severity-ordered findings:

- **Critical** — will produce wrong or unsafe work. Must be fixed before approval.
- **Major** — will cause rework or a failed fence group.
- **Minor** — worth fixing, not blocking.

Each finding names the task ID, what is wrong, and what would make it right. End with an
explicit verdict: **ready for approval** or **not ready**, and if fixes were applied, what
changed.

## What you must not do

- Do not implement anything.
- Do not approve the plan. The human does that.
- Do not relax a verification class to make a task easier to pass.
- Do not rewrite the approach; if the approach is wrong, say so as a Critical finding.
