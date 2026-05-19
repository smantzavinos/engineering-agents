# Repository Quality Process Foundation — Execution Worklog

## Entry-Point Contract

- **Read this file first** every time you start working on this plan.
- Execute exactly ONE task per sub-agent call. Do not execute multiple tasks.
- Do not add new tasks to the current plan/worklog task list unless the human explicitly changes scope.
- After completing a task: update this file, commit, and stop.

## Working Rules

- Strict TDD (Red → Green → Break-it → Verify). No change without a failing test first unless the plan explicitly documents an exception.
- Git commits are per plan task. Do NOT push until explicitly requested.
- Follow the plan's TDD checklists exactly — do not skip the break-it check.
- Non-blocking follow-up work does **not** become a new plan task.
- Before T3, this repo has **no formal backlog mechanism yet**. Note accepted non-critical follow-up work in this worklog only; do not invent a backlog system.
- Before T4, this repo has **no canonical requirements mechanism yet**. Do not invent one early; only apply the approved requirements-system introduction in T4.

## References

- Plan: `./plan.md`
- Approach: `./approach.md`
- Brief: `./brief.md`
- Plan review: `./plan_review.md`

## Completion Criteria

All of these must be true before the plan is considered complete:
- [ ] All tasks marked done below
- [ ] `./tests/run-tests.sh fast` passes for each completed task
- [ ] `./tests/run-tests.sh all` passes before plan completion
- [ ] Root `AGENTS.md` routes to all canonical docs and local guidance files introduced by this plan
- [ ] Backlog and requirements mechanisms are documented as agent-executable systems for this repo
- [ ] Final commit made

## Prerequisites

### Environment Setup
- **Required services:** none documented for this plan's task gate. No long-running service start/stop commands are documented in the repo docs read for this worklog.
- **Required env vars:** none documented in the repo docs read for this worklog.
- **Runtime / tooling prerequisites:**
  - `bash`, `jq`, and `node` are required for `./tests/run-tests.sh fast` per `tests/README.md`
  - `nix` is required for the flake-eval portion of `./tests/run-tests.sh all` per `tests/README.md`
  - `pi` installed and `home-manager switch` already run are required for the Pi proof-set portion of `./tests/run-tests.sh all` per `tests/README.md`
- **Runtime versions:** not documented in the repo docs read for this worklog; do not invent version requirements.
- **Setup command:** `home-manager switch --flake .#<hostname>` is the documented setup/apply command in `README.md` for installing the repo-managed tooling.
- **Stop commands:** none documented.

## Baseline Gate Audit

Baseline audit already exists in `plan.md`; carry it forward here. Do **not** rerun or reinterpret it unless a later task needs fresh evidence.

| Command | Scope | Baseline status | Notes |
|---------|-------|----------------|-------|
| `bash tests/specs/repo-structure-spec.sh` | package-wide | pass | Passed during assessment on 2026-05-19 |
| `./tests/run-tests.sh fast` | package-wide | pass | Passed during assessment on 2026-05-19 |
| `./tests/run-tests.sh all` | repo-wide | ambiguous | Reported overall success during assessment while proof-set verification emitted `Unable to locate Pi module entrypoint .../@mariozechner/pi-coding-agent/dist/index.js`; this is in-scope and must be fixed |

- [x] All gates checked before implementation began
- [x] Pre-existing failures documented above

## Testing & Verification

### Commands
| Command | Scope | When to run | What it checks |
|---------|-------|-------------|----------------|
| `bash tests/specs/repo-readiness-docs-spec.sh` | touched-files | During TDD loops for readiness-doc tasks | The repo-local operational contract docs and routes required for this plan exist and contain key anchors |
| `bash tests/specs/proof-set-runtime-spec.sh` | touched-files | During TDD loops for verification-hardening work | The proof-set helper resolves supported Pi module layouts and fails correctly on broken assumptions |
| `./tests/run-tests.sh fast` | package-wide | Before marking each task complete | The repo-local shell spec suite still passes after each documentation and helper change |
| `./tests/run-tests.sh all` | repo-wide | Before plan completion | The repo's broader verification surface, including flake evaluation and proof-set verification, is trustworthy and green |
| `./tests/run-tests.sh full` | repo-wide | Optional release smoke after plan completion | Pi CLI smoke checks still work once the main gates are green |

### Gate Policy
- Policy: `allow-scoped-completion`
- If a broader gate fails for unrelated reasons: log the failure in `Unrelated Gate Failures Log`, confirm the task's own fast-feedback command(s) and `./tests/run-tests.sh fast` pass, then continue scoped task execution. Do **not** mark the overall plan complete until `./tests/run-tests.sh all` passes.
- Special case for this plan: before T2 lands, the repo-wide `all` gate is known-ambiguous because of the in-scope proof-set module-path issue. Treat `./tests/run-tests.sh fast` as the reliable task gate until T2 repairs verification trust.

