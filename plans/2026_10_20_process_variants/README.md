# Process variants: one example epic under four process designs

Status: exploration, 2026-10-20. Nothing here changes the skills yet.

Owner decision after the first round: no further parallelism inside a plan (variant C is kept for the record only). Work goes into running plans in parallel and into shortening a single plan's end-to-end time; variant B+ and the single-plan section below follow from that.

## Why

The example trace in `docs/frontier-pipeline.md` showed that its critical path was a chain of dependent children, not capacity. This compares the current process with candidate changes on the same seven-child epic, to see which changes matter before any skill change.

## Method

- `tools/process-sim.mjs` schedules an epic under the execution rules of `skills/orchestrate` (planning, unit start order, lanes, integration, checkpoints, epic close; the rules modelled are listed at the top of the tool). It writes a scenario; `tools/scenario-trace.mjs` turns that into a Work Trace; `tools/work-trace-render.mjs` draws it.
- **Durations** are the median run times of the pilot's eras C and D (fast verification), per phase: plan 15, plan review 5, plan fixes 10, scout <1, refresh 11, refresh review 5, code review 6, fixes 10, review 2 4, integration conflict 8, integration T1 6, full gates 8, epic review 8. Builds 25–45 (era C/D median 36–40). Orchestrator latency between steps 1 min (measured median 0.3, p75 2.4).
- **The epic** is the one from the docs example: 01 data model; 02 list, 03 detail and 04 import (group G1) on 01; 05 editor on 03; 06 permissions split by its planner into 06a and 06b (group G2) on 01; 07 export on 02 and 05. The same children have plan fixes, refreshes, code-review fixes and one integration conflict in every variant.

Illustrative, not a forecast. Medians hide the long tail (large fix rounds, stalls), and no failure paths are modelled.

## Variants

| Variant | What changes | Trace |
|---|---|---|
| A | Current process: 3 lanes, 2 planning worktrees | `variant-a.svg` |
| B | Contract-first dependencies (01 also delivers the detail and edit contracts, +5 min build; 05 and 07 then depend only on 01), final checkpoint alongside the epic-diff review, conditional code pass 2 (only after `design` majors), 4 lanes | `variant-b.svg` |
| C | B plus a child orchestrator per child (owns the plan loop and the lane, parent of their calls), an early review of the first part while the rest is built, and T1 by a helper alongside the final review. Not pursued | `variant-c.svg` |
| B+ | B plus T1 alongside code review (the implementer hands off at commit; a helper runs T1 while the reviewer reads, and again after fixes), the refresh reviewed inside code review 1 instead of a separate refresh review, 3 planning worktrees, 6 lanes | `variant-bplus.svg` |

## Results

| | Elapsed | vs A |
|---|---|---|
| A current | 6h11 | |
| B | 4h38 | −1h33 (−25%) |
| C | 4h28 | −1h43 |
| B+ | 3h54 | −2h17 (−37%) |

**One change at a time** (from A, or from B):

| Change | Elapsed | Effect |
|---|---|---|
| A + 4 lanes | 6h10 | −1 min |
| A + contract-first dependencies | 5h55 | −16 min |
| A + final checkpoint alongside the epic review | 6h03 | −8 min |
| A + conditional code pass 2 | 6h01 | −10 min |
| B with 6 lanes | 4h36 | −2 min |
| B with 6 lanes and 3 planning worktrees | 4h08 | −30 min |
| B + early review and T1 alongside, no child orchestrator | 4h24 | −14 min |
| B + child orchestrators only | 4h42 | +4 min |
| B + T1 alongside code review | 4h21 | −17 min |
| B + refresh reviewed in code review | 4h38 | 0 (no refreshed child on the critical path) |
| B + critical-path planning order | 4h38 | 0 |
| B + backfill start order | 4h36 | −2 min |
| B + faster T1 (5 → 4 min, integration T1 6 → 4) | 4h33 | −5 min |
| B + T1 alongside + refresh in review, 3 planning, 6 lanes (B+) | 3h54 | −44 min |
| B+ + critical-path planning order | 4h11 | +17 min |
| B+ with 4 lanes / 5 lanes | 4h16 / 4h11 | |
| B+ with 2 planning worktrees | 4h21 | |

## What it shows

