# Repository Setup

This document defines what a repository needs in order to work effectively with the autonomous coding agent development process. These are prescriptive requirements — a well-set-up repo produces dramatically better results from the process.

---

## Core Principle

Agents don't need to read all documentation for every change. They need to **discover the correct information at the correct time** based on what they're doing. AGENTS.md files at different directory levels enable this progressive discovery.

---

## Required Repository Structure

### AGENTS.md (Root)

Every repository must have a root-level `AGENTS.md` that serves as the entry point for any coding agent working in the repo. It must contain or reference:

| Section | Purpose | Required |
|---------|---------|----------|
| Rules | Git practices, search tool preferences, verification policy | ✅ |
| Tech Stack | Languages, frameworks, key libraries | ✅ |
| Architecture References | Links to architecture docs | ✅ |
| Coding Rules | Links to coding standards/rules files | ✅ |
| Design Rules | Links to design principles/rules files | ✅ if UI exists |
| Test Infrastructure | Links to test architecture and commands | ✅ |
| Task Tracking | Backlog store, ID format, capture policy, lifecycle operations, source backlink format, and `Up next` lookup | ✅ for standard/epic autonomous execution; recommended for simple changes |
| Requirements | Requirements posture, store, ID format, traceability policy, test citation format, and approval boundary | ✅ if repo maintains requirements; otherwise document that it does not |
| Per-Directory Rules | Index of subdirectory AGENTS.md files | ✅ |
| Issues and Learnings | Link to issues/learnings log | Recommended |

**Key requirement:** The root AGENTS.md should tell agents *where to find* detailed information, not contain all the detailed information itself. It's a routing document.

### Per-Directory AGENTS.md Files

Directories with specialized rules should have their own AGENTS.md. The coding agent harness should automatically read these when working in those directories. Examples:

```
repo/
  AGENTS.md                          # Root — routing to all docs
  src/
    components/
      AGENTS.md                      # Component patterns, naming, structure rules
    api/
      AGENTS.md                      # API patterns, error handling, validation rules
  e2e/
    AGENTS.md                        # E2E test authoring rules, fixture patterns
  packages/
    backend/
      AGENTS.md                      # Backend-specific patterns
```

**What goes in per-directory AGENTS.md:**
- Architectural patterns specific to that directory
- Design rules applicable only to those files
- Test patterns for that type of code
- Common mistakes to avoid
- Examples of the correct pattern

---

## Required Documentation

### Architecture

A document describing the system's high-level structure. Must cover:

- System boundaries and major modules
- Core data flow
- External integrations and dependencies
- Key constraints
- How modules relate to each other

**Location:** Referenced from root AGENTS.md. Common: `docs/architecture.md` or `docs/engineering/architecture.md`

### Test Architecture / Strategy

A document defining the testing approach. Must cover:

| Content | Why agents need it |
|---------|-------------------|
| Test levels (unit, integration, e2e, etc.) | Skills reference test *types*; this defines what those types mean in this repo |
| What each level proves | Agents need to know which test type to write for which situation |
| Exact commands per test level | Plans and worklogs reference exact commands — this is the canonical source |
| When each command should be run | During TDD loops vs task completion vs final verification |
| Scope of each command | Touched-files, package-wide, or repo-wide |
| Test data / fixture strategy | Where fixtures live, how to create test data |
| Environment requirements | What needs to be running for tests to work |

**This is the most critical repo document for the process.** Skills define test *types* (unit, integration, e2e, golden). This document defines how those types map to actual commands in this repo. See [Standard Test Levels](../references/standard-test-levels.md) for the full definition of standard levels that repos must map to.

**Location:** Referenced from root AGENTS.md. Common: `docs/engineering/test_architecture.md` or `docs/testing-strategy.md`

### Coding Rules

Standards and patterns that apply across the codebase:

- Naming conventions
- Error handling patterns
- Import organization
- Common anti-patterns to avoid
- Language-specific idioms

**Location:** Referenced from root AGENTS.md.

