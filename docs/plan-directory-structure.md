# Plan Directory Structure

This document defines the naming conventions, directory layout, and artifact specifications for engineering plans at each level.

---

## Naming Convention

### Plan directories

```
YYYY_MM_DD_<descriptive_slug>/
```

- Date is the creation date
- Slug is snake_case, short, and descriptive
- Examples:
  - `2026_05_01_add_user_notifications/`
  - `2026_04_17_fix_auth_race_condition/`
  - `2026_05_01_auth_migration/` (epic)

### Plans root

Plans live in a `plans/` directory (or equivalent) within the repository. The exact location is repo-specific and documented in the repo's AGENTS.md or engineering docs.

Common patterns:
- `plans/` (small repos)
- `docs/engineering/plans/` (repos with structured docs)

---

## Simple Plan Directory

```
plans/2026_05_01_fix_typo_in_readme/
├── brief.md
└── state.json
```

### brief.md (simple)

Minimal intent capture:

```markdown
# Fix Typo in README

**Type:** simple
**Created:** 2026-05-01

## What
Fix misspelled "authentication" in the Getting Started section of README.md.

## Why
User-facing documentation should be error-free.
```

---

## Standard Plan Directory

```
plans/2026_05_01_add_user_notifications/
├── brief.md
├── findings/
│   ├── current_state.md
│   ├── code_structure.md
│   └── dependencies.md
├── approach.md
├── approach_review.md
├── sequential: plan.md + plan_review.md + worklog.md
│   or team: team_plan.md + team_plan_review.md + team-worklog.md
├── code_review.md
└── state.json
```

### Findings Directory

Research findings are split across multiple files with descriptive names. This serves two purposes:

1. **Discoverability** — Later stages (approach, plan, execution) can load only the findings relevant to what they're doing without reading all research output
2. **Context efficiency** — Agents load smaller, focused documents rather than one large monolithic findings file

#### Standard Findings File Types

| Filename | Purpose | When to create |
|----------|---------|----------------|
| `current_state.md` | What exists today, how it works, where it lives | Always |
| `code_structure.md` | Relevant modules, patterns, file organization | When the change touches multiple areas |
| `dependencies.md` | Libraries, services, APIs involved and their constraints | When external dependencies matter |
| `root_cause.md` | Bug root cause analysis with evidence | Bug fix workflows |
| `library_research.md` | External library evaluation, API docs, usage patterns | When introducing or upgrading libraries |
| `prior_art.md` | Similar existing patterns, related features | When following existing patterns matters |
| `constraints.md` | Discovered constraints not obvious from the brief | When research reveals non-obvious limitations |

**Naming rule:** Use descriptive snake_case names. The filename should tell an agent whether the content is relevant to their current task without opening the file.

**Minimum:** At least `current_state.md`. Add others based on what the research actually discovers. Don't create empty files for the sake of structure.

### brief.md (standard)

Full intent documentation:

```markdown
# Add User Notifications

**Type:** standard
**Created:** 2026-05-01
**Owner:** <name or agent>

## Goals
- [ ] Users receive real-time notifications for relevant events
- [ ] Notifications persist and can be marked as read
- [ ] Notification preferences are configurable per user

## Non-Goals
- Push notifications to mobile devices (future work)
- Email notifications (separate initiative)
- Notification grouping/batching

## Constraints
- Must work within existing WebSocket infrastructure
- Must not degrade page load performance
- Must be backwards-compatible with existing user settings schema

## Motivation
Users currently have no way to know when relevant events occur without manually checking. This creates friction in collaborative workflows where timely awareness matters.

## Success Criteria
- Notifications appear within 2 seconds of the triggering event
- Users can configure which event types generate notifications
- Read/unread state persists across sessions
```

### findings/

Research output split into focused files:

```markdown
# findings/current_state.md

# Current State: User Notifications

**Created:** 2026-05-01
**Plan:** ../brief.md

## Summary
No notification system exists today. Users discover events by manually
navigating to relevant pages.

## Event System
- Events are dispatched via `src/events/dispatcher.ts`
- Existing listeners in `src/events/listeners/` follow a consistent pattern
- Events carry typed payloads defined in `src/events/types.ts`

## User Data
- User settings stored in `src/user/settings.ts`
- Settings schema uses a flat key-value structure
- No existing notification preferences

## Real-Time Infrastructure
- WebSocket connection managed in `src/websocket/`
- Currently used only for live data updates, not notifications
- Connection lifecycle handles reconnection automatically
```

