---
name: discover-and-design
description: Fast path from a clear request to brief.md plus approach.md. Use for straightforward work when goals are known and the design is not a real fork. For vague, high-blast-radius, or multi-option problems use Discovery then Design instead.
compatibility: pi
disable-model-invocation: true
---

# Discover and Design (speed run)

Produce an accepted `brief.md` and `approach.md` in one sitting. Optimized for
work that is already well-posed. You may do light codebase research. You do not
run a Socratic interview or a multi-option design workshop.

## When to use / when to stop

**Use when:** the human already knows the outcome, the change is local, and
there is at most one obvious design.

**Stop and tell them to use `/discovery` then `/design` when:**

- goals, non-goals, or success criteria are actually unclear
- two or more designs are real, not cosmetic
- the work is epic-sized or cross-cutting
- research turns up a safety, compatibility, or scope surprise

Do not pretend a speed run is still appropriate after that. Hand off.

## Process

1. **Restate the request** in a few sentences. Confirm only what is actually
   ambiguous. Do not walk a question checklist.
2. **Look at the code** that will change. One focused research pass is enough.

subagent({
  agent: "worker",
  task: "Research [specific files/modules]. Write findings to [path/findings/current_state.md]. Keep it short and evidence-based.",
  skill: "research"
})

Skip the delegate if you can answer from a few file reads in this session.
3. **Write both artifacts** into the plan directory (ask for the path if
   missing). Use the templates in [references/brief-template.md](references/brief-template.md)
   and [references/approach-template.md](references/approach-template.md).
   Keep them short. Record plan level. If the repo maintains requirements,
   cite IDs or list questions; do not edit canonical requirements.
4. **Show the paths and wait.** Do not commit until the human accepts both
   files. Then commit `brief.md`, `approach.md`, `findings/` (if any), and
   `state.json` as `design: speed-run approach for <slug>`.
5. **Next step:** "The approach is ready. Write the Parallel plan with `/dynamic-create-plan`, review it with `/dynamic-review-plan`, and once you have approved it run `/dynamic-execute-plan` (DAG per fence group)."

For a true simple change (obvious, tiny, no design), write only `brief.md` at
plan level `simple` and say they can implement directly.

## Quality bar

- Goals, non-goals, and success criteria are explicit.
- The approach names the files/modules that change and what stays the same.
- Findings are factual and cite paths. No speculation presented as fact.
- No task list, no `tasks.json`, no implementation.

## What you must not do

- Do not implement.
- Do not write `plan.md` or `tasks.json`.
- Do not invent a second ceremony. If it needs ceremony, this is the wrong skill.
- Do not skip the human accept-and-commit gate.
