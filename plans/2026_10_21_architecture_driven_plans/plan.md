# Architecture-driven plans

**Status:** draft, revision 3 (2026-11-17), reviewed once, not approved · **First draft:** 2026-10-21 · **Branch:** `pilot/arch-plans` (from `pilot/process-retro` at `d424a19`) · **Input:** [`handoff.md`](handoff.md), the original design handoff, kept as history; this plan supersedes it · **Evidence:** `plans/2026_10_15_process_retro/`, `plans/2026_10_20_process_variants/README.md`, ADR 0006 · **Builds on:** the frontier pipeline (`docs/frontier-pipeline.md`), still a pilot · **Changes (proposed):** `skills/scope`, `plan`, `review`, `implement`, `orchestrate`, `assess-repo`; new `run-plan` and `run-epic`; a model-to-code check under `tools/`; skill frontmatter, agent definitions and where role skills are installed (`dist/`, the Nix modules); `docs/frontier-pipeline.md`; a new ADR

**Revision 3** answers the first fresh review, which found revision 2 not ready to build from. Where each major finding is answered: M1 §4.6 · M2 §4.10 · M3 §4.6 · M4 §4.3, §4.5 · M5 §4.5 · M6 §4.7 · M7 §4.8 · M8 §4.9 · M9 §4.9 · M10 §6 · M11 §4.4. It has not been reviewed again.

**Owner's decisions, 2026-11-17:**
- a plan is as large as the work needs (§4.9);
- the human approves new patterns (§4.5);
- epics stay rare, with one detailed model per plan (§4.9);
- the first pilot runs with no parallel work (§5);
- the plan is approved in the `scope` session, as today (§4.8);
- the tool resolves code references and reports what changed; this repo owns the tag rules on top (§4.10).

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
- review effort goes to deviations, one-off code and new patterns. A reviewer skips only what a rule has proved (§4.5);
- end-to-end time is no worse than the current pipeline on comparable work. Better is the stretch goal, not the gate.

## 2. Decisions so far

| Topic | Decision |
|---|---|
| Default unit of work | **One plan, as large as the work needs.** Work is never split to meet a size number. An epic is only for genuinely distinct plans or workstreams (§4.9). |
| Who does what | `scope` agrees the scope, has the plan and model written and reviewed, and gets the human's approval. A new **`run-plan`** builds one approved plan. A new **`run-epic`** (today's `orchestrate`, slimmed down) coordinates plans and calls `run-plan` for each (§4.2, §4.8). |
| Design artifact | Each plan has a **c4ish model** (JSON) of the elements it adds, changes, reuses or removes, plus the unchanged context one hop from them. The tool validates it and renders the diagrams and the tour. |
| One home per kind of content | The model says what is built and how the pieces connect. `plan.md` says why, and what proves it. The tour says in what order to look. Nothing is stated twice (§4.4). |
| Product and engineering | One plan model shows both views: what changes for the user (product concepts) and how it is built (containers, components, data). |
| Lifetime | The model and its diagrams belong to the plan and are **throwaway** after it. At close the model is brought in line with the code and becomes the review record in the PR. It is not maintained afterwards. |
| Pattern catalog | **Project-owned**, in the project's docs. It starts with a small key set and grows as plans touch new areas. |
| Pattern states | Every element that lives in code is **catalogued**, a **partial fit**, **proposed** (this plan adds the pattern to the catalog) or **bespoke** (a one-off with a stated reason) (§4.5). |
| New patterns | **The human approves** every change to the catalog, at the plan's approval gate (§4.5). |
| Finding pattern uses | **Comment tags in code** at the definition (§4.3). Search finds every use. Untagged code is "unknown". **No central index** of where patterns are used. |
| Conformance | A rule per pattern where the shape is checkable. A rule fails tagged code that doesn't match its pattern, and warns on untagged code of a known shape. |
| Model and code agree | Each element points at its definition in code. A mechanical check compares the two in both directions, and the approved model is compared with the shipped one (§4.6). |
| Deviations | Three classes: detail, model change judged by the reviewer, and re-approval by the human (§4.7). |
| Models in an epic | Epics are rare. **Each plan in an epic has its own detailed model.** The epic records only what crosses plans, with a small overview model only when useful (§4.9). |
| Framework scope | engineering-agents defines the process, the catalog's required fields and the tag convention. It ships no project vocabulary. |
| Skill visibility | Skills are loaded when the process needs them, not discovered by every model (§4.1). |