```markdown
# findings/dependencies.md

# Dependencies: User Notifications

**Created:** 2026-05-01
**Plan:** ../brief.md

## Internal Dependencies
- Event system (`src/events/`) — source of notification triggers
- WebSocket layer (`src/websocket/`) — delivery channel
- User settings (`src/user/settings.ts`) — preference storage

## External Dependencies
- None required for MVP
- Future: push notification service for mobile (out of scope)

## Integration Points
- Event dispatcher: notifications subscribe to events
- WebSocket: notifications piggyback on existing connection
- Database: new table for notification persistence

## Constraints
- WebSocket payload size limited to 64KB
- Event listener registration is synchronous at startup
- User settings schema migration required for preferences
```

### approach.md

Conceptual model and structural decisions:

```markdown
# Approach: Add User Notifications

**Created:** 2026-05-01
**Plan:** ./brief.md
**Based on:** ./findings.md

## Solution Model

### Components
- **NotificationService** — generates notifications from events
- **NotificationStore** — persists notifications per user
- **NotificationChannel** — delivers notifications via WebSocket
- **NotificationPreferences** — user-configurable filters
- **NotificationUI** — displays notifications in the app

### How They Fit Together
<description of the interaction model>

## Key Decisions

| Decision | Chosen | Rationale | Alternatives Considered |
|----------|--------|-----------|------------------------|
| Storage | Existing DB with new table | Consistent with user data patterns | Separate notification service (too heavy) |
| Delivery | Piggyback on existing WebSocket | Already available, no new infra | SSE (would require new endpoint) |
| Filtering | Server-side based on preferences | Reduces client load | Client-side filtering (chatty) |

## What Changes vs What Stays
- **Changes:** New notification table, new event listeners, new UI component
- **Stays:** Event system interface, WebSocket connection lifecycle, user settings schema structure

## Boundary Definitions
- NotificationService only reacts to events; it never triggers them
- NotificationStore is the single source of truth for notification state
- UI reads only from the store; never from the event system directly

## Patterns to Follow
- Follow existing event listener pattern in `src/events/listeners/`
- Follow existing store pattern from `src/stores/`
- UI component follows existing panel pattern
```

### plan.md (sequential planning)

Detailed implementation plan (see the create-plan skill for full template). Contains:
- Execution contract (strict TDD)
- Change summary
- Goals/non-goals
- Task graph with dependencies and an optional per-task `Touched files` (write-set) field
- Task details with TDD checklists
- Verification plan
- Coverage matrix

This artifact belongs to the sequential strict-TDD pipeline.

### team_plan.md (team planning)

Created directly from the reviewed approach instead of from `plan.md`. Contains:

- acceptance contracts and early contract-test packets (one or two verifier lanes)
- frozen design decisions and framework boundary checks
- a DAG task table with lane tags, write sets, dependencies, and relay successors
- resource locks and named verification profiles
- risk tier and implementer class (mechanical, bounded-cheap, standard, complex)
- live-review checklists and reviewer-created remediation protocol
- one-retry escalation to a Strong rescue implementer created on demand
- a throughput summary (critical path, ready width, role multiplicity, cheap-lane share)
- wave commit gates (maximum four concurrent members)

### team_plan_review.md

Reviews contract completeness, packet ownership and decision-completeness, DAG ready width
and role multiplicity, resource locks, role/model cost, lane-claim coordination, active
slots, remediation, escalation, and independent final review.

### plan_review.md

Iterative review findings (see the review-plan skill for full template). Contains:
- Open decisions roll-up
- Open significant issues roll-up
- Per-review entries with findings categorized by severity
- Applied changes to plan
- Review summary with pass/continue status

### worklog.md

Execution tracking document (see the create-worklog skill for full template). Contains:
- Entry-point contract (read this first every iteration)
- Completion criteria
- Testing & verification section with exact commands
- Plan task status
- Repo backlog capture policy for follow-up work
- Backlog item IDs created during execution
- Requirement changes applied during execution, when relevant
- Next step pointer
- Loop log entries

### team-worklog.md (team-mode execution only)

Lead-owned compact wave ledger created from reviewed `team_plan.md`. Per-task transient
state lives on the live team task board, not here. Contains:
- baseline gate evidence
- per-wave commit entries (tasks included, gate profile, result, commit hash)
- deviations and critical decisions
- remediation summaries and evidence references
- rescue escalations, fresh final review, closure, backlog, and requirement records

### code_review.md

Post-implementation review (see the review-code skill for full template). Contains:
- Open issues roll-up
- Coverage matrix audit
- Requirement alignment checks, when relevant
- Per-review entries with findings
- Implementer response sections
- Review summary with pass/continue status

