# Architecture-driven plans

**Status:** draft, revision 4 (2026-11-17), reviewed twice, not approved · **First draft:** 2026-10-21 · **Branch:** `pilot/arch-plans` (from `pilot/process-retro` at `d424a19`) · **Input:** [`handoff.md`](handoff.md), the original design handoff, kept as history; this plan supersedes it · **Evidence:** `plans/2026_10_15_process_retro/`, `plans/2026_10_20_process_variants/README.md`, ADR 0006 · **Builds on:** the frontier pipeline (`docs/frontier-pipeline.md`), still a pilot · **Changes (proposed):** `skills/scope`, `plan`, `review`, `implement`, `orchestrate`, `assess-repo`; new `run-plan` and `run-epic`; a model-to-code check under `tools/`; skill frontmatter, agent definitions and where role skills are installed (`dist/`, the Nix modules); `docs/frontier-pipeline.md`; a new ADR

**Revision 3** answers the first fresh review, which found revision 2 not ready to build from. Where each major finding is answered: M1 §4.6 · M2 §4.10 · M3 §4.6 · M4 §4.3, §4.5 · M5 §4.5 · M6 §4.7 · M7 §4.8 · M8 §4.9 · M9 §4.9 · M10 §6 · M11 §4.4. 

**Revision 4** answers the second review where the answer is a rule: the tag must agree with the model (§4.6), one tag grammar (§4.3), every model field in one deviation class (§4.6, §4.7), approvals recorded (§4.8), and what is mechanical (§4.7). The exact method of the model-to-code check is not settled on paper any more. It is settled by building the tool feature against failing cases (§4.6, Q11). Epic children, large-diff groups and the pilot's measures wait for the pilot (§7). It has not been reviewed again.

**Since revision 4:** two tool features and the check under `tools/` were built, and the sections that depend on them now record what exists. This text has not been reviewed.
- *2026-11-17, code references,* built against a failing case for each item §4.6 listed, and released. §4.6 check 2 records the method that works.
- *2026-11-18, comparing two versions of a model,* released. §4.6 check 3 and the stop in §4.7 say how they use it.
- *2026-11-18, the check,* `tools/model-check.mjs`. §4.10 records what building it settled.
- *2026-11-20, the skills.* The process is now carried by the skills, which win where they differ from this text: `scope`, `plan`, `implement` and `review` rewritten; `run-plan` and `run-epic` in place of `orchestrate`; a shared `architecture-model` skill that holds the rules of §4.4–§4.8 and ships the check; `map-patterns`, which writes a project's catalog from its existing code; and the catalog contract of §4.3 as `docs/references/pattern-catalog.md`. The role skills stay visible (§4.1). The older sequential pipeline is retired for Pi and kept for the other harnesses (ADR 0007), so a Pi session sees one skill for each job. One gap found while writing `run-epic`: check 2 counts code from the approval commit, so in an epic other children's integrated work shows as unaccounted (§7 Q12).

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
               │  ─► review ─► human approval (tour)                model-to-code check ─► code review ─► gates
               │                                                    both checks again ─► as-built tour in the PR
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
- `run-plan` builds one approved plan. It is today's `orchestrate` without lanes, groups or checkpoints: build → model-to-code check → code review loop → gates → both checks again, run by a helper → close. It stops for re-approval (§4.7). It has no plan loop and no parallel work; packages (§5) are not part of it yet.
- `run-epic`: units, integration, checkpoints and cross-plan contracts. For each plan it runs the plan loop, as `orchestrate` does today, and then `run-plan`, in-session or as a child orchestrator.
- `orchestrate` is retired or becomes a thin alias. Existing safety rules carry over unchanged: recovery, stop conditions, ledgers, test tiers and the no-rerun rules.

