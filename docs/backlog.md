# Backlog

## System

This file is the canonical backlog for this repo. Record durable follow-up work here instead of leaving it only in chat, ephemeral notes, or plan discussions.

Use this backlog for non-critical work that is accepted but does not belong in the current task. Critical discoveries that affect correctness, safety, scope, or verification are not backlog-only items: raise them immediately so the current plan can be adjusted.

## Required Operations

| Operation | Required contract |
|-----------|-------------------|
| Create item | Add a new item from the template below in the appropriate lifecycle section. |
| Assign stable ID | Give each new item the next unused `TASK-XXXX` identifier and never reuse an old ID. |
| Reference format | Refer to backlog items as `TASK-XXXX` in plans, worklogs, reviews, commits, and chat. |
| Source backlink | Every item must include a `Source:` line that points back to the originating plan, worklog, review, or discussion artifact. |
| List Inbox | Review `## Inbox` for newly accepted work that is not yet prioritized. |
| List Up next | Review `## Up next` for the highest-priority items that are ready to pull soon. |
| Mark Ready | Move an item into `## Ready` when it is clarified enough to execute without more triage. |
| Mark Done | Move an item into `## Done` when the work is finished and the durable record should remain visible. |
| Mark Canceled | Move an item into `## Canceled` when it will not be pursued; keep the ID and reason. |
| Defer / Icebox | Move an item into `## Icebox` when it is intentionally deferred with no near-term execution slot. |
| Mark Blocked | Move an item into `## Blocked` when progress is waiting on another decision, task, or dependency. |
| Critical item policy | If the discovery could change the current task or plan correctness, safety, scope, or verification, stop and raise it immediately instead of quietly adding it to the backlog. |

## Item Template

Use this template for every new item:

```markdown
### TASK-XXXX — Short title
- Status: Inbox
- Summary: One or two sentences describing the work.
- Source: <path, review section, issue, or conversation reference>
- Notes: Optional constraints, links, or acceptance cues.
```

The `TASK-XXXX` placeholder describes the required stable ID format. Replace `XXXX` with the next unused four-digit number.

## Related Docs
- `plans/README.md` — when plans and worklogs should capture accepted follow-up work here.
- `docs/requirements.md` — cite requirement IDs there when backlog work implies durable requirement changes.
- `docs/issues_learnings.md` — use the learnings log for repeat observations that are not yet accepted backlog work.

## Up next

_No items yet._

## Ready

### TASK-0001 — Upgrade @aliou/pi-guardrails 0.9.5 → 0.15.0
- Status: Ready
- Summary: Bump the held pi-guardrails managed package. Requires handling breaking changes: v0.12.0 split guardrails into three extensions (policy / path-access / permission-gate) and renamed public event-bus events; v0.14.0 migrated `pathAccess.allowedPaths` config from `string[]` to `{ kind, path }[]` (auto-migration `010`). v0.13.1 loosened Pi peer deps (compatible with our 0.80.x runtime).
- Source: Package-update review session (commits 822f83d..80a8d19); changelog https://github.com/aliou/pi-guardrails/releases
- Notes: Verify how `nix/modules/pi/default.nix` loads guardrails (single extension vs the new three-extension layout) and confirm our out-of-store `guardrails.json` (guardrailsConfigPath) auto-migrates cleanly on first launch. Update proof-set.json / version fields; run `./tests/run-tests.sh all`.

### TASK-0002 — Fork-currency audit: retire out-of-date forks where upstream has the fix
- Status: Ready
- Summary: Three managed git packages point at personal (`smantzavinos/*`) forks that are now well behind their true upstreams. For each, confirm which customizations the fork carries, check whether upstream has since incorporated an equivalent, and either (a) drop the fork and pin the real upstream, or (b) rebase the fork onto current upstream if the customization is still unique.
- Source: Package-update review session; fork/upstream compares via GitHub API (2026-07-13).
- Notes:
  - **pi-subagents** → upstream `nicobailon/pi-subagents` (fork 2 ahead / 232 behind). Custom commits: `feat: apply agentOverrides to user agents (not just builtins)`, `fix: disableBuiltins takes priority over agentOverrides for builtins`. NOTE: the staleness warning comparing our pin to the fork's own `main` is a false positive — evaluate against `nicobailon` upstream instead.
  - **pi-hooks** → upstream `prateekmedia/pi-hooks` (5 ahead / 8 behind). Custom commits: ralph-loop escape-sequence RPC-stdout fix, `execute()` parameter-order fix, auto-detect project-local agents when `agentScope` omitted, `processClosed` vs `proc.killed` SIGKILL fallback, `vscode-languageserver-protocol` import path for v3.18+.
  - **pi-gitnexus** → upstream `tintinweb/pi-gitnexus` (1 ahead / 18 behind; disabled by default). Custom commit: `fix: stop MCP child process on session_shutdown to prevent hang`.
  - Any fork we drop must keep the pinned-commit + idempotent-install contract (see `nix/AGENTS.md`) and update `tests/fixtures/proof-set.json`.

## Inbox

_No items yet._

## Clarification needed

_No items yet._

## In progress

_No items yet._

## In review

_No items yet._

## Blocked

_No items yet._

## Icebox

_No items yet._

## Done

_No items yet._

## Canceled

_No items yet._
