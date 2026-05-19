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

## Up next

_No items yet._

## Ready

_No items yet._

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
