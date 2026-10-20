# Review ledger: pipeline throughput

## plan pass 1

Reviewed `plan.md` at 1031568 against `plans/2026_10_20_process_variants/README.md`, `tools/process-sim.mjs`, the current `scope`, `orchestrate` (+ `lanes.md`, `checkpoint-failures.md`), `implement`, `review`, `plan` skills, `docs/frontier-pipeline.md`, and the settled `plans/2026_10_16_pipeline_tuning/plan.md`. §3 "Agreed" decisions are not re-argued; the findings below concern the rules that implement them.

### P1-01 · major · design · C1 (line 17) vs `scope` → Children / Do, `review` → epic mode
**Problem:** "put that contract in the foundation child, *or in a small earlier child*" creates a contract-only child: schema, types or an interface with no behaviour. That contradicts three rules the plan doesn't touch: `scope` → Children ("A child is a cohesive vertical slice … ending in a testable scenario"), `scope` → Do ("a layer ends with nothing to show"), and `review` → epic mode ("each child is a cohesive slice"). An epic that follows C1 this way would draw a major under the epic-mode slice check. A new child also adds a link and a fixed cost of about 30–40 min to the chain C1 is trying to shorten. The evidence models only the foundation option: 01 takes the contracts, +5 min build. No variant adds a child.
**Fix:** Drop "or in a small earlier child". The rule becomes: the contract goes into the earliest child that the dependent already depends on, usually the foundation. If you keep the option, add an explicit exception to the slice rule in `scope` and `review` epic mode: a contract child ends in its contract tests. Note the extra link it costs.

### P1-02 · major · design · C2 (lines 25–29) vs `orchestrate` → Where work runs, Checkpoints step 2
**Problem:** Today the final checkpoint runs full gates on the final tree: the epic-close fixes plus the base-branch merge. Under C2:
- the checkpoint branch carries the base merge but not the fixes;
- the fixes' T1 runs in the work-branch worktree, before the green checkpoint has merged there;
- so the merged result (fixes plus base merge) is never verified by anything.

The order is also undefined:
- The epic-close implementer writes in the work-branch worktree, and the epic-diff reviewer commits the epic ledger there. "Merging into the work branch: only when no one is writing there" means the green checkpoint can't merge until both have stopped. The plan doesn't say when the fixes' T1 runs relative to that merge.
- A red final checkpoint (step 4) runs a checkpoint-fix implementer on the checkpoint branch while the epic-close implementer fixes on the work branch. These are parallel fixes on two branches with a likely conflict at merge. `checkpoint-failures.md` step 4 would also steer the epic-close implementer to stop, since it "builds on the broken code". The plan doesn't say whether it does.

The simulator (`close.fix` then `close.t1`) has no merge step, so the evidence doesn't cover this either.
**Fix:** State the order:
1. The review and the checkpoint run.
2. The fixes are built, with no T1 inside.
3. Once the work-branch worktree is idle, merge the green checkpoint (existing conflict rule).
4. A helper runs the fixes' T1 on the merged tip, widened or escalated as `plan` → Gates says.

For a red final checkpoint, say whether the epic-close fixes continue (recommended: yes, they touch different code) and that the fixes' T1 runs only after the checkpoint fix has merged.

### P1-03 · major · design · C3 (line 33)
**Problem:** The code-mode kinds are `design`, `boundary`, `tests`, `T1` and `wording`. They have no tag for the most common code major, wrong behaviour or a logic bug. They also have none for the majors `review` code mode already defines: a missing or undelivered Deliverable, docs not updated, a refresh major (C5) and an integration or merge error. The reviewer has to force each one into a tag, and the tag decides whether pass 2 runs. A logic bug tagged `tests`, because the fix comes with a test, would skip the re-check. The plan-mode list it copies also has `claims`, `scope` and `cohesion`, but C3 doesn't say whether code mode drops them.
**Fix:** Make the no-re-check set the closed one: "a major is `tests`, `T1` or `wording` only if its fix can't change production behaviour; tag every other major `design` or `boundary` (correctness, deliverables and refresh majors are `design`)." Say whether `claims`, `scope` and `cohesion` apply in code mode.

