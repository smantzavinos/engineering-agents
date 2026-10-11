# Frontier pipeline: prototype → epic → autonomous execution

Status: vision, awaiting owner review
Date: 2026-10-10
Scope: one pipeline, Pi only. Other paths (discovery-first, dispatcher, Hermes, OpenCode) are untouched until this one is proven.

This document deliberately does not follow `plans/README.md` or the plan template. The template is part of what is being replaced.

---

## 1. Why

The current process was built to make cheap models behave consistently. Every stage has a long skill, a fixed template, a reviewer checklist, verification classes, execution tiers, per-task TDD, per-task commits, and a worklog. That scaffolding paid off when the implementer was weak. With frontier models doing the work, it now mostly costs time and context.

Evidence from a 15-child prototype build-out epic in a production TypeScript monorepo (Oct 9–10, current process):

| Observation | Number |
|---|---|
| Wall time, child 01 / child 02 | 4.4 h / 10.5 h (13 children remain) |
| Share of child 02 time spent running tests | ~70% (E2E alone ~54%) |
| E2E runs in two children | 109 targeted + 33 full-suite |
| Cause | Each task's plan required the package-wide unit, check, lint and build gates plus a growing E2E grep. Every E2E run rebuilt the app and booted a local backend. |
| Model reasoning share of child 02 | 26% |
| Epic design artifacts before any code | approach 62 KB, epic 30 KB, runbook 17 KB |
| Decision log after 2 of 15 children | 122 KB, 121 entries |
| Child plan size | ~460 lines each: task tables, tiers, classes, TDD checklists |
| Skill text loaded along the current path | ~2,500 lines plus templates |

The models did not slow this down; the process did. Work was cut into 17 tasks per child, each with its own red/green/verify ceremony and gates, and low-tier models did the implementing.

## 2. Principles

1. **Frontier models drive every step that needs judgment.** Orchestrating, planning, implementing, reviewing and arbitrating all run on frontier or near-frontier models.
2. **The cost lever is delegation, not downgrading.** Frontier agents send read-heavy, low-judgment work to fast, cheap helpers to save their own context and tokens. The frontier agent decides; the helper fetches.
3. **Small sessions, not small tasks.** One planner session and one implementer session per child plan. Each self-compacts before handing back, so it stays resumable and cheap to continue.
4. **Fresh eyes for every review.** Every review pass is a new session. Authors are never fresh; reviewers always are.
5. **Say what, not how.** Skills state goals, outputs, constraints and stop conditions, and trust the model with the method. A skill that needs a template to work is too long.
6. **Test at the right altitude.** Run targeted tests while building and the full gates once at the end. Never run the full suite per step.
7. **Disk is the memory.** Anything that must survive compaction or a crash lives in a file in the plan directory or in git, not in chat.

## 3. The pipeline at a glance

```
[human + agent]       PROTOTYPE      → prototype/<slug> branch + PROTOTYPE.md
        │
[human + orchestrator] EPIC PLANNING → epic.md (scope, children, acceptance)
        │                               fresh review → fix → human approves
        │                               orchestrator self-compacts
        ▼
[orchestrator, autonomous] for each child plan:
        ├─ PLAN LOOP       planner (resumed, compacted) ⇄ fresh plan reviewer
        ├─ IMPLEMENT LOOP  implementer (resumed, compacted) ⇄ fresh code reviewer
        │                    disputes → oracle
        └─ CLOSE           record state, orchestrator self-compacts, next child
        ▼
EPIC CLOSE                   one fresh whole-epic review → PR process (existing)
```

## 4. Stages

### 4.1 Prototype (human-paired)

This stage replaces discovery and design for this pipeline. Keep the substance of today's `prototype-first`:
- a fast, throwaway build on `prototype/<slug>`;
- a running change list;
- hacks noted as they happen;
- a pushed branch;
- a `PROTOTYPE.md` with the verdict, the changes made, numbered acceptance scenarios, what was faked, the shortcuts taken, and open questions.

Cut everything else. The prototype is the spec for behavior: every accepted demo behavior becomes an acceptance scenario of the real build.

Output: the pushed branch and `PROTOTYPE.md`. Tracker linkage stays as today (a backlog issue), described in one paragraph rather than a procedure.

Disposal is decided during epic planning and recorded in `epic.md`:
- **wipe-and-rebuild** is the default: the real work branches off the default branch and rebuilds cleanly, using the prototype as reference;
- **clean up the prototype** is equally allowed when its structure is sound. The real work branches off the prototype and hardens it in place. This will often be the better choice.

### 4.2 Scope: epic or single plan (interactive)

