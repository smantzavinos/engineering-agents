---
name: create-new-repo-docs
description: "Bootstrap a new repository by creating a durable documentation foundation: README, architecture, requirements, testing strategy, ADRs, and user workflow docs. Use this for greenfield repos when you want to define the project through core documents instead of a speculative implementation plan."
compatibility: pi
---

## What I do
- Create a documentation foundation for a brand new repository.
- Prefer durable source-of-truth docs over a speculative implementation plan.
- Create strong, cross-linked templates for:
  - `README.md`
  - `CONTRIBUTING.md`
  - `ROADMAP.md`
  - `docs/architecture.md`
  - `docs/glossary.md`
  - `docs/requirements.md`
  - `docs/testing-strategy.md`
  - `docs/workflows/README.md`
  - one or more workflow overview + workflow-details docs
  - `docs/adr/0001-foundation.md`
- Capture:
  - who the key users/personas are
  - what those users are trying to accomplish
  - the intended user workflows for using the project
  - major architectural boundaries and core concepts
  - tagged requirements that can be verified later
  - the testing approach, test levels, tools, and verification commands
- Use the templates in `templates/` in this skill directory as starting points, then adapt them to the project rather than copying them blindly.

## When to use me
Use this when:
- you are starting a new repo from scratch
- you want to define the project through core documentation first
- you need clarity on users, workflows, architecture, requirements, and testing before or alongside implementation
- the first durable deliverables should be docs, not a large phased execution plan

Do NOT use this when:
- you are planning changes in an existing repo
- you need a change plan for already-existing code (`create-plan`)
- you explicitly need a charter-style greenfield execution plan with phases/tasks (`create-new-repo-project-plan`)
- you only want a single document rather than a repo doc foundation

## Greenfield Doc-First Rule (MANDATORY)
For most new repos, I SHOULD create the core documentation set directly instead of creating a large execution plan.

If the user asks for a new repo plan, I SHOULD first check whether they actually want:
- foundational repo docs (`README`, architecture, requirements, workflows, testing strategy), or
- a charter/phased project plan

If they mostly want the foundational docs, I MUST use this skill.
If they explicitly want milestone sequencing / approval / phased execution tracking, I MAY use `create-new-repo-project-plan` instead.

## Clarification Gate (MANDATORY)
Before writing files, I MUST ask any clarifying questions needed to avoid wrong scope, vague personas, missing workflows, or incorrect output location.

If critical inputs are missing, I must respond in this format and wait for confirmation:

**What I understood:** <1-3 bullets>

**What I'm unsure about:** <specific unknowns>

**Questions:**
- <question 1>
- <question 2>

**If you want me to proceed with assumptions:** say "Proceed with assumptions." I will then:
- record assumptions explicitly in the relevant docs
- flag risky assumptions in open questions / architecture notes / testing notes as appropriate

## Research Gate (opt-in; ask first)
If background research would materially improve the docs (e.g. prior art, comparable tools, competing UX patterns, tech constraints, naming conventions, testing approaches), I MUST:
1) propose specific research topics and what I expect to learn, and
2) ask the user to confirm before doing the research.

MUST NOT: start research without explicit user confirmation.

## What I need
Ask for any missing info before writing (skip only if already provided):
- repo/project name
- repo root or destination directory
- project type (CLI, library, service, web app, TUI, etc.)
- primary users/personas
- top user goals / jobs-to-be-done
- key workflows to document
- current scope target:
  - target-state vision
  - MVP scope
  - current delivery slice
- constraints (stack, platform, compliance, offline/online, integration, budget/time)
- preferred testing tools/frameworks
- required docs beyond the default set, if any
- whether any docs should be omitted from the default set
- whether the repo already exists on disk

If the repo does not exist yet, I MUST require an explicit destination directory or future repo root path. I MUST NOT silently treat the current working directory as the future repo root without confirmation.

## Default output set
Unless the user requests otherwise, create:

- `README.md`
- `CONTRIBUTING.md`
- `ROADMAP.md`
- `docs/architecture.md`
- `docs/glossary.md`
- `docs/requirements.md`
- `docs/testing-strategy.md`
- `docs/workflows/README.md`
- `docs/workflows/<workflow>_user_workflow.md`
- `docs/workflows/<workflow>_user_workflow_details.md`
- `docs/adr/0001-foundation.md`

Add optional docs when relevant:
- `docs/api.md`
- `docs/security.md`
- `docs/operations.md`
- `docs/release.md`

## Documentation rules (MANDATORY)

