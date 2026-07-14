# Nix Directory Guide

Read this file before editing modules, generated-package helpers, or checked-in policy data under `nix/`.

## Module Boundaries
- Keep `nix/modules/pi/` focused on Pi installation, managed-package wiring, settings, and repo-shipped agent/skill assets.
- Keep `nix/modules/opencode/` focused on OpenCode configuration and plugin wiring.
- Do not move repo-process policy into Nix unless it materially affects generated configuration or installation behavior.

## Managed Package Sources
- Every `git`-source managed package in `nix/modules/pi/default.nix` must pin an immutable 40-hex commit (not a branch/tag ref). This keeps no-change home-manager rebuilds offline and fast: the activation script resolves the commit purely and skips the uninstall/reinstall when the installed `installedCommit` already matches. Mutable refs force a `git ls-remote` and defeat the skip.
- To update a git-source package, bump its `spec`/`installSpec` commit (nixpkgs-style) and update `tests/fixtures/proof-set.json` in the same change. The `startup-staleness-warning` extension surfaces when an upstream branch has moved past the pin.
- External skills/extensions that are not npm managed packages (`visual-explainer`, `agent-kit`) come from pinned non-flake flake inputs (`visualExplainer`, `agentKit`) and are wired via store-path symlinks/copies in the activation script — never runtime `git clone`. Update them with `nix flake update <input>`. When wiring paths, verify the target exists in the pinned tree: agent-kit's Pi extensions live at `extensions/<name>/<name>.ts` (a stale `pi/extensions/...` path silently produces dangling symlinks).

## Compile Helper Behavior
- `nix/modules/pi/compile-managed-packages.mjs` is a contract helper, not a scratch script.
- Preserve its documented CLI surface, exit codes, deterministic ordering, and generated output shape when changing it.
- Update the related specs and fixtures in the same task whenever helper behavior intentionally changes.

## Guardrails Config
- `nix/modules/pi/guardrails.json` is checked-in policy data consumed by generated Pi config.
- Keep it valid JSON and treat rule IDs, protected patterns, and confirmation behavior as durable contract surface.
- Prefer narrow policy edits over broad rewrites so verification remains understandable.

## Generated Package Conventions
- Generated package directories should stay reproducible and path-safe.
- Preserve conventions such as generated package metadata, `_source` links, and selected-resource manifests unless a task explicitly changes that contract.
- When introducing a new generated package behavior, document it in the touched tests or helper comments.

## Anti-Patterns
- Do not mix Pi and OpenCode concerns in one module when the split already exists.
- Do not change generated package layout silently without matching regression coverage.
- Do not hand-edit derived outputs when the source declaration or helper should be fixed instead.