## 3. Shape of the process

```
prototype ─► scope ──────────────────────────────────────────────► run-plan ──────────────────────► PR
               │  agree scope ─► plan.md + model + tour             build (one implementer), code tagged
               │  ─► review ─► human approval (tour)                code review ─► gates ─► model-to-code check
               │                                                    approved versus shipped ─► as-built tour in the PR
               └─► epic (rare): epic.md ─► run-epic: per plan, a plan loop then run-plan (§4.9)
```

- **scope** decides one plan (default) or an epic. For one plan it runs the plan loop and the approval gate (§4.8).
- **plan** writes `plan.md` and the model against the catalog. Each element has a change state (new, modified, reused, removed) and, when it lives in code, a pattern state and a code reference. The model carries one review tour.
- **review (plan mode)** checks the model as well as the text (§4.11).
- **implement** tags each definition it creates or changes. It follows the pattern's reference implementation, and handles a departure from the model by its class (§4.7). Before handoff it brings the model in line with what it built.
- **review (code mode)** reads by pattern state (§4.5), judges the recorded deviations, and owns the model-to-code result and the approved-versus-shipped comparison (§4.6).
- **Close:** the comparison and the as-built tour go in the PR. They are the review record, not documentation.

## 4. Changes

### 4.1 Skill visibility and loading

Today every installed skill is visible to every model, including retired-process skills. Proposed tiers:

| Tier | Skills | Mechanism |
|---|---|---|
| Entry points | `prototype`, `scope`, `run-plan`, `run-epic` | `disable-model-invocation: true`; the human starts them with `/skill:name` |
| Role skills | `plan`, `implement`, `review`, and the body of `run-plan` | Loaded only by the agent definition that needs them |
| Utilities | `delegate`, `test-quality`, `backlog` | Visible to models |
| Retired process | `create-plan`, `execution-orchestrator`, `review-plan`, `execute-task`, … | Not installed (part of the adoption ADR) |

**Constraint, confirmed** in pi-subagents 0.77.0 (`buildSkillInjection` in `src/agents/skills.js`, and its changelog): skills marked `disable-model-invocation: true` are filtered out of subagent prompts, **even when an agent definition names them**. Two consequences:
- **Role skills can't simply be hidden.** Options: (a) keep them outside the global skills directory and resolve them through the agent definition's own skill path; (b) inline the role instructions into the agent definition; (c) leave them visible. Prefer (a): pi-subagents documents an agent's skill path as private to that agent.
- **`run-plan` is needed twice:** by the human for a single plan, and by `run-epic`'s child orchestrators. A hidden entry point never reaches a child. So its body is a role skill of the orchestrator agent, and the entry point is a thin wrapper that loads it.

One smoke run settles both (Q7).

### 4.2 `run-plan` and `run-epic`
- `run-plan` builds one approved plan. It is today's `orchestrate` without lanes, groups or checkpoints: build → code review loop → gates → model-to-code check → close. It stops for re-approval (§4.7). It has no plan loop and no parallel work; packages (§5) are not part of it yet.
- `run-epic`: units, integration, checkpoints and cross-plan contracts. For each plan it runs the plan loop, as `orchestrate` does today, and then `run-plan`, in-session or as a child orchestrator.
- `orchestrate` is retired or becomes a thin alias. Existing safety rules carry over unchanged: recovery, stop conditions, ledgers, test tiers and the no-rerun rules.

### 4.3 Catalog contract (framework side)
- **Required fields per entry:**
  - id (`<family>/<name>`), what it means, when to use it;
  - its reference implementation (a code reference, §4.6);
  - verification expectations;
  - its **check**: `rule` with the rule's path, or `judgment`;
  - for a rule, **what it proves** and what it leaves to the reader.
- **Location:** a project declares in its agent guide where its catalog lives, and which paths the model-to-code check leaves out (tests, docs, generated files). The framework doesn't fix a path.
- **Catalog profile:** the project keeps one c4ish profile beside the catalog, durable and separate from any plan. It is the machine-readable index of the catalog: one entry per pattern with its id, label, family, how it is drawn and a link to the pattern's section in the catalog docs. The Markdown docs hold the content. It lists patterns, not where they are used, so it is not a usage index. Plan models reference the profile.
- **Tag convention:** one comment directly above the definition, in the language's own comment syntax. When the definition is a whole file, the tag is the file's first comment. Forms:

  | Form | For |
  |---|---|
  | `@pattern <id>` | Follows the pattern. Several ids are separated by commas |
  | `@pattern <id> partial: <what differs>` | A partial fit. Rules skip it |
  | `@pattern bespoke: <what it is>` | A one-off |

  A missing tag means "unknown". Tags are added when code is created or changed for a plan, never as a mass retrofit. One page in `docs/`.