### P1-04 · major · design · C4 step 3–4 (lines 49–50), §5 C4 risk
**Problem:** C4 doesn't define what happens when T1 is red and the review has approved. Orchestrate step 3 resumes the implementer, which fixes the T1 failures. Then:
- **Review of the fixes:** it isn't clear whether a reviewer sees them. The reviewer replied approved, so the C3 skip conditions hold trivially (`pass 2 needed: no`, no majors), and a T1-failure fix ships unreviewed. A T1-failure fix can be a substantive behaviour change. Today it is made before pass 1 and reviewed there.
- **Pass cap:** it isn't stated whether a T1-only fix pass counts toward the cap of 4 or toward Escalation. `lanes.md` step 4 counts a red group T1 as a pass; lane T1 has no rule.
- **Repeated reds:** a second red T1 after the fixes (step 4) has no rule either.

The §5 risk says a red T1 "costs one pass, not two". That holds only when the review also asked for changes. With an approved review it adds a resume, a fix and a T1 that today's flow doesn't have. The simulator models no failure paths, and the README gives no red-T1-at-handoff rate. So C4's saving (about 9 min per child) assumes T1 is green on the reviewed commit.
**Fix:** Add one rule:
- Every fix pass, including a T1-only one, counts toward the cap.
- If the fix pass fixed T1 failures, pass 2 runs on that range unless every T1 fix touched only tests or fixtures (the implementer says so in its fix-pass entry).
- A red T1 after the fixes means another fix pass under the same rule.

Add the red-T1-at-handoff rate to §6, as the condition C4 depends on.

### P1-05 · major · design · C4 step 1, 3 (lines 47–49), `review` change (line 52)
**Problem:** The plan doesn't say who decides that a lane T1 is red. Today `implement` → Gates classifies failures: one that passes alone and lies outside the diff is a flake, a baseline failure is not yours, and one being fixed on a checkpoint branch is ignored. The implementer records these in its ledger. The plan removes that from the implementer and from the reviewer ("T1 results are the orchestrator's"; the "flakes are outside the diff" check is dropped). It gives the helper or orchestrator no rule in its place. Baseline failures are routine, so the orchestrator will either resume the implementer for them, wasting a fix pass, or guess. Flakes also go unrecorded in `state.json` → flakes and Quarantine.
**Fix:** In C4 step 1, give the T1 helper the rule `lanes.md` step 3 already uses for group T1:
- It reruns a failure alone.
- A failure that passes alone and lies outside the child's diff, or that is in the baseline digest or under a running checkpoint fix, is not red.
- Its digest lists each one as flake, baseline or red.

The orchestrator records flakes as it does for checkpoints.

### P1-06 · major · design · C4 step 1 (line 47), `implement` → Build ("Keep built artifacts and services warm"), `lanes.md` → The pool
**Problem:** C4 doesn't say who owns the lane's test services between the implementer's handoff, the T1 helper's run and the implementer's next fix pass. The implementer is told to keep services warm on the lane's ports and leaves them running at handoff. The T1 helper then boots the harness on the same ports, gets "port taken" or reuses a server it didn't start, and stops or leaves it as it judges. The resumed implementer then finds its warm server gone or restarted. A port failure that survives one retry is an environment stop (`orchestrate` → Recovery), so this can halt a lane. Today one session (the implementer, with its own helper) owns the ports end to end.
**Fix:** Add one rule in `implement` → Handoff and the T1 helper task: "Stop the services you started on the worktree's ports before you hand off. The T1 helper boots its own and stops them when done." The alternative is to let the helper reuse a warm server only after the existing freshness check, but that is more mechanism. Give the helper the lane's environment and port check, as `lanes.md` → The pool requires for every lane task.

### P1-07 · major · design · C5 (lines 58–60) vs `orchestrate` → Where work runs ("One writer per worktree")
**Problem:** A refresh major found in code review pass 1 "goes to a fresh plan-author for the plan and to the implementer for the code". Plan changes after approval run in the child's worktree (`orchestrate` → Planning), which is the lane, and so does the implementer. The plan doesn't order them, so the orchestrator may launch both together: two writers in one worktree. It also doesn't say whether the implementer fixes the code against the old plan or waits for the corrected one. The step that C5 removes, a separate refresh review before Implement, also held the budget update and the check against the review-load signal. With it gone, the plan doesn't say these still happen before the implementer starts. A refresh that pushes the estimate over the signal could otherwise be built whole without the separable-concerns check.
**Fix:**
- On a refresh major, the fresh plan-author fixes the plan first. The implementer is resumed after that commit, with both the ledger and the plan fix, and the pass counts as one fix pass.
- In Start step 4: "Update the budget and apply Sizing and scope before Implement, whether or not the refresh is reviewed separately."