### 4.3 Catalog contract (framework side)
- **Required fields per entry:**
  - id (`<family>/<name>`), what it is, the shared code it goes through, what it protects against;
  - its shape: a diagram, a short code block with the line for each requirement marked, and a wrong example;
  - its reference implementation: one golden example (a code reference, §4.6). It is a full fit (owner): it meets every requirement and has every test the entry asks for. Code that falls short is fixed, or another example is chosen;
  - numbered requirements (`R1`, `R2`, …), each with what checks it: a test, the reviewer, or a rule with the rule's path. Conventions are listed apart: missing one is a review comment, not a partial fit;
  - the tests a new definition needs;
  - how it appears in a plan model: element kind, relationships, contract clause.
- **Choosing:** each catalog area opens with one table from what the code is to the pattern that fits. Entries do not repeat it.
- **An entry states the rule, not the state of the code (owner):** the golden example is its only pointer to code that uses the pattern. It names the shared code the pattern goes through and the test files a new definition adds to. It lists no partial fits, no divergences and no usage counts; those are findings for the backlog or a plan.
- **Location:** the framework doesn't fix a path. A project's agent guide points to one machine-readable file that lists where the catalog docs, the profile and the rules live, and which paths the model-to-code check leaves out (tests, docs, generated files).
- **Catalog profile:** the project keeps one c4ish profile beside the catalog, durable and separate from any plan. It is the machine-readable index of the catalog: one entry per pattern with its id, label, family, how it is drawn, its reference implementation and a link to the pattern's section in the catalog docs. The Markdown docs hold the content. It lists patterns, not where they are used, so it is not a usage index. Plan models reference the profile.
- **Tag convention:** one comment directly above the definition, in the language's own comment syntax. When the definition is a whole file, the tag is the file's first comment. Forms:

  | Form | For |
  |---|---|
  | `@pattern <id>` | Follows the pattern |
  | `@pattern <id> partial: <what differs>` | A partial fit, naming the requirements it misses (`partial: R4`). That pattern's rule skips it |
  | `@pattern bespoke: <what it is>` | A one-off |
  | `; also <id>, <id>` added to any form | Further patterns the definition carries. Their rules still run |

  A proposed pattern's tag looks like a catalogued one; the check looks the id up in the profile and in the model's proposed patterns. A file type with no comment syntax carries no tag. A missing tag means "unknown". Tags are added when code is created or changed for a plan, never as a mass retrofit. One page in `docs/`.
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
- **A rule can't be loosened to earn a skip.** A diff that touches a catalog, rule or profile file that the approved `plan.md` doesn't list is a re-approval deviation (§4.7). A reference implementation is ordinary code: changing one is a model change, and the reviewer checks it still shows the pattern.
- **A proposal** is a first-class part of the plan: the catalog entry, the profile entry, the reference implementation and its check. The tour points at each one. They are built in the plan's diff, and `plan.md` → Changes outside the model lists the catalog files. When the profile entry lands, the same commit drops the pattern from the model's proposed patterns.
- **Second use.** Before marking an element bespoke, the plan author searches for `@pattern bespoke` code doing the same job. If there is one, the plan proposes a pattern that covers both. The earlier code joins the model as a reused element with a code reference, and is retagged. That edit is allowed outside the plan's claims. Untagged older code is not found this way; that is accepted.
- **Who approves.** The human approves every change to the catalog: a proposed pattern, or a change to an existing one. They are already approving the plan from the tour, so this adds no stop to a single plan. Bespoke elements need no separate approval: the tour points at them, and the plan reviewer checks each reason.
- **During a build** a shape nobody planned is built as bespoke, recorded as a model change, and proposed in a follow-up. The implementer doesn't stop to propose a pattern.
- **Untagged changed code** is "unknown" and gets a full read.

### 4.6 Tying the model to the code

Validation shows that a model is well formed. It cannot show that the model is right or complete: a model with a wrong or missing element still validates. Three checks close that gap.

**Code references.** Each new, modified or removed element that lives in code names its definition:
- `path#Name`, or `path#Outer.Inner` for a member: a named definition in the file, such as a function, a class, a type, or one table in a schema file that holds several;
- a label, where the code declares no name: an entry of a list by one of its properties, a call statement such as a route or a command by the text it is given, a case of a switch by its value. The tool's authoring reference gives the forms;
- `path` alone, when the whole file is the definition.