- `assess-repo` checks that a catalog and its profile exist with the same pattern ids, that the tool is installed, and that the rules run.

### 4.4 One home per kind of content

| Content | Home | Not repeated in |
|---|---|---|
| What is built in code: elements, change state, pattern, code references, relationships, who enforces each data relationship | Model | `plan.md` (its Changes section becomes a link to the model) |
| Changes with no place in the picture: migrations, configuration, dependency bumps, build and CI, docs, test infrastructure | `plan.md` → Changes outside the model | Model |
| Interfaces: arguments, results, access rule, limits, failure behaviour | Model contracts, as named clauses | `plan.md` |
| Risks and open questions about a specific element or connector | Model notes, attached to it | `plan.md` |
| Why: decisions, rejected alternatives, deviations from the prototype | `plan.md` → Design | Model notes, tour narration |
| Risks with no place in the picture (rollout, schedule, environment) | `plan.md` → Risks | Model |
| Scenarios, the tests list, gates, claims, budget, done-when, handoff | `plan.md` | Model. The model holds only each scenario's id and title, to tie it to a tour step |
| Order and emphasis for the reader | Tour narration: one to three sentences per step | It states nothing that isn't in the model or `plan.md` |

- **The plan questions** (access and visibility, failure and concurrency, limits and load) are answered where they are drawn: a contract clause, an enforcement level or a note. `plan.md` gives each a one-line pointer to the ids, or "n/a".
- **Claims** in `plan.md` list directories, routes and tables. The files come from the model's code references.
- **No separate notes file** beside the model.
- **`plan.md` keeps:** goal, context, design decisions, changes outside the model, scenarios, tests, gates, claims, done-when, risks, handoff, and a link to the model. It should come out shorter than today's.

### 4.5 Pattern states and how code is read

Every element that lives in code is in exactly one state. Containers, product concepts and removed elements have none.

| State | Meaning | In the model | Tag | Code review |
|---|---|---|---|---|
| Catalogued | Follows a catalog pattern | The pattern id | `@pattern <id>` | With a passing rule: the reviewer **skips what the rule proves** and reads the rest. Without a rule: a normal read against the reference implementation |
| Partial fit | Follows a pattern except where stated | The id, marked partial, with what differs | `@pattern <id> partial: …` | Full read of what differs; rules skip it |
| Proposed | No pattern fits and the shape will be reused. This plan adds it to the catalog | A proposed pattern | `@pattern <id>` | Full read. The entry, the rule and the reference implementation are part of the diff |
| Bespoke | No pattern fits and this is a one-off | Marked bespoke, with a one-line reason | `@pattern bespoke: …` | Full read |

- **What a rule buys.** A rule proves a shape, not the logic inside it. The reviewer still reads the logic, the contract and the tests. So the saving is bounded by what each catalog entry says its rule proves, and the pilot measures it.
- **A rule can't be loosened to earn a skip.** A diff that touches a catalog entry, a rule or a reference implementation, beyond what the approved plan proposes, is a re-approval deviation (§4.7).
- **A proposal** is a first-class part of the plan: the catalog entry, the profile entry, the reference implementation and its check. The tour points at each one. They are built in the plan's diff. Tags may use an id from the profile or from the model's proposed patterns.
- **Second use.** Before marking an element bespoke, the plan author searches for `@pattern bespoke` code doing the same job. If there is one, the plan proposes a pattern that covers both. The earlier code joins the model as a reused element and is retagged; a tag sits above the definition, so the definition itself is unchanged. Untagged older code is not found this way; that is accepted.
- **Who approves.** The human approves every change to the catalog: a proposed pattern, or a change to an existing one. They are already approving the plan from the tour, so this adds no stop to a single plan. Bespoke elements need no separate approval: the tour points at them, and the plan reviewer checks each reason.
- **During a build** a shape nobody planned is built as bespoke, recorded as a model change, and proposed in a follow-up. The implementer doesn't stop to propose a pattern.
- **Untagged changed code** is "unknown" and gets a full read.