A new session on a frontier model becomes the orchestrator. It reads `PROTOTYPE.md` and the prototype diff, using helpers to scout the codebase and research anything external. It then drafts `epic.md` with the human.

The human and orchestrator iterate until scope is agreed. That covers:
- what is in and out;
- how the prototype changes split into child plans, and in what order;
- the error paths and lifecycle the prototype skipped;
- which quality gates apply;
- what the autonomous phase may decide alone.

Then:
1. The orchestrator launches a fresh reviewer on `epic.md`.
2. Findings go to the human. The orchestrator fixes them.
3. Repeat until the human approves.
4. Commit `epic.md`.
5. The orchestrator self-compacts. Its note is: the epic path, "begin autonomous execution at child 01", and the stop conditions.

From here on, the human is only pulled in by a stop condition (§8).

If scoping shows the work fits one plan, there is no `epic.md`. The orchestrator spawns the planner, and the human iterates on `plan.md` through the orchestrator. The plan then gets a fresh review and human approval. Execution runs only the implement loop (§4.4) and the close (§4.6).

### 4.3 Per-child plan loop (autonomous)

```
planner = spawn planner(child N context)           → writes NN_<slug>/plan.md, self-compacts, returns summary
loop:
  review = spawn fresh reviewer(plan.md, epic.md, prior findings)
  if review.approved: break
  planner = resume planner(review findings)        → revises, self-compacts, returns
```

- Every planner call continues the same session. The session is compacted at the end of every call, so the reviewer's findings land in a planner that remembers its reasoning but carries little context.
- The reviewer is a new session every pass (§7).
- The orchestrator approves the plan when the reviewer has no open blocker or major findings. There is no human gate unless a stop condition fires.

### 4.4 Per-child implement loop (autonomous)

```
impl = spawn implementer(plan.md)                  → implements everything, runs gates, iterates to green,
                                                     commits, self-compacts, returns summary + gate evidence
loop:
  review = spawn fresh code reviewer(child diff, plan.md, gate evidence, prior findings)
  if review.approved: break
  impl = resume implementer(review findings)       → fixes, or disputes via oracle; re-runs affected gates,
                                                     commits, self-compacts, returns
```

- **Implement the whole plan, top to bottom.** No per-task dispatch, no TDD ceremony, no per-task commits. The implementer writes the tests the plan calls for. Every acceptance scenario gets one, and each test is written alongside the code it covers.
- **Quality gates come at the end** (§6). Iterate until all gates pass, then hand back.
- **Disputes go to the oracle.** If the implementer disagrees with a finding or is unsure, it consults a fresh oracle session. It then records the ruling next to the finding in `review.md`, and later reviewers treat ruled items as settled.
- **Commits:** the implementer commits in logical units with conventional messages. The child ends on a clean tree.

### 4.5 Child close

The orchestrator does the following:
1. Mark the child done in `state.json`.
2. Append any follow-ups to the tracker, if the epic pre-authorized that.
3. Self-compact. Its note is: the epic path, the next child, and anything learned that changes later children.
4. Start the next child.

If a learning invalidates part of `epic.md`, the orchestrator may update unstarted children within the agreed scope. Changing scope is a stop condition.

### 4.6 Epic close

When the last child is done:
1. One fresh review of the full epic diff against `epic.md` and `PROTOTYPE.md`, focused on cross-child seams and parity with the acceptance scenarios.
2. Fix any findings through a resumed implementer session.
3. Hand off to the existing `pull-request` process, which is unchanged in this plan.

## 5. Sessions, compaction, and memory

| Session | Lifetime | Model class | Compaction |
|---|---|---|---|
| Orchestrator | Whole epic; interactive, then autonomous | frontier | After epic approval, after each child, and whenever it crosses its threshold |
| Planner (per child) | Spawned once, resumed per review round | frontier | `self_compact` at the end of every call |
| Implementer (per child) | Spawned once, resumed per review round | frontier | `self_compact` at the end of every call, and mid-run if it grows large |
| Plan/code/epic reviewer | One pass | frontier | Never; it is short-lived |
| Oracle | One question | frontier (max reasoning) | Never |
| Helpers | One errand | fast/cheap | Never |

Mechanics:
- **Self-compaction** uses `@nicknisi/pi-checkpoint`'s `self_compact({ note_to_self })`. Every handback works the same way:
  1. Finish the work.
  2. Write durable state to disk.
  3. Call `self_compact` with a note covering what was done, where it lives, what's open, and how to continue.
  4. After compaction, the continuation turn writes a short reply of at most 15 lines. That reply is what the parent receives.