### Cross-linking
The generated docs MUST reference each other clearly.

At minimum:
- `README.md` links to architecture, requirements, testing strategy, workflows, and ADRs.
- workflow docs link back to the workflow index and related docs.
- requirements link to workflows and testing strategy where relevant.
- testing strategy links back to requirements.
- architecture links to glossary and ADRs.

### README
The README must clearly explain:
- what the project is
- who it is for
- why it exists
- how to get started
- primary usage workflow(s)
- current status / maturity
- key commands (or planned commands if not implemented yet)
- where deeper docs live

### Architecture doc
The architecture doc must cover:
- system context
- major modules/boundaries
- core data flow
- external integrations
- major constraints
- operational assumptions
- key decisions and tradeoffs
- which user workflows drive the design

### Requirements doc
The requirements doc must use stable requirement IDs.

It must include:
- personas / user types
- workflow requirements
- functional requirements
- non-functional requirements
- operational/support requirements when relevant
- acceptance criteria
- a verification column mapping each requirement to planned tests or checks

Preferred requirement IDs:
- `PERS-001`
- `WF-001`
- `FR-001`
- `NFR-001`
- `OPS-001`

### Testing strategy doc
The testing strategy doc must explicitly define:
- test levels
- what each level is meant to prove
- tools/frameworks used
- exact commands, when known
- requirement coverage / traceability
- any manual verification required
- how docs/examples are kept honest

At minimum, consider:
- unit tests
- integration tests
- end-to-end tests
- contract/golden tests (when relevant)
- docs validation
- manual verification

### User workflow docs
Workflow docs are REQUIRED for any repo with non-trivial user interactions.

They should be written from the user’s point of view and must capture:
- key users/personas
- target-state workflow intent
- what the user does
- in what order they do it
- which surfaces/interfaces are involved
- which questions the project should help the user answer

For each major workflow, create two docs:

1. `<workflow>_user_workflow.md`
   - target-state workflow overview
   - audience, persona, purpose, scope
   - why the doc exists
   - interaction model
   - high-level journey
   - core concepts/naming
   - end-to-end workflow table
   - surface model
   - intended user experience
   - key user questions
   - open questions
   - relationship to other docs

2. `<workflow>_user_workflow_details.md`
   - step-by-step operational detail
   - primary surface
   - supporting surfaces
   - context the system should already know
   - data visible to the user
   - local actions available
   - conversational/assistant actions available (if applicable)
   - exact user action pattern
   - result / exit condition
   - handoff into the next step/workflow

These workflow docs are target-state references, not implementation plans or gap trackers.

### ADRs
At least one ADR should capture the initial repo foundation decisions, such as:
- product shape
- architecture style
- stack/tooling defaults
- documentation approach
- testing approach

## Template usage (MANDATORY)
This skill ships with templates under `templates/`.

I MUST:
- use those templates as the default starting point
- adapt them to the project
- remove sections that are truly not applicable
- mark inapplicable required sections as `N/A — <reason>`

I MUST NOT:
- leave raw placeholder tokens like `<...>` or `[TBD]` in final generated docs
- create docs that are not cross-linked
- omit primary personas or intended workflows
- define requirements without a verification approach
- define test levels without naming tools when those tools are already known

## Quality bar (MANDATORY)
The generated docs should be strong enough that a new contributor can answer:
- What is this project?
- Who is it for?
- What are the main user workflows?
- What must the project do?
- How will we know it is done?
- How will we test it?
- Where do the major architectural decisions live?

## Non-goals
- I do not create a speculative implementation plan by default.
- I do not modify source code unless the user explicitly asks.
- I do not assume the product has only one user persona.
- I do not invent stack/tooling choices when the user wants them decided explicitly.
- I do not write final docs with unresolved placeholders.

## Examples
Prompt:
"Create the initial docs for a new repo for a CLI tool used by release engineers. Primary workflows are scanning a repo, reviewing findings, and exporting a report. Use Vitest and Playwright."

Expected:
- Core repo docs are created under the target repo root.
- Workflow docs are created for the major user journeys.
- Requirements use stable tags.
- Testing strategy maps those requirements to unit/integration/E2E coverage.
- README links to the deeper docs.

Prompt:
"Bootstrap a new service repo with docs first. I want README, architecture, requirements, testing strategy, and workflow docs for the operator and API consumer personas."

Expected:
- The requested docs are created.
- Personas and workflows are explicit.
- Requirements and testing are linked.
- No large phased implementation plan is produced unless the user explicitly asks for one.