### Task Tracking / Backlog

A document or AGENTS.md section defining how the repo tracks work outside the current plan. It must map the process-level task-tracking hooks from [Task Tracking](./references/task-tracking.md) to repo-specific operations.

At minimum, document:

| Content | Why agents need it |
|---------|-------------------|
| Backlog store | Where captured follow-ups are written |
| Stable ID format | How worklogs/reviews reference items durably |
| Create-item procedure | How an agent records accepted follow-up work |
| Reference format | How worklogs, reviews, TODOs, commits, and summaries cite items |
| Source backlink format | How the created item points back to the plan/worklog/review that produced it |
| `Inbox` / untriaged lookup | How agents find captured work needing triage |
| `Up next` lookup | How agents find human-approved next work |
| Lifecycle transitions | How to mark ready, done, canceled, deferred/iceboxed, or blocked |
| Agent capture policy | Whether agents ask before creating items or have pre-authorization |
| Critical/blocking policy | When agents must stop instead of silently backlogging |
| Tool/auth/fallback | Required CLI/auth/project access and what to do if unavailable |

Small repos can use a single `docs/backlog.md`. Larger repos can use GitHub Issues + Projects or another tracker. Without these hooks, standard/epic autonomous execution runs in a degraded mode where agents must stop and ask instead of durably capturing accepted follow-up work.

**Location:** Referenced from root AGENTS.md. Common: `docs/backlog.md`, `docs/task-tracking.md`, or `docs/engineering/software_development_process.md`.

### Requirements Handling

If the repo maintains requirements, document how the repo maps the process-level requirements hooks from [Requirements Handling](./references/requirements.md) to repo-specific files, commands, and approval policy.

At minimum, document:

| Content | Why agents need it |
|---------|-------------------|
| Requirements posture | Whether the repo maintains requirements, explicitly does not, is unclear, or likely needs them |
| Requirements store | Where current durable requirements live |
| Actor/persona definitions | How agents find who the system serves |
| Use case definitions | How agents find durable user/system goals |
| Workflow/scenario definitions | How agents find concrete flows and alternate paths |
| Functional requirements | Where required behaviors/capabilities are defined |
| Non-functional requirements | Where quality constraints are defined |
| Operational requirements | Where deploy/operate/support constraints are defined |
| Stable ID format | How briefs/plans/tests/reviews cite requirements durably |
| Test citation format | How tests cite the requirements they verify |
| Traceability rules | Which links are manually maintained and in which direction |
| Apply approved changes | How execution updates canonical requirements after approval |
| Retire/replace requirements | How durable requirements are removed, replaced, or materially changed |
| Approval boundary | When agents must ask before changing canonical requirements |
| Validation/query commands | Any read-only commands or reports, if available |
| Tool/auth/fallback | Required CLI/auth access and what to do if unavailable |

The root `AGENTS.md` should usually contain only a routing blurb:

```markdown
## Requirements
- Posture: maintains requirements
- System: Markdown requirements in `docs/requirements.md`
- Stable IDs: `ACT-001`, `UC-001`, `WF-001`, `FR-001`, `NFR-001`, `OPR-001`
- Tests cite requirements they verify using `Requirement: FR-001`
- Draft requirement changes live in plan artifacts until approved
- Canonical requirement edits require human approval unless explicitly delegated
```

Small repos can use a single `docs/requirements.md`. Larger repos can use a requirements CLI, generated reports, product docs, or another durable system.

### Design Rules (if UI exists)

Standards for UI implementation:

- Component patterns
- Styling approach (theme, spacing, colors)
- Accessibility requirements
- Responsive behavior rules
- State management patterns

**Location:** Referenced from root AGENTS.md.

---

## Recommended Documentation

### Tech Stack LLM Instruction Files

Framework-specific rule files that agents should read before making changes in those areas:

- `convex_rules.txt` — Backend data layer rules
- `sveltekit_rules.txt` — Frontend framework rules
- `react_rules.txt` — React patterns
- etc.

