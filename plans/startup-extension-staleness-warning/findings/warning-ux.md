# Startup warning UX and failure handling in the Pi wrapper

**Created:** 2026-05-19
**Topic:** Startup-visible warning surfaces, current update guidance, and low-noise/actionable message content for stale managed Pi plugins in this repo
**Plan:** `plans/startup-extension-staleness-warning/brief.md`

## Summary
This repo does not currently ship a repo-owned launcher that runs before every `pi` start. The README tells users to run upstream `pi` directly, and the Home Manager module installs the upstream Pi package rather than a wrapper binary (`README.md:41-56`, `README.md:145-158`, `nix/modules/pi/default.nix:345-349`). The repo-owned logic around managed extensions runs during Home Manager activation, where it installs package sources, compiles facade packages, writes `managed-packages.report.json`, and prints any compile warnings to stdout (`nix/modules/pi/default.nix:575-658`). As a result, the current repo already has install-time warning surfaces, but not a documented per-startup warning surface of its own.

The existing user guidance for updates is fragmented. The only update helper is `scripts/check-updates.sh`, packaged by the flake overlay as `check-updates` (`scripts/check-updates.sh:3-9`, `flake.nix:81-86`). However, the Pi Home Manager module does not install that helper into `home.packages` (`nix/modules/pi/default.nix:345-349`), the README/docs do not mention it (repo-wide `rg -n "check-updates|update checker|plugin update|extension update" README.md docs` returned no matches on 2026-05-19), and the script’s default declaration path points at `scripts/pi.nix`, which does not exist in this repo (`scripts/check-updates.sh:13-18`). In direct observation on 2026-05-19, running `./scripts/check-updates.sh --dry-run` from the repo root exited 2 with `declaration file does not exist: .../scripts/pi.nix`.

## Findings

### There is no repo-owned pre-launch wrapper; startup-visible UX has to live inside Pi or in Pi-loaded extensions
- The flake exposes a Pi Home Manager module and installs `piPkg = llmAgents.packages.${pkgs.system}.pi`; it does not define a separate wrapper executable for launching Pi (`flake.nix:62-76`, `nix/modules/pi/default.nix:230`, `nix/modules/pi/default.nix:345-349`).
- The README’s user-facing startup instructions are `home-manager switch --flake .#<hostname>` for applying config and then `pi` for interactive use (`README.md:41-56`, `README.md:145-158`).
- The generated Pi settings leave startup output enabled via `quietStartup = false` (`nix/modules/pi/default.nix:237-243`).
- The repo configures Pi to load managed packages from generated local facades under `./packages/<packageId>` (`nix/modules/pi/default.nix:263-269`), and those facades are created during activation under `~/.pi/agent/packages/<packageId>` (`nix/modules/pi/default.nix:575-658`, `nix/modules/pi/compile-managed-packages.mjs:610-646`). Any startup warning owned by this repo therefore needs to surface through Pi runtime/UI, not through a repo-owned shell launcher that already exists.

### The repo already includes one startup-capable UI extension surface, but its behavior is documented upstream rather than in-repo
- `pi-powerline-footer` is one of the managed packages declared by this repo (`nix/modules/pi/default.nix:69-77`). Because all non-local managed packages are added to `piSettings.packages`, it is part of the runtime package set (`nix/modules/pi/default.nix:222-225`, `nix/modules/pi/default.nix:263-269`).
- In the upstream `pi-powerline-footer` README captured during this research, the package describes a **“welcome overlay”** shown on startup and says it can display custom extension status items via `ctx.ui.setStatus(...)` plus `powerline.customItems` configuration (`/tmp/pi-github-repos/nicobailon/pi-powerline-footer/README.md:17-18`, `/tmp/pi-github-repos/nicobailon/pi-powerline-footer/README.md:82-120`).
- That same upstream README says the preset selection is restored on startup from `~/.pi/agent/settings.json` (`/tmp/pi-github-repos/nicobailon/pi-powerline-footer/README.md:55-80`).
- The repo’s theme file also defines `warning` and `customMessage*` colors (`nix/modules/pi/default.nix:378-399`). This confirms the configured Pi theme has explicit styling slots for warning-colored/status-like UI text, although this repo does not contain production code that currently emits a startup custom message.