A reference is a name, not a line number, so it survives edits around it. The tool parses the file to find the definition and its extent (§4.10). A name is the full chain of names around the definition, and it must pick one definition. An element that spans several definitions or files lists several references, and a part can carry its own. A reused element may carry one. At plan time the path is enough; the name is exact by handoff.

**1. Scenarios are walked (plan time).** The model lists the plan's acceptance scenarios by id and title, and each tour step names the scenarios it walks. A scenario with no step fails validation.

**2. Model-to-code (before code review, and again at close).** The tool reports, for each reference, what happened to it between the base commit and the working tree: added, removed, modified or unchanged. The check under `tools/` applies this table to that report:

| Element | Passes when |
|---|---|
| New | Every reference is added, and its tag agrees with the model |
| Modified | Every reference resolves, at least one is added, modified or changed through something it is built from, and each tag agrees with the model |
| Removed | Every reference is removed |
| Reused, with a reference | Every reference is unchanged, and not changed through something it is built from. A change means it is modified, which is a model change (§4.7) |

**A tag agrees with the model** when it names the element's pattern and its further patterns, says `partial` exactly when the model marks a partial fit, and says `bespoke` exactly when the model marks the element bespoke. Anything else fails. So a rule can't be switched off by a tag the human didn't approve.

Then, over the whole diff, from the tool's list of changed lines and the references that contain each:
- *built, not modelled:* an added or changed `@pattern` tag that isn't in the comment above a referenced definition fails;
- *unaccounted:* every changed line in production code inside no reference is listed, whatever tags the file carries. Lines in files that `plan.md` → Changes outside the model lists are marked as such. The reviewer reads the list in full, and either accepts each run of lines as glue or raises the missing element as a major.

Several elements in one file are told apart by their references.

**How the cases are handled.** Two reviews found cases the earlier wording got wrong. The tool feature was built against a failing case for each, and checked on real code. The tool's own decision log holds the rules; this is what they mean here:

| Case | What happens |
|---|---|
| The tag line | The comment lines directly above a definition are outside it. The tool says where they are and whether they changed. A changed tag alone doesn't make an element modified, so earlier code can be retagged |
| A definition renamed, or moved to another file | Its reference stops resolving, and the tool hints where it went. The implementer corrects the reference; a reference is not a compared field (check 3) |
| Deleted lines | They are placed by where the definitions were at the base |
| One name declared twice | In one place, such as a value and a type, it is one definition. In two different places the reference fails until it is qualified |
| A whole-file reference beside named ones | It owns the lines of that file that the named references don't |
| A definition built from a shared block | The tool reports it as changed through that block, within one file. Across files it is not followed: that stays with the reviewer |
| No name, or a file the tool can't parse | A default export with no name has a fixed name. Code that declares nothing is named by its label. A file type the tool doesn't parse takes a whole-file reference. In a file that mixes script and markup, names reach the script; the markup takes the whole-file reference |
| Code that was only laid out again | The tool compares syntax, not text, so a definition the formatter re-wrapped is unchanged. A file it doesn't parse is compared as text |
| A change that was merged long ago | The tool can compare two commits instead of a commit and the working tree, so later work is not counted. The check itself reads the working tree: a trial on old work checks out the last commit of that work |
| An element across several definitions or files | Several references on the element, or on its parts |

**3. Approved versus shipped.** The model at the approval commit (§4.8) is compared with the current one, by element id. Ids don't change after approval.

| Compared | Not compared |
|---|---|
| Elements: kind, parent, change state, pattern, further patterns, fit, parts, libraries, divergence, and which engineering elements implement a product element | Titles, labels and descriptive text |
| Data: fields, indexes, and ties with their enforcement | Code references |
| Relationships: ends, kind, enforcement, and the contract each uses | Views, layout and tours |
| Contracts, clause by clause | The text of a note, and narration |
| Absences; risk and question notes, by what they are attached to | Provenance |
| Scenarios and proposed patterns | A proposed pattern becoming a catalogued one |