These are typically placed in a `.llm/` directory or similar, and referenced from AGENTS.md with guidance on when to read them (e.g., "read before making any backend changes").

### Architecture Decision Records (ADRs)

Documented decisions about why things are the way they are. Critical for agents to understand constraints and avoid re-litigating settled decisions.

### Issues and Learnings Log

A running list of:
- Bugs encountered and their resolutions
- Documentation deficiencies discovered
- Patterns that don't work as expected
- Recurring mistakes and their prevention

Agents should add entries when they discover issues during execution.

---

## Verification Command Documentation

The process depends heavily on knowing the exact verification commands for a repository. These must be documented explicitly.

### Required Command Categories

| Category | Example | Used when |
|----------|---------|-----------|
| Fast feedback | `pnpm test -- --filter=<file>` | During TDD loops (rapid iteration) |
| Type check | `pnpm typecheck` | After any code change (catches cross-module issues) |
| Lint | `pnpm lint` | Before task completion |
| Unit tests | `pnpm test` | Per-task verification |
| Integration tests | `pnpm test:integration` | When integration points change |
| E2E tests | `pnpm test:e2e` | When user-facing behavior changes |
| Build | `pnpm build` | Before final completion |
| Full verification | `pnpm verify` (or equivalent) | Before marking plan complete |

### Command Documentation Format

For each command, document:

```markdown
### <Command Name>

**Command:** `<exact command>`
**Scope:** touched-files | package-wide | repo-wide
**When to run:** during TDD loops | before task completion | before plan completion
**What it catches:** <specific failure modes this command detects>
**Prerequisites:** <services that must be running, env vars needed>
**Expected baseline:** pass | known failures (list)
```

### Why This Matters

The skills define that you should "run the task completion gate" or "run fast feedback during TDD." The repo docs define what those commands actually ARE. Without this documentation:
- Agents guess at commands (often wrong)
- Plans include placeholder commands
- Verification is inconsistent or incomplete

---

## Plans Directory

The repo needs a designated location for engineering plans:

```
plans/                    # or docs/engineering/plans/
  README.md              # Optional: guidance for plan creation in this repo
  2026_05_01_feature_x/
  2026_05_02_bug_fix_y/
```

### Plans README (Recommended)

A README in the plans directory can provide repo-specific planning guidance:
- Where to find verification commands
- Repo-specific constraints on plans
- Links to architecture and testing docs
- Any repo-specific plan conventions

---

## Comprehensive Repository Layout Example

This is an example of a well-structured repository that works optimally with the autonomous development process. Not every repo needs all of these, but this represents what a mature setup looks like:

