# Extension/plugin update-check current state

**Created:** 2026-05-19
**Topic:** Existing manual extension/plugin update-check logic, current staleness semantics, and git-source gaps
**Plan:** plans/startup-extension-staleness-warning/brief.md

## Summary
The only repo-owned update-check mechanism I found is `scripts/check-updates.sh`, which is packaged as a `check-updates` helper by the flake overlay (`scripts/check-updates.sh:3-9`, `flake.nix:81-86`). The script does not inspect installed extension state directly. Instead, it parses the declarative `piPackages` blocks in `nix/modules/pi/default.nix` and requires `source.type`, `source.packageName`, `source.spec`, and `source.installSpec` for every package, plus `source.version` for npm packages only (`scripts/check-updates.sh:57-103`, `nix/modules/pi/default.nix:20-220`).

Current staleness detection is registry-only and npm-only. For `source.type == "npm"`, the script calls `npm view <packageName> version` and marks a package stale only when that registry version differs from the declared `source.version`; `--update` then rewrites only `spec`, `installSpec`, and `version` for those npm entries (`scripts/check-updates.sh:195-339`, `scripts/check-updates.sh:367-454`). For `git` sources, the script does not resolve upstream refs, compare commits, or classify them as stale; it only emits a warning code to stderr indicating that a manual update is required (`scripts/check-updates.sh:402-406`). That means git-based installs are currently missed for stale detection, even though this repo actively uses several git-backed packages such as `pi-subagents`, `pi-hooks`, `pi-ext-*`, and `pi-gitnexus` (`nix/modules/pi/default.nix:21-37`, `nix/modules/pi/default.nix:142-170`, `nix/modules/pi/default.nix:212-219`).

## Findings

### The repo currently has one manual update checker, packaged as a standalone helper
- The only explicit repo-owned update-check helper is `scripts/check-updates.sh`, described as “Check or apply registry-backed updates for unified Pi package declarations” (`scripts/check-updates.sh:3-9`).
- The flake overlay packages that script as a `check-updates` binary by copying only the shell script into `$out/bin` and marking it executable (`flake.nix:81-86`).
- I did not find a second repo-level update checker for Pi extensions/plugins. Repository search only surfaced this script and its packaging/existence checks.

### The checker reads declaration metadata from `piPackages`, not live installed package state
- The script’s parser reads a Nix file and looks specifically for a `piPackages = { ... }` attrset (`scripts/check-updates.sh:106-120`).
- Each package must provide `source.type`, `source.packageName`, `source.spec`, and `source.installSpec`; npm packages must also provide `source.version` (`scripts/check-updates.sh:78-103`).
- The current declarations live in `nix/modules/pi/default.nix`, where packages are declared as either `npm` or `git`. Examples:
  - `pi-subagents` and `pi-hooks` are git sources (`nix/modules/pi/default.nix:21-37`).
  - `pi-agent-guidance`, `pi-mcp-adapter`, `pi-web-access`, and most other managed packages are npm sources with explicit versions (`nix/modules/pi/default.nix:39-140`, `nix/modules/pi/default.nix:172-209`).
  - `pi-ext-leader-key` and `pi-ext-review` are separate package IDs that both point at the same git package/spec (`nix/modules/pi/default.nix:142-170`).
  - `pi-gitnexus` is also a git source (`nix/modules/pi/default.nix:212-219`).
- The parser sorts by `packageId` and emits one row per declaration; it does not deduplicate by `packageName` or `installSpec` before checking (`scripts/check-updates.sh:187-188`, `scripts/check-updates.sh:367-389`).

### Current staleness semantics are “declared npm version differs from latest npm registry version”
- For npm packages, the checker runs `npm view "$package_name" version`, prints `current -> latest`, and records an update when `current_version != latest_version` (`scripts/check-updates.sh:391-400`).
- If no npm entries differ, the script exits successfully after printing `No registry-backed npm package updates available.` (`scripts/check-updates.sh:414-417`).
- If `--update` is passed, the script rewrites only the npm declaration fields `spec`, `installSpec`, and `version` in the Nix file (`scripts/check-updates.sh:283-314`, `scripts/check-updates.sh:422-454`).
- This means today’s definition of “stale” is entirely based on npm registry version drift from the declared version in `piPackages`; there is no installed-vs-remote comparison for git sources.

### Git-based installs are explicitly excluded from stale determination
- The `git)` case in the main loop does not query git remotes, fetch refs, or compare commits/tags. It only prints `[PI_PACKAGE_WARN_GIT_SOURCE_MANUAL_UPDATE] <packageId> uses git source <spec>` to stderr (`scripts/check-updates.sh:402-404`).
- Unlike npm entries, git entries are never appended to the `updates` array, so they never affect the reported update count and are never rewritten by `--update` (`scripts/check-updates.sh:386-400`, `scripts/check-updates.sh:420-454`).
- The declaration contract itself reflects this: npm requires `source.version`, while git does not (`scripts/check-updates.sh:87-101`). There is therefore no built-in “current version” field for git that the script compares.
- The repo has real git-based packages today, including branch-based specs (`pi-subagents`, `pi-gitnexus`) and an apparently pinned commit spec for `pi-ext-*` (`nix/modules/pi/default.nix:21-27`, `nix/modules/pi/default.nix:142-170`, `nix/modules/pi/default.nix:212-217`). All of them are currently under-handled by the checker because the checker never resolves whether the upstream branch or repository has advanced.

