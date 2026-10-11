# Draft skills: frontier pipeline

These are drafts of the new skills described in [../plan.md](../plan.md) §12. They are not installed or rendered. When promoted, they move to `skills/<name>/` and the subagent calls are written with the harness `{{delegate:...}}` macros (see `skills/AGENTS.md`).

| Skill | Who uses it | Lines |
|---|---|---|
| [prototype](prototype/SKILL.md) | human + agent, paired session | 38 |
| [scope](scope/SKILL.md) | orchestrator, interactive with the human | 54 |
| [orchestrate](orchestrate/SKILL.md) | orchestrator, autonomous | 62 |
| [plan](plan/SKILL.md) | planner subagent (resumed per review round) | 45 |
| [implement](implement/SKILL.md) | implementer subagent (resumed per review round) | 51 |
| [review](review/SKILL.md) | fresh reviewer subagent (new every pass) | 51 |
| [delegate](delegate/SKILL.md) | every frontier agent | 44 |

The total is about 345 lines. The current path uses about 2,500 lines plus templates.

## Flow

```
prototype ─► scope ─► orchestrate ─┬─ plan ⇄ review(plan)     ┐ per child
 (human)    (human)    (autonomous) ├─ implement ⇄ review(code)│
                                    └─ close, self_compact      ┘
                                   then review(epic-diff) ─► PR process
```

## How the drafts were written

- **Outcome first.** Each skill opens with what to produce and why, in 2–4 sentences.
- **Short rules.** Steps and artifact outlines appear only where the output must have a shape. Do's and don'ts appear only where a strong model could plausibly go wrong.
- **No ceremony.** Nothing a frontier model does anyway: no "read before editing", "run tests", or TDD scripts.
- **No templates.** Artifact sections are listed in a few lines. The model writes the document.
- **Shared conventions are stated once each.** Handoffs use `self_compact` followed by a short reply. Disk is the memory: `state.json`, `review.md`, git. The cap is 4 review passes. Delegation patterns are in `delegate`.

## Agents these skills assume

| Agent | Class | Tools | Notes |
|---|---|---|---|
| orchestrator | frontier | read, bash, edit, write, subagent, self_compact | The interactive session; uses `scope`, then `orchestrate` |
| planner | frontier | read, bash, edit, write, subagent, self_compact | Resumed across plan review rounds |
| implementer | frontier | read, bash, edit, write, subagent, self_compact | Resumed across code review rounds |
| reviewer | frontier | read, bash, write, subagent | New session every pass; writes only `review.md` |
| oracle | frontier, max reasoning | read, bash | Settles disputes and course-setting forks |
| helper | fast | read, bash, edit | Delegation errands; read-only unless the errand allows edits |
| researcher | fast | read, web search/fetch | External research |

Models are a repo hook. Helpers are defined by tools and model, not by pattern. Scout, sweep, run-and-digest and the rest are errands described in `delegate`.

## Not covered here

- PR preparation, PR review and babysitting: the existing `pull-request` and `babysit-pr` skills, unchanged.
- Backlog operations: the existing `backlog` skill.
- Repo-specific gate commands: these come from each repo's docs. The skills only say when to run them.
