# Plan — SDP Simplification + Hermes SDP Docs

Approach of record: `brief.md` (rulings section). Baseline: fast suite
708 passed / 0 failed (4 specs fail on missing python3 in devshell —
pre-existing, disclosed in PRs #1–#3, unchanged by this plan).

Branch strategy: one branch per task group below, stacked in order;
each task's PR opens only after its verify passes. PR A/B branch from
`main`; PR C branches from PR A's branch (shares `docs/hermes/README.md`).

---

## T1 — Canonical verification classes + break-it demotion
- class: contract
- tier: low
- writes: docs/testing-strategy.md, docs/coding-rules.md,
  docs/process.md (§4A/§5A/§7A TDD wording), skills/create-plan/SKILL.md
  + references/plan-template.md, skills/execute-task/SKILL.md,
  skills/review-code/SKILL.md + references/code-review-template.md,
  skills/create-worklog/references/worklog-template.md,
  skills/review-plan/SKILL.md + references/review-template.md,
  docs/orchestration.md (create-team-plan excluded — archived whole in T4)
- details:
  - testing-strategy.md: add Verification Classes section
    (contract / characterization / check / none) with the class-selection
    test: "would a test here catch a real regression, or only pin volatile
    content?" `none` legitimate for prose/config-without-contract.
  - break-it: removed from per-task TDD checklists everywhere; kept as a
    footnote — "for high-risk invariants (money, auth, data loss), break the
    invariant once to prove the test bites." review-code no longer requires
    per-task break-it evidence; worklog template drops the break-it field.
  - create-plan TDD checklist becomes Red → Green → Verify.
  - dynamic-* wording NOT touched here (T4 archives those files wholesale).
- verify: `nix develop --command ./tests/run-tests.sh fast` (0 failures
  beyond baseline); `grep -ri "break-it" docs/ skills/ --include="*.md"`
  shows only the footnote + retired-archive hits;
  `bash tests/specs/skill-content-spec.sh` green.

## T2 — One pipeline in process.md + plan template tiers
- class: contract
- tier: high
- writes: docs/process.md (Feature Development section: delete parallel
  branch; sequential becomes the pipeline; final stage chains into PR
  review per docs/references/pr-review.md), skills/create-plan/references/
  plan-template.md (+execution tier field per task, +verification class
  field), docs/plan-levels.md (terminology alignment), plans/README.md
  (artifact expectations: sequential only; team_plan.md marked retired).
- details:
  - Opportunistic-parallel rule written into process.md: the orchestrator
    may dispatch independent tasks concurrently; bounds are that
    orchestrator's own policy for its environment (no universal cap in the
    canon — human ruling 2026-09-23).
  - Execution tier vocabulary: `high` / `low` — maps to existing
    `subagents.agentOverrides` routing; plan template gains a Tier column.
- verify: fast suite; `grep -n "parallel (Pi)" docs/process.md` empty;
  `bash tests/specs/repo-readiness-docs-spec.sh` green (T2 updates its
  assertions where process.md anchors change).

## T3 — docs/hermes/dev-process.md (the Hermes SDP manual)
- class: check
- tier: high
- writes: docs/hermes/dev-process.md (new), docs/hermes/README.md
  (+1 index row), tests/specs/hermes-docs-spec.sh (+contract anchors)
- details:
  - Pipeline summary + pointers to process.md (no restating).
  - Skill-sync checklist: what each agent-side skill must cover, mapped to
    canonical sections (plan structure incl. class+tier fields, review loop
    to zero Criticals, TDD scope rule, PR handoff).
  - Written-down conventions from LLS practice: findings as a separate
    dispatched phase with file:line anchors; two-reviewer loop to zero
    Criticals; STOP-class taxonomy (STOP-AND-ASK vs proceed).
- verify: fast suite; new spec asserts anchors exist; README index row.

## T4 — Retire parallel machinery + team-mode + ADR-0005
- class: check
- tier: low
- writes: git mv skills/dynamic-create-plan skills/dynamic-execute-plan
  skills/dynamic-review-plan skills/dynamic-review-code tools/check-plan.mjs
  workflows/wave.mjs skills/dynamic-create-plan/references/tasks-schema.md
  → docs/investigations/2026-09-23-retired-parallel-execution/;
  git mv skills/create-team-plan skills/review-team-plan
  skills/create-team-worklog skills/execution-orchestrator-team → same
  archive dir (team-mode = parallel experiment #2, same ruling);
  docs/adr/0005-retire-parallel-execution.md (Status: Accepted; what died —
  DAG machinery AND team-mode; what survived: verification classes, baseline
  gates, repo-hooks referencing); harnesses/pi.json + harnesses/opencode.json,
  nix config lists, flake.nix check, README skill table rows, AGENTS.md
  Planning Artifacts section (drop parallel pointers — **needs
  approval-gated edit flagged**), tests/README.md inventory,
  tests/run-tests.sh (drop wave-engine-spec.sh + plan-check-spec.sh),
  delete tests/specs/wave-engine-spec.sh + plan-check-spec.sh + their
  fixtures.
- details: archive via git mv (history preserved); a short README.md inside
  the archive dir states why + where the survivors went. dist/ re-render.
- verify: fast suite (with wave/plan-check specs gone, baseline count
  changes — assert 0 failed); `grep -rn "dynamic-" README.md AGENTS.md
  harnesses/ nix/ flake.nix` empty; flake-eval-spec green.

## T5 — Spec realignment + full-suite proof
- class: contract
- tier: low
- writes: tests/specs/skill-content-spec.sh (drop anchors referencing
  retired surfaces: dynamic-*, team skills, execution-orchestrator-team;
  keep anchors for surviving files), tests/specs/
  repo-readiness-docs-spec.sh (ADR-0005 row, archived-dir assertion,
  team ADRs 0002/0003/0004 marked superseded-by-0005), tests/specs/
  repo-structure-spec.sh (skill list final state)
- details: this task reconciles every spec with the post-retirement tree so
  the suite is green without the retired files. Also the readiness spec's
  team-ADR assertions (0002/0003 superseded; add 0004 superseded by 0005).
- verify: full fast suite 0 failed; every touched spec individually green.

## T6 — PR series + handoff
- class: none
- tier: low
- writes: none (git/gh only)
- details: PR A = T1+T2 (branch feat/sdp-simplify, off main); PR B = T4+T5
  (branch feat/retire-parallel-execution, stacked on A); PR C = T3 (branch
  feat/hermes-dev-process, stacked on A; one-line conflict risk with the
  #4 branch on docs/hermes/README.md — resolve toward superset). Each PR
  body per the PR body contract with filled review-rules table.
- verify: gh pr view mergeable=CLEAN ×3; linked correctly (base= per
  stacking); review-rules tables filled.

---

## Dependency graph (opportunistic-parallel notes)

T1 → T2 (template fields reference the classes) → T3, T4 (both depend on
T2's canonical wording), T4 → T5, T6 last. T3 ∥ T4 are disjoint — the
orchestrator MAY run them concurrently; everything else sequential.

## Risks
- Spec anchor churn is the biggest breakage surface (T5 exists because of
  it). Mitigation: T5 runs the full suite; no task marks done with failures
  beyond the disclosed baseline.
- AGENTS.md edit in T4 is approval-gated: batch it into the same nod that
  approves PR A's merge.
- The plan itself uses the new format (classes, tiers, no break-it) — if
  the format feels wrong here, say so before execution; that feedback IS
  the T1/T2 review.
