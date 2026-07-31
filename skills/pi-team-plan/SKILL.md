---
name: pi-team-plan
description: Human-triggered Pi team planning contract. Use after intent is clear to author and mechanically validate one self-contained Crew execution plan.
harnesses: [pi]
disable-model-invocation: true
metadata:
  domain: pi-team
---

# Pi Team Plan

## Role

Work with the human to turn agreed intent into the sole authored execution contract:
`plans/YYYY_MM_DD_<slug>/plan.md`. `disable-model-invocation: true` makes this skill
**human-triggered**: a human must invoke it rather than a model invoking it automatically. It does
not prohibit model-assisted drafting or a fresh model review after the human starts the workflow;
plan and risk approval remain human decisions.

## Plan contract

Read `references/plan-contract.md` before authoring or validating a plan. `Plan schema: 1` is
required. The reference is the self-contained schema-1 grammar, ID/list/lane/risk/path/check/
integration/wave rules, and exact task-packet template. Do not substitute another plan format,
team worklog, or source change.

## Process

1. Confirm human intent, unchanged boundaries, acceptance evidence, risk labels, and whether
   `Approval` is `auto` or `requested`.
2. Create the plan using the reference's exact grammar. Resolve every worker decision in
   `## Decisions` before dispatch. Packets must be decision-complete: one explicit write set,
   minimal worker-safe check, contracts, decisions, integration group, and bounded deliverable.
   Define enough file-disjoint ready work for at most four workers per computed wave.
3. Run `pi-team check <plan-path> --json`. Correct every diagnostic; mechanical validity never
   proves semantic sufficiency.
4. Commission a **fresh semantic review** of the authored plan. It must assess intent coverage,
   packet sufficiency, write-set isolation, checks, integration groups, and risk classification.
   Record findings beside the plan and revise until clean.
5. Present the clean plan and review to the human when approval was requested. Otherwise execution
   may proceed, except that risk-labelled tasks still wait for their individual human approvals.

## Approval boundary

Never waive risk approval. Tasks labelled `migration`, `destructive`, `auth`, or `api-contract`
remain pending until the active `pi-team` profile requires and the human performs approval. Do not
reinterpret a risk label, hide it in another task, or turn a requested plan approval into auto.

## Stop conditions

Stop and ask the human if intent, risk, ownership, check adequacy, or a decision is ambiguous.
Do not materialize the Crew board, dispatch workers, run broad gates, commit, or modify code.
