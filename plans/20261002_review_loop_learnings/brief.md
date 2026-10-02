# Brief: Review-loop learnings from LLS practice → upstream skills

**Date:** 2026-10-02
**Author:** Dean (Hermes agent, LLS)
**Level:** Standard-lite (additive skill-content edits + spec anchors; no design choices, no code paths)

## Goal

Port five field-proven review-loop learnings from LLS internal practice into the
canonical skills, so every agent using this repo's process gets them.

## Learnings (each earned by a real failure)

1. **Pre-review self-audit (create-plan)** — before spending expensive
   independent reviewer lanes, the planner mechanically audits the draft:
   grep every status/error/event vocabulary against the frozen spec, trace
   gate dependencies for cycles, check every coverage-matrix claim has an
   owning task, grep stale sibling docs for contradictions. Proven: on an
   11-pass internal epic loop, a pre-audit would have prevented at least one
   full round (invented event-name map + stale cross-doc line were both
   mechanically findable).
2. **Unique finding file per reviewer per round (review-plan)** — two
   reviewers pointed at the same file: the late one overwrote the other's
   record; findings survived only via reconstruction with a provenance
   header. Naming collision = broken audit trail.
3. **Rate-limit staggering (review-plan)** — same-provider reviewer launches
   are staggered; a reviewer lost to 429s is re-dispatched, and the round
   record states which rounds ran short.
4. **Verdict provenance (review-plan)** — a pass counts only over the exact
   commit it reviewed; a PASS on stale bytes does not terminate the loop, and
   a NEEDS_ANOTHER_PASS on pre-fix bytes may already be resolved.
5. **Static security scan gate (review-code)** — reviewers catch logic, but a
   deterministic grep of added lines catches the known dangerous classes
   (secrets, shell injection, eval/exec, unsafe deserialization, SQL
   string-building) every time.

## Scope

- `skills/create-plan/SKILL.md`, `skills/review-plan/SKILL.md`,
  `skills/review-code/SKILL.md` (canonical only; dist/ via renderer)
- `tests/specs/skill-content-spec.sh` (RED-first anchors)
- No deletions/renames; no changes to skill-resources.json, harnesses, nix

## Verification

- RED proof: new spec rows fail before content lands, pass after
- `./tests/run-tests.sh fast` (task gate), render `--check`, `pi-dev.sh --verify`
  (skills changed → e2e-local row per pr-review-hooks.md)