1. **Shortening the chain is the large win, but only together with capacity.** Contract-first dependencies alone save 16 min and 4 lanes alone save 1 min; together (with the two small changes) they save 1h33. With 05 and 07 off the chain, the epic becomes wide, and lanes and planning slots become the limit.
2. **Once the chain is short, capacity is the next limit.** In B, 07's plan waits for a planning slot (lower-numbered children go first) and then for a lane; G2 waits for lanes. 6 lanes and 3 planning worktrees take B to 4h08. The start-order rule also matters: with 5 lanes, G2 (needing 2) waits and holds back 07, which would fit.
3. **The final-checkpoint and code-pass-2 changes are small but free:** 8–10 min each, with no added mechanism.
4. **Child orchestrators don't buy speed by themselves** (+4 min: one more launch per phase). Early review and T1 alongside review save about 14 min here, because a code review is about 6 min and T1 about 5 at the pilot's speeds. Their case rests on other grounds: a smaller epic orchestrator, recovery and context per child, parallel implementers inside a child instead of splits (not modelled), and a trace that groups each child's work in one box.
5. **The docs example overstated the timeline.** With measured durations, the same epic takes 6h11, not 13h40; the fixed cost per child is about 30–40 min, not an hour.

## Single-plan time

Measured in the pilot (eras C and D, 22 children), a child took 79 min median (p75 134) from build start to merged:

| Phase | Median | p75 |
|---|---|---|
| Build (implementer, T1 inside) | 36 | 44 |
| Code review loop (review, fixes, review 2) | 25 | 48 |
| Approved → merged (integration) | 8 | 38 |
| Refresh, when the scout finds a relevant change (elapsed) | 38 | 100 |
| Plan loop (critical path only for a lone plan or the first child) | 34 | 111 |
| Orchestrator latency between steps | 0.3 | 2.4 |

**The build is mostly commands, not the model.** In era D, implementers spent 70% of their time in tool calls and 30% in the model; reviewers and plan-authors spent over 90% in the model. Most of the command time was T1: a median T1 took 5.5 min against an assumed 2.5, and a child runs it about four times on its critical path (end of build, after fixes, at integration, reruns).

**T1 never narrowed.** Its end-to-end tests were 60% of its time, and replaying the selection policy on every child merge selected the whole suite every time. Three rules widened it: any backend source file, any edit to the test map (every child adds its new tests to the map), and edits to test helpers. Without them the median selection would be about a third of the suite. This is repository work, not process: the analysis and the levers are in the pilot repository's retro (`t1_breakdown.md`).

**Levers for one plan**, in order of effect:

1. **Faster T1** (repository): select only what a test-map edit adds; map backend modules to the tests that use them; size test workers by free lanes. Expected about 1.5–2 min per T1 run, 6–8 min per child.
2. **T1 alongside code review** (process): the implementer hands off when the code is committed; a helper runs T1 while the reviewer reads; a red T1 joins the fix list. Saves one T1 per review pass: about 9 min per child in the model (01: 70 → 61 min from start to approval).
3. **Refresh reviewed inside code review 1** (process), unless the refresh changed claims or scenarios: about 4 min per refreshed child. A wrong refresh is then caught after it is built, not before.
4. Already in place: plan questions and the deliverables map (shorter fix rounds), conditional plan and code pass 2, environment fixes for integration.

## What the second round shows

1. **B+ takes the epic to 3h54** (−44 min from B, −2h17 from A). T1 alongside review is worth 17 min on its own and more with capacity (it frees lanes sooner).
2. **Capacity: 3 planning worktrees and 6 lanes, together.** Either alone does little; together they take B+ from 4h21 to 3h54. 6 lanes means 6 pool worktrees and test workers budgeted across them.
3. **No new ordering rules.** Critical-path planning order and backfill starts gave 0–2 min on B and cost 17 min on B+ (planning 07 ahead of 06's sizing delayed group G2 behind lane contention). Schedule effects of this kind swing ±15 min with small changes; child-number order stays.
4. **Faster T1 shows little in the model** (−5 min) because the model runs T1 once per build; in the pilot it ran about four times per child, so the real effect is larger. Measure after the repository change.

## Regenerate

```
D=plans/2026_10_20_process_variants
for v in a b c bplus; do
  node tools/process-sim.mjs $D/variant-$v.epic.json -o $D/variant-$v.scenario.json
  node tools/scenario-trace.mjs $D/variant-$v.scenario.json -o $D/variant-$v.trace.json --validate-with <work-trace checkout>
done
node tools/work-trace-render.mjs --work-trace <work-trace checkout> --width 3200 $D/variant-*.trace.json
```
