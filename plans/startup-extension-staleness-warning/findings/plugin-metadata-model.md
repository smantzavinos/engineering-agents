# Plugin source types and installed metadata model

**Created:** 2026-05-19
**Topic:** Managed Pi plugin/extension source types, installation flow, and runtime metadata available for version/ref detection in this repo
**Plan:** `plans/startup-extension-staleness-warning/brief.md`

## Summary
This repo’s Pi plugin system is centered on the `piPackages` declaration set in `nix/modules/pi/default.nix`. In the current checked-in configuration, every managed package is declared as either `source.type = "npm"` or `source.type = "git"`; there are no current `local` entries in that file (`nix/modules/pi/default.nix:20-220`). The surrounding tooling contract does recognize a third type, `local`, but the compiler currently skips local declarations instead of materializing them into runtime facade packages (`scripts/check-updates.sh:78-100`, `nix/modules/pi/compile-managed-packages.mjs:702-704`, `tests/specs/compiler-contract-spec.sh:201-210`).

At runtime, the repo does not point Pi directly at the raw npm/global install locations. Instead, activation installs package sources under `~/.pi/packages/lib/node_modules/<packageName>`, then compiles facade packages under `~/.pi/agent/packages/<packageId>` and shared source symlinks under `~/.pi/agent/sources/<materializedKey>` (`nix/modules/pi/default.nix:588-644`, `nix/modules/pi/compile-managed-packages.mjs:725-780`). The repo-generated metadata that survives this process is limited: `meta/source.json` records `source.type`, `source.spec`, `source.materializedKey`, `sourceManifestName`, `sourceRoot`, and `selectedResources`, but it does not persist `installSpec`, npm `version`, or any resolved git commit/ref beyond the original `spec` string (`nix/modules/pi/compile-managed-packages.mjs:560-577`, `610-645`).

## Findings

### Managed package declarations use a `source` block with `type`, `packageName`, `spec`, and `installSpec`
The repo’s canonical managed-plugin declarations live in `piPackages` in `nix/modules/pi/default.nix` (`nix/modules/pi/default.nix:20-220`). Each package entry has a `source` object. The currently used patterns are:

- **npm-backed packages** include:
  - `type = "npm"`
  - `packageName = "..."`
  - `spec = "package@version"`
  - `installSpec = "package@version"`
  - `version = "..."`
  Examples include `pi-web-access`, `pi-ding`, and `catppuccin-mocha` (`nix/modules/pi/default.nix:59-139`).
- **git-backed packages** include:
  - `type = "git"`
  - `packageName = "..."`
  - `spec = "github:owner/repo[#ref]"`
  - `installSpec = "github:owner/repo[#ref]"`
  Examples include `pi-subagents`, `pi-hooks`, `pi-ext-leader-key`, `pi-ext-review`, and `pi-gitnexus` (`nix/modules/pi/default.nix:21-37`, `142-169`, `212-219`).
- **local sources** are supported by the update-checker/parser contract and by compiler input fixtures, but none are present in the current `piPackages` attrset. The sample parser fixture includes `type = "local"` with a filesystem `spec`/`installSpec` (`tests/spec-fixtures/update-checker/pi.nix.sample:1-29`), and the checker explicitly accepts `local` as a valid type (`scripts/check-updates.sh:87-100`).

The update checker’s parser treats `type`, `packageName`, `spec`, and `installSpec` as mandatory for all declarations, and additionally requires `version` for npm sources (`scripts/check-updates.sh:78-97`). For npm sources it enforces that both `spec` and `installSpec` match `"${packageName}@${version}"` (`scripts/check-updates.sh:87-97`).

### Only non-local packages are surfaced to Pi runtime settings
The Pi settings object is generated with `packages = map (packageId: "./packages/${packageId}") piRuntimePackageIds`, and `piRuntimePackageIds` is computed by filtering out any package whose `source.type == "local"` (`nix/modules/pi/default.nix:222-225`, `263-266`).

This means the runtime package list written into `~/.pi/agent/settings.json` references only generated facade packages under `./packages/<packageId>` (`nix/modules/pi/default.nix:265-274`, `565-575`). A local declaration may be structurally valid to the tooling, but it is not part of the runtime package set produced by this module.

### Install behavior differs by source type before the facade compiler runs
The `installPiExtensions` activation script materializes package sources before building facades (`nix/modules/pi/default.nix:576-658`):

