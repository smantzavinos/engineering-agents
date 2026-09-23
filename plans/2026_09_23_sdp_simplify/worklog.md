# Worklog — SDP Simplification

Task gate: `nix develop --command ./tests/run-tests.sh fast` (0 failed beyond disclosed baseline; python3-missing specs excluded).
Final gate: same, after T5, plus every touched spec individually green.

## Backlog capture policy

Repo backlog: `docs/backlog.md` (TASK-XXXX IDs). Critical discoveries: stop and ask.

## NEXT STEP

T2 — one pipeline in docs/process.md + plan template tiers in plans/README.md. T1 complete; see Execution log.

## Execution log

### T1 — Verification classes canonical + break-it demoted — DONE
- Spec-first: 12 assertions added to repo-readiness-docs-spec.sh; confirmed RED (exactly those 12 failed).
- docs/testing-strategy.md: Verification Classes section now applies to every plan; TDD-scope rule written (regressions, not volatile content); break-it = high-risk-invariant footnote, reviewer-initiated; Ownership section generalized off dynamic-workflow framing.
- docs/process.md §4A/§5A/§7A: classes + tiers in plan stage; class-specific execution steps; break-it line removed.
- docs/coding-rules.md: Verification Rules de-parallelized (every plan declares classes; no fence wording; host-verification rule generalized).
- skills: create-plan (+template: class/tier fields, no break-it, Red→Green→Verify), execute-task (class-driven execution), review-code (+template: verification evidence replaces break-it evidence), review-plan (+template: class-declared checks), worklog template.
- Fixups caught by own spec: TDD term restored in coding-rules; line-wrap broke "high-risk invariant" anchor; case mismatch in review-plan anchor.
- Verify: readiness spec 263/0; fast suite 682/0 (baseline for this branch; excludes PR #3 assertions not yet merged).
