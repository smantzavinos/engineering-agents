# Architecture-driven plans

**Status:** draft for discussion, not reviewed or approved · **Date:** 2026-10-21 · **Branch:** `pilot/arch-plans` (from `pilot/process-retro` at `d424a19`) · **Input:** [`handoff.md`](handoff.md), the design handoff; this plan supersedes it where they differ · **Evidence:** `plans/2026_10_15_process_retro/`, `plans/2026_10_20_process_variants/README.md`, ADR 0006 · **Changes (proposed):** `skills/scope`, `plan`, `review`, `implement`, `orchestrate`; new `run-plan`; skill frontmatter and agent definitions; `docs/frontier-pipeline.md`; a new ADR

## 1. Why

Two problems, in priority order:

1. **A human can no longer follow the work at a reasonable cost.**
   - Plans are freeform since we dropped the old long template. They are shorter, but it isn't clear from them what will happen.
   - After an autonomous run, the implementation is close to impossible to understand at a high level without a lot of reading.
   - Nothing holds the codebase to a fixed set of patterns. Each problem is solved on its own, so review means reading every line.
2. **The fixed cost of each plan still dominates.** In the pilot, the overhead per child (refresh, review loops, integration) outweighed build time. Splitting a feature into children multiplied that cost.

The answer to both is a plan whose design is a **structured architecture model**, rendered as a diagram the human approves at a glance. It is built from a **project-owned catalog of component types and patterns**, so the code converges on a known set of patterns instead of drifting. Throughput is the second goal: one coherent plan instead of many children, and possibly contract-first fan-out inside it (§5, experimental).

**Success:**
- the human understands and approves a plan from its diagram and a short `plan.md`, in minutes;
- delivered code declares which catalogued pattern it implements, and new patterns appear only through an explicit, reviewed step;
- end-to-end time is no worse than the current pipeline on comparable work. Better is the stretch goal, not the gate.

## 2. Decisions so far