### 4.6 Tying the model to the code

Validation shows that a model is well formed. It cannot show that the model is right or complete: a model with a wrong or missing element still validates. Three checks close that gap.

**Code references.** Each new, modified or removed element that lives in code names its definition:
- `path#Name`, or `path#Outer.Inner` for a member: a named definition in the file, such as a function, a class, a type, or one table in a schema file that holds several;
- `path` alone, when the whole file is the definition.

A reference is a name, not a line number, so it survives edits around it. The tool parses the file to find the definition and its extent (§4.10). A reference must resolve to exactly one definition. An element with parts gives each part its own reference. A reused element may carry one.

**1. Scenarios are walked (plan time).** The model lists the plan's acceptance scenarios by id and title, and each tour step names the scenarios it walks. A scenario with no step fails validation.

**2. Model-to-code (before code review, and again at close).** Between the base commit and the head:

| Element | Passes when |
|---|---|
| New | Its reference resolves at the head and not at the base, and its tag is above it |
| Modified | It resolves at both, lines inside it changed, and its tag is above it |
| Removed | It resolved at the base and does not resolve at the head |
| Reused, with a reference | It resolves at the head and no line inside it changed. A change means it is modified, which is a model change (§4.7) |

Then, over the whole diff:
- *built, not modelled:* an added or changed `@pattern` tag that isn't above a referenced definition fails;
- *unaccounted:* every changed hunk in production code outside the new and modified definitions is listed, whatever tags the file carries. The reviewer reads the list in full, and either accepts each hunk as glue or raises the missing element as a major.

Several elements in one file are told apart by their references. A moved or renamed definition fails until its reference is updated; that is a detail, not a deviation, unless a contract names it.

**3. Approved versus shipped.** The model at the approval commit (§4.8) is compared with the current one, by element id. Ids don't change after approval.

| Compared | Not compared |
|---|---|
| Elements: change state, pattern and fit, parts | Code references |
| Relationships: ends, kind, enforcement | Views, layout and tours |
| Contracts, clause by clause | Note and narration text |
| Data fields, indexes and ties | A proposed pattern becoming a catalogued one |
| Scenarios and proposed patterns | |

Every difference must match a deviation recorded in the ledger (§4.7).

**Who runs what.** The plan author fills in the references it can foresee. The implementer makes them exact before handoff, runs checks 2 and 3, and records the commands and results in the ledger as it does for the fast gates. The code reviewer treats those as claims and owns the verdict on both: an unrecorded difference is a major, and a re-approval difference is a stop. `run-plan` reruns both on the final commit; a new difference goes back to review.

### 4.7 Deviations during the build

`implement` says today: a wrong detail is fixed and noted; a wrong plan in substance is a stop. With a model, "substance" can be defined. A deviation is a difference from the approved model in what check 3 compares.

| Class | What changed | What happens |
|---|---|---|
| **Detail** | Nothing that is compared: an element's internals, private names, file layout, code references, tests | Build it and note it in the ledger. Update the references |
| **Re-approval** | Any of the list below | Stop |
| **Model change** | Every other difference | The implementer updates the model in the same commit as the code and records the deviation with its reason. The code reviewer judges each one, and may raise any of them to re-approval. The human sees them in approved versus shipped |

**Re-approval** is needed for:
- a data element, a container or a product element added or removed;
- enforcement on a data relationship moved down this order: `platform`, `platform-correlated`, `our-code`, `nothing`. Also a new data relationship enforced by `our-code` or `nothing`. (`derived` is outside the order; a change to or from it is a model change.);
- a contract removed, a clause removed, or an access clause changed;
- a change to the catalog: an entry, a rule, a reference implementation or the profile, beyond what the plan proposes;
- a scenario that can't be delivered as approved.

**Model changes** include: a component added, split, merged or dropped; a change state that flips (planned as reused, built as modified); a new bespoke or partial-fit element; one catalogued pattern swapped for another; a relationship added, removed or rerouted without lowering enforcement; data fields, indexes or ties changed; a clause added, or a clause other than access changed; an exported name in a contract.

The re-approval list is mechanical: check 3 can sort differences into it without judgment. Loosening that it can't see, such as a limit raised in a clause's text, is caught by the reviewer raising a model change.

