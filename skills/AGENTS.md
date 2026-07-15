# Skills Directory Guide

Read this file before creating or materially editing anything under `skills/`.

## Skill Structure
- Each skill lives in `skills/<name>/` with a required `SKILL.md` entrypoint.
- `SKILL.md` files are **canonical, harness-neutral templates**. They are rendered per harness into `dist/skills/<harness>/` by `tools/render-skills.mjs`. See `docs/skill-rendering.md`.
- `SKILL.md` starts with YAML frontmatter. Keep `name` and `description` accurate. Do **not** add a `compatibility:` line — the renderer injects it per harness. Add other metadata only when it has a durable consumer.
- Use the `harnesses: [..]` frontmatter key only to restrict a skill to specific harnesses
  (default: all). OpenCode-only skills currently include `configure-opencode` and the team
  planning/execution skills.
- Express harness-specific delegation with macros, never with hardcoded `subagent(...)`/`task(...)` calls:
  - `{{delegate:ROLE skill=NAME}}prompt text{{/delegate}}` (the `skill=` part is optional)
  - `{{note:KEY}}` for harness-specific phrasing
  - New roles/notes must be added to both `harnesses/pi.json` and `harnesses/opencode.json`.
- After editing any skill, run `node tools/render-skills.mjs --write` and commit the regenerated `dist/`. Never hand-edit `dist/`.
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