---

## Requirement Traceability in Plan Artifacts

When a repo maintains requirements, plan artifacts should cite stable requirement IDs where useful:

| Artifact | Requirement role |
|----------|------------------|
| `brief.md` | Records relevant existing actors/use cases/workflows/requirements and requirement questions |
| `approach.md` | Explains how the approach satisfies requirements and drafts proposed requirement changes |
| `plan.md` | Maps approved requirement edits to implementation tasks and cites requirement refs per task |
| `worklog.md` | Records requirement changes applied during execution |
| `code_review.md` | Checks implementation against cited requirements and flags undocumented requirement changes |

Canonical requirements docs should normally contain current accepted requirements. Draft or unclear requirement changes stay in planning artifacts until approved and applied.

---

## Epic Plan Directory

```
plans/2026_05_01_auth_migration/
├── brief.md
├── findings/
│   ├── current_state.md
│   ├── code_structure.md
│   └── migration_research.md
├── approach.md
├── approach_review.md
├── epic.md
├── epic_review.md
├── state.json
├── 01_schema_changes/
│   ├── brief.md
│   ├── findings/
│   │   └── current_state.md
│   ├── approach.md
│   ├── approach_review.md
│   ├── plan.md
│   ├── plan_review.md
│   ├── worklog.md
│   ├── code_review.md
│   └── state.json
├── 02_api_layer/
│   ├── brief.md
│   ├── findings/
│   │   ├── current_state.md
│   │   └── dependencies.md
│   ├── approach.md
│   ├── approach_review.md
│   ├── plan.md
│   ├── plan_review.md
│   ├── worklog.md
│   ├── code_review.md
│   └── state.json
└── 03_frontend_updates/
    ├── brief.md
    ├── findings/
    │   └── current_state.md
    ├── approach.md
    ├── approach_review.md
    ├── plan.md
    ├── plan_review.md
    ├── worklog.md
    ├── code_review.md
    └── state.json
```

#### approach_review.md

Approach review findings (see the review-approach skill for the full template). Contains:
- Open decisions roll-up
- Open significant issues roll-up
- Per-review entries with findings by severity
- Applied changes to the approach
- Review summary with pass/continue status

---

## Epic-Level Artifacts

Epics have three distinct root-level planning artifacts:

- **`brief.md`** — Overall intent, motivation, constraints, and why this is an epic
- **`approach.md`** — The overall architectural approach for the initiative, structural decisions that affect all child plans, and key boundaries between workstreams
- **`epic.md`** — The decomposition artifact: workstreams, child plans, sequencing, and execution record
- **`epic_review.md`** — Review findings for the epic decomposition (completeness, sequencing, preparatory work, and first-child-plan readiness)

Epics also have a root-level `findings/` directory for research that applies to the whole initiative.

Child plans within the epic also have their own research and approach phases, but these are scoped to that specific child plan's concerns. The epic-level findings provide shared context that child plans can reference without duplicating.

**When child plan research is lighter:** Because epic-level findings already established the broad context, child plan research focuses on the specific module/area that child plan touches. It references the epic findings rather than re-discovering the same information.

### epic.md

Lightweight roadmap/index that captures epic decomposition and execution state:

```markdown
# Epic: Auth Migration

**Created:** 2026-05-01
**Status:** In Progress
**Owner:** <name>

## Relationship to Other Epic Artifacts
- `brief.md` — initiative intent, goals, constraints, and why this is an epic
- `approach.md` — overall architectural strategy and workstream boundaries
- `epic.md` — this file; decomposition into workstreams and child plans

## Epic Summary
See `brief.md` for full scope and constraints. This file focuses on decomposition and execution ordering.
## Source Documents
- `docs/architecture.md` — current auth architecture section
- `docs/requirements/auth-requirements.md` — auth requirements
- `docs/adr/0005-jwt-migration.md` — migration decision record

## Research Summary
See `findings/` for detailed research. Key discoveries:
- Current session store handles ~10k concurrent sessions
- JWT migration requires token table + user-provider associations
- Existing WebSocket auth will need adapter pattern during transition

## Approach Summary
See `approach.md` for full architectural approach. Key decisions:
- Dual-auth adapter pattern during transition (both mechanisms active)
- Schema-first approach (data layer before API before frontend)
- Feature flag per-user for gradual rollout

## Workstreams

### 1. Schema & Data Layer
**Goal:** Establish the new auth data model and migration path.

#### 01_schema_changes
**Status:** Complete
**What this builds:** New JWT token table, user-provider association table,
migration scripts for existing sessions.

### 2. API Layer  
**Goal:** Implement new auth endpoints and middleware.

#### 02_api_layer
**Status:** In Progress
**What this builds:** OAuth2 callback endpoints, JWT issuance/validation middleware,
backward-compatible session fallback.

### 3. Frontend
**Goal:** Update the frontend to use new auth flow.

#### 03_frontend_updates
**Status:** Not Started
**What this builds:** New login flow UI, token refresh logic, provider selection.

## Sequencing
- Workstream 1 must complete before Workstream 2 (API depends on schema)
- Workstream 2 must complete before Workstream 3 (frontend depends on API)
- Within each workstream, child plans execute in numbered order

## Cross-Cutting Concerns
- Backward compatibility during migration period
- Existing tests must continue passing at every step
- Feature flag for gradual rollout

## Execution Record
| Child Plan | Created | Completed | Duration |
|-----------|---------|-----------|----------|
| 01_schema_changes | 2026-05-01 | 2026-05-01 | 2.5 hrs |
| 02_api_layer | 2026-05-02 | — | — |
| 03_frontend_updates | — | — | — |

## Deferred Follow-ups
- <discovered during execution>
```

