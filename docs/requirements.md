# Requirements

## System

This file is the canonical source for the repo's current accepted requirements.

- **Posture:** this repo maintains requirements because it ships durable process, verification, and contributor-contract behavior.
- **Store:** keep current accepted requirements in `docs/requirements.md`.
- **Stable IDs:** use `ACT-001`, `UC-001`, `WF-001`, `FR-001`, `NFR-001`, and `OPR-001`.
- **Reference format:** cite requirement IDs directly in briefs, approaches, plans, worklogs, reviews, commits, and summaries.
- **Test citation format:** tests cite the requirements they verify using `Requirement: <ID>`.
- **Traceability rules:** actors support use cases; workflows reference use cases; functional requirements reference the use case they support; non-functional and operational requirements declare their scope; tests point up to requirements instead of requirements manually listing every test.
- **Apply approved changes:** apply approved requirement edits in the task that implements them and record the changed IDs in the matching worklog entry.
- **Retire or replace requirements:** edit the canonical entry in this file with the approved replacement or superseding note; do not silently delete historical intent from active execution artifacts.
- **Approval boundary:** draft requirement changes stay in brief/approach/plan artifacts until approved, and canonical requirement edits require human approval unless explicitly delegated by the current plan or worklog.
- **Validation/query guidance:** use read-only queries such as `grep -n '^### ACT-' docs/requirements.md`, `grep -n '^### FR-' docs/requirements.md`, and `grep -RIn 'Requirement: ' tests/` to inspect the current requirement set and test citations.

## Required Operations

| Operation | Required contract |
|-----------|-------------------|
| List actors/personas | Review `## Actors and Personas` for the current user/operator/system definitions. |
| List use cases | Review `## Use Cases` for the durable goals the repo supports. |
| List workflows | Review `## Workflows` for the concrete execution and maintenance flows. |
| List functional requirements | Review `## Functional Requirements` for required repo behavior. |
| List non-functional requirements | Review `## Non-Functional Requirements` for quality constraints. |
| List operational requirements | Review `## Operational Requirements` for verification and operating constraints. |
| Discover stable IDs | Use the documented prefixes and the existing headings in this file; new IDs must be unique and monotonic within their prefix family. |
| Reference format | Cite requirements by stable ID, for example `FR-001` or `OPR-001`, in plans, worklogs, reviews, commits, and summaries. |
| Test citation format | Add a `Requirement: <ID>` comment near the test logic that verifies the cited requirement. |
| Apply approved changes | Update this file only when the current plan/worklog explicitly approves the requirement change, then record the affected IDs in the worklog. |
| Retire or replace requirements | Replace or annotate the affected entry in this file with the approved superseding guidance instead of inventing a second canonical store. |
| Validation/query guidance | Use read-only grep/search commands to inspect IDs and citations before changing anything. |
| Tool/auth/fallback | No special tool or auth is required beyond local repo access; if the repo is unavailable, stop instead of inventing requirement state. |

## Actors and Personas

### ACT-001 — Maintainer
Maintains the repo's canonical process docs, verification helpers, and contributor contract.

### ACT-002 — Contributor
Implements scoped changes in the repo and must follow the documented planning, testing, backlog, and requirements rules.

### ACT-003 — End-user
Consumes the repo as a reference implementation or installs its tooling and expects the documented workflows and verification surface to be reliable.

## Use Cases

### UC-001 — Validate repo changes before completion
**Actors:** ACT-001, ACT-002

Contributors need clear fast and task-completion gates so they can verify changes before recording work as done.

### UC-002 — Configure the repo for autonomous process execution
**Actors:** ACT-001, ACT-002

Maintainers need durable routing, guidance, and verification contracts so autonomous agents can work without undocumented assumptions.

### UC-003 — Capture accepted follow-up work durably
**Actors:** ACT-001, ACT-002

Contributors need a canonical place to record approved non-critical discoveries so the work is not lost in chat or transient notes.

### UC-004 — Maintain durable repo requirements
**Actors:** ACT-001

Maintainers need a lightweight canonical system for the repo's accepted requirements so changes can be proposed, approved, cited, and queried consistently.

## Workflows

### WF-001 — Execute task-level verification
**Use case:** UC-001

Run the task's fast-feedback spec during the TDD loop, then run `./tests/run-tests.sh fast` before updating worklogs or completing the task.

### WF-002 — Add or update repo-local operating contracts
**Use case:** UC-002

Introduce or revise canonical repo docs, route them from `AGENTS.md`, and keep the touched contract under executable readiness checks.

### WF-003 — Capture accepted follow-up work
**Use case:** UC-003

When non-critical work is accepted but out of scope, record it in `docs/backlog.md` with a stable `TASK-XXXX` ID and a source backlink to the originating artifact.

### WF-004 — Apply approved requirement updates
**Use case:** UC-004

Keep draft requirement changes in plan artifacts until approval, then update `docs/requirements.md`, cite the relevant IDs in touched artifacts, and record the change in the worklog.

## Functional Requirements

### FR-001 — Root routing and canonical repo docs
**Use case:** UC-002

The repo shall provide a root `AGENTS.md` that routes contributors and agents to the canonical architecture, coding-rules, development-environment, testing-strategy, backlog, and requirements docs.

### FR-002 — Explicit verification surface
**Use case:** UC-001

The repo shall document the exact fast-feedback, task-completion, and final verification commands that contributors must use for scoped and repo-wide validation.

### FR-003 — Durable backlog for accepted follow-up work
**Use case:** UC-003

The repo shall provide a canonical backlog with stable `TASK-XXXX` IDs, source backlinks, and executable lifecycle operations for accepted non-critical follow-up work.

### FR-004 — Canonical requirements system
**Use case:** UC-004

The repo shall maintain a lightweight canonical requirements system in `docs/requirements.md` that includes actors, use cases, workflows, functional requirements, non-functional requirements, operational requirements, stable IDs, citation guidance, and approval boundaries.

### FR-005 — Requirement citations in materially edited readiness specs
**Use case:** UC-004

Materially edited readiness-related tests shall cite the requirements they verify using the documented `Requirement: <ID>` format.

### FR-006 — Trustworthy proof-set verification behavior
**Use case:** UC-001

The proof-set verification path shall support the current `@earendil-works/pi-coding-agent` namespace and the legacy `@mariozechner/pi-coding-agent` namespace, while reporting missing entrypoints as explicit non-zero environment failures.

## Non-Functional Requirements

### NFR-001 — Lightweight and local
**Scope:** global

The backlog and requirements systems shall remain lightweight, Markdown-based, and stored in the repo so contributors can inspect and update them with standard local tooling.

### NFR-002 — Concise, executable documentation
**Scope:** global

Repo-operating docs shall stay concise, routing-oriented where appropriate, and specific enough to be checked by durable shell-based readiness specs.

## Operational Requirements

### OPR-001 — Verification gate roles
**Scope:** global

`./tests/run-tests.sh fast` is the task completion gate for this plan, and `./tests/run-tests.sh all` is the final plan gate.

### OPR-002 — Requirement change application policy
**Scope:** UC-004, WF-004

Approved requirement changes shall be applied during normal task execution, and the affected requirement IDs shall be recorded in the matching worklog update.
