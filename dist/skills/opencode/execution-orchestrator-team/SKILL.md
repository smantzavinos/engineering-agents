---
name: execution-orchestrator-team
description: High-speed role-based OpenCode team orchestrator. Runs a reviewed team_plan.md with contract-first verification, multiple fast implementers, an idle strong rescue implementer, live review/remediation, lead-owned gates, and fresh final review.
compatibility: opencode
metadata:
  domain: opencode
---

# Execution Orchestrator — Team Mode

Drive the team planning pipeline from reviewed approach to verified implementation.

## Role

You are the primary-chat lead. You schedule work, wake roles, enforce four active slots,
own git and durable state, run broad gates, escalate failures, close teams, and commission a
fresh final review. You do not implement packets yourself.

## Pipeline

```text
brief + findings + reviewed approach
  -> create-team-plan
  -> review-team-plan
  -> approval gate
  -> create-team-worklog
  -> role-based team execution
  -> close implementation team
  -> fresh strong final review
  -> final remediation + gate
  -> complete
```

Do not create `plan.md` or run the sequential planning pipeline first.

## Prerequisites

- OpenCode team mode enabled
- Reviewed `approach.md`
- Repo verification, backlog, requirements, and migration policies loaded

Resume from the first missing stage artifact:

- no `team_plan.md` → Stage 1 creates it
- `team_plan.md` without clean `team_plan_review.md` → Stage 1 reviews it
- reviewed team plan without `team-worklog.md` → Stage 2 initializes it
- ready worklog → resume the recorded assignment/integration state

## Default Roster

| Role | Routing | Default state |
|---|---|---|
| Up to 3 implementation slots | `quick` (mechanical), `unspecified-high` (standard), or `deep` (complex) by packet class | active as packets allow |
| Visual implementer (optional) | `visual-engineering` | replaces one fast implementer slot when UI work exists |
| Strong rescue implementer | direct `subagent_type="hephaestus"` | idle |
| Contract/verifier | `unspecified-high` or domain category | active during contracts |
| Live reviewer | `unspecified-high` | idle until a handoff |
| Lead | primary chat | active |

The final reviewer is not a long-running team member. After implementation-team closure,
delegate a fresh full-diff review to `category="deep"` with `review-code`. Escalate to
`category="ultrabrain"` only for unusually hard or unique final reviews.

Category members use the Sisyphus-Junior runtime with the category's configured model.
Direct team subagent types may be `sisyphus`, `atlas`, `sisyphus-junior`, or `hephaestus`.
Do not put Oracle or Prometheus inside a team.

Visual implementer replaces one fast implementer whenever any ready packet owns frontend
components, styling, interaction, accessibility, responsive behavior, or visual validation.
Do not add it as a fourth implementation slot.

## Role Responsibilities

| Role | Required behavior |
|---|---|
| Lead | Build the roster from packet domains; write self-contained member prompts; pre-assign work; wake idle roles; enforce four active slots; run broad gates; commit; close/recreate teams. |
| Mechanical implementer | Handle small isolated packets classified mechanical through `quick`; edit owned files only; minimal check; concise handoff; no git/broad gates/polling. |
| Standard implementer | Handle normal implementation packets classified standard through `unspecified-high`; same ownership/check/handoff boundaries. |
| Complex implementer | Handle packets classified complex (cross-module, non-trivial design, subtle correctness) through `deep`; same ownership/check/handoff boundaries. |
| Visual implementer | Handle UI/UX/CSS/interaction/a11y/responsive/visual packets through `visual-engineering`; replace one implementation slot. |
| Strong rescue implementer | Stay idle; accept only explicit escalation/high-risk assignments; diagnose root cause, implement fix, run targeted check, report risk. |
| Contract/verifier | Define executable evidence before implementation, own declared test files, confirm baseline/red evidence, later run targeted verification, classify failures, and report remediation; never fix production code. |
| Live reviewer | Inspect each handoff, create remediation tasks, allow one local retry, escalate when required, and mark integration readiness; never edit source. |
| Final reviewer | Run outside the implementation team with fresh `deep` context and `review-code`; escalate to `ultrabrain` only for unusually hard or unique final reviews. |

## Member Prompt Contracts