- **Resume** uses pi-subagents `resume` on the retained child run. The orchestrator stores each child's latest planner and implementer run ids in `state.json`, so a crashed orchestrator can pick them up again.
- **The source of truth is files**:
  - `epic.md`, `state.json`, each child's `plan.md` and `review.md`, and git;
  - compaction notes are a convenience.

## 6. Testing and quality gates

The repo defines its gates; the pipeline defines when to run them.

| When | What |
|---|---|
| While implementing | Whatever the implementer judges useful: single test files, a single E2E grep for the test being written, a type check. Never the full suite. |
| End of implementation | Every gate the plan lists, run once in full: the repo's typecheck, lint, unit, build, E2E. Fix the failures, then re-run only what failed. Finish with one full green pass. |
| Code review | The reviewer reads the gate evidence. It runs targeted tests only when it doubts a claim, and never repeats the full suite. |
| Epic close | One full gate run on the final tree. |

Gate runs are long and their logs are large, so the implementer hands them to a fast subagent (the run-and-digest pattern, §9). It returns a digest: pass or fail per gate, failing test names, the key assertion lines, and log paths. The implementer reads a full log only when the digest is not enough.

Flaky tests: a failure that passes on an isolated re-run is recorded and counts as a pass. A flake class seen twice becomes a tracker item.

Repo-side speedups are separate from this process but often still needed. They are reusing the built app and a warm backend across E2E runs, and running E2E in parallel workers. Track them in that repo's backlog.

## 7. Review policy

- **Fresh session every pass.** The reviewer receives:
  - the artifact (plan, or diff with gate evidence);
  - its governing context: `epic.md` and `PROTOTYPE.md`, plus `plan.md` for code reviews;
  - the `review.md` ledger of prior findings, responses and oracle rulings.

  Fresh means no conversation history, not no knowledge of prior findings. The ledger is how passes converge instead of re-litigating.
- **Severity:**
  - *blocker* and *major* findings must be resolved;
  - *minor* findings are fixed when cheap, otherwise acknowledged;
  - nits are not reported.

  Pass 2 and later look first at whether earlier findings were fixed. A new finding at those passes must be blocker or major, or it must come from the fix itself.
- **Disputes:** the author may reject a finding with a rationale, or consult the oracle. An oracle ruling is final for that finding.
- **Pass cap:** if blockers remain after the 4th pass of any loop, stop for the human.
- **Output:** findings are appended to the child's `review.md`. Each pass gets a heading, and each finding gets an ID, a severity, a location, a problem and a suggested fix. The reviewer's reply to the orchestrator is the verdict plus counts.

## 8. Stop conditions (when autonomy pauses)

- A discovery contradicts `epic.md` scope or a premise of the prototype.
- A scope change: adding, removing or merging a child, or dropping an acceptance scenario.
- A destructive or irreversible action, or anything touching shared infrastructure, production data, pushes or merges.
- A review loop hits its pass cap.
- A gate failure the implementer cannot resolve and cannot show is pre-existing.
- Oracle and implementer both remain unsure on a blocker.
- **A major fork in the road with no clear winner.** A decision that sets the course for a large share of the remaining work, such as an architectural choice in child 1 of a 12-child epic, goes to the oracle first. Continue if the oracle names a clearly better option. Stop for the human only if it does not.

The default is full automation. Every other decision is made autonomously. Tricky decisions are recorded with their justification in a short `decisions` section of `epic.md`: the options, the choice, why, and whether the oracle was consulted. That section holds only those non-obvious decisions; it is not a running log.

## 9. Delegation to fast helpers

Rule of thumb: **delegate when the work is read-heavy, the output is easy to check, and a wrong answer is cheap to catch.** Keep anything that commits the project to a choice.

| Delegate to a helper | Keep on the frontier agent |
|---|---|
| Codebase scouting: "where is X handled", "list every call site of Y with file:line", "how does Z flow end to end" | Deciding what to change and how |
| External research: library docs, API behavior, version changes, prior art | Choosing between options |
| Running gates and long test suites, and digesting logs | Diagnosing non-obvious failures from the digest |
| Reading screenshots, comparing prototype vs. real UI | Judging whether the UI matches intent |
| Mechanical sweeps once the pattern is fixed: rename, adopt a component at N call sites, update imports. The frontier agent reviews the diff. | Writing the pattern itself; any non-uniform edit |
| Git archaeology: "why did this change", "when did this behavior appear" | Interpreting what history implies for the design |
| Gathering review context: diff stats, touched-file → test mapping, finding which docs reference a changed route | The review judgment itself |
| Verifying a claim: "does this function still exist / is this route registered" | — |