### P1-08 · major · design · C6 (lines 68–70), C4 step 1 (line 47), O1
**Problem:** The worker-count rules contradict each other, and the budget can be oversubscribed:
- C4 runs the helper "with the child's E2E worker count", a per-child value as in today's Implement step. C6 instead sizes per run, "split … across the T1 and checkpoint runs in flight when each one starts".
- Splitting at start time oversubscribes. A T1 that starts alone takes the whole budget. When a second starts, the split gives each half, but the first already holds all of it. Example: budget 8, run A starts alone with 8, run B starts with 4, total 12.
- The split doesn't count other users of workers: the T0 E2E specs of building lanes, implementer-run T1 (integration conflict fixes, checkpoint fixes, epic-close fixes), and checkpoint-fix reruns.
- The `scope` floor of "at least 2 E2E workers per lane" sizes for every lane running T1 at once, which C6's own split rule is meant to avoid. With O1's proposal (keep cores ÷ 4) it caps `maxLanes` at 4 on a 32-core host. The default then ships B+ at 4 lanes (4h16, README), not the 3h54 that §1 claims.

The simulator holds T1 at 5 min regardless of how many T1s run at once, and doesn't model memory. So the 6-lane gain, B+ 4h16 → 3h54, rests on T1 not slowing under contention. The evidence doesn't show that.

The plan also doesn't say:
- whether `scope`'s default `maxLanes` of 4 stays;
- that 6 lanes need 6 pool worktrees in the repo (rollout).

**Fix:**
- One rule in `lanes.md`: "When a T1 or checkpoint run starts, give it the budget minus the workers held by runs in flight, at most an even share of the budget across those runs, and at least 1. Pass that count in its task." Use it for helper and implementer T1 alike, and drop "the child's E2E worker count" from C4.
- Replace the `scope` per-lane floor with "`maxLanes` at most the pool size and memory ÷ 6 GB; default 4".
- On O1: keeping the default is reasonable. State in §1 that the expected default is about 4h16, and that more lanes wait for the #142 measurement of E2E time against worker count and concurrent runs. Add per-run worker count and T1 duration to §6, so O1 can be decided from data.

### P1-09 · minor · C1 (line 17), §5
**Problem:** C1 introduces a new risk that §5 doesn't list: contract drift. When 03 implements the contract that 01 delivered and finds it wrong, 05, which depends only on 01, is building against the old contract in parallel. The break shows up only at integration or a checkpoint.
**Fix:** Add the risk to §5, and a one-line rule in `scope` or `lanes.md` → Claims: "a child that must change a contract an earlier child delivered reports it, as for a claim."

### P1-10 · minor · C2 (line 26)
**Problem:**
- "Start the epic-diff review and the final checkpoint together" conflicts with Checkpoints step 2 ("The run for C+1 waits until C is green and merged"). The simulator's close gate also waits for the previous checkpoint.
- The replacement list drops today's step 4 ("Hand off to the PR process …").
- The epic-close implementer's own T1 belongs in C4's "Unchanged" list (line 44), next to the integration and checkpoint-fix defaults. After P1-02 it may move to a helper instead.

**Fix:** "Start the review at once, and the final checkpoint as soon as the previous one has merged." Keep the PR handoff step. List the epic-close T1 owner in C4.

### P1-11 · minor · C4 `implement` text (lines 41–44)
**Problem:** The plan doesn't say what `implement` text changes besides Gates step 1. Lines that would still contradict C4:
- Gates step 2 ("Fix the failures. Rerun only what failed") and step 3 (the escalation exception);
- the Delegation bullet;
- Handoff's first evidence bullet ("the commands run, with pass/fail and duration per gate");
- the orchestrate Implement step ("passes T1");
- the no-pool rule "While a child's implementer or code reviewer is running there … run no git commands", which needs to name the T1 helper too.

Other gaps:
- **Escalation:** it isn't stated who runs the full gates when the plan escalates (presumably the helper).
- **Selection format:** "the repo's selection command without running it" is ambiguous. The ledger should record the resolved command lines (with explicit base and spec list), not a command that re-selects at run time. The reviewer's ledger commit moves HEAD during T1, and the tree-match rule needs exact command lines.
- **Worktree:** step 1 says "in the lane worktree". Single-plan and no-pool runs use the work-branch worktree.

**Fix:** List each line to replace. Say that the ledger records exact T1 command lines. Write "the child's worktree" instead of "the lane worktree".