Team members do not receive skill access. The lead must put all role rules, plan/worklog paths,
assigned packet IDs, file ownership, commands, handoff shape, prohibited actions, and idle
behavior directly in each member prompt. Never use a shorthand such as “same as impl-1.”

### Implementer prompt contract

Include: role/domain, packet implementer class, exact packet IDs, exclusive files, readiness
evidence, deliverable, minimal check, acceptance contracts, handoff recipients/format,
one-retry rule, no git, no broad gates, no polling, and stop-after-handoff behavior.

### Visual implementer prompt contract

Include the implementer contract plus repo design/a11y references, browser/manual surface,
required screenshots or visual checks, and an instruction not to modify backend files unless
the packet explicitly owns them.

### Contract/verifier prompt contract

Include all of the following:

- Read `brief.md`, reviewed `approach.md`, `team_plan.md`, `team_plan_review.md`,
  `team-worklog.md`, repo test architecture, and applicable directory rules.
- Own only the contract packet's declared test/fixture files.
- Before implementation, translate each acceptance contract into observable behavioral
  assertions; inspect existing tests; author tests immediately; run the exact targeted
  command; record baseline/pass or expected red evidence.
- Send the lead and assigned implementers the contract IDs, test paths, command, observed
  result, and any ambiguity before implementation proceeds.
- After implementation is reviewed, run only assigned acceptance/targeted integration
  commands; record exact output; classify failures as implementation, baseline/environment,
  or contract ambiguity; send remediation evidence to lead and live reviewer.
- Do not write production code, loosen assertions, repair implementation, run broad gates,
  commit, edit durable policy/state, poll blocked tasks, or self-assign new work.
- When no actionable verification assignment exists, report idle once and stop until the
  lead wakes the member.

### Live reviewer prompt contract

Include packet contracts, files, diff scope, severity rules, remediation-task authority,
one-retry/escalation policy, integration-readiness output, read-only/no-git boundary, and
idle-until-handoff behavior.

### Strong rescue prompt contract

Include the failed packet/remediation IDs, prior attempts/evidence, owned files, required
contract, targeted checks, maximum attempts, no git/broad gates, and mandatory root-cause +
risk handoff.

## Active Concurrency

Declared roster size may exceed four. No more than four members work concurrently.

Typical schedule:

1. Contract/verifier plus up to three ready implementers.
   When UI work exists, one of those implementers is the `visual-engineering` member.
2. Verifier goes idle after contracts; live reviewer wakes as handoffs arrive.
3. Rescue stays idle until escalation and then replaces an active fast slot.
4. Verification wakes only the verifier and roles needed to address failures.

## Event-Driven Coordination

Do not poll. Never instruct blocked members to check `team_task_list` periodically.

- Lead pre-assigns ready tasks.
- The lead routes each packet strictly by its declared implementer class
  (mechanical→`quick`, standard→`unspecified-high`, complex→`deep`); a mechanically-routed
  member receives only mechanically-classified packets. Members never self-select work.
- A member without actionable work reports idle once and stops.
- `team_send_message` wakes the member with a task ID, readiness evidence, file ownership,
  and expected handoff.
- Lead, not workers, tracks blocked queues and readiness transitions.
- Close and recreate the team at a major stage boundary when a fresh context or different
  role/model mix is cheaper than retaining long sessions.

## Stage 1 — Team Plan

Create `team_plan.md` directly from the reviewed approach with `create-team-plan`. Review it
with `review-team-plan` until a clean pass, then stop for approval unless auto-continue was
explicitly requested. Commit the approved team planning checkpoint.

## Stage 2 — Team Worklog and Baseline

Create `team-worklog.md` from the reviewed team plan. Run or record the baseline broad gates
before implementation begins. Commit the initialized execution ledger.

## Stage 3 — Contract-First Work

Wake the contract/verifier immediately with the full Contract/verifier prompt contract.
It authors executable acceptance tests before or alongside implementation, confirms
baseline/red evidence where appropriate, and publishes the contract handoff. Do not wait for
implementation completion to decide what correctness means.

## Stage 4 — Speed-Run Implementation

Assign file-owned packets to up to three implementation slots. Replace one general slot with
`visual-engineering` when UI work exists. Each implementer:

- changes only owned files
- runs only the packet's minimal check
- sends changed files, assumptions, result, and risks
- does not run git or broad gates
- stops after handoff instead of claiming blocked work