### Install-time behavior also shows why git sources are under-handled at runtime
- Home Manager installation logic deduplicates npm installs by `[packageName, installSpec]`, skips reinstall when the installed global npm version already matches `source.version`, and otherwise installs the declared npm spec (`nix/modules/pi/default.nix:594-610`).
- Git installs are also deduplicated by `[packageName, installSpec]`, but they are always uninstalled/reinstalled from the declared install spec; there is no stored version comparison step analogous to npm (`nix/modules/pi/default.nix:612-624`).
- After installation, the generated runtime declarations written to `managed-packages.declarations.json` keep only `source.type`, `source.spec`, and `source.materializedPath` for non-local packages; `packageName`, `installSpec`, and npm `version` are not preserved there (`nix/modules/pi/default.nix:626-642`).
- The compiler enforces only `source.type`, `source.spec`, and `source.materializedPath` for non-local sources (`nix/modules/pi/compile-managed-packages.mjs:691-710`). This means the compiled runtime metadata is optimized for locating materialized package contents, not for performing later update comparisons.

### The current checker under-handles shared git sources and manual workflows
- The install path deduplicates git installs by `[packageName, installSpec]` (`nix/modules/pi/default.nix:613-617`), but the checker loops package declarations without deduplication (`scripts/check-updates.sh:367-389`).
- Because `pi-ext-leader-key` and `pi-ext-review` share the same git package/spec (`nix/modules/pi/default.nix:142-170`), the manual checker would emit separate git-manual-update warnings for each package ID rather than one warning per underlying installed source.
- In direct observation on 2026-05-19, running the checker against `tests/spec-fixtures/update-checker/pi.nix.sample` with a mocked `npm view` result of `1.2.3` printed `No registry-backed npm package updates available.` on stdout while still only warning `[PI_PACKAGE_WARN_GIT_SOURCE_MANUAL_UPDATE] sample-git uses git source github:example/sample-git#abc123` on stderr. Git status did not change the exit code or the update summary.

## Constraints Discovered
- The manual checker is tightly coupled to the `piPackages` declaration shape and will exit with an unsupported-contract error if that shape changes (`scripts/check-updates.sh:78-103`, `scripts/check-updates.sh:119-120`, `scripts/check-updates.sh:181-185`).
- The script’s default declaration path is `${SCRIPT_DIR}/pi.nix` (`scripts/check-updates.sh:13-15`), but this repo’s actual package declarations are in `nix/modules/pi/default.nix` (`nix/modules/pi/default.nix:20-220`). In direct observation on 2026-05-19, running `./scripts/check-updates.sh --dry-run` from the repo root failed with `declaration file does not exist: .../scripts/pi.nix`.
- The flake overlay copies only the shell script into `$out/bin/check-updates`; it does not package a sibling `pi.nix` file there (`flake.nix:81-86`).
- Runtime-generated package declarations keep source location metadata, not enough npm/git update metadata to reproduce the manual checker’s npm comparison directly from `managed-packages.declarations.json` (`nix/modules/pi/default.nix:626-642`, `nix/modules/pi/compile-managed-packages.mjs:691-710`).

## Risks
- If startup warnings are aligned to the current manual checker without adding new git-remote resolution, all git-backed extensions/packages will continue to be excluded from “stale” results even though the brief requires them to be considered stale when upstream advances.
- Shared underlying git installs can generate repeated manual-update warnings because the checker works per `packageId`, not per deduplicated installed source (`scripts/check-updates.sh:367-389`, `nix/modules/pi/default.nix:612-617`).
- Depending on how users invoke `check-updates`, the default declaration-file path may make the manual workflow fail before any staleness determination occurs (`scripts/check-updates.sh:13-15`, `flake.nix:81-86`).

## References
- `scripts/check-updates.sh` — the only manual update checker; parses `piPackages`, compares npm versions, and warns-only for git/local sources.
- `nix/modules/pi/default.nix` — authoritative managed package declarations and the Home Manager install logic for npm/git packages.
- `nix/modules/pi/compile-managed-packages.mjs` — validates runtime declaration shape; expects `materializedPath` for non-local sources and does not preserve richer update metadata.
- `flake.nix` — packages `scripts/check-updates.sh` as the `check-updates` helper.
- `tests/spec-fixtures/update-checker/pi.nix.sample` — minimal fixture showing the three supported source types (`npm`, `git`, `local`) used by the checker contract.
