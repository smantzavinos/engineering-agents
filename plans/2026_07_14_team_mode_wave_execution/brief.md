**Type:** standard
**Created:** 2026-07-14
**Owner:** exploration/design session

## Goals
- [ ] Define an alternative **fast execution mode** that uses OpenCode team mode to execute independent plan tasks in parallel, as a peer to the existing sequential [execution-orchestrator](../../skills/execution-orchestrator/SKILL.md) rather than a replacement.
- [ ] Establish the **wave** as the execution unit: the plan task graph is sliced into ordered waves of parallel-executable tasks, and a team is thrown at each wave.
- [ ] Specify how the mode is configured (team spec, member roles, bounds) and how it works end-to-end (slice → claim → implement in parallel → review live and at wave end → commit wave → advance).
- [ ] Document the differences, considerations, and rigor tradeoffs versus the sequential mode, so the choice between "fast" and "maximum rigor" is explicit and intentional.
- [ ] Anticipate the issues the parallel/shared-tree model introduces and pre-emptively specify solutions.
- [ ] Deliver a concrete **wave-slicing algorithm specification** as the first load-bearing design piece.

## Non-Goals
- Implementing the new skill, the team worklog artifact, or the plan-template changes. This work is exploration and design only for now.
- Replacing or deprecating the sequential execution orchestrator. It remains the default and the maximum-rigor path.
- Changing plan creation, plan review, or approach review for the sequential path.
- Git worktree-based isolation. Shared-tree with a single committer is the chosen model; worktree isolation is explicitly rejected (see approach).
- Preserving every rigor guarantee of the sequential mode. Team mode deliberately trades some rigor (e.g. the per-task break-it check) for throughput.

## Constraints
- Must fit OpenCode team-mode bounds: max 8 members, max 4 parallel workers, max 32KB/message, max 256KB unread inbox.
- Category team members always route through `sisyphus-junior`; `oracle`/`prometheus` are not eligible as team members. This is the same executor/model routing already used by the sequential OpenCode path, so it is not a downgrade.
- `loadSkills` is ignored for team members — members receive behavior only through their `prompt`. Skill discipline must therefore be injected by instructing members to read the canonical skill file, not by loading it.
- Must preserve: strict TDD minus the break-it step (Red → Green → Verify), coherent commits with a matching execution-log update, backlog/requirement capture through documented repo mechanisms, and local-only commits (no push).
- Must integrate with existing plan artifacts and the repo process docs (`docs/orchestration.md`, `docs/plan-directory-structure.md`, `plans/README.md`) without introducing a second canonical source for verification, backlog, or requirements policy.

## Motivation
The sequential execution orchestrator is deliberately serial: one sub-agent per task, a single mutable worklog cursor (`NEXT STEP`), and one atomic commit per task on one branch. This maximizes rigor and reproducibility but leaves latent parallelism on the table — the [plan template](../../skills/create-plan/references/plan-template.md) already encodes a task graph with an explicit `Depends on` column, yet tasks whose dependencies are already satisfied still run one at a time.

OpenCode team mode provides parallel multi-agent coordination (a lead plus up to four concurrent workers, a shared task list with `blockedBy`, and message-based coordination). Applying it to the independent portions of a plan can materially reduce wall-clock time. The point of this mode is **speed**; when a user wants the most in-depth process possible, they continue to use the existing sequential structure.

## Success Criteria
- A documented, reviewable design exists for a team-mode "wave" execution alternative, captured as durable plan artifacts in this directory.
- The design clearly states which parts of the lifecycle stay sequential and which become parallel, and why.
- The git, coordination, worklog, and review models are specified concretely enough to build a skill from.
- A wave-slicing algorithm is specified with inputs, outputs, invariants, edge cases, and a worked example.
- Every anticipated failure mode of the shared-tree parallel model has at least one pre-emptive mitigation.

## Requirement Context
Relevant existing requirements, if the repo maintains them:
- Actors/personas: engineers running the autonomous execution process via OpenCode.
- Use cases: executing an approved plan to completion.
- Workflows/scenarios: the Execution phase described in `docs/orchestration.md`.
- Requirements: `FR-002` (canonical verification command surface), `OPR-001` (gate policy) are relevant to how the wave gate runs; no requirement currently mandates sequential-only execution.

Requirement questions:
- Should a new execution mode be captured as a durable requirement/ADR, or does it remain a process-doc + skill addition only?

## Plan Level
standard

**Rationale:** This introduces a new execution strategy with a novel coordination model, a new algorithm (wave slicing), a new artifact (team worklog), and cross-document integration, but it is scoped to the Execution phase and does not require epic-level decomposition.

## Key Decisions Made (during exploration)
| Decision | Chosen | Rationale |
|----------|--------|-----------|
| Scope of parallelism | Implementation phase only (Step 5); plan/review/worklog/final-review stay sequential | Only task execution has parallelizable units; the rest is an inherently serial artifact pipeline. |
| Execution unit | The **wave** (a batch of parallel-executable tasks), not the individual task | Speed comes from batching independent work and reviewing it together; per-task granularity is the sequential mode's job. |
| Git model | Shared working tree, single committer (the lead) | Avoids git index races (only one agent runs git) and surfaces file conflicts live/early rather than at a merge step. Worktree isolation rejected. |
| Conflict strategy | Detect at wave-planning time via per-task declared file sets; genuine overlaps serialize into different waves or are resolved live by the workers | "Identify conflicts earlier" — file overlap is a slicing input, not a commit-time surprise. |
| Coordination substrate | `team_task_list` (`blockedBy` = plan deps) as the live board; a new **team worklog** as the durable record | The single-`NEXT STEP` worklog cannot express a parallel front. |
| Review model | A reviewer is a team member; reviews happen live (per task) and at wave end | Category members match today's review tier, so quality is preserved; a persistent reviewer also gains cross-wave integration context. |
| Break-it check | Dropped by default in this mode | It is the largest single per-task time cost; the reviewer's test-adequacy gate partially compensates. This is the explicit speed-for-rigor trade. |
| Relationship to sequential mode | Peer alternative, opt-in | Maximum-rigor work keeps using the sequential orchestrator unchanged. |

## Open Questions (to resolve during planning)
- How should file-set overlap be computed when tasks declare globs rather than explicit paths? (v1 proposes a conservative path/prefix check; glob-precision is a follow-up.)
- Should the final cross-wave review remain mandatory, or become optional in a maximum-speed sub-mode given per-wave reviews already ran?
- One persistent team for the whole plan vs. respawn per wave-group for very large plans — what plan size should trigger respawn?
- Does the team worklog become a new `create-team-worklog` skill, or a branch inside `create-worklog`?
- Should wave slicing live in the planner (static waves written into `plan.md`) or in the orchestrator (computed at execution time from the task graph)?