| Topic | Decision |
|---|---|
| Default unit of work | **One plan.** It may be large. An epic is only for genuinely distinct plans or workstreams. |
| Default runner | A single plan runs with a dedicated **`run-plan`** skill, not with `orchestrate`. A new **`run-epic`** skill (today's `orchestrate`, slimmed down) coordinates plans by calling `run-plan` for each. |
| Design artifact | Each plan has a **c4ish model** (JSON) of the components it adds, changes, reuses or removes, plus the unchanged context they touch. c4ish validates and renders it. `plan.md` holds only what the diagram can't: decisions, risks, acceptance scenarios, gates. |
| Product and engineering | One plan model shows both views: what changes for the user (product concepts) and how it is built (containers, components, data). |
| Lifetime | The model and its diagrams belong to the plan and are **throwaway** after it. They are not maintained as repo documentation. |
| Pattern catalog | **Project-owned**, in the project's docs. It starts with a small key set and grows as plans touch new areas. Each entry has a type, variations, the intended form, a reference implementation and its verification expectations. |
| Finding pattern uses | **Comment tags in code**, Doxygen-style, at the definition: for example `@pattern <type>/<variation>`. Search finds every use. Untagged code is "unknown". **No central index** of where patterns are used. |
| Conformance | ast-grep rules per pattern where the shape is checkable: untagged instances of a known type, and tagged code that doesn't match its pattern. Untagged code warns; it doesn't block. |
| New patterns | When no catalogued pattern fits, the plan proposes one. The proposal is a first-class part of the plan: a catalog entry, a reference implementation and a reviewer check. Whether it also needs explicit human approval is open (Q4). |
| Framework scope | engineering-agents defines the process, the catalog's required fields and the tag convention. It ships no project vocabulary. |
| Skill visibility | Skills are loaded when the process needs them, not discovered by every model (§4.1). |

## 3. Shape of the process

```
intent (prototype or brief) ─► scope ─► run-plan ─────────────────────────────► PR
                                  │       plan + c4ish model ─► review ─► human approval (diagram)
                                  │       build (one implementer, or packages: §5)
                                  │       code review ─► gates ─► reconcile model to the code
                                  └─► run-epic (rare): run-plan per plan, plus cross-plan contracts
```

- **scope** decides one plan (default) or an epic. Epic promotion rules are qualitative, not a line count (Q6).
- **plan** writes `plan.md` and the c4ish model against the catalog, and marks each component as new, modified, reused or removed, with its pattern.
- **review (plan mode)** checks the model as well as the text:
  - every component maps to a catalog pattern or a proposed new one;
  - relationships are complete;
  - contracts can be implemented;
  - access, failure and concurrency are covered.
- **Human approval** is on the rendered diagram plus `plan.md`.
- **implement** tags each definition it creates or changes with its pattern. It follows the pattern's reference implementation and departs from it only where the plan says so.
- **review (code mode)** checks conformance: tags present and correct, code matching the pattern, no undeclared new patterns. It reads deviations closely and pattern-conforming code lightly.
- **Close:** reconcile the model with what was built, so the final diagram shows what shipped. That is the review record, not documentation.

## 4. Changes

### 4.1 Skill visibility and loading

Today every installed skill is visible to every model, including retired-process skills. Proposed tiers:

| Tier | Skills | Mechanism |
|---|---|---|
| Entry points | `prototype`, `scope`, `run-plan`, `run-epic` | `disable-model-invocation: true`; the human starts them with `/skill:name` |
| Role skills | `plan`, `implement`, `review` | Loaded only by the agent definition that needs them |
| Utilities | `delegate`, `test-quality`, `backlog` | Visible to models |
| Retired process | `create-plan`, `execution-orchestrator`, `review-plan`, `execute-task`, … | Not installed (part of the adoption ADR) |

**Constraint found:** pi-subagents filters skills marked `disable-model-invocation: true` out of subagent prompts, **even when an agent definition names them** (`buildSkillInjection`). So role skills can't simply be hidden. Options:
- (a) keep role skills outside the global skills directory and resolve them through the agent definition's local skill paths;
- (b) inline the role instructions into the agent definition;
- (c) leave role skills visible.

Prefer (a). Check that resolution works before relying on it.

### 4.2 `run-plan` and `run-epic`
- `run-plan`: the single-plan loop, which is today's `orchestrate` without lanes, groups or checkpoints:
  - plan loop → human approval → build → code review loop → gates → close;
  - plus the package fan-out of §5, when the plan has packages.
- `run-epic`: units, integration, checkpoints and cross-plan contracts. Each plan runs through `run-plan`, either in-session or as a child orchestrator.
- `orchestrate` is retired or becomes a thin alias. Existing safety rules carry over unchanged: recovery, stop conditions, ledgers, test tiers and the no-rerun rules.

### 4.3 Catalog contract (framework side)
- **Required fields per entry:** id (`<type>/<variation>`), what it means, when to use it, its reference implementation (file path), verification expectations, and, if checkable, its ast-grep rule.
- **Location:** a project declares where its catalog lives in its agent guide. The framework doesn't fix a path.
- **Catalog profile:** the project keeps one c4ish profile beside the catalog, durable and separate from any plan. It is the machine-readable index of the catalog: one entry per pattern with its id, label, family, how c4ish draws it (colour, icon) and a link to the pattern's section in the catalog docs. The Markdown docs hold the content. It lists patterns, not where they are used, so it is not a usage index. Plan models reference the profile; a plan that proposes a pattern adds its entry there.
- **Tag convention:** the comment syntax per language, one tag per definition, and the meaning of a missing tag. One page in `docs/`.
- `assess-repo` checks that a catalog exists and that the tag rules run.

### 4.4 Plan content
- **`plan.md` keeps:** goal, scenarios, decisions, risks, gates and handoff. It gains a link to the model and a "New patterns" section. The Changes section shrinks, because the model carries it.
- **The model carries:** containers, components with type, variation and change state, relationships (with kind and enforcement), libraries used inside components, product-level concepts touched, and contracts.
- **Rendered diagrams** are committed beside the model for review.
- **Review tour:** the model carries one guided tour across its views. Each step focuses elements, sets highlights, can trace an ordered path through the design, and has short narration. Every new, modified, removed or proposed element and every risk note appears in at least one step (c4ish lint). The tour orders the review; it does not replace the design narrative in `plan.md`.

### 4.5 Review
- **Plan mode:** the model checks in §3. A component with no pattern, and an undeclared new pattern, are both majors.
- **Code mode:** tag and conformance checks; run the ast-grep rules on the changed files.
- **Close:** the model matches the built code.

## 5. Experimental: work packages inside one plan

This revisits the "no parallelism inside a plan" decision (process-variants README) and ADR 0006 (**three earlier parallel designs**, including a DAG with write-sets and fences, were retired because coordination cost exceeded the speedup). It is **not adopted** by this plan; it is tested only after §4 works.

- **Hypothesis:** one approved plan and model, a small contract commit, then a few coarse packages built in parallel lanes, each with a code review, then one integration. This beats both one serial implementer and multiple child plans.
- **Why it might work now, when ADR 0006 failed:**
  - coarse packages instead of tasks;
  - strong models;
  - proven lane worktrees and claims;
  - T1 tiers;
  - measured per-step costs to size against.
- **First step:** list each ADR 0006 failure mode and how this design avoids it.
- **A contract is real code.** It is the producer's exported interface with its validators and a stub body, committed before fan-out. The consumer compiles against the actual generated types, not a prose description.
- **Packages are derived from the model** but aren't one per component (handoff §7). Package data stays outside the architecture model.
- **Gate:**
  - a paper simulation (`tools/process-sim.mjs`) with honest per-package overheads: savings counted only on the critical path, plus the cost of repeated T1 runs;
  - then one real pilot against a comparable single-implementer plan.

## 6. Validation

1. **Paper:** model an existing example plan (`plans/2026_10_20_process_variants/`) as one plan with a c4ish model. Can a reviewer approve it from the diagram? What did the model expose that the prose hid?
2. **Real pilot:** a project adopts a starter catalog and tags, then runs one feature through `run-plan` with a model. Measure:
   - human time to approve the plan;
   - tag coverage and conformance on the changed code;
   - new patterns proposed and whether they were justified;
   - review findings by kind;
   - end-to-end time against the pilot era-D medians.
3. **Packages** (§5): only after 1–2.
4. **Adoption ADR:** covers the frontier pipeline and this plan, retires the old skills, and records measured outcomes separately from intent.

## 7. Open questions

- **Q1. Package definition:** fields, whether packages can be revised while running, and partial-component ownership (handoff §10.A). Only needed for §5.
- **Q2. Model scope:** how much unchanged context a plan model includes; a rule of thumb is one hop from anything changed.
- **Q3. Tag syntax:** one generic form (`@pattern id`) for every language, or per-language idioms. Also whether a tag may carry a variation-specific parameter.
- **Q4. New-pattern approval:** reviewer only, or explicit human approval as with breaking schema changes.
- **Q5. Model at close:** reconcile fully, or only flag drift.
- **Q6. Epic promotion rules.**
- **Q7. Role-skill loading:** option (a) in §4.1 works with pi-subagents local skill paths. Verify before choosing.

## 8. Not in scope
- The c4ish tool itself. It is a separate product, and this plan uses it as it exists.
- Any project's catalog content.
- A central index of where patterns are used.
- Maintained architecture documentation.