Every field of the tool's model belongs in one column; a field the tool adds later is compared until this table says otherwise. Every difference from the latest approval must match a deviation recorded in the ledger (§4.7).

The tool does the comparison. It sorts each difference into an aspect, and its `structure` aspect is the Compared column: the check runs the comparison against the approval commit, keeps `structure`, and reads the result. Three things to know:
- *Matching is by id.* A part or a tie whose title or fields may change needs an id, or the change reads as one removed and one added. A note needs an id for the same reason.
- *A proposed pattern that became catalogued* shows as a proposed pattern removed. The check drops it when the profile now holds that pattern.
- *The tool also counts as structure* an element's lifecycle and area, and a library's version. They are compared.

**Who runs what.** The plan author fills in the references it can foresee. The implementer makes them exact before handoff, runs checks 2 and 3, and records the commands and results in the ledger as it does for the fast gates. The code reviewer treats those as claims and owns the verdict on both: an unrecorded difference is a major, and a re-approval difference is a stop. `run-plan` has a helper rerun both on the final commit; a new difference goes back to review.

### 4.7 Deviations during the build

`implement` says today: a wrong detail is fixed and noted; a wrong plan in substance is a stop. With a model, "substance" can be defined. A deviation is a difference from the approved model in what check 3 compares.

| Class | What changed | What happens |
|---|---|---|
| **Detail** | Nothing that is compared: an element's internals, private names, file layout, code references, tests | Build it and note it in the ledger. Update the references |
| **Re-approval** | Any of the list below | Stop |
| **Model change** | Every other difference | The implementer updates the model in the same commit as the code and records the deviation with its reason. The code reviewer judges each one, and may raise any of them to re-approval. The human sees them in approved versus shipped |

**Re-approval** is needed for:
- a data element, a container or a product element added or removed. Removed includes a change state that becomes `removed`;
- enforcement on a data relationship or a tie moved down this order: `platform`, `platform-correlated`, `our-code`, `nothing`. A move from either of the first two to `derived` counts as down. Also a new data relationship or tie enforced by `our-code` or `nothing`;
- a contract removed, a clause removed, or the clause named `access` changed. A contract's access rule is always written in a clause of that name;
- a catalog, rule or profile file changed that the approved `plan.md` → Changes outside the model doesn't list;
- a scenario that can't be delivered as approved.

When a difference fits this list and the model-change list, this list wins.

**Model changes** include: a component added, split, merged or dropped; a change state that flips (planned as reused, built as modified); a new bespoke or partial-fit element; one catalogued pattern swapped for another; a relationship added, removed or rerouted without lowering enforcement; data fields, indexes or ties changed without lowering enforcement; a clause added, or a clause other than `access` changed; a library added; a reference implementation changed.

**What is mechanical.** The check under `tools/` sorts differences into the re-approval list from two inputs: the comparison in check 3, and the changed paths set against the catalog, rule and profile paths. It needs the profile to say which kinds are data, containers and product elements (§4.10). Two things stay judgment: whether a scenario the model keeps can still be delivered, and loosening the comparison can't see, such as a limit raised in a clause's text or more changed in a listed catalog file than the plan proposed. The reviewer catches those by raising a model change.

**The stop.** The implementer commits its work and the changed model, and stops. `run-plan` gives the human a tour of only what differs from the latest approval. The tool writes it from the same comparison: one step per differing item, shown where the current model draws it. An element or connector that is gone is drawn in its place, struck through and marked as dropped. A smaller thing that is gone (a field, a part, a contract clause, a note) is described in words, with the place it was lit. The human can:
- **approve:** `run-plan` records the re-approval (§4.8) and the same implementer continues;
- **ask for changes:** the implementer changes the model and `run-plan` shows it again;
- **reject:** the implementer builds what was approved. If that can't be built, the plan is wrong in substance: `run-plan` stops, and the human reopens `scope` for a new plan loop and approval.