### Desktop notification is available in the package set, but the shipped notification extension is not a startup surface
- `pi-notify` is also a managed package in this repo (`nix/modules/pi/default.nix:109-117`).
- In the upstream `pi-notify` README captured during this research, the extension says it sends a native desktop notification when the agent finishes and is waiting for input, i.e. on `agent_end`, not on startup (`/tmp/pi-github-repos/ferologics/pi-notify/README.md:1-4`, `/tmp/pi-github-repos/ferologics/pi-notify/README.md:41-51`).
- The same upstream README documents terminal compatibility limits: tmux requires passthrough, and Terminal.app/Alacritty are unsupported (`/tmp/pi-github-repos/ferologics/pi-notify/README.md:7-25`, `/tmp/pi-github-repos/ferologics/pi-notify/README.md:87-90`).
- Within this repo/wrapper, that makes `pi-notify` relevant as an already-installed auxiliary surface, but not evidence of an existing startup warning channel.

### The current update workflow is not documented for end users in README/docs
- The README covers installation (`home-manager switch`) and interactive usage (`pi`, `/preset ...`) but contains no user-facing documentation for checking or applying managed Pi package/plugin updates (`README.md:18-56`, `README.md:145-166`).
- A repo-wide search on 2026-05-19 for `check-updates`, `update checker`, `plugin update`, and `extension update` in `README.md` and `docs/` returned no matches.
- The only explicit update helper is `scripts/check-updates.sh`, which describes `--dry-run`, `--update`, and `--help` in its own usage text (`scripts/check-updates.sh:20-29`).
- The flake overlay packages that script as `check-updates` (`flake.nix:81-86`), but the Pi module’s `home.packages` list does not include that overlay package (`nix/modules/pi/default.nix:345-349`). From the checked-in module code alone, end users enabling `engineering-agents.pi` do not automatically get a documented, PATH-installed `check-updates` command.

### The current checker’s messaging style is concise, coded, and split between stdout and stderr
- On startup-like/informational output, the checker prints a small header and the declaration file path (`scripts/check-updates.sh:364-365`).
- For npm packages, it prints one line per package in the form `<packageId> (<packageName>): <current> -> <latest>` (`scripts/check-updates.sh:391-400`).
- For git and local sources, it does not classify freshness. Instead, it emits stable warning codes to stderr:
  - `[PI_PACKAGE_WARN_GIT_SOURCE_MANUAL_UPDATE] <packageId> uses git source <spec>`
  - `[PI_PACKAGE_WARN_LOCAL_SOURCE_NO_AUTO_UPDATE] <packageId> uses local source <spec>`
  (`scripts/check-updates.sh:402-407`)
- After iterating packages, it prints a short summary on stdout: either `No registry-backed npm package updates available.` or `Registry-backed npm updates available: <count>`, followed in dry-run mode by `Run with --update to apply these version changes.` (`scripts/check-updates.sh:414-424`).
- In direct observation against `tests/spec-fixtures/update-checker/pi.nix.sample` on 2026-05-19 with a mocked npm response, stdout contained only the header, one npm version line, the update count, and the `Run with --update...` instruction, while stderr contained the git/local warnings. This confirms the helper already uses a low-noise summary + coded-detail split.

### The current checker is not ready to be quoted to users verbatim without repo-specific context
- The checker defaults `NIX_FILE` to `${SCRIPT_DIR}/pi.nix` (`scripts/check-updates.sh:13-18`). There is no `scripts/pi.nix` in this repo.
- In direct observation on 2026-05-19, `./scripts/check-updates.sh --dry-run` failed with:
  - `Managed Pi package update checker`
  - `Declaration file: /home/spiros/code/engineering-agents/scripts/pi.nix`
  - `declaration file does not exist: /home/spiros/code/engineering-agents/scripts/pi.nix`
  and exited with code 2.
- The actual managed declarations live in `nix/modules/pi/default.nix` (`nix/modules/pi/default.nix:20-220`).
- Because the script’s only built-in user instruction is `Run with --update to apply these version changes.` (`scripts/check-updates.sh:422-424`), a startup warning that tells users merely to “run check-updates” would not match the checked-in repo state unless it also supplies the correct declaration-path context or an updated wrapper invocation.

