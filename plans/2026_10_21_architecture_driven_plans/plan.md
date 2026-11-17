# Architecture-driven plans

**Status:** draft, revision 2 (2026-11-17), not reviewed or approved · **First draft:** 2026-10-21 · **Branch:** `pilot/arch-plans` (from `pilot/process-retro` at `d424a19`) · **Input:** [`handoff.md`](handoff.md), the original design handoff, kept as history; this plan supersedes it · **Evidence:** `plans/2026_10_15_process_retro/`, `plans/2026_10_20_process_variants/README.md`, ADR 0006 · **Builds on:** the frontier pipeline (`docs/frontier-pipeline.md`), still a pilot · **Changes (proposed):** `skills/scope`, `plan`, `review`, `implement`, `orchestrate`; new `run-plan`; skill frontmatter and agent definitions; `docs/frontier-pipeline.md`; a new ADR

**Revision 2** brings the draft up to date with the diagram tool as built, and adds what the first draft left open: one home per kind of content (§4.4), three pattern states (§4.5), a check that ties the model to the code (§4.6), deviation rules (§4.7), the approval gate (§4.8), plan size (§4.9) and what the process needs from the tool (§4.10). The owner's decisions of 2026-11-17 are in: a plan is as large as the work needs (§4.9), the human approves new patterns (§4.5), epics stay rare with one detailed model per plan (§4.9), and the first pilot runs with no parallel work (§5).

## 1. Why

Two problems, in priority order:

1. **A human can no longer follow the work at a reasonable cost.**
   - Plans are freeform since we dropped the old long template. They are shorter, but it isn't clear from them what will happen.
   - After an autonomous run, the implementation is close to impossible to understand at a high level without a lot of reading.
   - Nothing holds the codebase to a fixed set of patterns. Each problem is solved on its own, so review means reading every line.
2. **The fixed cost of each plan still dominates.** In the pilot, the overhead per child (refresh, review loops, integration) outweighed build time. Splitting a feature into children multiplied that cost.

The answer to the first is a plan whose design is a **structured architecture model**, shown to the human as a diagram and a guided tour. It is built from a **project-owned catalog of patterns**, so the code converges on a known set instead of drifting. This plan addresses the first problem. The second is addressed by not splitting work into more plans than it needs (§4.9). Parallel work inside one plan stays experimental (§5).

**Success:**
- the human understands and approves a plan from its tour and a short `plan.md`, in minutes;
- delivered code declares which pattern it implements, the model is checked against that code, and the human sees what shipped against what they approved;
- review effort goes to deviations, one-off code and new patterns. Code gets a light read only where a rule checks its pattern (§4.5);
- end-to-end time is no worse than the current pipeline on comparable work. Better is the stretch goal, not the gate.

## 2. Decisions so far