The same path applies when code review finds a re-approval difference after the build.

### 4.8 The approval gate

The gate is in `scope`, where the human already is. `run-plan` builds without them.

When the plan review is clean, `scope` gives the human:
- the command that opens the tour in the viewer, and the path of the static tour pages;
- the link to `plan.md`;
- a short list: the scenarios, the proposed patterns, the bespoke elements with their reasons, and any open question notes.

The human approves, approves with changes, or rejects. Changes go back to the same plan-author and through one more review.

- **Where things live.** The model is `model.c4ish.json` beside `plan.md`, committed. The rendered diagrams and tour are generated when needed and not committed.
- **Recording approval.** The session that receives the approval adds one line to `plan.md`: `Approved: <date> <commit>`, naming the commit that holds the approved model. A re-approval during the build adds `Re-approved: <date> <commit>` and what changed (§4.7). Check 3 compares against the latest of these lines. The PR shows shipped against the first, with re-approved differences marked. A build agent never writes an approval line. The check can't tell who wrote one, so it prints the lines it relied on and the reviewer confirms each against the human's approval.
- **Handover.** The human then starts `run-plan` with the plan's path. `scope` doesn't continue into the build.

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
- **The epic records only what crosses plans.** `epic.md` names each cross-plan contract and the plan that owns it; the clauses are in that plan's model. A plan that uses the contract copies it into its own model as reused, and the owner's copy wins. A small overview model of how the plans connect is added only when it helps. It shows no plan's internals.
- **No detailed model for the whole epic.** It would force all design up front and repeat each plan's detail (handoff §4.C).

### 4.10 What the process needs from the tool

The tool is a separate product and knows nothing of this process: no tags, no deviation classes, no catalog rules. It exists and is installable: `validate` (schema, references, notation lint, strict per-tour coverage), `render`, `tour`, `view`, an authoring reference (`guide`) and a version report. The process needs these additions, each proved by a check that fails on a broken fixture:

| Need | For | State |
|---|---|---|
| A code reference on an element and on a part (`path#Name`) | §4.6 | Built |
| A report on a model's code references between a base commit and the working tree: whether each resolves at each end and its extent, what happened to it, and for every changed line, at the base and at the head, which references contain it. The tool parses source to do this (tree-sitter) | §4.6 check 2 | Built. The tool's authoring reference lists the languages it parses; any other file takes a whole-file reference |
| A code reference on a pattern in a profile, for its reference implementation | §4.3 | Built. The same report, run on a profile, says whether each one resolves and what changed in it |
| A category for each kind of element in a profile: container, code, data or product | §4.6, §4.7 | Built. The tool prints the profile as it reads it, and warns when a new or modified element of a code or data kind states no pattern |
| Ids on parts and on ties, and a fit and a bespoke marker on parts | §4.6 check 3 | Built. Ids are optional, and a name used twice in one element fails validation |
| Scenarios in the model, a tour step naming the scenarios it walks, and a failure when none walks one | §4.6 check 1 | Built. A scenario counts as walked when a step of any tour names it |
| A bespoke marker with a required reason, drawn distinctly and counted by tour coverage | §4.5 | Built. It stands in place of a pattern. Coverage counts it when its element or part is new or modified |
| A comparison of two versions of a model, by id, reported by kind of difference, and a tour of only what differs | §4.6 check 3, §4.7 | Built. Dropped elements and connectors are drawn; dropped fields, parts, contracts and notes are words only |

This repo adds a small check under `tools/` on top of that report. It reads the tags, the project's path file (§4.3), `plan.md` and the comparison, and applies the tables in §4.6 and §4.7. Which lines count as unaccounted is its decision, not the tool's. Code references replaced the model's earlier `sources` field, which moved the tool's model schema to version 1.