```
repo/
├── README.md                              # What this is, who it's for, how to start
├── AGENTS.md                              # Root routing doc (see below)
├── CONTRIBUTING.md                        # How to contribute, PR workflow
├── .pi/
│   └── settings.json                      # Agent model overrides (subagents.agentOverrides)
├── .llm/                                  # Tech stack instruction files
│   ├── sveltekit_rules.txt                # Framework-specific rules
│   ├── convex_rules.txt                   # Backend rules
│   └── tailwind_patterns.txt              # Styling patterns
├── docs/
│   ├── architecture.md                    # System boundaries, modules, data flow
│   ├── backlog.md                         # Simple Markdown backlog (or task-tracking doc)
│   ├── requirements.md                    # Simple Markdown requirements (if repo maintains requirements)
│   ├── glossary.md                        # Domain language and terms
│   ├── getting_started.md                 # Environment bootstrap for agents/devs
│   ├── engineering/
│   │   ├── coding_rules.md                # Naming, error handling, patterns
│   │   ├── design_principles.md           # Design philosophy and approach
│   │   ├── design_rules.md                # Theme, spacing, components, accessibility
│   │   ├── test_architecture.md           # Test levels, commands, fixtures, scope
│   │   ├── issues_learnings.md            # Running log of issues and resolutions
│   │   ├── maintenance.md                 # Routine maintenance procedures
│   │   └── adr/                           # Architecture Decision Records
│   │       ├── README.md                  # ADR index
│   │       ├── 0001-foundation.md         # Initial architecture decisions
│   │       └── 0002-auth-approach.md      # Auth architecture decision
│   ├── product/
│   │   ├── requirements.md                # Tagged requirements (FR-001, etc.)
│   │   ├── user_workflows/                # User workflow docs
│   │   │   ├── README.md                  # Workflow index
│   │   │   ├── auth_workflow.md           # Target-state workflow
│   │   │   └── auth_workflow_details.md   # Step-by-step operational detail
│   │   └── routes/                        # Per-route UI documentation
│   │       └── dashboard.md
│   └── operations/
│       ├── deployment.md                  # How to deploy
│       └── monitoring.md                  # Observability and alerts
├── plans/                                 # Engineering plans directory
│   ├── README.md                          # Repo-specific planning guidance
│   ├── 2026_05_01_add_notifications/       # Standard plan
│   └── 2026_05_01_auth_migration/          # Epic plan
├── src/
│   ├── AGENTS.md                          # Source-level patterns (optional)
│   ├── components/
│   │   └── AGENTS.md                      # Component patterns, naming, structure
│   ├── api/
│   │   └── AGENTS.md                      # API patterns, error handling, validation
│   ├── lib/
│   │   └── AGENTS.md                      # Shared library rules
│   └── stores/
│       └── AGENTS.md                      # State management patterns
├── packages/                              # Monorepo packages (if applicable)
│   ├── backend/
│   │   └── AGENTS.md                      # Backend-specific patterns
│   └── shared/
│       └── AGENTS.md                      # Shared package rules
├── e2e/
│   ├── AGENTS.md                          # E2E test authoring rules, fixture patterns
│   └── fixtures/
│       └── README.md                      # How fixtures work, how to add new ones
└── tests/
    └── AGENTS.md                          # Unit/integration test patterns
```

### What Each AGENTS.md Level Contains

**Root AGENTS.md** (routing):
```markdown
# Project Agent Guide

## Rules
- Git practices, verification policy

## Tech Stack
- Languages, frameworks, key libraries

## LLM Instruction Files
- `.llm/sveltekit_rules.txt` — read before frontend changes
- `.llm/convex_rules.txt` — read before backend changes

## Architecture
- `docs/architecture.md`

## Test Infrastructure
- `docs/engineering/test_architecture.md`

## Task Tracking
- Backlog: `docs/backlog.md`
- New agent-discovered follow-ups: add to `Inbox`
- Stable IDs: `TASK-0001`
- Up next: items under `## Up next`
- Critical items: stop and ask before continuing current-plan execution

## Requirements
- Posture: maintains requirements
- Requirements: `docs/requirements.md`
- Stable IDs: `ACT-001`, `UC-001`, `WF-001`, `FR-001`, `NFR-001`, `OPR-001`
- Tests cite requirements they verify using `Requirement: FR-001`
- Draft requirement changes live in plan artifacts until approved
- Canonical requirement edits require human approval unless explicitly delegated

## Coding Rules
- `docs/engineering/coding_rules.md`

## Design Rules
- `docs/engineering/design_principles.md`
- `docs/engineering/design_rules.md`

## Per-Directory Rules
- `src/components/AGENTS.md`
- `src/api/AGENTS.md`
- `e2e/AGENTS.md`
- `packages/backend/AGENTS.md`

## Issues and Learnings
- `docs/engineering/issues_learnings.md`
```

**Per-directory AGENTS.md** (specific rules):
```markdown
# E2E Test Rules

## Patterns
- Always use page objects from `./fixtures/pages/`
- Never use raw selectors in test files
- Each test must be independent (no shared state between tests)

## Fixture Data
- Seed data lives in `./fixtures/seed/`
- Use `resetDB()` helper before each test suite