Helper contract (in every helper agent definition):
- answer the question asked;
- cite `file:line` or the URL;
- say "not found" rather than guess;
- keep it to the length requested;
- never edit outside the task.

Delegation is opportunistic. Skills say *what* is delegable, not *when*. The frontier agent decides.

These are **patterns, not agent types**. Each row above is an example of an errand a frontier agent gives a fast subagent: scout, research, run-and-digest, sweep, verify-a-claim, look, history. The `delegate` skill lists them, and the frontier agent is free to invent others. The only fast agent definitions needed are the ones whose tools or model differ:
- a general `helper` with read, bash and edit tools; it is read-only unless the errand says otherwise;
- a `researcher` with web tools;
- a vision-capable agent, if the repo needs one.

## 10. Roles and models

Frontier roles: orchestrator, planner, implementer, reviewer, oracle.
Fast agents: `helper`, `researcher`, and vision if the repo needs it (§9).

These replace the old roles:
- `worker-high`, `worker-low` and `worker` become the implementer plus helpers. A separate `ui-worker` is kept only if the repo wants a distinct UI model.
- `plan-reviewer` and `code-reviewer` become one `reviewer`. The skill mode chooses plan, code or epic.

Models stay a repo hook, because each repo maps roles to models. For example:
- frontier: the strongest available Claude Opus / GPT model;
- helpers: a Haiku / Flash-class model.

Plans no longer assign tiers.

## 11. Artifacts (minimal set)

```
plans/<date>_<epic>/
  PROTOTYPE.md        copied from the prototype branch (input, unchanged)
  epic.md             goal, scope in/out, acceptance scenarios → child map, children in order
                      (goal / depends on / done when, a few lines each), gates, autonomy limits,
                      decisions (short). Target: a few pages.
  state.json          per child: status, latest planner/implementer run ids, base commit, review pass counts
  NN_<child>/
    plan.md           goal, context links, design decisions, changes by area,
                      tests to add (mapped to acceptance scenarios), gates, done criteria, risks.
                      Free-form, no task table. Target: ≤150 lines.
    review.md         append-only ledger: plan passes, code passes, responses, oracle rulings
```

A single plan (not an epic) works as today: one plan directory with `PROTOTYPE.md`, `plan.md`, `review.md` and `state.json` at its root, and no `epic.md` or `NN_` subdirectories.

Retired from this pipeline:
- `brief.md`, `approach.md` and its review, `findings/`;
- `worklog.md`, `runbook.md`, a separate decisions log, per-child brief and approach;
- task tables, verification classes, execution tiers, TDD checklists.

## 12. Skills to write

Targets: each skill ≤ ~80 lines, and the whole pipeline ≤ ~400 lines (~2,500 today). No reference templates beyond a short skeleton inside the skill.

Drafts live in [`skills/`](skills/README.md) next to this plan.

| New skill | Used by | Replaces on this path |
|---|---|---|
| `prototype` | human + agent session | `prototype-first` (trimmed) |
| `scope` | orchestrator, interactive phase | `discovery`, `design`, `discover-and-design*`, `review-approach`, epic parts of `software-development` |
| `orchestrate` | orchestrator, autonomous phase | `execution-orchestrator`, `create-worklog` |
| `plan` | planner | `create-plan` + `plan-template` |
| `implement` | implementer | `execute-task` |
| `review` (modes: epic, plan, code, epic-diff) | reviewer | `review-epic`, `review-plan`, `review-code` + templates |
| `delegate` | every frontier agent | Scattered delegation guidance in presets and agent files |

The interactive skill is named `scope` rather than `epic` because it produces either an epic or a single plan.

Untouched for now:
- `pull-request`, `babysit-pr`, `backlog`, `triage-backlog`, `work-item`;
- `assess-repo`, `configure-*`, `create-skills`, `skill-sync`.

Writing rules for the new skills:
- State the outcome, the outputs, the hard constraints and the stop conditions. Leave out method unless it is non-obvious and was learned the hard way.
- Point to repo docs rather than restating them.
- No rule exists only to fence off a past weak-model failure. Keep such a rule only if the failure recurs with frontier models in the pilot.
- No ceremony a frontier model would do anyway, such as "read the file before editing" or "run tests after changes".

## 13. Prerequisites and risks