### The wrapper already has two warning/failure handling patterns: non-blocking coded warnings and hard failures for contract/dependency issues
- `check-updates.sh` uses exit code 2 for missing dependencies or unsupported declaration-contract problems (`scripts/check-updates.sh:36-39`, `scripts/check-updates.sh:73-100`, `scripts/check-updates.sh:361-362`). It uses exit code 1 for usage/update failures such as npm version lookup failure (`scripts/check-updates.sh:31-44`, `scripts/check-updates.sh:393-395`).
- By contrast, git/local source handling in the checker is warning-only and does not affect the exit code or summary counts (`scripts/check-updates.sh:402-417`).
- The activation flow also shows a non-blocking warning pattern: npm install failures are downgraded with `|| echo "Warning: $install_spec install failed"`, and `visual-explainer` update failure is downgraded with `|| echo "Warning: visual-explainer update failed"` (`nix/modules/pi/default.nix:603-609`, `nix/modules/pi/default.nix:664-670`).
- The compile helper returns structured warnings instead of failing when it prunes stale generated artifacts; those warnings are written into `managed-packages.report.json` and printed as `[<code>] <message>` lines during activation (`nix/modules/pi/compile-managed-packages.mjs:580-607`, `nix/modules/pi/compile-managed-packages.mjs:753-790`, `nix/modules/pi/default.nix:644-646`).
- Tests already normalize warning payloads as `{ code, message, packageId?, path? }` and reject unknown warning codes in the snapshot harness (`tests/scripts/resource-snapshot.mjs:13-19`, `tests/scripts/resource-snapshot.mjs:278-306`, `tests/scripts/resource-snapshot.mjs:699-701`).

### Existing repo metadata indicates what is actionable to show, and what is likely to create noise
- The facade package seen by Pi is synthetic: `package.json` is generated with `name: pkg.packageId`, `private: true`, and `version: '0.0.0-generated'` (`nix/modules/pi/compile-managed-packages.mjs:636-644`). The original source identity is stored separately in `meta/source.json` as `source.type`, `source.spec`, `source.materializedKey`, `sourceManifestName`, and `selectedResources` (`nix/modules/pi/compile-managed-packages.mjs:560-577`, `nix/modules/pi/compile-managed-packages.mjs:643-644`).
- This means short package IDs are the most stable user-facing identifiers already available inside Pi runtime. The raw facade version is not actionable because it is always synthetic (`nix/modules/pi/compile-managed-packages.mjs:636-644`).
- Two declared package IDs, `pi-ext-leader-key` and `pi-ext-review`, intentionally point at the same git source/spec and differ only by which extension resource they expose (`nix/modules/pi/default.nix:142-170`). The compiler also deduplicates runtime sources by `{ type, spec }` into one shared `materializedKey` (`nix/modules/pi/compile-managed-packages.mjs:125-140`, `nix/modules/pi/compile-managed-packages.mjs:725-739`). This is concrete evidence that printing long raw git specs per package ID can duplicate content and increase noise.
- The repo already separates concise human messages from deeper metadata: `managed-packages.report.json` stores structured warnings, while the activation script prints only `[code] message` lines (`nix/modules/pi/default.nix:644-646`, `tests/scripts/resource-snapshot.mjs:476-494`). That same split is consistent with the update checker’s summary-on-stdout, coded-detail-on-stderr behavior (`scripts/check-updates.sh:364-424`).

### The only clearly evidenced “next step” in repo-owned user guidance is still to re-apply the Home Manager config
- The README’s installation/apply instructions tell users to run `home-manager switch --flake .#<hostname>` (`README.md:41-45`).
- `check-updates.sh --update` only rewrites declaration fields in a Nix file (`scripts/check-updates.sh:283-338`, `scripts/check-updates.sh:422-454`); it does not install packages or regenerate facades by itself.
- Package install/materialization happens later in Home Manager activation via `installPiExtensions` (`nix/modules/pi/default.nix:575-658`).
- Based on the code in this repo, “update available” and “changes applied to the running Pi package set” are two separate steps. The first is declaration rewrite; the second is `home-manager switch` rerunning activation.

### The extension-spec docs constrain what counts as an existing repo-owned failure-handling option
- The repo’s extension spec says the minimal extension operates entirely on the local filesystem and has **no network dependencies** (`docs/extension-spec.md:221-223`).
- The same document lists **notification hooks** as a future consideration, explicitly not part of the v1 extension (`docs/extension-spec.md:227-234`).
- That means this repo’s own extension-spec documentation does not currently define a repo-owned, networked startup notification mechanism for stale remote plugin checks.

