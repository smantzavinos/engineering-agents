# Pipeline throughput: shorter chains, T1 off the review path, more capacity

**Status:** draft · **Date:** 2026-10-20 · **Evidence:** `plans/2026_10_20_process_variants/README.md` (variants A, B, B+; single-plan time), the pilot repo's `t1_breakdown.md` · **Changes:** `skills/scope`, `orchestrate` (+ `references/lanes.md`), `implement`, `review`, `plan`; `docs/frontier-pipeline.md` and its example diagram

## 1. Why

On the example epic with the pilot's measured durations, the current process takes 6h11. Variant B+ takes 3h54 (−37%). It shortens the dependency chain, takes T1 and a few reviews off the critical path, and adds planning and lane capacity. Parallelism inside a plan (child orchestrators, parallel implementers) is out of scope by owner decision.

**Target:** on the next epic, against pilot era D: per child, build start to code approval down by about 10 min (one T1 off each review pass, fewer second passes); the critical path no longer than the content's real dependencies; no unit waiting for a planning worktree while one could be added.

Skill text stays generic and concise: rules only. Evidence stays here and in the variants README.

## 2. Changes

### C1. Contract-first dependencies (scope time)

**`scope` → epic.md → Children:** a child depends on another only for what it needs built. When it needs only a contract (schema, API, types, a component's interface) from a child that also builds behaviour, put that contract in the foundation child, or in a small earlier child, and depend on that instead. Record in the entry which contract a dependency is for.

**`scope` → Do:** "Keep the dependency chain short: the longest chain sets the epic's length, and each link adds a child's fixed cost."

**`review` → epic mode:** check that each dependency is needed for built behaviour, not only for a contract that an earlier child could deliver. A dependency that lengthens the longest chain for a contract alone is a major.

### C2. Final checkpoint alongside the epic-diff review

**`orchestrate` → Epic close:**
1. Start the epic-diff review and the final checkpoint together, on the same work-branch commit.
2. The fixes go to the implementer, as today. It runs T1 for the fixes.
3. The epic is done when the review's fixes are approved, their T1 is green and the final checkpoint is green and merged. Rerun the full gates only if the fixes' T1 widens or escalates (`plan` → Gates); otherwise their T1 is the proof.
4. A red final checkpoint follows `references/checkpoint-failures.md`, as any checkpoint.

### C3. Conditional code pass 2

**`review` → code mode:** tag every major with its kind, as in plan mode: `design` or `boundary` (a fix needs a re-check), or `tests`, `T1` or `wording` (it doesn't). **Reply:** end with `pass 2 needed: yes` if any blocker or any major that needs a re-check is open, otherwise `pass 2 needed: no`.

**`orchestrate` → Per child → Implement:** after pass 1 with changes needed, skip pass 2 only when the reviewer replied `pass 2 needed: no`, the implementer fixed every major and rejected none, and the T1 for the fixes is green. Append `approved after fixes, no pass 2` to the ledger, record `codePass2Skipped` in `state.json`, and treat the code as approved. Escalation (Bounds) is unchanged: it applies when pass 2 runs and isn't approved.

### C4. T1 alongside code review

The implementer hands off when the build is committed. A helper runs T1 on that commit while the reviewer reads.

**`implement` → Gates:**
- While building, run the targeted checks (T0) as today. Don't run T1. At the end, compute the T1 selection (the repo's selection command without running it, or the plan's Gates commands) and record it in the ledger with the reason for each spec. Then hand off.
- After fixes, the same: record the selection for the fixes (what failed and what the fix touches) and hand off. T1 failures you are given are findings: fix them like review findings.
- Unchanged: the tree-match no-rerun rule, the integration and checkpoint-fix defaults (`Review findings`), which still run their own T1.

**`orchestrate` → Per child → Implement**, for every pass:
1. Launch the code reviewer and a T1 helper together, in the lane worktree, on the implementer's commit. The helper runs the selection the ledger records, with the child's E2E worker count. It writes nothing tracked: it replies with a digest and the log path.
2. Record each T1 run in `state.json` (commit, tree, command, result, duration, log path).
3. **Both done:** approved and green → approved (Close). Otherwise resume the implementer with the ledger path, the pass number and, if T1 is red, the digest and log path. Its fix-pass entry records the failures it fixed.
4. **Pass 2 skipped (C3):** the helper's T1 for the fixes runs alone; green means approved.

**`review` → code mode:** while a T1 helper runs in the same worktree, don't run tests; record a doubt as a finding that names the check. The T1 evidence check becomes: the ledger's selection covers the actual diff, and the commands match the plan. T1 results are the orchestrator's.

**`orchestrate` → Don't:** the no-rerun rule reads "a passing run in the ledger or `state.json`".

### C5. A refresh reviewed inside code review pass 1

**`orchestrate` → Start step 4:** a fresh plan-author refreshes the plan (as today). If its reply says claims or scenarios changed, one fresh reviewer reviews the refresh first (as today). Otherwise there is no separate refresh review: the implementer starts on the refreshed plan, and code review pass 1 is given the refresh commit.

**`review` → code mode:** if given a refresh commit, review it in the same pass, as in Plan refresh (does the plan still fit the integrated code, and is the edit correct?). Head those findings `refresh` in the pass. A refresh major goes to a fresh plan-author for the plan and to the implementer for the code, as the existing rule for a wrong refresh fix says.

**`plan` → Refresh:** no change; its reply already says whether claims or scenarios changed.

### C6. Capacity

**`orchestrate` → Planning:** up to three planning worktrees (was two). They need no install, so the cost is disk only.

**`scope` → Parallel groups:** set `maxLanes` from the machine: at most the pool size, about 6 GB of memory per lane, and at least 2 E2E workers per lane from the machine-wide budget. The budget default stays cores ÷ 4 until measured (see O1).

**`lanes.md` → E2E workers:** split the budget across the T1 and checkpoint runs in flight when each one starts, not across all running lanes; a lane that is building runs only targeted checks. Pass each T1 helper its count.

### C7. Docs

**`docs/frontier-pipeline.md`:** update the lifecycle (Start, Implement, Close, Epic close), the T1 row and the roles table to C1–C6. Replace the example with the calibrated B+ epic from `plans/2026_10_20_process_variants/` (simulated, durations from the pilot's medians), and correct its claims (elapsed time, the fixed cost per child of about 30–40 min).

## 3. Owner decisions

Agreed on 2026-10-20: C1 (at scope, no runtime mechanism), C2, C3 (pass 2 still runs after any `design` or `boundary` major), lanes configurable; drafting C4–C6.

**Open:**
- **O1. Lanes and E2E budget.** B+ assumes 6 lanes; with 4 the gain is about 22 min smaller (4h16 instead of 3h54). Six lanes at 2 workers each need 12 E2E workers, above the cores ÷ 4 default on a 32-core host. Proposed: keep the default, and raise it in the repo once E2E time against worker count is measured (pilot repo #142, lever 3).

## 4. Not changed

Code-review pass 1 and plan-review pass 1; integration once per group; unit start order (child number) and planning order (child number). The variants showed critical-path planning order and backfill starts give nothing on the example and can cost 17 min, so neither is adopted. No parallelism inside a plan.

## 5. Risks

- **C4:** the reviewer reads code that T1 may still fail, and a T1 failure costs a fix pass that pass 1 would otherwise have seen together. The fix pass merges both lists, so it costs one pass, not two.
- **C3:** a fix to a `tests` or `T1` major ships without a second look. The epic-diff review sees it.
- **C5:** a wrong refresh is found after it is built. Mitigated by keeping the separate review when claims or scenarios changed.
- **C6:** more lanes share the same E2E budget; without the split-by-runs rule, each T1 would get fewer workers and run longer.

## 6. Measure (next epic vs pilot era D)

From `state.json`: per child, build start to code approval; T1 runs and their durations; `codePass2Skipped`; refreshes reviewed inside code review; planning-worktree waits and unit start waits; epic close duration.

## 7. Rollout

1. Edit the skills on `pilot/process-retro`, then `node tools/render-skills.mjs --write` and commit `dist/`.
2. `./tests/run-tests.sh fast`; `grep -iE` for product names.
3. Fresh review of the plan first (pass cap 4), then of the skill diff against it.
4. Push with the owner's OK; flake bump and session restart. Applies from the next epic.