**The stop.** The implementer commits its work and the changed model, and stops. `run-plan` gives the human a tour of only what differs from the approved model. On approval, that commit becomes the approved model and the same implementer continues. On rejection, the implementer builds what was approved; if it can't, the plan goes back to its author. The same path applies when code review finds a re-approval difference after the build.

### 4.8 The approval gate

The gate is in `scope`, where the human already is. `run-plan` builds without them.

When the plan review is clean, `scope` gives the human:
- the command that opens the tour in the viewer, and the path of the static tour pages;
- the link to `plan.md`;
- a short list: the scenarios, the proposed patterns, the bespoke elements with their reasons, and any open question notes.

The human approves, approves with changes, or rejects. Changes go back to the same plan-author and through one more review. Approval is the commit that adds an `Approved:` line to `plan.md`; the approved model is the model at that commit.

In an epic the plans are written during the run, so their gate differs (§4.9).

### 4.9 Size, and epics

**Size.** A plan is as large as the work needs. It is never split to meet a size number: each extra plan adds a fixed cost (§1), and it cuts one design into pieces the human has to hold together. `scope` chooses an epic only when the work holds genuinely distinct plans or workstreams, meaning parts with their own goal that could each be approved and shipped alone.

The review-load signal (about 7k changed lines) stops being a limit and stays as an estimate recorded in `plan.md`. It appears in five places that change: `scope` (choosing the shape, and the signal itself), `plan` → Sizing, `review` (plan mode and epic mode), `orchestrate` → Sizing, and `docs/frontier-pipeline.md`.

What a large plan costs, and the answer to each:
- *Approval.* The human reads the tour, which grows with the number of changed elements, not with lines of code.
- *Code review.* One very large diff is more than a reviewer can judge in one pass. Above the signal it is reviewed in groups:
  - the changed files are divided by container. A file whose definitions belong to one container goes to that group. Files shared between containers, unaccounted hunks, tests and docs form a last group;
  - one fresh reviewer per group, one after another in the same worktree, each adding its own section to the ledger;
  - a last reviewer reads the joins: the contracts between groups, the deviations, and the results of checks 2 and 3. It gives the single verdict. The pass rules of `review` apply to that verdict.
- *Build.* One implementer builds serially, so build time grows with size. That is accepted: in the pilot the fixed cost per plan outweighed build time (§1). Packages (§5) are the answer if serial build becomes the bottleneck.
- *Context.* A large model is more for the plan author, the plan reviewer and the implementer to hold, across more compactions. Nothing here answers that.

None of this has been run. The pilot records build time, compactions, review passes and findings against plan size.

**Epics.** An epic is the rare case, and the process adds little to it:
- **Each plan in an epic has its own detailed model,** written and reviewed as a single plan's is.
- **Who approves each plan** follows `epic.md` → Autonomy, as today, with one exception: a plan that changes the catalog always stops for the human.
- **A proposed pattern is claimed in `epic.md`,** as files are, so that two plans written at the same time don't propose the same shape twice.
- **The epic records only what crosses plans.** `epic.md` names each cross-plan contract and the plan that owns it; the clauses are in that plan's model. A small overview model of how the plans connect is added only when it helps. It shows no plan's internals.
- **No detailed model for the whole epic.** It would force all design up front and repeat each plan's detail (handoff §4.C).

### 4.10 What the process needs from the tool

The tool is a separate product and knows nothing of this process: no tags, no deviation classes, no catalog rules. It exists and is installable: schema v0, `validate` (schema, references, notation lint, strict per-tour coverage), `render`, `tour`, `view`, an authoring reference (`guide`) and a version report. The process needs these additions, each proved by a check that fails on a broken fixture:

| Need | For |
|---|---|
| A code reference on an element or part (`path#Name`), and a way for a profile to say which kinds of element live in code | §4.6 |
| A report on a model's code references between a base commit and the working tree: whether each resolves, its extent, whether lines inside it changed, and the changed hunks outside every new and modified definition. The tool parses source to do this (tree-sitter), for the languages the adopter uses | §4.6 check 2 |
| Scenarios in the model, a tour step naming the scenarios it walks, and a failure when none walks one | §4.6 check 1 |
| A bespoke marker with a required reason, drawn distinctly and counted by tour coverage | §4.5 |
| A comparison of two versions of a model, by id, reported by kind of difference, and a tour of only what differs | §4.6 check 3, §4.7 |