### epic_review.md

Epic decomposition review findings. Contains:
- Open decisions roll-up for epic decomposition
- Open significant issues roll-up
- Per-review entries focused on workstream completeness, sequencing, and preparatory work
- Applied changes to `epic.md`
- Review summary with pass/continue status

---

### Epic approach.md

The epic-level approach defines the overall architectural strategy and is distinct from `epic.md`, which defines decomposition into child plans:

```markdown
# Approach: Auth Migration

**Created:** 2026-05-01
**Epic:** ./epic.md
**Based on:** ./findings/

## Overall Architecture

### Dual-Auth Adapter Pattern
During migration, both session-based and JWT-based auth coexist behind a
unified adapter interface. Each request is tried against JWT first, falls
back to session if no valid JWT exists.

### Migration Phases
1. Schema — new tables alongside existing (no removal yet)
2. API — new endpoints + middleware adapter
3. Frontend — new login flow behind feature flag
4. Cutover — flag to 100%, deprecation period, cleanup (future epic)

## Key Decisions

| Decision | Chosen | Rationale |
|----------|--------|----------|
| Migration strategy | Parallel run (both active) | Zero downtime, gradual rollout |
| Token storage | Database (not Redis) | Simpler ops, existing infra, acceptable latency |
| Provider abstraction | Adapter per provider | Clean separation, testable, extensible |
| Rollout mechanism | Per-user feature flag | Gradual, reversible, observable |

## What Changes vs What Stays
- **Changes:** Auth middleware, login flow, token management, user-provider model
- **Stays:** Permission/RBAC system, protected route patterns, API response shapes

## Workstream Boundaries
- Schema workstream owns the data model; API workstream consumes it read-only
- API workstream owns the middleware adapter; frontend consumes the auth endpoints
- No workstream modifies the permission system

## Risk Mitigations
- Feature flag allows instant rollback at any phase
- Dual-auth means existing sessions never break
- Each child plan includes backward-compatibility verification
```

---

## State.json

Minimal state tracking for continuation enforcement:

```json
{
  "level": "standard",
  "phase": "executing",
  "status": "active",
  "mode": "sequential | team"
}
```

### Phase Values

| Phase | Meaning |
|-------|---------|
| `draft` | Brief created, nothing else yet |
| `researching` | Research in progress |
| `researched` | Research complete |
| `designing` | Approach in progress |
| `designed` | Approach complete |
| `planning` | Plan being written |
| `planned` | Plan complete |
| `reviewing` | Plan review in progress |
| `reviewed` | Plan review complete (passed) |
| `ready` | Worklog created, ready to execute |
| `executing` | Implementation in progress |
| `reviewing_code` | Code review in progress |
| `complete` | All stages done successfully |
| `blocked` | Cannot proceed (needs human decision) |

### Status Values

| Status | Meaning |
|--------|---------|
| `active` | Currently being worked on |
| `paused` | Interrupted, can be resumed |
| `complete` | This phase/plan is done |
| `blocked` | Needs human intervention |

Team plans reuse the normal phase values and set `"mode": "team"`; they do not add
team-specific phases.

### Epic State

Epic state.json adds child plan tracking:

```json
{
  "level": "epic",
  "phase": "executing",
  "status": "active",
  "currentChild": "02_api_layer",
  "completedChildren": ["01_schema_changes"]
}
```
