# Worklog — SDP Simplification

Task gate: `nix develop --command ./tests/run-tests.sh fast` (0 failed beyond disclosed baseline; python3-missing specs excluded).
Final gate: same, after T5, plus every touched spec individually green.

## Backlog capture policy

Repo backlog: `docs/backlog.md` (TASK-XXXX IDs). Critical discoveries: stop and ask.

## NEXT STEP

T3 — docs/hermes/dev-process.md. T1+T2+T4 complete (T5 realigned inline); see Execution log.

## Execution log

### T1 — Verification classes canonical + break-it demoted — DONE
- Spec-first: 12 assertions added to repo-readiness-docs-spec.sh; confirmed RED (exactly those 12 failed).
- docs/testing-strategy.md: Verification Classes section now applies to every plan; TDD-scope rule written (regressions, not volatile content); break-it = high-risk-invariant footnote, reviewer-initiated; Ownership section generalized off dynamic-workflow framing.
- docs/process.md §4A/§5A/§7A: classes + tiers in plan stage; class-specific execution steps; break-it line removed.
- docs/coding-rules.md: Verification Rules de-parallelized (every plan declares classes; no fence wording; host-verification rule generalized).
- skills: create-plan (+template: class/tier fields, no break-it, Red→Green→Verify), execute-task (class-driven execution), review-code (+template: verification evidence replaces break-it evidence), review-plan (+template: class-declared checks), worklog template.
- Fixups caught by own spec: TDD term restored in coding-rules; line-wrap broke "high-risk invariant" anchor; case mismatch in review-plan anchor.
- Verify: readiness spec 263/0; fast suite 682/0 (baseline for this branch; excludes PR #3 assertions not yet merged).

### T2 — One pipeline + plan tiers + ADR 0006 — DONE
- Spec-first: 10 assertions, confirmed RED (exactly 10 failed).
- docs/process.md: single pipeline (plan → review → worklog → execute → code review → PR review); §4B–8B replaced by "Opportunistic Parallel Dispatch" (bounds = orchestrator's own policy, human ruling) + "9. PR Review" chaining into pr-review.md; commit discipline de-parallelized; bug-fix stages de-branched.
- docs/adr/0006-retire-parallel-execution.md: new Accepted ADR (what died: dynamic workflow, team mode; what survived: verification classes, baseline gates, repo-hook referencing, execution tiers). ADR 0004 + 0005 → Superseded; ADR index updated.
- docs/architecture.md: Core Flow 3 routes to sequential pipeline + ADR 0006 instead of the Parallel path.
- docs/plan-levels.md: single artifact tree, single stage ladder, team artifacts removed from responsibilities table.
- plans/README.md: sequential-only artifact contract; team artifacts marked RETIRED.
- Fixups caught by own spec: assertion needles vs intentional prose ("no tasks.json" mention), capital-S "Superseded", stale 0004-Accepted assertion.
- Verify: readiness spec 272/0; fast suite 690/0.

### T4 — Retire parallel machinery + team-mode + spec realignment — DONE
(T5 merged into T4: spec realignment executed together with the moves, since
both touch the same assertion surfaces.)
- Archived via git mv to docs/investigations/2026-09-23-retired-parallel-execution/:
  dynamic-{create,execute,review}-plan, dynamic-review-code, direct-plan,
  create-team-plan, review-team-plan, create-team-worklog,
  execution-orchestrator-team, tools/check-plan.mjs, workflows/wave.mjs,
  docs/approaches/parallel.md, docs/execution-patterns.md. Archive README
  records what died and what survived.
- De-wired: harnesses/pi.json (hiddenSkills + notes), skill-resources.json
  (→ empty on this branch; the pull-request packaging belongs to the #3
  lineage), nix piSkills/pi default/opencode config lists, flake.nix
  activation checks, agents/planner.md (no tasks.json/write-set; + tier),
  agents/preset.jsonc (Execute mode rewritten sequential-first; valid JSON,
  references only Pi-installed skills), nix execute.md agent (single
  orchestrator path), README (14-skill table, workflows, principles),
  docs/plan-directory-structure.md (retired-artifacts note), tests
  (wave-engine + plan-check specs deleted; runner + inventory updated;
  render-spec asserts retired skills never render again; skill-content
  team blocks removed; readiness + structure + flake-eval lists pruned).
- Lineage correction mid-task: hermes-docs-spec + docs/hermes/ live on the
  feat/hermes-docs branch (#4 stack), NOT on this main-based branch —
  reverted premature references here.
- Fixups caught by suite: skill-resources unknown-skill rejection (renderer
  forbids tombstone keys), preset.jsonc raw-quote JSON breakage + double
  escaped newlines, preset→Pi-tree skill-link check (execute-task is
  OpenCode-only; preset now references only review-approach).
- Verify: structure 72/0, readiness 272/0, proof-set 31/0, skill-content
  37/0, render 60/0, preset 17/0; only the 4 disclosed python3-env
  failures remain.
