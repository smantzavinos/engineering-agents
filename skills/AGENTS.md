# Skills Directory Guide

Read this file before creating or materially editing anything under `skills/`.

## Skill Structure
- Each skill lives in `skills/<name>/` with a required `SKILL.md` entrypoint.
- `SKILL.md` starts with YAML frontmatter. Keep `name`, `description`, and `compatibility` accurate; add other metadata only when it has a durable consumer.
- Use `references/` for durable supporting artifacts such as templates, checklists, or example documents.
- Use a local `templates/` directory only when the skill truly ships starter files that must stay next to the skill.
- Keep the main skill file readable on its own; supporting files should reduce clutter, not hide the contract.

## Naming Rules
- The `name` in frontmatter must match the directory name.
- Directory names stay lowercase kebab-case.
- Keep `SKILL.md` spelled exactly in all caps so discovery remains compatible with the supported tooling.

## Process Constraints
- Skills define reusable process, stop criteria, and required artifacts; they should not become task-specific scratchpads.
- Prefer one focused skill per job over one large skill with many loosely related branches.
- When a skill requires verification, cite the canonical repo commands instead of inventing new top-level commands.
- If a skill needs extra context, point to repo docs or `references/` instead of duplicating large policy blocks inline.

## Anti-Patterns
- Do not move durable process rules into chat-only conventions.
- Do not add optional scaffolding directories unless a real skill uses them.
- Do not let a skill name drift from its directory or from how agents invoke it.
