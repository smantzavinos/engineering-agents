# Architecture-Driven Engineering Plans: Design Handoff

**Date:** 2026-10-21  
**Target repository:** [`smantzavinos/engineering-agents`](https://github.com/smantzavinos/engineering-agents)  
**Starting point:** branch [`pilot/process-retro`](https://github.com/smantzavinos/engineering-agents/tree/pilot/process-retro)  
**Status:** Design direction agreed in discussion; **not yet implemented or validated**. This document is a handoff for investigation, simulation, refinement, and a controlled pilot—not a claim that every implementation choice below has been finalized.

## 1. Executive summary

Redesign the normal engineering workflow around **one potentially substantial implementation plan** that contains a **structured, C4-inspired component architecture**, rather than defaulting to an epic with multiple child plans whenever a change is large.

Each project defines its **own catalog of allowed component types, variations, and implementation-pattern references**. The engineering-agents framework defines the process and generic schema/extension points, not a fixed SvelteKit/Convex taxonomy.

A plan declares the components and their relationships in a **machine-readable JSON model**. Render architecture diagrams from this model; do not treat a hand-edited diagram as the source of truth. Separate **runtime/architectural dependencies** from **actual implementation prerequisites**. Stabilize interfaces/contracts where useful so, for example, a Convex query and the Svelte UI consuming it can be implemented in parallel.

From the architecture and contracts, derive **dynamic implementation work packages**. A work package is **not** necessarily one component, one architectural layer, one vertical slice, or one child plan. Package boundaries should balance dependency readiness, ownership and code conflicts, cohesion, verification, reviewability, integration cost, and the critical path. These packages may execute concurrently while sharing one reviewed plan.

**Epics stay available, but become exceptional:** use them to coordinate meaningfully distinct plans/workstreams contributing to a larger vision, whether those plans run sequentially or concurrently. Do not create epics merely because a plan spans multiple architectural components, contains substantial code, or benefits from parallel execution.

Keep strong independent design/code review and meaningful verification, but avoid multiplying full planning/review/integration loops merely to enable parallelism. **Throughput and quality must both be measured.**

## 2. Problem and motivation

The engineering process evolved when models needed fine-grained instructions. Historically, plans often contained approximately 8–15 prescribed implementation steps, individual TDD cycles, per-step verification, and repeated review. That structure became expensive and no longer appears justified for many tasks with stronger coding models.

The user has been shifting away from micro-task checklists toward concise plans that make architectural decisions, define expected deliverables and contracts, and let capable implementers decide local coding details. The main goals are:

- **Higher end-to-end throughput**, not simply fewer words in a plan or more simultaneously running agents.
- **More useful parallelism**, particularly by breaking unnecessary dependency chains.
- **Consistent quality**, explicit correctness contracts, and independent review.
- **Predictable integration**, reduced code/write conflicts and repeated test runs.
- **Reusable project-specific engineering patterns**, without hard-coding one application stack into the agent framework.
- **Default simplicity:** a single plan should handle substantial features; multi-plan epic orchestration should not be routine.

The existing branch has already made significant improvements: cohesive vertical-slice child plans, fast T0/T1/full-gate tiers, parallel lanes/worktrees, claims, early planning, conditional extra review passes, targeted refresh, deliverable evidence, and measured process simulations. This proposal should **build on** those lessons, not discard them.

### Evidence from current retrospective work

The current experiment in [`plans/2026_10_20_process_variants/README.md`](https://github.com/smantzavinos/engineering-agents/blob/pilot/process-retro/plans/2026_10_20_process_variants/README.md) records:

- A **simulated**, seven-child example: current process variant A at **6h11**, proposed B+ at **3h54** (approximately 37% shorter *in the model*). This is illustrative, **not a measured production speedup**.
- Pilot measurement over 22 children in eras C/D: **79-minute median** from build start to merged; median build 36 minutes, code review loop 25 minutes, and integration 8 minutes. Other phases can add latency when they hit the critical path.
- In the pilot, repeated T1 tests materially affected build time; test selection was often too broad. Improving decomposition will not help enough if package-level verification recreates the same repeated cost.
- Shortening dependency chains was powerful; adding lanes alone did little until enough independent work existed.

**Important distinction:** the October 20 exploration explicitly recorded a decision *against further parallelism inside a plan*, based on variant C. **We are now proposing to revisit that decision**, but with a different mechanism: **one shared, contract-first architecture and multiple independent work packages**, not merely adding a child orchestrator or more subagents to a traditional child plan. Treat this as a new hypothesis to test, not as a previously approved change. Existing measurements and simulation inputs remain useful baselines.

## 3. Decisions reached in this conversation

| Topic | Agreed direction | Rationale |
|---|---|---|
| Default scope | Prefer **one plan**, which may be large in code/behavioral scope | Avoid fixed overhead and proliferation of child plans for work that is one coherent feature |
| Epics | Reserve for **genuinely distinct coordinated plans/workstreams** | Epic orchestration should be exceptional, not the mechanism for every parallelizable task |
| Architectural modeling | Put the **detailed C4-inspired architecture in the individual plan** by default | The plan owns a coherent implementation architecture; forcing detailed design at epic scope creates unnecessary global upfront work |
| Epic architecture | When an epic exists, document only **cross-plan boundaries, contracts, and dependencies** needed for coordination | Avoid duplicating the full internals of each plan |
| Model source of truth | **JSON structured data**, rendered as diagrams | Agents can validate, inspect, compare, and use the graph without parsing visuals |
| Component vocabulary | **Defined per project/repository**; engineering-agents supplies hooks/conventions | Different repositories have different component types, variants, and implementation practices |
| Implementation patterns | Catalog entries point to documented patterns and examples | Patterns can be reused without bloating every plan with instructions |
| Implementation partitioning | Derive **dynamic work packages** from the architecture/dependencies; **not 1:1 with components** | Components are design units; execution needs ownership, cohesion, conflict and timing considerations |
| Parallelism | Separate **runtime dependency** from **implementation blocking dependency**; use stable contracts to enable parallel work | A UI can depend on a query's interface without waiting for query implementation |
| Verification | Verify at **appropriate contract, package, integration, and whole-plan levels** | Preserve quality without repeating a complete test/review cycle for every small component or prescribed step |
| Optimization target | Optimize **critical path and end-to-end delivery**, with quality constraints | More agents or smaller packages can make throughput worse |

These are **directional design decisions**, not detailed commitments about the exact schema, scheduler, renderer, repository layout, or test commands.

## 4. Alternatives considered and why

### A. Traditional detailed plan with many sequential TDD steps

**Upside:** high explicitness; straightforward progress bookkeeping; suitable when models require micro-instructions.  
**Downside:** expensive handoffs, repeated tests/reviews, rigid tasks, often redundant with strong-model judgment.  
**Disposition:** do not restore as the default. Detailed steps remain optional for unusually risky or mechanical migrations that benefit from them.

### B. Make a large feature an epic with many small child plans

**Upside:** existing worktree orchestration and child review loops already support concurrency; each child has a clear deliverable.  
**Downside:** per-child plan, refresh, test, review and integration overhead; artificial dependency chains; children are often separated solely to get parallel lanes.  
**Disposition:** keep for genuinely separable plans, **not** as the default response to a large feature.

### C. Full detailed architecture for the entire epic, then child-plan fragments

**Upside:** strong global dependency visibility; easy to assign architectural regions to multiple plans.  
**Downside:** significant upfront design; epic becomes overly prescriptive; duplicated plan-level detail; unnecessary for the usual single-plan case.  
**Disposition:** **not** the default. Document an epic-wide high-level landscape only when cross-plan coordination demands it.

### D. Independent architecture diagrams inside every small child plan

**Upside:** local ownership and limited up-front design.  
**Downside:** can preserve the undesirable child-plan proliferation and duplicate interfaces across neighboring children.  
**Disposition:** plan-level architecture is correct, but **plans themselves should be fewer and able to cover more scope**.

### E. One substantial architecture-driven plan with dynamically grouped packages

**Upside:** a single coherent design and review; packages share contracts and can run concurrently; lower duplicated planning overhead; dynamic grouping can optimize throughput rather than enforce component boundaries.  
**Downside:** more complex integration/ownership than a single implementer; interfaces must be reliable; package scheduling/verification need care; design defects may affect several concurrent workers.  
**Disposition:** **preferred hypothesis**. Prototype and measure before replacing the existing workflow.

## 5. Recommended three-level model

### Level 1: Project-defined component catalog (persistent, repo-owned)

A repository declares the component **types**, **variations/patterns**, and **conventions** it supports. `engineering-agents` defines a generic catalog schema, validation rules, planning questions, and hooks. A repository may extend or specialize these definitions without having to fork the entire agent process.

For a **SvelteKit + Convex** project, *illustrative* types might be:

| Container | Example component types | Example variations/patterns |
|---|---|---|
| SvelteKit | route/page, UI component, client-state manager/store, server adapter | read-only view, editable form, paginated list, optimistic mutation, live data subscription |
| Convex | table/schema, query, mutation, action, authorization rule | filtered query, paginated query, transactional update, tenant-scoped access, background/third-party action |
| Cross-cutting | contract/interface, external integration, test fixture | shared DTO/validator, mocked API contract, integration adapter |

These are examples only. **The project selects the actual vocabulary** (including whether a “manager” abstraction is appropriate). A catalog entry should identify a type/variation, explain what it means, and link to implementation guidance, representative code, and relevant verification expectations; avoid copying those patterns into every plan. The catalog may also provide diagram styling or grouping metadata.

### Level 2: One plan's C4-inspired architecture (the design source of truth)

For each substantial plan, capture the relevant *changed/added* architecture, with references to the unchanged context. This is a **planning architecture**, not an exhaustive inventory of the entire repository.

- Containers identify meaningful runtime/deployment/data-system boundaries (e.g., SvelteKit app and Convex backend); use C4 terminology pragmatically rather than forcing files/functions into the wrong level.
- Components have stable IDs, a project-defined type/variation, purpose, owning container, source/pattern references, affected surfaces, and explicit interfaces where needed.
- Relationships distinguish calls/uses/data flow from design-time contracts and actual build prerequisites.
- State whether a component is new, modified, reused, or removed; capture high-risk behavior and cross-cutting requirements (auth, tenant isolation, validation, concurrency, failure, lifecycle).
- Render diagrams from JSON; renderable grouping/style hints are metadata, not the authoritative architecture.

**Keep the human-facing `plan.md` concise:** goal, design rationale, significant decisions/tradeoffs, non-obvious contracts, scenarios and acceptance criteria, risks, verification intent, and references to the architecture file/catalog. Do not duplicate all nodes in prose. An `approach.md` can be retained for genuinely distinct alternative analysis and major decisions, but should **not** be a compulsory duplicate of `plan.md` and the architecture JSON. Keep a concise intent brief (`brief.md` or accepted prototype handoff) where useful.

### Level 3: Derived execution/work-package graph (the scheduling artifact)

Derive **work packages** from the architectural model and approved contracts. The package graph is **separate from the architecture graph** and can be regenerated or adjusted as reality changes without redefining the design.

A package declares:

- scope/outcomes and components or component portions it owns;
- required **contract/design** milestones and true implementation prerequisites;
- **write/claim ownership** including shared files, schemas, generated registries and tests;
- acceptance and verification obligations, including contract, package and seam checks;
- integration/readiness conditions and affected downstream packages;
- anticipated effort and risk, primarily to support prioritization, reviewability, and bounded execution.

Packages may be vertical feature slices, multiple tightly related components in one layer, or cross-layer groupings. **Do not enforce one component per package, one package per layer, or exactly one package per acceptance scenario.** Conversely, avoid one giant package when stable contracts allow independent work with tolerable integration cost.

## 6. The central concept: dependency semantics and contract-first fan-out

**A dependency in a C4/runtime diagram is not automatically a scheduling dependency.** Model at least these distinctions:

1. **Runtime/architectural relationship:** “UI calls query.” It describes the finished system, not which code must be written first.
2. **Contract dependency:** “UI and query implementations require an agreed query signature, data shape, access/failure semantics.” Can be satisfied by an approved interface even before either implementation exists.
3. **Implementation prerequisite:** “Package B truly requires generated code, a migration, or another package’s integrated implementation.” This can block its start.
4. **Ownership/integration conflict:** “Packages touch the same table/registry/file or incompatible shared infrastructure.” This may require exclusive claims, coordination, or serial execution even if the features have no architectural dependency.

A contract-first milestone should be **small and intentionally stable**, not a forced full implementation layer. Define enough for the producer and consumer to proceed independently: identity, input/output types and validation, permission/tenant rules, errors, pagination shape, ordering, refresh/realtime semantics where applicable, and required compatibility guarantees.

For Convex specifically, investigate practical constraints: the real query's type often comes from Convex function definitions and generated `api` types. A written JSON shape alone does not guarantee the UI compiles independently. A workable contract could involve typed shared validators, a stable stub/export, an adapter/interface, or generated code made available before fan-out. **Choose the least artificial mechanism that fits the repository's real code-generation and build system.** If the shared contract itself must change, invalidate and review affected packages rather than pretending concurrency remains safe.

### Illustrative execution graph

A feature “lead inbox” might have this *logical* graph (not a required package split):

```text
           [Contract: Lead list + update semantics]
                         |
          +--------------+----------------+
          |              |                |
     [Convex list]  [Svelte inbox UI] [Convex update]
          |              |                |
          +-------+------+----------------+
                  |
        [Integration / seam verification]
                  |
          [Whole-plan validation]
```

The Svelte work can use an agreed typed interface and controlled mock/stub while Convex is being implemented. Actual packaging might combine `Convex update` with related permission logic, or join UI state handling with the route and components. Package boundaries are chosen for execution efficiency, **not copied mechanically from the diagram**.

## 7. Dynamic package construction: proposed heuristics

Have the agent first identify *contract milestones* and the **real** prerequisite DAG, then group compatible implementation work into packages. Evaluate candidate groupings using these principles:

1. **Unblock the fan-out early.** Prefer a minimal, solid contract/foundation milestone that lets multiple implementers proceed; do not force all backend implementation to finish before frontend starts.
2. **Group tightly coupled changes.** Code that shares unstable internal details, many edits to the same files, or a single correctness invariant often belongs together.
3. **Respect claims.** Separate packages should preferably have disjoint writable surfaces and clear ownership of schema, auth rules, generated artifacts, shared registries and test harness files.
4. **Aim for independently reviewable, provable outcomes.** A package can be verified using targeted checks and a documented contract, even if the end-user experience only works after integration.
5. **Amortize overhead.** Package granularity should reflect measured costs of agent launch, review, T1, merge, and potential refresh—not an arbitrary “one node, one worker” rule or strict lines-of-code limit.
6. **Minimize the critical path, not the number of packages.** Extra parallel work is beneficial only if it outweighs contention, integration cost, and downstream delay.
7. **Retain flexibility.** The planner/orchestrator may merge, split or re-order packages when new information warrants it, while preserving approved scope and contracts and re-reviewing changed boundaries.

**Suggested initial implementation:** let a strong planning agent propose work packages using a small set of explicit heuristics, then validate them. Do **not** build a complex optimization solver, general-purpose scheduler, or reusable mega-framework before the first convincing pilot. The existing worktree/claim machinery may provide much of what is needed.

## 8. Planning, execution, review, and verification lifecycle (proposed)

1. **Intent and scope:** capture the desired behavior, acceptance scenarios, exclusions, key constraints and current-code findings. Do not require a prototype for all entry paths; the current prototype-first workflow can remain one supported path.
2. **Architecture and decisions:** load the project catalog; design only relevant components, relationships and contracts in JSON; record significant tradeoffs in concise prose.
3. **Architecture/contract review:** one strong independent review of system correctness, missing behavior, access, concurrency, data integrity, significant boundaries, and whether contracts are implementable. Correct material flaws **before** widespread parallel build.
4. **Derive packages:** create the execution DAG and claims from the approved architecture; explicitly label the unblock/fan-out milestones, risks and integration obligations. Review package boundaries for artificial dependencies, collisions and test gaps. This is **not** one full child-plan author/reviewer loop per package.
5. **Concurrent implementation:** schedule packages when their actual prerequisites are met; use isolated worktrees where needed; share typed contracts and pattern links; implementers use local judgment rather than following detailed TDD step lists. Carry forward the existing per-package targeted checks and evidence ledger as appropriate.
6. **Targeted independent code review:** review each meaningful package diff and its tests, especially high-risk behavior. Do not replace independent review with merely checking that tests passed. Rereview changed code rather than the full unchanged diff where safe.
7. **Integration and seam validation:** integrate compatible packages early enough to expose type/contract/behavior mismatches; execute relevant integration tests and cross-package reviews; avoid a forced all-at-once integration barrier where it would extend the critical path.
8. **Whole-plan verification and close:** run appropriate broad gates, verify each acceptance scenario and boundary, reconcile implemented architecture to the JSON model, and review the integrated diff for gaps/contract drift. Reuse the retrospective's gate-deduplication and no-identical-tree rerun rules.

### Preserve existing quality work

Do **not** treat architecture modeling as a substitute for unit, contract, integration or E2E tests. A useful division is:

| Verification boundary | Main responsibility |
|---|---|
| Interface/contract | Typed compatibility, validation, auth/visibility obligations, error semantics |
| Component/package | Focused behavior and invariants, targeted T0/tests, independent code review |
| Package integration/seams | Provider–consumer compatibility, shared data mutations, concurrency, cross-container behavior |
| Complete plan | Acceptance scenarios, meaningful end-to-end flow, affected full-gate coverage, integrated architecture review |

Prefer existing `test-quality`, T0/T1/full-gate rules and evidence mapping, adapting their **scope and timing** carefully. In particular, avoid simply running full T1 for every tiny package *and* at every integration, which could erase any speed gain. A final green whole-plan result is required even when packages passed independently.

## 9. Candidate artifact layout and schema (illustrative only)

This is a **lean candidate**, not a settled filesystem contract:

```text
repo/
  docs/engineering/
    component-catalog.json        # project-owned vocabulary
    patterns/                     # project-owned examples and guides
  plans/YYYY_MM_DD_feature/
    brief.md                      # intent, or link to accepted prototype
    plan.md                       # concise decisions/acceptance/risks
    architecture.json             # source of truth for planned components
    packages.json                 # derived execution graph; may evolve
    review.md                     # plan/package/code evidence as appropriate
    state.json                    # orchestrator's state
    diagrams/                     # generated SVG/other renderings
```

For an epic, keep each distinct plan's own `architecture.json`; use `epic.md` and, only when useful, a **small** epic-level map of plan-to-plan relationships. Avoid recreating a full architecture model across the epic and its constituent plans.

Conceptual, **non-normative** JSON sketch:

```json
{
  "catalog": "../../docs/engineering/component-catalog.json",
  "containers": [
    { "id": "web", "name": "SvelteKit" },
    { "id": "backend", "name": "Convex" }
  ],
  "components": [
    { "id": "leadList", "container": "backend", "type": "convex.query", "variation": "paginated", "contract": "contracts/lead-list" },
    { "id": "leadInbox", "container": "web", "type": "svelte.ui", "variation": "list", "uses": ["contracts/lead-list"] }
  ],
  "relationships": [
    { "from": "leadInbox", "to": "leadList", "kind": "runtime-call" }
  ]
}
```

The actual schema should be designed **after testing a few representative features**, and should be strict enough to validate references and known component types but permissive enough for new project-specific variations. Do not force work-package assignments into the component records: keep implementation scheduling distinct from architecture. Reuse JSON Schema and TypeScript types if natural for the repository. A renderer should accept the validated model; which layout engine to use remains open.

## 10. Open design questions (do not silently decide these)

**A. Exactly what is a package?** Determine the smallest useful fields, whether packages are plan-author-generated once or revised while running, and whether package claims include subcomponent ownership. Verify that the model can represent a package that spans layers and a package that owns only part of one component.

**B. Contract readiness:** what constitutes an *approved and consumable* contract, particularly with Convex-generated TypeScript types, schema migration and codegen? Should a minimal contract milestone be a separate package or a pre-implementation part of the plan? Prefer the cheaper mechanism that unlocks real concurrency.

**C. Package workspaces and integration:** can existing lane/worktree machinery be reused with a single plan? How are shared plan/model edits serialized? When can a package be merged and downstream work proceed—without creating unnecessary group-wide barriers?

**D. Review placement:** retain one mandatory independent architecture/plan review and real code review, but determine when reviews are per-package versus integrated seam versus whole-plan, and how reviewers avoid duplicating prior work. Define explicit scope/contract-change re-review triggers.

**E. Verification ownership:** where should a contract be tested exactly once, how should test selection compose across packages, and what warrants broad T1/full gates? Use real command timings, not optimistic assumptions.

**F. What qualifies for epic promotion?** Propose qualitative rules based on independently meaningful plans, major uncertainty or separately governable outcomes—not an arbitrary changed-line count. Document when a single large plan becomes unmanageable and why.

**G. Catalog ownership and validation:** choose project-level config paths, schema extensions, pattern links, display metadata and evolution/versioning without overengineering.

**H. Architecture freshness:** will `architecture.json` describe intended changes only, or also become maintained documentation of implemented state? At a minimum reconcile it at completion; do not promise a continuously maintained repository architecture inventory without a separate decision.

**I. Source artifact entry path:** keep brief/approach support but avoid duplicating design across markdown, JSON and rendered diagrams. Ensure architecture-driven planning works **with or without** the current prototype-first path.

**J. Layout tool:** choose a JSON-to-diagram renderer only after basic schema requirements are clear; preserve independent work on C4-style visualization and on work-execution timeline visualization. The existing **Work Trace** project visualizes agent execution, **not** the application architecture.

None of these questions blocks preparing a **testable prototype**. They should be explicitly resolved or deferred during that work.

## 11. Proposed validation experiment

**Do not replace the frontier pipeline immediately.** Work on `pilot/process-retro` (or a new experimental branch from it) and establish repeatable baselines.

### Experiment 1: Model an existing example as one plan

Take the existing seven-child illustrative epic in [`plans/2026_10_20_process_variants/`](https://github.com/smantzavinos/engineering-agents/tree/pilot/process-retro/plans/2026_10_20_process_variants) and model the same behaviors as **one architecture-driven plan with dynamically grouped work packages**. Make sure all original acceptance scenarios, changed surfaces, boundary conditions and integrations remain covered. Do not improve the numbers by silently deleting work or tests.

Create two or three plausible package decompositions, including (i) naively layered, (ii) contract-first fan-out, and (iii) a less fragmented/cohesion-oriented variant. Vary the assumptions for package review, test execution and integration overhead, and simulate the critical path with realistic resource limits. Reuse or extend the existing [`tools/process-sim.mjs`](https://github.com/smantzavinos/engineering-agents/blob/pilot/process-retro/tools/process-sim.mjs) and Work Trace outputs where practical.

**Caution:** existing simulation durations are per *child*, not per new package. A fair comparison needs separate estimates for package planning, code review, integration, and test repetition. A seven-child-to-one-plan relabeling alone proves nothing.

### Experiment 2: Implement a modest real feature twice or compare a matched pair

Use a representative SvelteKit/Convex change with a typed backend contract, dependent UI, meaningful auth/tenant rules and some end-to-end behavior. Compare the existing frontier workflow with the new approach under similar models, machine limits and test harness. If a same-feature A/B is too expensive, use closely matched changes and state the uncertainty.

Record: elapsed time from scope approval to green integrated work; critical-path waiting; total model/runtime/cost; worker utilization; number and duration of reviews/refreshes; T0/T1/full-gate invocations and durations; conflicts and rework; escaped defects, missing contract/authorization cases and integration failures. Compare **quality**, not just wall clock.

### Experiment 3: Decide on adoption

Adopt the new approach only if it demonstrates worthwhile end-to-end speed improvement **without degraded correctness or unmanageable orchestration complexity**. Calibrate package heuristics against observed overhead. Keep the existing process as a fallback for unusual work and for projects without parallel-ready infrastructure.

## 12. Suggested implementation sequence for the process agent

1. **Audit the current branch's applicable skills and prior decisions.** Treat [`skills/scope/SKILL.md`](https://github.com/smantzavinos/engineering-agents/blob/pilot/process-retro/skills/scope/SKILL.md), [`skills/plan/SKILL.md`](https://github.com/smantzavinos/engineering-agents/blob/pilot/process-retro/skills/plan/SKILL.md), [`skills/orchestrate/SKILL.md`](https://github.com/smantzavinos/engineering-agents/blob/pilot/process-retro/skills/orchestrate/SKILL.md), [`skills/orchestrate/references/lanes.md`](https://github.com/smantzavinos/engineering-agents/blob/pilot/process-retro/skills/orchestrate/references/lanes.md), `skills/review`, `skills/implement`, `skills/test-quality`, the retrospective, and process-variants results as the starting point. Legacy `docs/plan-levels.md` is **not** the frontier pilot's source of truth.
2. **Draft one minimal real catalog and one plan-level architecture model** for a representative project. Avoid a massive cross-repository pattern standardization effort.
3. **Validate contract fan-out in actual code.** Establish how a Svelte UI can type-check and be tested against a Convex query contract before its production implementation exists. Resolve codegen and shared-file ownership early.
4. **Propose multiple work-package groupings** and simulate the difference, including realistic per-package overhead and resource contention.
5. **Build a small renderer/validator** from JSON, only to the extent necessary to inspect and review plans. Avoid making diagram layout a prerequisite for throughput experiments.
6. **Modify skills incrementally**—likely `scope`, `plan`, `review`, `implement`, `orchestrate` and lane handling—preserving safe recovery, worktrees, review logs, test tiers and stop conditions. Do not blindly transplant the old epic-child state machine into every package.
7. **Run a real pilot**, examine the Work Trace and quality evidence, then revise package sizing, contract rules and review/verification ownership.
8. **Update docs and adopt only after results.** Explicitly distinguish agreed design intent, approved skill changes and measured outcomes.

## 13. Guardrails / non-goals

- Do **not** assume more parallel implementers automatically means faster delivery.
- Do **not** build a general-purpose DAG solver or task orchestration framework before validating the concept.
- Do **not** require full-repository architecture modeling or a complete global C4 model to change one feature.
- Do **not** enforce a fixed component vocabulary in `engineering-agents` or bake in Convex/Svelte-specific rules beyond example adapters.
- Do **not** recreate per-component TDD checklists or per-package full child-plan loops.
- Do **not** split packages solely to meet line-count thresholds; retain reviewability and bounded scope as signals.
- Do **not** infer that a runtime edge forces serial implementation.
- Do **not** remove independent review, important auth/concurrency checks or final integrated verification for speed.
- Do **not** confuse the application's architecture diagram with **Work Trace**, which describes agent activity and timing.
- Do **not** treat speculative simulation improvements as measured outcomes.

## 14. Definition of a successful design

A strong engineer can take **one concise, reviewed plan plus a validated architecture model and project-specific patterns**, generate a small set of appropriately sized, low-conflict work packages, stabilize only the interfaces that unlock useful concurrency, implement and verify packages with targeted evidence, and integrate them into one correct delivered feature **faster than the current child-plan-heavy pipeline**—without requiring the user to hand-manage micro-steps or multiply plans for ordinary features.

**First task for the receiving agent:** evaluate and refine this design *against the current retrospective branch and its experiments*; report important disagreements or missing evidence; then produce a minimal test architecture/package model and a fair simulation plan **before implementing large process changes**.