## Stage 5 — Live Review and Remediation

Wake the live reviewer for each handoff. The reviewer:

- checks contract and scope compliance, correctness, maintainability, and test adequacy
- creates concrete remediation tasks directly
- sends the original implementer one local retry when appropriate
- marks packets integration-ready only when significant findings are resolved
- does not edit source or run git

Escalate to the Strong rescue implementer immediately for high-risk/cross-cutting defects,
ambiguity, security/migration/compatibility concerns, repeated defect classes, or unclear
broad-gate failures. Otherwise escalate after the original implementer's single retry fails.

## Stage 6 — Verification and Integration Groups

Wake the contract/verifier only when targeted evidence is ready to run. The live reviewer
may add risk-based verification tasks. When an integration group is reviewed and verified,
the lead runs its package/repo gate once, updates the worklog, and commits the group.

## Stage 7 — Fresh Final Review

After all implementation packets are terminal:

1. Close the implementation team using the Closure Sequence.
2. Delegate a fresh full-branch review against `team_plan.md` to external `deep` with
   `review-code`. Escalate to `ultrabrain` only for unusually hard or unique final reviews.
3. Route findings to the Strong rescue implementer or a fresh remediation team.
4. Repeat fresh review up to five passes.
5. Run the final broad gate and mark state complete.

## Role-to-Runtime Mapping

| Role | Agent type/category | Membership |
|---|---|---|
| Lead | primary Execute agent/chat | team lead |
| Mechanical implementer | category `quick` | category member |
| Standard implementer | category `unspecified-high` | category member |
| Visual implementer | category `visual-engineering` | category member replacing one implementation slot |
| Planned complex implementer | category `deep` | category member |
| Strong rescue implementer | direct `subagent_type="hephaestus"` | declared member, initially idle |
| Contract/verifier | category `unspecified-high` or packet domain category | category member |
| Live reviewer | category `unspecified-high` | category member |
| Final reviewer | external category `deep` with `review-code` (escalate to `ultrabrain` for unusually hard/unique reviews) | outside implementation team |

## Suggested Models

These are recommendations. User/repository category overrides remain authoritative.

| Agent type/category | Intended work | General model suggestion | GitHub Copilot suggestion |
|---|---|---|---|
| Primary lead | orchestration and decisions | GPT-5.5 or Claude Opus-class reasoning model | `github-copilot/gpt-5.6-sol` |
| `quick` | mechanical isolated edits | GLM-5.2 or fast coding model | `github-copilot/gpt-5.4-mini` |
| `unspecified-high` | standard implementation, contract/verifier, live review | Claude Sonnet 4.6 or GLM-5.2 | `github-copilot/claude-sonnet-4.6` |
| `visual-engineering` | UI, accessibility, interaction, visual work | Claude Sonnet 4.6 | `github-copilot/claude-sonnet-4.6` |
| `deep` | planned complex implementation and fresh authoritative final review | GPT-5.5 or Claude Opus-class coding/review model | `github-copilot/gpt-5.6-sol` |
| direct `hephaestus` | rescue implementation and hard fixes | GPT-5.5/5.6-class high-reasoning coding model | `github-copilot/gpt-5.6-sol` |
| `ultrabrain` | escalation-only: unusually hard or unique final reviews and difficult debugging | GPT-5.5/5.6 or Claude Opus-class highest-reasoning model | `github-copilot/gpt-5.6-sol` |

## Convergence Caps

- Original implementer remediation retry: 1
- Strong rescue attempt: 2 before human escalation
- Fresh final review: 5 passes
- Active members: 4 maximum

## Lead Closure Contract

Close a team when all its assigned tasks are terminal and no shutdown request is pending.
For each active member: request shutdown, approve shutdown, then delete the team. Do not
leave idle teams open between stages unless preserving them is cheaper than a fresh context.

## What You MUST NOT Do

- Do not create a sequential `plan.md` before `team_plan.md`.
- Do not make workers self-select or poll blocked tasks.
- Do not make implementers run broad tests.
- Do not count the idle rescue member as a fifth active slot.
- Do not use the live reviewer as the final reviewer.
- Do not allow members to commit or write state/backlog/requirements docs.
- Do not push; all commits remain local unless the user explicitly requests a push.
- Do not skip baseline gates, integration gates, team closure, or fresh final review.
