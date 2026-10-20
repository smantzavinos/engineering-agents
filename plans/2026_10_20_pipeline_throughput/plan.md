# Pipeline throughput: shorter chains, T1 off the review path, more planning capacity

**Status:** draft, revised after plan pass 1 · **Date:** 2026-10-20 · **Evidence:** `plans/2026_10_20_process_variants/README.md` (variants A, B, B+; single-plan time), the pilot repo's `t1_breakdown.md` · **Changes:** `skills/scope`, `orchestrate` (+ `references/lanes.md`, `references/checkpoint-failures.md`), `implement`, `review`; `docs/frontier-pipeline.md` and its example diagram

## 1. Why

On the example epic with the pilot's measured durations, the current process takes 6h11. With the changes below and today's default of 4 lanes, it takes about 4h16 (−31%); with 6 lanes, 3h54. The changes shorten the dependency chain, take T1 off the review path and add planning capacity. Parallelism inside a plan (child orchestrators, parallel implementers) is out of scope by owner decision.

**Target:** on the next epic, against pilot era D, per child: build start to code approval down by about 10 min (one T1 off each review pass, fewer second passes); no unit waiting for a planning worktree.

The 6-lane figure assumes T1 doesn't slow when several run at once; the simulator doesn't model that. More lanes wait for that measurement (O1).

Skill text stays generic and concise: rules only. Evidence stays here and in the variants README.

## 2. Changes

### C1. Contract-first dependencies (scope time)