| Topic | Decision |
|---|---|
| Default unit of work | **One plan, as large as the work needs.** Work is never split to meet a size number. An epic is only for genuinely distinct plans or workstreams (§4.9). |
| Default runner | A single plan runs with a dedicated **`run-plan`** skill, not with `orchestrate`. A new **`run-epic`** skill (today's `orchestrate`, slimmed down) coordinates plans by calling `run-plan` for each. |
| Design artifact | Each plan has a **c4ish model** (JSON) of the elements it adds, changes, reuses or removes, plus the unchanged context one hop from them. The tool validates it and renders the diagrams and the tour. |
| One home per kind of content | The model says what is built and how the pieces connect. `plan.md` says why, and what proves it. The tour says in what order to look. Nothing is stated twice (§4.4). |
| Product and engineering | One plan model shows both views: what changes for the user (product concepts) and how it is built (containers, components, data). |
| Lifetime | The model and its diagrams belong to the plan and are **throwaway** after it. At close the model is brought in line with the code and becomes the review record in the PR. It is not maintained afterwards. |
| Pattern catalog | **Project-owned**, in the project's docs. It starts with a small key set and grows as plans touch new areas. |
| Pattern states | An element is **catalogued**, **proposed** (this plan adds the pattern to the catalog) or **bespoke** (a one-off with a stated reason). A second use of a bespoke shape becomes a proposal (§4.5). |
| New patterns | **The human approves** every change to the catalog, at the plan's approval gate (§4.5). |
| Models in an epic | Epics are rare. **Each plan in an epic has its own detailed model.** The epic records only what crosses plans, with a small overview model only when useful (§4.9). |
| Finding pattern uses | **Comment tags in code** at the definition: `@pattern <id>`, or `@pattern bespoke`. Search finds every use. Untagged code is "unknown". **No central index** of where patterns are used. |
| Conformance | A rule per pattern where the shape is checkable. A rule fails tagged code that doesn't match its pattern, and warns on untagged code of a known shape. A light read is earned only by a passing rule. |
| Model and code agree | A mechanical check at close, in both directions, plus a comparison of the approved model with the shipped one (§4.6). |
| Deviations | Three classes: detail, model change judged by the reviewer, and re-approval by the human (§4.7). |
| Framework scope | engineering-agents defines the process, the catalog's required fields and the tag convention. It ships no project vocabulary. |
| Skill visibility | Skills are loaded when the process needs them, not discovered by every model (§4.1). |

## 3. Shape of the process

```
intent (prototype or brief) ─► scope ─► run-plan ─────────────────────────────────► PR
                                  │       plan.md + model + tour ─► review ─► human approval (tour)
                                  │       build (one implementer, or packages: §5), code tagged
                                  │       code review ─► gates ─► model-to-code check
                                  │       approved versus shipped ─► as-built tour in the PR
                                  └─► run-epic (rare): run-plan per plan, plus cross-plan contracts (§4.9)
```

- **scope** decides one plan (default) or an epic.
- **plan** writes `plan.md` and the model against the catalog. Each element has a change state (new, modified, reused, removed) and a pattern state. The model carries one review tour.
- **review (plan mode)** checks the model as well as the text (§4.11).
- **Human approval** is on the tour plus `plan.md` (§4.8).
- **implement** tags each definition it creates or changes. It follows the pattern's reference implementation, and handles a departure from the model by its class (§4.7). Before handoff it brings the model in line with what it built.
- **review (code mode)** reads by pattern state (§4.5), judges the recorded deviations, and checks the model-to-code result.
- **Close:** the approved model is compared with the shipped one. That comparison and the as-built tour go in the PR. They are the review record, not documentation.

## 4. Changes

### 4.1 Skill visibility and loading

Today every installed skill is visible to every model, including retired-process skills. Proposed tiers:

| Tier | Skills | Mechanism |
|---|---|---|
| Entry points | `prototype`, `scope`, `run-plan`, `run-epic` | `disable-model-invocation: true`; the human starts them with `/skill:name` |
| Role skills | `plan`, `implement`, `review` | Loaded only by the agent definition that needs them |
| Utilities | `delegate`, `test-quality`, `backlog` | Visible to models |
| Retired process | `create-plan`, `execution-orchestrator`, `review-plan`, `execute-task`, … | Not installed (part of the adoption ADR) |

**Constraint, confirmed** in pi-subagents 0.77.0 (`buildSkillInjection`, and its changelog): skills marked `disable-model-invocation: true` are filtered out of subagent prompts, **even when an agent definition names them**. So role skills can't simply be hidden. Options:
- (a) keep role skills outside the global skills directory and resolve them through the agent definition's local skill paths;
- (b) inline the role instructions into the agent definition;
- (c) leave role skills visible.

Prefer (a). Check that resolution works before relying on it (Q7).

### 4.2 `run-plan` and `run-epic`
- `run-plan`: the single-plan loop, which is today's `orchestrate` without lanes, groups or checkpoints:
  - plan loop → human approval (§4.8) → build → code review loop → gates → model-to-code check → close;
  - plus the package fan-out of §5, when the plan has packages.
- `run-epic`: units, integration, checkpoints and cross-plan contracts. Each plan runs through `run-plan`, either in-session or as a child orchestrator.
- `orchestrate` is retired or becomes a thin alias. Existing safety rules carry over unchanged: recovery, stop conditions, ledgers, test tiers and the no-rerun rules.

### 4.3 Catalog contract (framework side)
- **Required fields per entry:** id (`<family>/<name>`), what it means, when to use it, its reference implementation (file path), verification expectations, and its **check**: `rule` with the rule's path, or `judgment`.
- **Location:** a project declares where its catalog lives in its agent guide. The framework doesn't fix a path.
- **Catalog profile:** the project keeps one c4ish profile beside the catalog, durable and separate from any plan. It is the machine-readable index of the catalog: one entry per pattern with its id, label, family, how it is drawn and a link to the pattern's section in the catalog docs. The Markdown docs hold the content. It lists patterns, not where they are used, so it is not a usage index. Plan models reference the profile.
- **Tag convention:** one comment directly above the definition, in the language's own comment syntax: `@pattern <id>`. One tag per definition. A bespoke definition is tagged `@pattern bespoke`, followed by a few words saying what it is. A missing tag means "unknown". Tags are added when code is created or changed for a plan, never as a mass retrofit. One page in `docs/`.
- `assess-repo` checks that a catalog and its profile exist, that the tool is installed, and that the rules run.

### 4.4 One home per kind of content

| Content | Home | Not repeated in |
|---|---|---|
| What is built: elements, change state, pattern, relationships, who enforces each data relationship | Model | `plan.md` (its Changes section becomes a link to the model) |
| Interfaces: arguments, results, access rule, limits, failure behaviour | Model contracts, as named clauses | `plan.md` |
| Risks and open questions about a specific element or connector | Model notes, attached to it | `plan.md` |
| Why: decisions, rejected alternatives, deviations from the prototype | `plan.md` → Design | Model notes, tour narration |
| Risks with no place in the picture (rollout, schedule, environment) | `plan.md` → Risks | Model |
| Scenarios, the tests list, gates, claims, budget, done-when, handoff | `plan.md` | Model. The model holds only each scenario's id and title, to tie it to a tour step |
| Order and emphasis for the reader | Tour narration: one to three sentences per step | It states nothing that isn't in the model or `plan.md` |

- **The plan questions** (access and visibility, failure and concurrency, limits and load) are answered where they are drawn: a contract clause, an enforcement level or a note. `plan.md` gives each a one-line pointer to the ids, or "n/a".
- **No separate notes file** beside the model.
- **`plan.md` keeps:** goal, context, design decisions, scenarios, tests, gates, claims, done-when, risks, handoff, and a link to the model. It should come out shorter than today's.

### 4.5 Pattern states and how code is read

| State | Meaning | In the model | Tag | Code review |
|---|---|---|---|---|
| Catalogued, with a rule | Follows a catalog pattern whose shape a rule checks | The pattern id | `@pattern <id>` | **Light read** once the rule passes: the tag, the contract, the tests |
| Catalogued, by judgment | Follows a catalog pattern that has no rule | The pattern id | `@pattern <id>` | Normal read, against the reference implementation |
| Partial fit | Follows a pattern except where stated | The id, marked partial, with what differs | `@pattern <id>` | Full read of what differs |
| Proposed | No pattern fits and the shape will be reused. This plan adds it to the catalog | A proposed pattern | `@pattern <id>` | Full read. The entry and reference implementation are part of the diff |
| Bespoke | No pattern fits and this is a one-off | Marked bespoke, with a one-line reason | `@pattern bespoke` | Full read |
| None | Something that has no pattern by nature, such as a container or a removed element | Explicitly none | — | — |

- **A proposal** is a first-class part of the plan: the catalog entry, the profile entry, the reference implementation and its check. The tour points at each one.
- **Second use.** Before marking an element bespoke, the plan author searches for `@pattern bespoke` code doing the same job. If there is one, the plan proposes a pattern that covers both instead.
- **Who approves.** The human approves every change to the catalog: a proposed pattern, or a change to an existing one. They are already approving the plan from the tour, so this adds no stop. Bespoke elements need no separate approval: the tour points at them, and the plan reviewer checks each reason. During a build nothing is added to the catalog; a shape that turns up there is built as bespoke and proposed in a follow-up.
- **Untagged changed code** is "unknown" and gets a full read.

### 4.6 Tying the model to the code

Validation shows that a model is well formed. It cannot show that the model is right or complete: a model with a wrong or missing element still validates. Three checks close that gap.

1. **Scenarios are walked (plan time).** The model lists the plan's acceptance scenarios by id and title. Each is walked by at least one tour step. A scenario with no step fails validation.
2. **Model-to-code (before code review, and again at close).** Each new, modified or removed component and data element names the files that hold it. Against the diff from the base commit:
   - *modelled, not built:* a new or modified element whose files the diff doesn't touch, or a removed element whose tagged definition is still there, fails;
   - *wrong tag:* an element's definition that doesn't carry its pattern's tag fails;
   - *built, not modelled:* a `@pattern` tag on a line the diff added or changed, in a file no element names, fails;
   - *unaccounted:* changed production files that no element names and that carry no tag are listed. The reviewer reads them in full, and either accepts them as glue or raises the missing element as a major. Tests, docs and generated files are excluded by the project's globs.
3. **Approved versus shipped (close).** The model at the approval commit is compared with the final one: elements, relationships, contracts and patterns that were added, removed or changed. Every line of that comparison must match a deviation recorded in the ledger (§4.7).

The plan author fills in the files it can foresee. The implementer makes them exact before handoff, runs the model-to-code check, and records the command and result in the ledger as it does for the fast gates. The reviewer treats that as a claim.

### 4.7 Deviations during the build

`implement` says today: a wrong detail is fixed and noted; a wrong plan in substance is a stop. With a model, "substance" can be defined:

| Class | What changed | What happens |
|---|---|---|
| **Detail** | Nothing the model shows: an element's internals, names, file layout, tests | Build it and note it in the ledger. No model change |
| **Model change** | An element added, split, merged or dropped that follows a catalogued pattern or is context; an element that becomes bespoke or a partial fit; one catalogued pattern swapped for another; a relationship added or rerouted with the same or stronger enforcement; a contract clause tightened | The implementer updates the model in the same commit as the code and records the deviation with its reason. The code reviewer judges each one. The human sees them in approved versus shipped |
| **Re-approval** | Enforcement weakened on a data relationship; a contract's access rule loosened, or its shape changed for a consumer outside the plan; a data element or container added or removed; any change to the catalog; a scenario that can't be delivered as approved | Stop. The human re-approves from the updated tour, which shows only what changed |

An unrecorded difference between the approved and the shipped model is a major in code review.

### 4.8 The approval gate

When the plan review is clean, `run-plan` stops and gives the human:
- the command that opens the tour in the viewer, and the path of the static tour pages;
- the link to `plan.md`;
- a short list: the scenarios, the proposed patterns, the bespoke elements with their reasons, and any open question notes.

The human approves, approves with changes, or rejects. Changes go back to the same plan-author and through one more review. On approval `run-plan` records the model's commit as the approved model, which close compares against.

### 4.9 Size, and epics

**Size.** A plan is as large as the work needs. It is never split to meet a size number: each extra plan adds a fixed cost (§1), and it cuts one design into pieces the human has to hold together. `scope` chooses an epic only when the work holds genuinely distinct plans or workstreams, meaning parts with their own goal that could each be approved and shipped alone.

This changes three places. `scope` today chooses a single plan only when the work fits the review-load signal (about 7k changed lines), and `plan` → Sizing and `docs/frontier-pipeline.md` repeat that. The signal stops being a limit. It stays as an estimate recorded in `plan.md`.

What a large plan costs, and the answer to each:
- *Approval.* The human reads the tour, which grows with the number of changed elements, not with lines of code.
- *Code review.* One very large diff is more than a reviewer can judge in one pass. The model divides it: above the signal, the diff is reviewed one group of elements at a time (a view or a container), each group by a fresh reviewer given the model and its group. The contracts and the model-to-code check (§4.6) cover the joins between groups. Light reads (§4.5) shrink what needs a full read.
- *Build.* One implementer builds serially, so build time grows with size. That is accepted: in the pilot the fixed cost per plan outweighed build time (§1). Packages (§5) are the answer if serial build becomes the bottleneck.

The pilot records build time, review passes and findings against plan size, to show where these answers stop working.

**Epics.** An epic is the rare case, and the process adds little to it:
- **Each plan in an epic has its own detailed model,** written, reviewed and approved as a single plan's is. Who approves each plan follows `epic.md` → Autonomy, as today.
- **The epic records only what crosses plans:** boundaries, contracts and dependencies, in `epic.md`. A small overview model of how the plans connect is added only when it helps. It shows no plan's internals.
- **No detailed model for the whole epic.** It would force all design up front and repeat each plan's detail (handoff §4.C).

### 4.10 What the process needs from the tool

The tool is a separate product and knows nothing of this process. It exists and is installable: schema v0, `validate` (schema, references, notation lint, strict per-tour coverage), `render`, `tour`, `view`, an authoring reference (`guide`) and a version report. The process needs four more things from it, each as a check that fails on a broken fixture:

| Need | For |
|---|---|
| A bespoke marker with a required reason, drawn distinctly and counted by tour coverage | §4.5 |
| Scenarios in the model, and a failure when no tour step walks one | §4.6 check 1 |
| A model-to-code check, given the model and a base commit | §4.6 check 2 |
| A comparison of two versions of a model | §4.6 check 3, §4.8 re-approval |

Until they exist, the reviewer does these by hand, which is acceptable for one pilot and not beyond it.

### 4.11 Review
- **Plan mode.** As well as today's checks:
  - the model validates with no errors or warnings, and the tour covers every review item;
  - every component and data element has a pattern state. One with none is a major. A bespoke reason that an existing pattern or existing bespoke code answers is a major;
  - every scenario is walked by a tour step that actually shows it;
  - contracts can be implemented, and the plan questions are answered where they are drawn;
  - context is one hop from what changes;
  - nothing is stated in two homes (§4.4). A repeat is a minor; a contradiction is a major.
- **Code mode.** Read by pattern state (§4.5). A diff above the review-load signal is read one model group at a time (§4.9). Run the rules on the changed files. Check the model-to-code result and read the unaccounted files. Judge each recorded deviation; one in the wrong class is a major.
- **Close.** Approved versus shipped matches the recorded deviations.

## 5. Experimental: work packages inside one plan

This revisits the "no parallelism inside a plan" decision (process-variants README) and ADR 0006 (**three earlier parallel designs**, including a DAG with write-sets and fences, were retired because coordination cost exceeded the speedup). It is **not adopted** by this plan. The first pilot runs with one implementer and no parallel work; packages are the next step after it, once §4 works.

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

1. **Paper (done, in an adopting project).** Two changes that were already built were modelled by hand and given tours. What that showed, and where it went:
   - one model needed four patterns the catalog didn't have, so new shapes are routine, not exceptional (§4.5);
   - contracts needed named clauses, and elements needed grouped parts and partial fits. The tool's schema now has these;
   - a model can validate and still be wrong or incomplete (§4.6);
   - only two or three of about seventeen starter patterns have a shape a rule can check (§4.5).

   Not yet tested: a model written before the code, and a model written by an agent.
2. **Real pilot.** A project adopts a starter catalog, tags and first rules, then runs one feature through `run-plan`, with the model written before the code, one implementer and no parallel work. Record a baseline first: the human's time to approve a comparable text plan. Measure:
   - human time to approve from the tour, and what the tour failed to show. Gaps in the diagrams are fixed by iterating on the tool and the authoring rules;
   - deviations by class, and the result of each model-to-code check;
   - the share of changed lines under a passing rule, and the unaccounted files;
   - patterns proposed and elements marked bespoke, and whether each held up in review;
   - review findings by kind;
   - build time and review passes against the plan's size (§4.9);
   - end-to-end time against the pilot era-D medians.
3. **Packages** (§5): the next step after 1–2.
4. **Adoption ADR:** covers the frontier pipeline and this plan, retires the old skills, and records measured outcomes separately from intent.

## 7. Open questions

**For the owner:** none open.

**Still open:**
- **Q1. Package definition:** fields, whether packages can be revised while running, and partial-component ownership (handoff §10.A). Only needed for §5.
- **Q7. Role-skill loading:** whether option (a) in §4.1 works with pi-subagents local skill paths. Verify before choosing.
- **Q9. Bespoke tags:** whether "a few words" after `@pattern bespoke` is enough for a plan author to find a second use, or a short name is needed.
- **Q10. Reviewing a large diff:** whether groups from the model, each read by its own fresh reviewer, catch what one reviewer over the whole diff would (§4.9). The pilot answers it.

**Settled in this revision:** Q2 model scope (one hop, §2). Q3 tag syntax (one generic form, §4.3). Q5 model at close (reconcile fully, mechanically, §4.6).

**Decided by the owner, 2026-11-17:** Q4 the human approves new patterns (§4.5). Q6 no size limit on a plan; an epic only for distinct workstreams (§4.9). Q8 epics stay rare: a detailed model per plan, and only cross-plan contracts at the epic level (§4.9). The first pilot has no parallel work; packages come after it (§5).

## 8. Not in scope
- Building the diagram tool. It is a separate product; §4.10 lists what this process needs from it.
- Any project's catalog content.
- A central index of where patterns are used.
- Maintained architecture documentation.