This repo adds a small check under `tools/` on top of that report. It reads the tags, the project's left-out paths and the comparison, and applies the tables in §4.6 and §4.7. The tool's model has a `sources` field today that holds file paths; code references replace it.

The pilot waits for these.

### 4.11 Review
- **Plan mode.** As well as today's checks:
  - the model validates with no errors or warnings, and the tour covers every review item;
  - every element that lives in code has a pattern state and, unless reused, a code reference. A missing one is a major. A bespoke reason that an existing pattern or existing bespoke code answers is a major;
  - every scenario is walked by a tour step that actually shows it;
  - contracts can be implemented, and the plan questions are answered where they are drawn;
  - context is one hop from what changes;
  - nothing is stated in two homes (§4.4). A repeat is a minor; a contradiction is a major.
- **Code mode.** Read by pattern state (§4.5). Run the rules on the changed files. Judge checks 2 and 3 and read the unaccounted hunks (§4.6). Judge each recorded deviation; one in too low a class is a major, and a re-approval difference is a stop (§4.7). A diff above the review-load signal is read in groups (§4.9).

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
   - a model can validate and still be wrong or incomplete, and several elements often share one file (§4.6);
   - only two or three of about seventeen starter patterns have a shape a rule can check (§4.5).

   Not yet tested: a model written before the code, a model written by an agent, and a human approving from a tour.
2. **Real pilot.** A project adopts a starter catalog, tags and first rules, then runs one feature through `scope` and `run-plan`, with the model written before the code, one implementer and no parallel work. Record:
   - **approval:** the human's time to approve from the tour, against their time on a text plan of similar size taken first; and what the tour failed to show. Gaps in the diagrams are fixed by iterating on the tool and the authoring rules;
   - **whether the approval was right:** afterwards, each code-review and later finding is marked as a design issue the tour showed, one it didn't show, or not a design issue;
   - **whether the checks can be trusted:** one audit by hand of the model against the code, counting what checks 2 and 3 passed wrongly and failed wrongly;
   - **cost:** the time and tokens spent writing the model, keeping it in line, and tagging;
   - **review:** deviations by class, the lines a rule let the reviewer skip, the unaccounted hunks, findings by kind, and defects found later in skipped code;
   - **patterns:** those proposed and the elements marked bespoke, and whether each held up in review;
   - **time:** end to end, per 1k changed lines. The pilot era-D medians are per child of at most about 7k lines, so they are a rough guide and not a like-for-like baseline.

   One run can't prove the process. The owner decides to adopt, revise or drop on three questions: was approval faster and right; did the checks catch real mismatches without false alarms; and did the model and tags cost less than they saved in review.
3. **Packages** (§5): the next step after 1–2.
4. **Adoption ADR:** covers the frontier pipeline and this plan, retires the old skills, and records measured outcomes separately from intent.

## 7. Open questions

**For the owner:** none open.

**Still open:**
- **Q1. Package definition:** fields, whether packages can be revised while running, and partial-component ownership (handoff §10.A). Only needed for §5.
- **Q7. Role-skill loading:** one smoke run of option (a) and of the `run-plan` wrapper (§4.1). Also whether an orchestrator started with `/skill:` keeps the skill text after it compacts; if not, its compaction note re-reads the file by path.
- **Q10. Reviewing a large diff:** whether groups, each read by its own fresh reviewer, catch what one reviewer over the whole diff would (§4.9). The pilot answers it.
- **Q11. Code references:** which definitions the tool can resolve in the first adopter's languages, and how much falls back to a whole-file reference (§4.6).

**Settled in revision 2:** Q2 model scope (one hop, §2). Q3 tag syntax (§4.3). Q5 model at close (reconcile fully, mechanically, §4.6). Q9 bespoke tags (`@pattern bespoke: <what it is>`, §4.3).

**Decided by the owner, 2026-11-17:** Q4 the human approves new patterns (§4.5). Q6 no size limit on a plan; an epic only for distinct workstreams (§4.9). Q8 epics stay rare: a detailed model per plan, and only cross-plan contracts at the epic level (§4.9). The first pilot has no parallel work (§5). The approval gate is in `scope` (§4.8). The tool resolves code references; this repo owns the tag rules (§4.10).

## 8. Not in scope
- Building the diagram tool. It is a separate product; §4.10 lists what this process needs from it.
- Any project's catalog content.
- A central index of where patterns are used.
- Maintained architecture documentation.
- An entry to `scope` from a brief with no prototype.