### Why the Gate Command Matters
The task completion gate `./tests/run-tests.sh fast` catches integration drift that targeted spec commands can miss, including runner wiring, shell-spec aggregation problems, stale test-suite documentation, doc-route inconsistencies, and cross-file contract mismatches between the touched docs/helpers and the repo's broader fast suite.

Always run the gate command before marking a task complete, even if the task-level fast-feedback command passes.

### Unrelated Gate Failures Log
| Date | Command | Failure | Related to current task? | Action |
|------|---------|---------|--------------------------|--------|
| none yet | n/a | n/a | n/a | n/a |

- If a task-specific test fails: fix before marking task complete.
- If `./tests/run-tests.sh all` still fails after T2 for reasons newly introduced by the current task, treat that as related and fix it before progressing.

## Backlog Capture Policy

- **Repo backlog:** none documented yet. This plan establishes the backlog mechanism in T3.
- **Before T3:** accepted non-critical follow-up work must be noted in this worklog only; it cannot yet be formally captured in a repo backlog.
- **Create item procedure after T3:** follow `docs/backlog.md` exactly once T3 creates it.
- **Stable ID/reference format after T3:** `TASK-XXXX` as specified by T3.
- **Default non-critical follow-up status after T3:** `Inbox`.
- **Default origin for execution follow-ups after T3:** use the source backlink rules defined in `docs/backlog.md` to point back to this plan/worklog/review.
- **Critical/current-plan-affecting discoveries:** stop and ask whether to fix immediately, re-plan, or defer after explicit approval.

Until T3 exists, do **not** invent backlog IDs, statuses, or storage locations.

## Backlog Items Created

None yet.

## Requirement Changes

This repo does not yet maintain a canonical requirements mechanism at worklog creation time. The approved requirement update in this plan is introduced in T4.

- **Repo requirements before T4:** none documented yet.
- **Repo requirements after T4:** `docs/requirements.md` (to be created by T4).
- **Approved requirement updates from plan:** introduce a canonical Markdown requirements system for this repo in T4.
- **Applied requirement updates:** none yet.
- **Requirement-change approval source:** `./plan.md` → `Requirement Updates` table.
- **Expected stable ID/reference format after T4:** `ACT-001`, `UC-001`, `WF-001`, `FR-001`, `NFR-001`, `OPR-001`.
- **Expected test requirement citation format after T4:** `Requirement: <ID>`.

If execution reveals a missing, unclear, or conflicting durable requirement before T4, stop and ask before inventing or editing canonical requirements. Only the approved T4 requirements-system introduction is pre-authorized by this plan.

## Task Status

- [ ] T1: Add root routing and core contributor docs
- [ ] T2: Canonicalize testing strategy and fix verification trust gap
- [ ] T3: Establish repo backlog/task-tracking contract
- [ ] T4: Establish lightweight requirements system
- [ ] T5: Add specialized-area guidance and `.llm/` instructions
- [ ] T6: Add operational memory docs and consistency cleanups
- [ ] T7: Final consistency sweep and repo-wide verification

## Decisions / Constraints Discovered (append-only)

Record any decisions made or constraints discovered during execution that weren't in the original plan:
- Before T3, follow-up work can only be noted in this worklog; there is no formal backlog yet.
- Before T4, there is no canonical repo requirements system; the only pre-approved change is introducing it in T4.
- `./tests/run-tests.sh all` is not a reliable task gate at baseline because of the proof-set module-entrypoint ambiguity; `./tests/run-tests.sh fast` is the reliable task gate until T2.

## NEXT STEP

**Current Task:** T1 — Add root routing and core contributor docs

Read `plan.md` § `T1: Add root routing and core contributor docs` for the full TDD checklist and implementation details.

After completing this task:
1. If T1 discovers accepted non-critical follow-up work, record it in this worklog only because T3 has not established the backlog yet.
2. Mark T1 done above.
3. Set NEXT STEP to T2.
4. Append to the execution log below.
5. Commit: `task(T1): <short description>`

## Execution Log

### T1 — YYYY-MM-DD
- **Changes:** <what was done>
- **Tests:** `bash tests/specs/repo-readiness-docs-spec.sh` → pass/fail
- **Verification:** `./tests/run-tests.sh fast` → pass/fail
- **Commit:** `<sha>` — `task(T1): <short description>`
- **Backlog items created:** none yet (no repo backlog mechanism until T3)
- **Requirement changes applied:** none
- **Notes:** <anything notable>