- It sets `NPM_CONFIG_PREFIX="$HOME/.pi/packages"`, so npm global installs land under `~/.pi/packages` instead of the system global prefix (`nix/modules/pi/default.nix:588-590`, `716-718`).
- **npm sources** are deduplicated by `[source.packageName, source.installSpec]`, compared against `npm list -g --depth=0 --json`, and skipped only when the installed dependency version exactly matches the declared `source.version` (`nix/modules/pi/default.nix:594-610`).
- **git sources** are also deduplicated by `[source.packageName, source.installSpec]`, but are always uninstalled and reinstalled from `installSpec`; the script removes `~/.pi/packages/lib/node_modules/$package_name` before calling `npm install -g --install-links --legacy-peer-deps "$install_spec"` (`nix/modules/pi/default.nix:612-624`). There is no pre-check equivalent to the npm `installed version == declared version` comparison.
- The activation script then writes `~/.pi/agent/managed-packages.declarations.json`, converting each non-local declaration into `{ type, spec, materializedPath }`, where `materializedPath` is `~/.pi/packages/lib/node_modules/<packageName>` (`nix/modules/pi/default.nix:626-642`). `installSpec` and npm `version` are not carried forward into that declarations file.

### The compiler turns materialized package directories into facade packages plus provenance metadata
`compile-managed-packages.mjs` consumes the generated declarations file and builds Pi-loadable facade packages (`nix/modules/pi/compile-managed-packages.mjs:649-780`). Key steps are:

1. **Materialized source identity** is normalized to `JSON.stringify({ type, spec })` and hashed to a `src-<16 hex chars>` key (`nix/modules/pi/compile-managed-packages.mjs:125-140`).
2. Each declaration’s `source.materializedPath` must exist and be a directory unless the source type is `local` (`nix/modules/pi/compile-managed-packages.mjs:702-723`).
3. The source package’s own `package.json` is loaded, and resources are discovered from `manifest.pi.*` declarations or directory conventions (`nix/modules/pi/compile-managed-packages.mjs:420-454`, `725-735`).
4. `expose.*` filters optionally select a subset of discovered resources; missing or overlapping selections are treated as contract errors (`nix/modules/pi/compile-managed-packages.mjs:456-537`).
5. The compiler writes:
   - `~/.pi/agent/sources/<materializedKey>` as a symlink to the materialized install directory (`nix/modules/pi/compile-managed-packages.mjs:725-735`).
   - `~/.pi/agent/packages/<packageId>/package.json` with Pi-facing `./_source/...` paths (`nix/modules/pi/compile-managed-packages.mjs:539-557`, `610-645`).
   - `~/.pi/agent/packages/<packageId>/meta/source.json` with provenance metadata (`nix/modules/pi/compile-managed-packages.mjs:560-577`, `610-645`).

The compiler contract test asserts that each generated facade contains exactly `package.json`, `_source`, and `meta/source.json`, and that `_source` resolves to the `sourceRoot` recorded in metadata (`tests/specs/compiler-contract-spec.sh:126-137`, `179-199`).

### The runtime metadata model records declared provenance, not observed installed version/ref state
The generated `meta/source.json` payload is defined by `buildMetadata()` and contains only:

- `schemaVersion`
- `packageId`
- `source.type`
- `source.spec`
- `source.materializedKey`
- `sourceManifestName`
- `sourceRoot`
- `selectedResources.{extensions,skills,prompts,themes}`

(`nix/modules/pi/compile-managed-packages.mjs:560-577`)

The metadata model does **not** include:

- `source.installSpec`
- npm `source.version`
- any installed npm version discovered at runtime
- any resolved git SHA, branch head, tag resolution, or fetched remote state

That omission is observable in both the metadata writer and the contract tests. The contract test only validates `source.type`, `source.spec`, `source.materializedKey`, `sourceManifestName`, `sourceRoot`, and selected resources (`tests/specs/compiler-contract-spec.sh:179-192`). The snapshot fixture for a successful install shows the same fields and nothing else under `sourceProvenance.source` (`tests/spec-fixtures/resource-snapshot.v2.ok.json:404-424`, `497-547`).

For npm packages, the only repo-owned place where a concrete version is compared to installed state is the activation-time `npm list -g` check, and that comparison is not written back into facade metadata (`nix/modules/pi/default.nix:594-610`). For git packages, the repo records the declared `spec` string but no local "installed ref" field after installation (`nix/modules/pi/default.nix:612-624`, `nix/modules/pi/compile-managed-packages.mjs:560-577`).

### Shared-source packages are intentionally split into multiple package IDs that point at one materialized source
`pi-ext-leader-key` and `pi-ext-review` both declare the same git `spec` (`nix/modules/pi/default.nix:142-169`). Because `materializedKey` is derived from only `{ type, spec }`, both facades share the same source key and therefore the same `~/.pi/agent/sources/src-...` entry (`nix/modules/pi/compile-managed-packages.mjs:125-140`, `725-739`).

The proof fixture and snapshot confirm this behavior: both packages carry the same `sharedSourceKey` / `materializedKey` and different `selectedResources.extensions` values (`tests/fixtures/proof-set.json:35-65`, `tests/spec-fixtures/resource-snapshot.v2.ok.json:497-547`).