## Constraints Discovered
- There is no checked-in repo launcher that runs before every `pi` start; startup-visible warnings have to be emitted inside Pi runtime or through Pi-loaded extensions (`flake.nix:62-76`, `nix/modules/pi/default.nix:345-349`).
- The README/docs do not currently teach users any plugin-update workflow beyond applying Home Manager config (`README.md:41-56`, `README.md:145-166`).
- The only update helper is not installed by the Pi module and defaults to a non-existent declaration path in this repo (`scripts/check-updates.sh:13-18`, `flake.nix:81-86`, `nix/modules/pi/default.nix:345-349`).
- Runtime facade metadata keeps `packageId` and original `source.spec`, but not a meaningful facade version or a resolved installed git SHA (`nix/modules/pi/compile-managed-packages.mjs:560-577`, `nix/modules/pi/compile-managed-packages.mjs:636-644`).
- Some logical packages share one underlying source (`pi-ext-leader-key` / `pi-ext-review`), so per-package raw-spec messaging can duplicate noise (`nix/modules/pi/default.nix:142-170`, `nix/modules/pi/compile-managed-packages.mjs:725-739`).
- The repo’s own extension spec does not currently define networked startup notifications; notification hooks are deferred (`docs/extension-spec.md:221-234`).

## Risks
- Reusing the current `check-updates` wording unchanged would direct users toward a helper that is undocumented in README/docs and fails by default in this repo (`scripts/check-updates.sh:13-18`, `scripts/check-updates.sh:422-424`).
- Showing raw facade package versions would be misleading because all generated facades use `0.0.0-generated` (`nix/modules/pi/compile-managed-packages.mjs:636-644`).
- Listing every stale/unknown package with full git spec strings can be noisy and repetitive for shared-source packages like `pi-ext-leader-key` and `pi-ext-review` (`nix/modules/pi/default.nix:142-170`, `nix/modules/pi/compile-managed-packages.mjs:725-739`).
- Treating remote-check failures as hard startup failures would not match the repo’s existing warning patterns, which already prefer coded warnings and best-effort continuation for several non-critical cases (`scripts/check-updates.sh:402-417`, `nix/modules/pi/default.nix:603-609`, `nix/modules/pi/default.nix:664-670`).
- Depending on startup surface choice, some already-installed extensions have terminal-specific limitations; for example, upstream `pi-notify` docs say desktop notifications are unsupported in Terminal.app and Alacritty and require tmux passthrough in tmux (`/tmp/pi-github-repos/ferologics/pi-notify/README.md:7-25`, `/tmp/pi-github-repos/ferologics/pi-notify/README.md:87-90`).

## References
- `README.md:18-56` — installation/apply/authentication instructions; no plugin update guidance.
- `README.md:145-166` — Pi usage instructions (`pi`, `/preset ...`), again without update guidance.
- `flake.nix:62-86` — exposes the Pi module and packages only the `check-updates` helper in the overlay.
- `nix/modules/pi/default.nix:69-117` — declares `pi-powerline-footer` and `pi-notify` as managed packages.
- `nix/modules/pi/default.nix:237-269` — generated Pi settings (`quietStartup = false`, `packages = ./packages/<packageId>`).
- `nix/modules/pi/default.nix:345-349` — Pi module `home.packages`; does not install the overlay `check-updates` helper.
- `nix/modules/pi/default.nix:575-658` — activation flow that installs managed packages, compiles facades, and prints compile warnings.
- `nix/modules/pi/compile-managed-packages.mjs:560-577` — provenance metadata written to `meta/source.json`.
- `nix/modules/pi/compile-managed-packages.mjs:636-644` — synthetic facade `package.json` with `version: '0.0.0-generated'`.
- `nix/modules/pi/compile-managed-packages.mjs:725-790` — shared-source deduping and structured warning/report generation.
- `scripts/check-updates.sh:13-29` — helper defaults/usage text.
- `scripts/check-updates.sh:364-424` — current stdout/stderr messaging and summary wording.
- `scripts/check-updates.sh:422-454` — `--update` rewrites declarations only.
- `tests/scripts/resource-snapshot.mjs:13-19` — warning code whitelist used by the snapshot harness.
- `tests/scripts/resource-snapshot.mjs:278-306` — normalized warning shape `{ code, message, packageId?, path? }`.
- `tests/scripts/resource-snapshot.mjs:476-494` — warning data loaded from `managed-packages.report.json`.
- `tests/scripts/resource-snapshot.mjs:699-701` — tests reject unknown warning codes.
- `docs/extension-spec.md:221-234` — extension-spec limits: local filesystem only; notification hooks deferred.
- `/tmp/pi-github-repos/nicobailon/pi-powerline-footer/README.md:17-18` — upstream doc for startup welcome overlay.
- `/tmp/pi-github-repos/nicobailon/pi-powerline-footer/README.md:82-120` — upstream doc for custom extension status items.
- `/tmp/pi-github-repos/ferologics/pi-notify/README.md:41-51` — upstream doc that notifications happen on `agent_end`, not startup.