**The check** is `tools/model-check.mjs`, with `code` (check 2), `approved` (check 3) and `all`. Its header documents the options and file formats. Building it, and two independent reviews of it, settled these:

- **The project's path file** is JSON: `profile`, `catalog`, `rules`, `leftOut` and `noTag` (file types that cannot carry a comment), as paths and globs from the repository root. A path with no wildcard also covers everything under it.
- **The check is judged by what was approved.** The path file, the profile and the plan's "Changes outside the model" list are read from git at the latest approval commit. The working copy is never used for them and there is no fallback, so the path file and profile must be committed before a plan is approved. A change to the path file or the profile stops like a catalog change. `approved` refuses to run without the path file.
- **Approval commits** must be in the history of HEAD, in the order the plan lists them.
- **A plan with no approval line** runs only as a trial (`--no-approval`), judged by the working copy and marked as a trial in the output. Only a trial may take reports made beforehand. An approved plan always runs git and the tool.
- **The command is fixed by the process.** The check can't know that `--plan` and `--project` name the right files. `run-plan` and the reviewer run it with the paths the project's agent guide names.
- **The profile says what each element kind is.** The check asks the tool for the profile as it reads it, and takes from that each kind's category, the style of each change state and which relationship kinds carry data. It keeps no list of its own, so it can't drift from the tool. A path file that lists `kinds` is refused.
- **Pattern states are checked.** An element of a code or data kind that the build creates or changes must name a pattern or be bespoke with a reason, on itself or on each of its parts, and must have a code reference. `pattern: null` means no pattern applies; on such an element it fails. Code under a bespoke element or part carries `@pattern bespoke:`.
- **A scenario dropped from the model** stops. One added is a model change. Whether a scenario the model keeps can still be delivered stays judgment.
- **Enforcement levels are roles.** A project's profile may name them differently, so the path file maps `platform`, `platform-correlated`, `our-code`, `nothing` and `derived` to its ids. An id the check can't rank makes the change a re-approval.
- **`derived` ranks between the platform levels and `our-code`,** so a move from `derived` to `our-code` or `nothing` is also down.
- **An `access` clause added** counts as changed.
- **Where a tag is required.** On a reference the build added or modified, the tag must be there and agree. On a reference the build left alone, in any element, reused ones included, a tag must agree if there is one. This follows "no mass retrofit" (§4.3) and stops a retag from switching a rule off.
- **A tag starts its comment line and is one line.** `@pattern` in a sentence or a string is not a tag. A tag wrapped onto a second line loses what is on that line, and then fails to agree. A line with no comment marker counts only inside a block comment that opens at the start of a line.
- **A part with its own pattern, fit or bespoke marker** is checked against the part; a part without one carries its element's tag. A part with its own change state is judged by it.
- **A kind change counts as added or removed.** An element whose kind turns into, or out of, data, container or product stops. So does a contract whose change state becomes removed. A change state that becomes removed on any other element is a model change.
- **A data relationship that states no enforcement** counts as enforced by nothing. Which relationship kinds carry data comes from the profile.
- **Deviations in the ledger** are a section headed "Deviations", one list item per differing item, starting with its key in backticks: `kind:id`, as the tool names it (`element:collector`). A re-approval difference stops whether or not it is recorded. A record that matches no difference is noted.
- **"Changes outside the model" in the plan** has the same form: a section with that heading, one list item per path or glob, starting with it in backticks. In both files the heading must match exactly (a number before it or a colon after it is fine) and fenced code is ignored.
- **Bases.** `code` compares code from the first `Approved:` commit. `--base` may move that to an earlier commit, never a later one. `approved` compares from the latest approval line.
- **Exit codes:** 0 pass, 1 a failure or a re-approval, 2 an error of any other kind. `--json` carries the verdict.

Every need in the table is built. The check needs a version of the tool that has them.