This means source freshness, if evaluated from repo-owned metadata, is naturally a property of the shared materialized source, while user-facing warnings would still need to map that source back to one or more facade `packageId`s.

### Local source support is partial and currently non-materializing
The compiler explicitly `continue`s when `source.type === "local"` (`nix/modules/pi/compile-managed-packages.mjs:702-704`). The compiler contract test verifies that a local declaration succeeds structurally but emits no compiled packages and no compiled sources (`tests/specs/compiler-contract-spec.sh:201-210`).

Separately, the update checker treats local sources as a supported declaration type but only prints `[PI_PACKAGE_WARN_LOCAL_SOURCE_NO_AUTO_UPDATE]` instead of performing version checks (`scripts/check-updates.sh:402-407`).

As a result, `local` is part of the declaration/update-checker contract, but not part of the current runtime facade generation path used by this module.

### Some extension/skill installs bypass the managed-package metadata model entirely
Two activation flows install resources directly into the agent directory instead of through `piPackages` + facade compilation:

- `installVisualExplainer` clones `visual-explainer` into `~/.pi/agent/skills/visual-explainer` and copies prompts directly into `~/.pi/agent/prompts` (`nix/modules/pi/default.nix:661-678`).
- `installAgentKit` clones `agent-kit` into `~/.pi/agent/repos/agent-kit`, then symlinks its extensions directly into `~/.pi/agent/extensions/direnv/index.ts` and `~/.pi/agent/extensions/ast-grep/index.ts`, and symlinks an `ast-grep` skill into `~/.pi/agent/skills/ast-grep` (`nix/modules/pi/default.nix:680-712`).

These resources do not go through `managed-packages.declarations.json`, do not receive `meta/source.json`, and do not participate in the facade `materializedKey`/`sourceRoot` model described above.

## Constraints Discovered
- The current checked-in `piPackages` declarations use only `npm` and `git`; `local` is supported by tooling contracts but is filtered out of runtime package loading and skipped by the compiler (`nix/modules/pi/default.nix:222-225`, `nix/modules/pi/compile-managed-packages.mjs:702-704`, `tests/specs/compiler-contract-spec.sh:201-210`).
- Repo-generated provenance metadata persists only declared source identity (`type` + `spec`) plus resource selection; it does not persist `installSpec`, npm `version`, or any resolved git commit/ref (`nix/modules/pi/compile-managed-packages.mjs:560-577`).
- The manual update checker aligns with that limitation: it can auto-check npm registry versions, but for git and local sources it only emits warnings and does not compute staleness (`scripts/check-updates.sh:391-407`).
- Multiple facade package IDs can intentionally share one materialized source when `type` and `spec` match, so any source-level status may need package-level fan-out (`nix/modules/pi/compile-managed-packages.mjs:125-140`, `725-739`; `tests/spec-fixtures/resource-snapshot.v2.ok.json:497-547`).
- Some installed extensions/skills in this repo bypass the managed-package system entirely and therefore have no `meta/source.json` provenance record (`nix/modules/pi/default.nix:661-712`).

## Risks
- A stale-check feature that relies only on `meta/source.json` will know the declared `spec` but not the locally observed installed version for npm or the resolved installed commit for git (`nix/modules/pi/compile-managed-packages.mjs:560-577`).
- Git-backed packages currently reinstall from `installSpec` during activation, but no repo-owned metadata records what commit/ref was actually materialized afterward (`nix/modules/pi/default.nix:612-624`).
- Shared-source facades such as `pi-ext-leader-key` and `pi-ext-review` can create duplicate or confusing warnings if status is computed per package ID instead of per materialized source (`tests/spec-fixtures/resource-snapshot.v2.ok.json:497-547`).
- Directly cloned/symlinked resources like agent-kit and visual-explainer do not fit the managed-package metadata model, so a startup checker scoped only to managed packages would not cover them (`nix/modules/pi/default.nix:661-712`).

## References
- `nix/modules/pi/default.nix` — canonical managed package declarations, runtime package list, activation-time install logic, and direct non-managed installs.
- `nix/modules/pi/compile-managed-packages.mjs` — declaration compiler, source deduping, facade generation, and `meta/source.json` schema.
- `scripts/check-updates.sh` — declaration parser/update checker; auto-checks npm, warns only for git/local.
- `tests/specs/compiler-contract-spec.sh` — contract assertions for generated facade layout and local-source behavior.
- `tests/spec-fixtures/resource-snapshot.v2.ok.json` — example of runtime provenance as observed by the snapshot tooling.
- `tests/scripts/resource-snapshot.mjs` — reads `managed-packages.report.json` and facade `meta/source.json` from `~/.pi/agent`.
- `tests/fixtures/proof-set.json` — proof-set fixture showing shared-source package IDs and expected selected resources.