| Item | Status / mitigation |
|---|---|
| `@nicknisi/pi-checkpoint` requires Pi ≥ 0.87.0; installed is 0.86.1 | Bump Pi in the nix module first. |
| `self_compact` inside a subagent: does the post-compaction continuation become the child's returned output? | Confirm in the spike. Fallback: the child writes its handoff note to the plan dir and ends; "resume" becomes a new session seeded with plan dir + note. Same effect, slightly less memory. |
| pi-subagents `resume` revives from the persisted session file; it must carry the compacted context, not the pre-compaction transcript | Confirm in the spike; measure resumed context size. |
| Nested delegation: frontier subagents launching helper subagents | Confirm it is allowed and budgeted under the pi-subagents spawn limits. |
| Compaction loses a detail that mattered | Mitigated by "disk is the memory": plan, review ledger, git and `state.json` hold everything needed to continue. |
| Whole-plan implementation produces a large diff that is hard to review | Plans stay child-sized. The implementer commits in logical units. The reviewer may use scouts to gather context. |
| Fewer gates mid-flight means regressions surface later | Accepted trade. The end-of-implementation full gate and fresh review catch them, which is cheaper than paying for gates on every step. |
| Epics already in flight depend on the installed skills | Build the new skills side by side under new names. Retire nothing until the pilot passes. |

## 14. Rollout

1. **Spike (≤ half a day).** Bump Pi, install pi-checkpoint in the dev environment, and confirm the four mechanics:
   - subagent `self_compact` and the handback;
   - `resume` of a compacted child;
   - two resume rounds;
   - nested helper calls.

   Decide primary or fallback mechanics.
2. **Write.** Create the six skills, the agent definitions (frontier and helpers), and the presets (`epic` and `orchestrate`, replacing `discovery`, `design` and `execute` for this path). Render `dist/`. Write ADR 0007, "Frontier-driven pipeline", that records this shift and supersedes the tier/TDD/worklog parts of current docs for this path.
3. **Pilot.** Run the pipeline on the next prototype-driven epic in a consuming repo. Optionally, once its current child closes and only if the owner chooses, switch the remaining children of an in-flight epic to it. Collect the §15 metrics.
4. **Adopt.** If the pilot meets the targets:
   - make this the default prototype-first path;
   - retire the replaced skills, templates and agents;
   - update `docs/process.md`, `docs/orchestration.md`, `agent-roles.md`, `plan-levels.md` and `plans/README.md`.

   If it misses, fix what the data points at before widening.

## 15. Success measures

Baseline: children 01–02 of the epic in §1.

| Measure | Baseline | Target |
|---|---|---|
| Wall time per L-sized child | 10.5 h | ≤ 3 h |
| Time in test execution | ~70% | ≤ 30% |
| Child plan length | ~460 lines | ≤ 150 lines |
| Epic artifacts before execution | ~110 KB | ≤ 25 KB |
| Review passes to approval (plan / code) | 2–3 / 2 | ≤ 2 / ≤ 2 |
| Peak context of any frontier session | not tracked | Stays under the compaction threshold without forced compaction |
| Cost per child | ~$20 | Same or lower despite frontier implementers |
| Defects found at epic/PR review that the child review missed | not tracked | Tracked; no worse than baseline |
| Human interventions during autonomy | — | Only §8 stop conditions |

## 16. Owner rulings and open questions

Ruled (2026-10-10):
- **Autonomy.** Execution continues with full automation, and tricky decisions are recorded with justification. A course-setting fork goes to the oracle, and stops for the human only if the oracle has no clear better choice (§8).
- **Pass cap.** 4 passes, for every review loop (§7).
- **Prototype disposal.** Wipe-and-rebuild is the default; cleaning up the prototype in place stays fully allowed (§4.1).
- **Single-plan work.** It stays a single plan, as today, not a one-child epic. During `scope`, the human iterates with the planner on `plan.md`. After approval, the same implement loop runs once (§11).
- **Planner vs. implementer.** Pilot (a) below; try (b) later.
- **Delegation.** Helpers are patterns given to frontier agents as examples, not subagent types. Sweep is one pattern among several (§9).

- **Plan approval.** In autonomous mode a clean fresh review is enough to approve a child plan. There is no human calibration check.

No open questions remain.

Background for the planner/implementer ruling:
- **Planner implements its own plan.** Attractive because the planner is already compacted and holds the reasoning, but the two roles may use different models.
   - pi-subagents `resume` keeps the child's stored agent, model and tool contract, and rejects a model override. A resumed planner therefore cannot switch to the implementer's model. It would also need edit tools in its own agent definition.
   - `context: "fork"` branches only from the *parent's* session, not a sibling child's.

   Options:
   - (a) Keep the sessions separate, and pass the planner's final handoff note to the implementer alongside `plan.md`. This is cheap and works across models. **Recommended for v1.**
   - (b) Use one "builder" agent per child on a single model that both plans and implements, resumed across both loops.
   - (c) Upstream a pi-subagents feature: resume with a model override, or fork from a retained child's session.

   Ruled: pilot (a); try (b) later.