**`scope` → epic.md → Children:** a child depends on another only for what it needs built. When it needs only a contract (schema, API, types, a component's interface) from a child that also builds behaviour, put that contract in the earliest child it already depends on (usually the foundation) and depend on that child instead. Record in the entry which contract a dependency is for. No contract-only children: every child stays a vertical slice.

**`scope` → Do:** "Keep the dependency chain short: the longest chain sets the epic's length, and each link adds a child's fixed cost."

**`review` → epic mode:** check that each dependency is needed for built behaviour, not only for a contract that an earlier child the dependent already depends on could deliver. A dependency that lengthens the longest chain for a contract alone is a major.

**`orchestrate` → lanes.md → Claims:** add "A child that must change a contract an earlier child delivered reports it, as for a file outside its claim." The existing claim-overlap rule then orders it against the children that use the contract.

### C2. Final checkpoint alongside the epic-diff review

**`orchestrate` → Epic close**, replacing steps 1–3:
1. Start the epic-diff review at once. Start the final checkpoint on the same work-branch commit as soon as the previous checkpoint has merged (Checkpoints step 2).
2. The fixes go to the implementer in the work-branch worktree, as today, without T1.
3. Once the fixes are committed and no one is writing in the work-branch worktree, merge the green final checkpoint (Checkpoints step 2, including its conflict rule).
4. A helper runs T1 for the fixes on the merged tip, with selection from the green checkpoint's tip, widened or escalated as `plan` → Gates says. Red goes back to the fixes' implementer, then T1 again.
5. Hand off to the PR process (today's step 4, unchanged).

A red final checkpoint follows `references/checkpoint-failures.md`. The epic-close fixes continue meanwhile (they aren't steered to stop); step 3 waits for the checkpoint fix to merge. **`checkpoint-failures.md` step 4:** add "Epic-close fixes aren't paused."

### C3. Conditional code pass 2

**`review` → code mode:** tag every major with its kind. A major is `tests`, `T1` or `wording` only if its fix can't change production behaviour. Every other major — wrong behaviour, a missing deliverable, docs, design, boundaries, claims, scope, a merge error — needs a re-check; tag it `design`, `boundary`, `claims`, `scope` or `cohesion` as in plan mode. **Reply:** end with `pass 2 needed: yes` if any blocker or any major that needs a re-check is open, otherwise `pass 2 needed: no`.

**`orchestrate` → Per child → Implement:** after a pass with changes needed, skip the next review only when the reviewer replied `pass 2 needed: no`, the implementer fixed every major and rejected none, and the T1 for the fixes is green (C4). Append `approved after fixes, no pass 2` to the ledger, record `codePass2Skipped` in `state.json`, and treat the code as approved. Escalation (Bounds) is unchanged: it applies when pass 2 runs and isn't approved.

### C4. T1 alongside code review

The implementer runs the fast gates and hands off. A helper runs the slow gates (unit and E2E tests) on that commit while the reviewer reads.

**`implement`:**
- **Gates step 1:** "At the end, run T1's fast gates (builds, typecheck, lint and format on changed files). Record in the ledger the exact command lines for the rest of T1 (units and E2E, with explicit base and spec list) and why each spec was picked. Don't run them; a helper does." Selection, whole-package and run-settings bullets stay; the Delegation bullet goes.
- **Gates step 2:** "Fix what the fast gates find. After a review, fix the findings and the T1 failures you are given, run the fast gates for the fixes, and record the remaining command lines for them (what failed and what the fixes touch)."
- **Gates step 3:** the escalation exception names the helper as the one that runs the full gates.
- **Handoff:** the first evidence bullet covers the gates you ran plus the recorded command lines. New bullet: "Stop the services you started on the worktree's ports before you hand off."
- Unchanged: the tree-match no-rerun rule, and the integration, checkpoint-fix and epic-close defaults (Review findings), which still run their own T1.

**`orchestrate` → Per child → Implement**, for every pass, in the child's worktree:
1. Launch the code reviewer and a T1 helper together on the implementer's commit. The helper runs the ledger's recorded command lines with the E2E worker count it is given (C5), booting and stopping its own services. It reruns each failure alone, and classifies it: a failure that passes alone and lies outside the child's diff is a flake; one in the baseline digest or under a running checkpoint fix is baseline; anything else is red. It writes nothing tracked: it replies with a digest and the log path.
2. Record each T1 run in `state.json` (commit, tree, command lines, workers, result, duration, log path) and any flakes, as for checkpoints.
3. **Both done:** review approved and T1 green → approved (Close). Otherwise resume the implementer with the ledger path, the pass number and, if T1 is red, the digest and log path. Its fix-pass entry records which T1 failures it fixed and whether each fix touched only tests or fixtures.
4. Every fix pass counts toward the pass cap, including one for T1 failures alone. After a fix pass, the next review runs unless C3's skip conditions hold, and every T1 fix touched only tests or fixtures. A red T1 after the fixes means another fix pass.
5. With no review (C3 skip), the helper's T1 for the fixes runs alone; green means approved.

The step's first sentence ("It builds everything, passes T1, …") becomes "It builds everything, passes the fast gates, records the rest of T1, …". **Where work runs (no pool):** the no-git-commands rule names the T1 helper with the implementer and code reviewer.

**`review` → code mode**, for a child's own passes:
- While a T1 helper runs in the same worktree, don't run tests. Record a doubt as a minor that names the check; the next T1 run includes it.
- The T1 evidence check becomes: the recorded command lines cover the actual diff and match the plan. T1 results come from the helper, through the orchestrator.

Integration, checkpoint-fix and epic-close reviews keep today's evidence and flake checks.

**`orchestrate` → Don't:** the no-rerun rule reads "a passing run in the ledger or `state.json`".

### C5. Capacity

**`orchestrate` → Planning:** up to three planning worktrees (was two). They need no install, so the cost is disk only.

**`scope` → Parallel groups:** `maxLanes` is at most the pool size and memory ÷ 6 GB; default 4. A pool needs a worktree per lane.

**`lanes.md` → E2E workers**, replacing the bullet: "When a T1 or checkpoint run starts, give it an even share of the budget across the runs then in flight, including it, but no more than the budget not already held, and at least 1. Pass that count in its task. Targeted checks while building use one worker." This applies to helper and implementer T1 alike. **`orchestrate` → Implement:** the implementer's task no longer carries an E2E worker count; the T1 helper's does.

### C6. Docs

**`docs/frontier-pipeline.md`:** update every passage C1–C5 changes:
- Roles table (implementer runs the fast gates; helper runs T1);
- Where work runs table (up to three planning worktrees; T1 helpers in the pool);
- A child, start to finish: Implement and Code review (T1 alongside, conditional pass 2);
- Units (contract-first dependencies, `maxLanes` default);
- Tiers, the T1 row;
- Epic close;
- History (this plan).

Replace the example with the B+ epic at the default 4 lanes from `plans/2026_10_20_process_variants/` (simulated, durations from the pilot's medians), with the elapsed time and a fixed cost per child of about 30–40 min. "Regenerating the diagram" names `tools/process-sim.mjs`, `tools/scenario-trace.mjs` and `tools/work-trace-render.mjs` with their commands.

## 3. Owner decisions

Agreed on 2026-10-20: C1 (at scope, no runtime mechanism), C2, C3 (pass 2 still runs after any major that needs a re-check), lanes configurable; drafting C4 and the capacity changes.

**Open:**
- **O1. Lanes.** Proposed: keep the default of 4 lanes and cores ÷ 4 E2E workers. Raise them in the repo once E2E time against worker count and concurrent runs is measured (pilot repo #142, lever 3, and §6). With 6 lanes, the example takes 3h54 instead of about 4h16, if T1 doesn't slow.

**Dropped after review:** reviewing a refresh inside code review pass 1. It gives about 4 min per refreshed child and nothing on the example epic, and needs a review sub-mode, a branch in Start and ordering between a plan-author and the implementer in one worktree.

## 4. Not changed

Code-review pass 1 and plan-review pass 1; the refresh and its review; integration once per group; unit start order and planning order (both child number). The variants showed critical-path planning order and backfill starts give nothing on the example and can cost 17 min, so neither is adopted. No parallelism inside a plan.

## 5. Risks

- **C1:** contract drift. A child that finds a delivered contract wrong while others build against it reports it (C1's claim rule); otherwise the break shows at integration or a checkpoint.
- **C2:** the fixes' T1 is the only check of the fixes on the final tree; full gates rerun only when it widens or escalates.
- **C3:** a `tests`, `T1` or `wording` fix ships without a second look. The epic-diff review sees it.
- **C4:** its saving assumes T1 is usually green at handoff. A red T1 after an approved review adds a fix pass that today happens before review. Measured in §6.
- **C5:** a T1 that starts alone takes a larger share; later runs get less until it ends.

## 6. Measure (next epic vs pilot era D)

From `state.json`, per child: build start to code approval; T1 runs with workers, runs in flight, duration and result; the rate of red T1 at handoff and T1-only fix passes; flakes and baseline failures the helper classified; `codePass2Skipped`; planning-worktree waits and unit start waits. Per epic: epic-close duration, and whether the final tree passed T1 after the checkpoint merge.

## 7. Rollout

1. Edit the skills on `pilot/process-retro`, then `node tools/render-skills.mjs --write` and commit `dist/`.
2. `./tests/run-tests.sh fast`; `grep -iE` for product names.
3. Fresh review of the skill diff against this plan (pass cap 4).
4. Push with the owner's OK; flake bump and session restart. Applies from the next epic. A repo that raises `maxLanes` needs that many pool worktrees.
