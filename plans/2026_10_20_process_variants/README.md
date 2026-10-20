# Process variants: one example epic under three process designs

Status: exploration, 2026-10-20. Nothing here changes the skills yet.

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
| C | B plus a child orchestrator per child (owns the plan loop and the lane, parent of their calls), an early review of the first part while the rest is built, and T1 by a helper alongside the final review | `variant-c.svg` |

## Results

| | Elapsed | vs A |
|---|---|---|
| A current | 6h11 | |
| B | 4h38 | −1h33 (−25%) |
| C | 4h28 | −1h43 |

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

## What it shows

1. **Shortening the chain is the large win, but only together with capacity.** Contract-first dependencies alone save 16 min and 4 lanes alone save 1 min; together (with the two small changes) they save 1h33. With 05 and 07 off the chain, the epic becomes wide, and lanes and planning slots become the limit.
2. **Once the chain is short, capacity is the next limit.** In B, 07's plan waits for a planning slot (lower-numbered children go first) and then for a lane; G2 waits for lanes. 6 lanes and 3 planning worktrees take B to 4h08. The start-order rule also matters: with 5 lanes, G2 (needing 2) waits and holds back 07, which would fit.
3. **The final-checkpoint and code-pass-2 changes are small but free:** 8–10 min each, with no added mechanism.
4. **Child orchestrators don't buy speed by themselves** (+4 min: one more launch per phase). Early review and T1 alongside review save about 14 min here, because a code review is about 6 min and T1 about 5 at the pilot's speeds. Their case rests on other grounds: a smaller epic orchestrator, recovery and context per child, parallel implementers inside a child instead of splits (not modelled), and a trace that groups each child's work in one box.
5. **The docs example overstated the timeline.** With measured durations, the same epic takes 6h11, not 13h40; the fixed cost per child is about 30–40 min, not an hour.

## Regenerate

```
D=plans/2026_10_20_process_variants
for v in a b c; do
  node tools/process-sim.mjs $D/variant-$v.epic.json -o $D/variant-$v.scenario.json
  node tools/scenario-trace.mjs $D/variant-$v.scenario.json -o $D/variant-$v.trace.json --validate-with <work-trace checkout>
done
node tools/work-trace-render.mjs --work-trace <work-trace checkout> --width 3200 $D/variant-*.trace.json
```
