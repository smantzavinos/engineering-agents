**Type:** standard
**Created:** 2026-05-19
**Owner:** pi discovery agent

## Goals
- [ ] End users running pi installed via this repo receive a startup-time warning when one or more installed plugins are out of date.
- [ ] The startup warning is non-blocking and does not prevent normal pi startup.
- [ ] The warning covers all supported plugin install types used by this repo, including git-based installs.
- [ ] The warning distinguishes confirmed stale plugins from plugins whose update status could not be determined.
- [ ] The warning tells users what action to take next using the repo's existing update/check workflow.

## Non-Goals
- Changing the plugin update or install pipeline.
- Implementing auto-update behavior.
- Redesigning broader plugin or extension management UX.
- Performing broader wrapper architecture cleanup beyond what is needed to restore user-visible stale-plugin notification.

## Constraints
- The solution must be implemented within this repo/wrapper and must not require pi core changes.
- Scope is limited to detection and startup-time notification only.
- Startup must never be blocked by stale-plugin checks or by failures while determining plugin status.
- Git-based installs are considered stale if upstream has advanced, even when the installed ref/tag is pinned.
- Notification behavior should align with the repo's manual update-check semantics so users do not receive contradictory results.

## Motivation
The wrapper around extensions configured in this repo prevents pi from surfacing its normal out-of-date extension warnings. As a result, end users can run pi without realizing their installed plugins are stale and need updating. The repo already has a manual update-check script, but it does not fully cover git-based installs, so it does not restore the lost startup-time visibility. This work matters now because users need timely, in-context awareness of stale plugins during normal pi startup, without requiring them to remember a separate maintenance command.

## Success Criteria
This work is successful when:
- A user starting pi through this repo receives a visible startup warning whenever one or more installed plugins are determined to be out of date.
- Git-based installs that are behind upstream are included in that warning behavior.
- If some plugins cannot be checked, pi still starts and the warning clearly distinguishes "out of date" from "could not determine status."
- No update/install workflow changes are required to deliver the notification.
- Startup warning behavior is verified for the supported plugin install types used by this repo.

## Requirement Context

Relevant existing requirements, if the repo maintains them:
- Actors/personas: end users running pi installed via this repo
- Use cases: N/A
- Workflows/scenarios: N/A
- Requirements: N/A

Requirement questions:
- Does the repo maintain durable requirement IDs or requirement documents that Design should map this work against?

## Plan Level
standard

**Rationale:** This is user-facing behavior with startup integration, multiple plugin source types, partial-failure behavior, and correctness concerns around how staleness is determined. It is larger than a simple fix but does not require epic-level decomposition.

## Key Decisions Made (during discovery)
| Decision | Chosen | Rationale |
|----------|--------|-----------|
| Target audience | End users running pi installed via this repo | They are the ones currently missing stale-plugin visibility during normal use. |
| User-visible behavior | Show a warning at pi startup | Restores the lost "notice it during normal use" workflow. |
| Delivery mechanism | Any repo-owned mechanism is acceptable | The goal is restored user-visible warning behavior, not parity with pi internals. |
| Scope boundary | Notification only | Update pipeline and plugin-management changes are intentionally out of scope. |
| pi core changes | Not allowed | This should be solved in the repo/wrapper. |
| Startup blocking | Never block startup | The warning is informational and must not reduce availability. |
| Partial failure handling | Show best-effort results with distinct wording for unknown status | Silent failures would recreate the current problem. |
| Git staleness semantics | Treat as stale if upstream has advanced | Prioritizes visibility so users know they need to update plugins. |

## Likely overlooked needs considered
- **Required now:** non-blocking startup behavior, git-install coverage, partial-failure visibility, actionable warning text, and test coverage across supported install types.
- **Recommended but deferrable:** warning-throttling strategy and clearer documentation of git-based "stale" semantics.
- **Future/backlog:** auto-update, dismiss/snooze controls, richer status/doctor UX, and broader wrapper cleanup.

## Open Questions (to resolve during research/design)
- Where in the repo/wrapper flow can startup-time stale-plugin detection and warning display be integrated reliably without modifying pi core?
- What local metadata already exists for installed plugin versions/refs across supported install types, and what additional remote checks are needed to determine staleness?
- How should git-based installs be checked consistently so "upstream has advanced" is determined correctly for the install modes used by this repo?
- What user-facing warning format is visible and actionable at startup while keeping startup latency and noise acceptable?
- How should Design test stale and "could not determine" outcomes across supported install types without relying on brittle live-network tests?
