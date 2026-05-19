# Templates Directory Guide

Read this file before adding or editing starter content under `templates/`.

## Starter Content Rules
- Templates should provide a clean starting point, not a second canonical copy of repo docs.
- Keep starter content concise, generic where appropriate, and aligned with the repo's current operating contract.
- Prefer placeholders for repo-specific values and keep durable process rules routed to the canonical docs.

## Placeholder Discipline
- Make placeholders obvious and easy to replace, for example `<hostname>` or `<repo-name>`.
- Use placeholders only where real user-specific values are expected.
- Remove stale example names, paths, or commands that could be copied as accidental truth.

## Anti-Patterns
- anti-pattern: baking this repo's local paths or assumptions into generic starter files
- anti-pattern: leaving ambiguous placeholders that do not tell the reader what value belongs there
- anti-pattern: duplicating long policy sections that should link back to the canonical docs instead