### P1-12 · minor · C4 (lines 42, 52)
**Problem:**
- With T1 off the implementer, lint, format and build failures reach the reviewer, and come back as fix passes that add noise to the fix range. T0 already covers typecheck, but not lint, format or build.
- The `review` change "T1 results are the orchestrator's" holds only for lane passes. Integration, checkpoint-fix and epic-close reviews still get implementer-run T1 evidence, and must keep checking it, including the flake check.
- "Record a doubt as a finding that names the check" doesn't say what severity the finding has. A major forces a fix pass for code that may be fine.

**Fix:**
- Keep the fast T1 gates (build, lint and format on changed files) in the implementer before handoff. The helper runs units and E2E.
- Scope the review text to lane passes.
- Make a doubt a minor that names the check, which the next T1 run includes.

### P1-13 · minor · C5 (line 58), §1
**Problem:**
- The evidence gives C5 0 min on the example epic, because no refreshed child is on the critical path, and about 4 min per refreshed child in the single-plan model. Against that, it adds a review sub-mode, a conditional branch in Start, and the P1-07 sequencing. That cuts against "simple rules over mechanism", for the smallest gain in the plan.
- "One fresh reviewer reviews the refresh first (as today)" leaves open whether today's second refresh pass still runs. Its trigger, claims or scenarios changed, is now always true in this branch.

**Fix:** Consider dropping C5, or say why 4 min per refreshed child is worth it. If you keep it, say "one refresh review, plus a second pass on the fix commits only if its majors changed claims or scenarios".

### P1-14 · minor · C7 (line 74), §7
**Problem:** C7's list leaves out several stale passages in `docs/frontier-pipeline.md`:
- the Where work runs table ("Planning (up to two)"; the Pool row should name T1 helpers);
- "A child, start to finish" step 4, Code review (conditional pass 2);
- the Units section (contract-first dependencies);
- "Regenerating the diagram", which still describes a hand-written scenario, while the new example comes from `tools/process-sim.mjs` and an epic.json;
- History, which needs this plan.

The example's lane count should match the O1 outcome (P1-08), or it will show 6 lanes that the default doesn't give.
**Fix:** Change C7 to "every passage C1–C6 changes". Name these passages, and the regeneration commands.

### P1-15 · minor · §6
**Problem:** The measures can't confirm the conditions C4, C5 and C6 depend on. They don't record:
- the red-T1-at-handoff rate and T1-only fix passes (P1-04);
- flakes and baseline failures classified by the helper;
- refresh majors found in code review, and their rework (C5);
- E2E workers per run against T1 duration and how many T1s ran at once (O1, C6);
- whether the final tree was verified (C2).

The second target, "the critical path no longer than the content's real dependencies", has no measure.
**Fix:** Add these fields. Or drop that target, or say how it is checked (for example, a sim replay of the epic's real durations).

## plan pass 1 response (author)

All findings accepted, in the revised `plan.md`:
- P1-01: contract goes into the earliest child the dependent already depends on; no contract-only children (C1).
- P1-02, P1-10: Epic close order stated (review at once; checkpoint after the previous merges; fixes without T1; merge the green checkpoint; T1 for the fixes on the merged tip; PR handoff kept). A red final checkpoint doesn't pause the fixes (`checkpoint-failures.md` step 4).
- P1-03: closed no-re-check set; every other code major needs a re-check (C3).
- P1-04: every fix pass counts toward the cap; a review follows T1 fixes unless they touched only tests or fixtures; red after fixes is another fix pass; red-at-handoff rate measured (C4 steps 3–5, §5, §6).
- P1-05: the helper classifies flake / baseline / red, as group T1 does (C4 step 1).
- P1-06: the implementer stops its services before handoff; the helper boots and stops its own (C4).
- P1-07, P1-13: the refresh-in-code-review change is dropped (§3 "Dropped after review").
- P1-08: one worker rule for all T1 and checkpoint runs (C5); `maxLanes` default 4, bounded by pool and memory; §1 states 4h16 at the default; O1 waits for measurement.
- P1-09: contract-drift risk and a claim-style report rule (C1, §5).
- P1-11: `implement` lines listed; exact command lines recorded; "the child's worktree"; helper runs escalated full gates; no-pool rule names the helper (C4).
- P1-12: the implementer keeps T1's fast gates; review text scoped to a child's own passes; a doubt is a minor (C4).
- P1-14: C6 lists every passage and the regeneration commands; the example uses the default 4 lanes.
- P1-15: measures added; the chain target dropped from §1 (the epic review checks it, C1).
