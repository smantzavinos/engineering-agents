# Evaluating the frontier pipeline

Status: ready to run
Date: 2026-10-12
Design: [plan.md](plan.md). Setup: branch `pilot/frontier-pipeline`.

## Question

Can the new pipeline (prototype → scope → autonomous plan/implement loops) deliver children of the same quality as the current process, with much less wall time and the same or lower cost?

We learn by running it on real work, not by refining the design on paper. Change the skills between children only when the data points at a cause. Log each change in the run log below.

## Pilot

Pick one, in this order of preference:
1. **The remaining children of the in-flight reference epic**, starting at a natural child boundary. Same codebase, same kind of children, same people. This gives the most comparable baseline. `scope` turns its existing epic artifacts into an `epic.md` for the remaining children; nothing is re-planned that is already done.
2. **The next prototype-driven epic.** This is a cleaner test of the whole path, including `prototype` and `scope`, but the comparison is weaker.

Run at least three children through the autonomous loops before judging. One child is an anecdote.

## Setup

1. Point the dotfiles flake's `engineering-agents` input at `pilot/frontier-pipeline` and bump its `llmAgents` lock to the same Pi 1.1.0 revision.
   - Switch only when no session on the old process is mid-run. Running sessions keep their old Pi, but newly launched children would load the new packages.
   - Check: `pi --version` reports 1.1.0, and `pi list` shows `pi-checkpoint` and `pi-subagents` 0.77.0.
   - Check that the GitHub Copilot models the agents use are listed by `pi --list-models github-copilot`. `claude-haiku-5.5` comes from the live catalog (`pi update --models`), not the baked one.
2. In the consuming repo:
   - Allow the new agents' models: `plan-author`, `implementer`, `reviewer` and `helper`, in `.pi/settings.json` → `subagents.modelScope.agents`, plus `agentOverrides` if the repo maps roles to other models.
   - Make sure its canonical gate commands are documented. The skills don't invent them.
3. Start the orchestrator with `/preset scope` on the prototype or epic, then `/preset orchestrate` after approval.
4. Record the baseline gate digest in `state.json` before child 1 (the `orchestrate` skill does this).

## What to measure

The §15 measures in [plan.md](plan.md), all read from the pipeline's own artifacts:

| Measure | Target | Source |
|---|---|---|
| Wall time per L-sized child | ≤ 3 h (baseline 10.5 h) | `state.json` phase timestamps |
| Share of time in test execution | ≤ 30% (baseline ~70%) | gate durations in ledger entries ÷ child wall time |
| Cost per child | ≤ baseline (~$20) | usage per run in `state.json` |
| Review passes to approval, plan / code | ≤ 2 / ≤ 2 | `state.json` pass counts |
| Plan length | ≤ 150 lines | `wc -l` |
| Escaped defects: found at epic-diff or PR review, or after merge, that the child review should have caught | no worse than baseline | epic-root ledger and PR review |
| Human interventions | only §8 stop conditions | `state.json` stops |

Also record per child, in a few lines each:
- **Mechanics incidents:**
  - compaction checkpoints and resumes;
  - deadline kills;
  - fallbacks to a fresh session;
  - spawn-budget hits.
- **Delegation:** helper launches and what they were used for. Is the frontier agent offloading, or reading everything itself?
- **Rule misses:** places where a frontier agent did something a skill should have prevented, or where a skill rule caused waste.

## Checkpoints

- **After child 1:** a quick look by the owner, not a gate.
  - Did the loops converge?
  - Is the code at the quality bar?
  - Did anything burn time?

  Fix only what the data shows, then continue.
- **After child 3:** decide.
  - **Adopt:** the targets are met or clearly trending there, with no quality regression. Continue the epic, then do §14 step 4 (adopt) and write ADR 0007.
  - **Fix and continue:** a specific cause misses a target. Change that rule or mechanic and run two more children.
  - **Stop:** quality regressed (escaped defects, reverted work), or the loops don't converge within the cap. Return the remaining children to the old process and write up why.

Abort early if a child stops more than twice on mechanics (not scope), or if one child costs more than twice the baseline.

## Known gaps going in

- A subagent's `self_compact` ends its run and needs a resume, and a second compaction in the same child is refused (plan.md §5.1). Subagents don't compact at the end of a round. Watch for children that hit the context warning mid-build.
- pi-checkpoint's thresholds can't be passed to children. 1M-window models compact at 225k/250k tokens; smaller windows use the patched 55/65/75% fallback.
- pi-mcp-adapter 5.x connects its servers at startup, so missing credentials (e.g. `ZAI_API_KEY`) show as startup errors rather than errors on first use.
- ADR 0007 is not written yet. Write it after the decision, recording what the pilot showed.

## Run log

Append one entry per child: date, child, wall time, cost, passes, stops, mechanics incidents, rule changes made before the next child.