## Common Mistakes
- Don't await navigation implicitly; use `waitForURL()`
- Don't assert on text that comes from i18n (use data-testid)
```

---

## Minimum Viable Setup

At minimum, a repo needs:

1. **Root AGENTS.md** with tech stack, architecture link, and verification commands
2. **Test documentation** with exact commands, their scope, and when to use them
3. **A plans directory** for plan artifacts

This is enough for the process to function for one-off/simple plans. Standard and epic autonomous execution also need task-tracking/backlog documentation so accepted follow-up work is durably captured instead of lost in chat.

The experience improves significantly with:
- Per-directory AGENTS.md files
- Architecture documentation
- Coding/design rules
- Tech stack instruction files
- ADRs
- Requirements handling documentation when the repo maintains durable requirements

---

## Setup Checklist

Use this checklist when preparing a repository for autonomous coding agent work:

### Essential (process won't work well without these)
- [ ] Root AGENTS.md exists with tech stack and doc references
- [ ] Test architecture document exists with exact commands, scope, and timing
- [ ] Plans directory exists
- [ ] Build/test/lint commands are documented and runnable
- [ ] For standard/epic autonomous execution: task-tracking/backlog mechanism documents all required hooks, including stable IDs, create-item procedure, reference format, source backlink format, lifecycle transitions, `Inbox`, `Up next`, agent capture policy, and critical/blocking policy

### Important (significantly improves results)
- [ ] Architecture document describes system boundaries and module relationships
- [ ] Coding rules document defines patterns and standards
- [ ] Per-directory AGENTS.md files exist for specialized areas (e2e, components, API, etc.)
- [ ] Verification commands include scope labels (touched-files, package-wide, repo-wide)
- [ ] Environment setup is documented (services, env vars, prerequisites)
- [ ] Requirements posture is documented; if the repo maintains requirements, all required requirements hooks are mapped, including test citation format, approved-change procedure, retire/replace procedure, validation/query commands, and approval boundary
- [ ] Tool-backed backlog/requirements systems document auth/access prerequisites, read-only vs mutating commands, and fallback procedures

### Recommended (further improves quality and reduces rework)
- [ ] Tech stack LLM instruction files (framework-specific rules)
- [ ] Design rules for UI components
- [ ] Architecture Decision Records (ADRs) for non-obvious choices
- [ ] Issues and learnings log
- [ ] Plans README with repo-specific guidance
- [ ] Getting started guide (for agent environment bootstrapping)

---

## How Skills Reference Repo Documentation

The separation of concerns between skills and repo docs works like this:

| Skills define (process-level) | Repo docs define (repo-specific) |
|-------------------------------|----------------------------------|
| "Write a unit test" | What test framework, where tests live, how to run them |
| "Run the task completion gate" | What the exact command is and what scope it covers |
| "Follow the existing pattern" | What the existing pattern actually is |
| "Update relevant documentation" | Where the relevant documentation lives |
| "Run fast feedback" | Which specific command gives fast feedback |
| "Check types" | What typecheck command exists and its scope |
| "Verify E2E behavior" | How to run E2E tests, what fixtures to use |
| "Capture a follow-up" | Where backlog items live, how IDs are assigned, how to create items, how to capture source backlinks, and how to list `Up next` |

Skills are technology-agnostic and reusable. Repo docs are the concrete implementation of those abstract process concepts.

---

## Anti-Patterns

### ❌ All rules in root AGENTS.md
Don't put everything in one file. Agents read the root AGENTS.md on every interaction — it should route, not contain.

### ❌ Verification commands only in package.json
Commands exist in package.json/Makefile/etc., but agents need to know *when* to run them and *what scope* they cover. That context belongs in documentation.

### ❌ Undocumented test infrastructure
If running tests requires starting services, setting env vars, or running migrations first, and that's not documented, agents will waste cycles or produce broken plans.

### ❌ Architecture only in developers' heads
If "everyone knows" the auth module doesn't import from the UI layer, but it's not written down, agents will violate that boundary.

### ❌ No issues/learnings feedback loop
Without a place to record discovered problems, the same mistakes repeat across plans. The issues log is how institutional knowledge accumulates.