### 4.11 Review
- **Plan mode.** As well as today's checks:
  - the model validates with no errors or warnings, and the tour covers every review item;
  - every new, modified or reused element that lives in code has a pattern state, and every new, modified or removed one has a code reference, at least to its path. A missing one is a major. A bespoke reason that an existing pattern or existing bespoke code answers is a major;
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
   - **approval:** the human's time to approve from the tour, against recorded approval times of earlier text plans where there are any; and what the tour failed to show. Gaps in the diagrams are fixed by iterating on the tool and the authoring rules;
   - **whether the approval was right:** afterwards, each code-review and later finding is marked as a design issue the tour showed, one it didn't show, or not a design issue;
   - **whether the checks can be trusted:** one audit by hand of the model against the code, counting what checks 2 and 3 passed wrongly and failed wrongly. One known mismatch is planted first, since a single run may have none of its own;
   - **cost:** an estimate of the time and tokens spent writing the model, keeping it in line, and tagging;
   - **review:** the reviewer's time on skipped code against fully read code, deviations by class, the lines a rule let the reviewer skip, the unaccounted hunks, findings by kind, and defects found later in skipped code;
   - **patterns:** those proposed and the elements marked bespoke, and whether each held up in review;
   - **time:** end to end, per 1k changed lines. The pilot era-D medians are per child of at most about 7k lines, so they are a rough guide and not a like-for-like baseline.

   One run can't prove the process. The owner decides to adopt, revise or drop on three questions: was approval quick enough and right; did the checks catch real mismatches without false alarms; and did the model and tags cost less than they saved in review.
3. **Packages** (§5): the next step after 1–2.
4. **Adoption ADR:** covers the frontier pipeline and this plan, retires the old skills, and records measured outcomes separately from intent.

## 7. Open questions

**For the owner:** none open.

**Still open:**
- **Q1. Package definition:** fields, whether packages can be revised while running, and partial-component ownership (handoff §10.A). Only needed for §5.
- **Q7. Role-skill loading:** one smoke run of option (a) and of the `run-plan` wrapper (§4.1). Also whether an orchestrator started with `/skill:` keeps the skill text after it compacts; if not, its compaction note re-reads the file by path.
- **Q10. Reviewing a large diff:** whether groups, each read by its own fresh reviewer, catch what one reviewer over the whole diff would (§4.9). The pilot answers it.
- **Q11. Code references:** the method of check 2 is built and recorded in §4.6. Still open: definitions built from code in another file; named references in file types the tool doesn't parse yet, where the first adopter's code needs them; and whether the check's tag rule for untouched references (§4.10) is right in practice.
- **Q12. Epic children:** the approval commit when review alone approves a child, who shows the tour at a catalog stop, a refresh after approval, the child's close, and when a proposed pattern is claimed (§4.9). Also the check's baseline: both checks count from the child's approval commit, so other children's integrated work shows as unaccounted lines, and their catalog or profile changes as a re-approval stop. Settle before the first epic; the pilot is a single plan.
- **Q13. Large-diff groups:** whether groups hold files or hunks, and how pass 2 and fix reviews run over them (§4.9). Settle before the first plan above the signal.

**Settled in revision 2:** Q2 model scope (one hop, §2). Q3 tag syntax (§4.3). Q5 model at close (reconcile fully, mechanically, §4.6). Q9 bespoke tags (`@pattern bespoke: <what it is>`, §4.3).

**Decided by the owner, 2026-11-17:** Q4 the human approves new patterns (§4.5). Q6 no size limit on a plan; an epic only for distinct workstreams (§4.9). Q8 epics stay rare: a detailed model per plan, and only cross-plan contracts at the epic level (§4.9). The first pilot has no parallel work (§5). The approval gate is in `scope` (§4.8). The tool resolves code references; this repo owns the tag rules (§4.10).

## 8. Not in scope
- Building the diagram tool. It is a separate product; §4.10 lists what this process needs from it.
- Any project's catalog content.
- A central index of where patterns are used.
- Maintained architecture documentation.
- An entry to `scope` from a brief with no prototype.
