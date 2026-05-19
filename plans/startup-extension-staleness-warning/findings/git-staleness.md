# Git-based plugin staleness detection in the current install model

**Created:** 2026-05-19
**Topic:** How this repo represents git-installed Pi packages today, what "upstream has advanced" can mean for those installs, which git metadata/commands could support that check, and which failure modes matter.
**Plan:** `plans/startup-extension-staleness-warning/brief.md`

## Summary
This repo declares managed Pi packages in `nix/modules/pi/default.nix`, then installs them into the global npm prefix during Home Manager activation. Git-backed packages are installed with `npm install -g --install-links --legacy-peer-deps "$install_spec"`, and the wrapper then generates facade packages under `~/.pi/agent/packages/<packageId>` that point back to a shared materialized source tree. The persisted wrapper metadata keeps the declared git `source.spec` and a derived `materializedKey`, but it does **not** record the resolved commit that was actually installed (`nix/modules/pi/default.nix:612-645`, `nix/modules/pi/compile-managed-packages.mjs:125-139,560-577,702-739`).

That missing resolved-commit record is the main constraint for git staleness detection. For npm packages, the repo can compare declared version vs registry version, and the existing `scripts/check-updates.sh` does that. For git packages, the current manual checker only emits a warning and does not determine freshness (`scripts/check-updates.sh:391-406`). The installed package trees are not local git checkouts, and their `package.json` metadata is not reliable as the source of truth for the install remote: some installed packages point at a different upstream repo than the declared install spec, and some expose no `repository` field at all (`/home/spiros/.pi/agent/managed-packages.declarations.json:49-103,153-158`; `/home/spiros/.pi/packages/lib/node_modules/pi-subagents/package.json:8-12`; `/home/spiros/.pi/packages/lib/node_modules/pi-gitnexus/package.json:7-14`; `/home/spiros/.pi/packages/lib/node_modules/pi-hooks/package.json:1-22`; `/home/spiros/.pi/packages/lib/node_modules/pi-ext/package.json:1-54`).

## Findings

### Git installs are declared centrally, but the persisted runtime metadata only preserves the declared spec
The repo's managed Pi packages live in the `piPackages` attrset in `nix/modules/pi/default.nix:20-220`. Current git-backed declarations include:

- `pi-subagents` with `spec = "github:smantzavinos/pi-subagents#feat/agent-overrides-all-sources"` (`nix/modules/pi/default.nix:21-28`)
- `pi-hooks` with `spec = "github:smantzavinos/pi-hooks"` (`nix/modules/pi/default.nix:30-37`)
- `pi-ext-leader-key` and `pi-ext-review` with the same pinned commit spec `github:tomsej/pi-ext#515352c80bc1ee7e22ed08add915efa220c4c822` (`nix/modules/pi/default.nix:142-169`)
- `pi-gitnexus` with `spec = "github:smantzavinos/pi-gitnexus#fix/session-shutdown-cleanup"` (`nix/modules/pi/default.nix:212-219`)

During activation, `installPiExtensions` installs npm sources only when the declared version is absent, but always reinstalls git sources by uninstalling the package name and then running `npm install -g --install-links --legacy-peer-deps "$install_spec"` (`nix/modules/pi/default.nix:594-624`). After installation, the activation script writes `managed-packages.declarations.json`, keeping only:

- `source.type`
- `source.spec`
- `source.materializedPath`
- optional `expose`

for non-local packages (`nix/modules/pi/default.nix:626-642`).

The compiler then derives a `materializedKey` from only `source.type` and `source.spec` (`nix/modules/pi/compile-managed-packages.mjs:125-139`) and writes facade metadata containing only:

- `source.type`
- `source.spec`
- `source.materializedKey`
- `sourceManifestName`
- `sourceRoot`
- selected resources

(`nix/modules/pi/compile-managed-packages.mjs:560-577,610-645`). There is no field for a resolved branch head, tag object, or installed commit SHA.

The current runtime files match that contract. For example, the live declaration file keeps git specs and materialized paths for `pi-ext-leader-key`, `pi-ext-review`, `pi-gitnexus`, `pi-hooks`, and `pi-subagents` (`/home/spiros/.pi/agent/managed-packages.declarations.json:49-103,153-158`), while `~/.pi/agent/packages/pi-ext-leader-key/meta/source.json` stores only the git spec plus a derived `materializedKey` (`/home/spiros/.pi/agent/packages/pi-ext-leader-key/meta/source.json:1-18`).

### Installed git package trees are npm materializations, not local git clones
The activation flow materializes git sources under the npm global prefix (`$HOME/.pi/packages/lib/node_modules/<packageName>`) and then symlinks wrapper-owned source roots back to those directories (`nix/modules/pi/default.nix:626-642`; `nix/modules/pi/compile-managed-packages.mjs:726-730,616-618`).

In the current installation, those materialized trees do not contain local git metadata. A direct filesystem inspection of:

- `~/.pi/packages/lib/node_modules/pi-subagents`
- `~/.pi/packages/lib/node_modules/pi-hooks`
- `~/.pi/packages/lib/node_modules/pi-ext`
- `~/.pi/packages/lib/node_modules/pi-gitnexus`

showed no `.git` directory, no `package-lock.json`, and no `.package-lock.json` for those package roots on 2026-05-19. That matches npm's documented behavior for git dependencies: npm clones/builds as needed and installs the resulting package content rather than preserving a working checkout. The npm docs state that git dependencies are installed from a git remote URL or GitHub shorthand and that `#<commit-ish>` selects the commit-ish while omission falls back to the default branch (npm install docs, "npm install <git remote url>" and "npm install github:<user>/<repo>[#<commit-ish>]" sections; https://docs.npmjs.com/cli/v10/commands/npm-install and https://docs.npmjs.com/cli/v10/configuring-npm/package-json#git-urls-as-dependencies).

Practical consequence: a startup freshness check cannot rely on local commands such as `git rev-parse`, `git remote get-url`, or `git status` inside the installed package directories, because those directories are not git repositories in this install model.

### Installed package.json metadata is insufficient, and sometimes misleading, for git freshness
The most stable local source of truth for git installs is the wrapper-generated `source.spec`, not the installed package's own `package.json`.

Evidence from the current installation:

- `pi-subagents` is declared from `github:smantzavinos/pi-subagents#feat/agent-overrides-all-sources` (`/home/spiros/.pi/agent/managed-packages.declarations.json:153-158`), but the installed package metadata says its repository is `git+https://github.com/nicobailon/pi-subagents.git` (`/home/spiros/.pi/packages/lib/node_modules/pi-subagents/package.json:8-12`).
- `pi-gitnexus` is declared from `github:smantzavinos/pi-gitnexus#fix/session-shutdown-cleanup` (`/home/spiros/.pi/agent/managed-packages.declarations.json:81-87`), but the installed package metadata points to `https://github.com/tintinweb/pi-gitnexus.git` (`/home/spiros/.pi/packages/lib/node_modules/pi-gitnexus/package.json:7-14`).
- `pi-hooks` is declared from `github:smantzavinos/pi-hooks` (`/home/spiros/.pi/agent/managed-packages.declarations.json:97-103`), but the installed package metadata has no `repository` field at all (`/home/spiros/.pi/packages/lib/node_modules/pi-hooks/package.json:1-22`).
- `pi-ext-leader-key` and `pi-ext-review` are both declared from the same pinned git source (`/home/spiros/.pi/agent/managed-packages.declarations.json:49-78`), but the installed `pi-ext` package also has no `repository` field (`/home/spiros/.pi/packages/lib/node_modules/pi-ext/package.json:1-54`).

In the observed installs, `gitHead` is also absent/null for these packages. That means the installed package metadata does not preserve enough information to answer "what commit is installed?" or even "which remote should be checked?" reliably.

### The current model already groups multiple facades that share one git source
`compile-managed-packages.mjs` hashes only `source.type` + `source.spec` to build the `materializedKey` (`nix/modules/pi/compile-managed-packages.mjs:125-139`). It then caches a single source root per `materializedKey` (`nix/modules/pi/compile-managed-packages.mjs:726-739`).

That behavior is visible in the live install:

- `pi-ext-leader-key` and `pi-ext-review` both record `materializedKey = "src-814e2d65bd08a81f"` in their metadata (`/home/spiros/.pi/agent/packages/pi-ext-leader-key/meta/source.json:4-18`; `/home/spiros/.pi/agent/packages/pi-ext-review/meta/source.json` in the current installation).
- `managed-packages.report.json` lists both packages against the same shared source root (`/home/spiros/.pi/agent/managed-packages.report.json`, entries for `pi-ext-leader-key` and `pi-ext-review`).

Practical consequence: a git staleness probe keyed by declared git spec can be reused across multiple wrapper package IDs that expose different subsets of one underlying repo.

### "Upstream has advanced" depends on what kind of git spec was declared
The npm docs distinguish these cases for git dependencies:

- no `#<commit-ish>` means use the repository default branch
- `#<commit-ish>` may be a branch, tag, or commit-ish
- `#semver:<range>` means resolve against matching tags/refs

(https://docs.npmjs.com/cli/v10/commands/npm-install and https://docs.npmjs.com/cli/v10/configuring-npm/package-json#git-urls-as-dependencies).

Applied to this repo's current declarations:

1. **No explicit ref** — `pi-hooks` uses `github:smantzavinos/pi-hooks` (`nix/modules/pi/default.nix:30-37`). For this form, "upstream has advanced" naturally maps to "the remote default branch HEAD is now at a different commit than the installed package was built from." On 2026-05-19, `git ls-remote --symref https://github.com/smantzavinos/pi-hooks.git HEAD` reported `refs/heads/main` and commit `5575c124425ce80bc677ff0e734a51fb0daa899c`.
2. **Named branch** — `pi-subagents` and `pi-gitnexus` use branch refs (`nix/modules/pi/default.nix:21-28,212-219`). For this form, the clearest meaning is "the named branch head has moved." On 2026-05-19, `git ls-remote --symref` showed:
   - `pi-subagents`: default `HEAD -> refs/heads/main` at `2f931d42624aa26693bf33f7cfceb76b28c34fdb`, while `refs/heads/feat/agent-overrides-all-sources` was `7fd616409b032fb942b311765578a3adb9b79586`
   - `pi-gitnexus`: default `HEAD -> refs/heads/master` at `9b982f448a5d60b4e31077edb897c3b7345d3d89`, while `refs/heads/fix/session-shutdown-cleanup` was `fa63bd3f6156cec943e42411ec0fc1909181dd2c`
3. **Pinned commit** — `pi-ext-leader-key` and `pi-ext-review` pin `#515352c80bc1ee7e22ed08add915efa220c4c822` (`nix/modules/pi/default.nix:142-169`). The brief explicitly says git installs are stale if upstream has advanced even when the installed ref/tag is pinned. In the current repo, `git ls-remote --symref https://github.com/tomsej/pi-ext.git HEAD refs/heads/* refs/tags/*` showed that `HEAD` and `refs/heads/main` are currently the same commit as the pin, while tag `v0.1.0` points elsewhere (`ef6f4ee14f8c4b3f5419ed0f266be112ecb38dd8`).

The repo does **not** currently define, in code, which remote ref counts as "upstream" for a pinned commit or tag. Because no resolved commit is stored locally, that meaning must be derived from policy plus a remote lookup, not from existing persisted metadata.

### Git commands that can support the check in this install model
Because the install roots are not git repos, the usable commands are remote-oriented rather than local-repo-oriented.

#### `git ls-remote --symref <url> HEAD [patterns...]`
Git's documentation says `git ls-remote` lists references in a remote repository and `--symref` shows what symbolic `HEAD` points to (https://git-scm.com/docs/git-ls-remote). This is the best fit for:

- discovering the default branch and its current OID
- checking a named branch (`refs/heads/<branch>`)
- checking a tag (`refs/tags/<tag>` and, for annotated tags, `refs/tags/<tag>^{}`)

For the current GitHub-hosted specs, this command succeeded directly against HTTPS remotes on 2026-05-19 and returned the data needed to resolve default-branch and branch-based meanings of "advanced".

#### `git ls-remote --exit-code <url> <pattern>`
The git docs say `--exit-code` returns status 2 when no matching refs are found. That is useful when the spec refers to a branch or tag name that no longer exists. It is **not** useful for raw commit SHAs, because a commit SHA is not a refname and `git ls-remote <url> <sha>` returned no match in the current test against `tomsej/pi-ext`.

#### Temporary-repo fetch for exact commit SHAs
A raw pinned commit may not appear in `ls-remote` output unless some advertised ref still points at it. In the current environment, a temporary repo plus `git fetch --depth=1 origin <sha>` succeeded for `515352c80bc1ee7e22ed08add915efa220c4c822` against `https://github.com/tomsej/pi-ext.git` on 2026-05-19. That is the strongest observed command for answering "does this exact pinned commit still resolve remotely?" in this install model.

#### Optional ancestry checks after fetching relevant refs
If the policy for pinned commits/tags is "stale when default branch has moved beyond the pinned object," then a temporary repo could also fetch both the pinned object and the chosen upstream ref and use ancestry/merge-base style checks. The current repo does not implement that today, but the install model does not expose any other local metadata that would answer that question.

### Failure modes for git freshness checks in this install model
The git check path in this repo is inherently remote-dependent, because the installed package trees are not local git repositories and the wrapper does not persist resolved install commits (`nix/modules/pi/compile-managed-packages.mjs:560-577,726-739`). That creates several distinct failure classes:

- **Offline / network failure:** `git ls-remote` and `git fetch` require remote connectivity. If DNS, TLS, proxying, or general network access fails, the repo has no local fallback metadata that can still prove freshness.
- **Authentication / authorization failure:** npm's git install docs explicitly describe git installs as using git remotes and note the git-related environment variables npm passes through for git operations. In practice that means private repos or expired credentials can fail during the same class of remote operations used for freshness checks (https://docs.npmjs.com/cli/v10/commands/npm-install).
- **Missing remote metadata locally:** installed package directories do not expose a usable local remote configuration. Some packages have no `repository` field at all (`/home/spiros/.pi/packages/lib/node_modules/pi-hooks/package.json:1-22`; `/home/spiros/.pi/packages/lib/node_modules/pi-ext/package.json:1-54`), and some point at a different upstream than the declared install spec (`/home/spiros/.pi/packages/lib/node_modules/pi-subagents/package.json:8-12`; `/home/spiros/.pi/packages/lib/node_modules/pi-gitnexus/package.json:7-14`).
- **Deleted or renamed remote refs:** for branch/tag specs, `git ls-remote --exit-code` can show that a named ref no longer exists, but that is an unresolvable/unknown state rather than proof that the installed copy is stale.
- **Detached-ref semantics for raw SHAs:** a raw commit SHA is not a refname, so `git ls-remote <url> <sha>` does not reliably answer whether that commit exists remotely. In the current environment, only a temporary repo plus `git fetch --depth=1 origin <sha>` proved the pinned `pi-ext` SHA resolvable.
- **Pinned tag handling:** tags may be lightweight or annotated, and `git ls-remote` can return both `refs/tags/<tag>` and `refs/tags/<tag>^{}`. Any tag-based check must account for that peeled-tag behavior (https://git-scm.com/docs/git-ls-remote).
- **Pinned-ref policy ambiguity:** the brief says pinned refs/tags should still count as stale when upstream advances, but the current codebase does not define whether "upstream" means default branch HEAD, the pinned branch head, a matching tag, or some other ref for a pinned object.

### The current manual update checker does not cover git freshness
`scripts/check-updates.sh` parses a `piPackages` attrset and validates only three source types: `npm`, `git`, and `local` (`scripts/check-updates.sh:57-103`). In its main loop:

- npm packages are compared to `npm view <package> version` and can be rewritten in place (`scripts/check-updates.sh:391-400`)
- git packages only emit `[PI_PACKAGE_WARN_GIT_SOURCE_MANUAL_UPDATE] <packageId> uses git source <spec>` (`scripts/check-updates.sh:402-404`)
- local packages only emit `[PI_PACKAGE_WARN_LOCAL_SOURCE_NO_AUTO_UPDATE] ...` (`scripts/check-updates.sh:405-406`)

So the existing workflow does **not** determine whether a git install is current or stale; it only labels git packages as requiring manual handling.

A separate constraint: the script defaults `NIX_FILE` to `${SCRIPT_DIR}/pi.nix` (`scripts/check-updates.sh:13-18`), but this repository currently has `scripts/check-updates.sh` and no `scripts/pi.nix` in-tree. In this repo as checked out on 2026-05-19, a caller must override `PI_UPDATE_CHECKER_NIX_FILE` or provide an equivalent file path. That matters for any startup warning that wants to direct users toward the existing check/update workflow.

## Constraints Discovered
- The wrapper persists declared git specs, but not the resolved commit that npm actually installed (`nix/modules/pi/default.nix:626-642`; `nix/modules/pi/compile-managed-packages.mjs:560-577`).
- Materialized install roots are npm package directories, not git working trees, so local git commands cannot be run in-place for freshness (`nix/modules/pi/compile-managed-packages.mjs:726-730`; observed current install under `~/.pi/packages/lib/node_modules/*`).
- Installed `package.json` metadata cannot be trusted as the install source of truth: it may point at a different upstream repo than the declared spec, or no repo at all (`/home/spiros/.pi/packages/lib/node_modules/pi-subagents/package.json:8-12`; `/home/spiros/.pi/packages/lib/node_modules/pi-gitnexus/package.json:7-14`; `/home/spiros/.pi/packages/lib/node_modules/pi-hooks/package.json:1-22`; `/home/spiros/.pi/packages/lib/node_modules/pi-ext/package.json:1-54`).
- Multiple wrapper package IDs can share a single git source root, so status must be deduplicated by git spec/materialized source, not just by package ID (`nix/modules/pi/compile-managed-packages.mjs:125-139,726-739`).
- The existing manual checker only warns for git packages; it does not compute stale-vs-current for them (`scripts/check-updates.sh:402-404`).
- The current `check-updates.sh` default declaration path does not exist in this repo checkout (`scripts/check-updates.sh:13-18`; observed `scripts/` contains only `check-updates.sh`).

## Risks
- **Unknown status for branch/no-ref installs:** because no resolved installed OID is stored, the repo cannot currently prove whether a branch/default-branch install is already at today's remote head or is behind it without adding some persisted install-time state.
- **Pinned-ref ambiguity:** the brief says pinned refs/tags should still count as stale when upstream advances, but the current codebase does not define which upstream ref should be compared against a pin. For commits not on the default branch, "advanced" may be ambiguous.
- **Network/auth fragility:** remote-oriented checks (`git ls-remote`, `git fetch`) can fail due to offline state, DNS/TLS issues, private repos, expired credentials, or repository removal/rename. The brief already requires these to be non-blocking and distinguishable from confirmed stale.
- **Missing/moved refs:** branch or tag names in a git spec can disappear; `git ls-remote --exit-code` can detect that, but it becomes an "unknown/unresolvable" condition rather than a confirmed stale state.
- **Annotated/lightweight tag differences:** tag checks need to account for peeled tags (`refs/tags/<tag>^{}`) because `git ls-remote` can return both the tag object and its dereferenced target.
- **Contradictory user guidance risk:** if startup warnings treat git packages as stale but the manual checker only prints generic manual-update warnings, messaging can contradict the existing workflow unless wording is careful.

## References
- `nix/modules/pi/default.nix:20-220` — canonical `piPackages` declarations, including all git-backed managed packages.
- `nix/modules/pi/default.nix:575-645` — activation script that installs npm/git sources and writes `managed-packages.declarations.json`.
- `nix/modules/pi/compile-managed-packages.mjs:125-139` — `buildMaterializedKey()` hashes only `source.type` + `source.spec`.
- `nix/modules/pi/compile-managed-packages.mjs:560-577` — `buildMetadata()` writes persisted facade provenance; no resolved commit is stored.
- `nix/modules/pi/compile-managed-packages.mjs:726-739` — compiler caches one source root per materialized key/spec.
- `scripts/check-updates.sh:13-18` — manual checker default input path configuration.
- `scripts/check-updates.sh:57-103` — checker parser contract for `npm`, `git`, and `local` sources.
- `scripts/check-updates.sh:391-406` — npm packages are checked; git/local packages only emit warnings.
- `/home/spiros/.pi/agent/managed-packages.declarations.json:49-103,153-158` — live persisted git declarations and materialized paths.
- `/home/spiros/.pi/agent/packages/pi-ext-leader-key/meta/source.json:1-18` — live facade metadata for a git-backed package.
- `/home/spiros/.pi/packages/lib/node_modules/pi-subagents/package.json:8-12` — installed package metadata points to a different repo than the declared git spec.
- `/home/spiros/.pi/packages/lib/node_modules/pi-gitnexus/package.json:7-14` — installed package metadata points to a different repo than the declared git spec.
- `/home/spiros/.pi/packages/lib/node_modules/pi-hooks/package.json:1-22` — installed git-backed package has no repository field.
- `/home/spiros/.pi/packages/lib/node_modules/pi-ext/package.json:1-54` — installed git-backed package has no repository field.
- `https://git-scm.com/docs/git-ls-remote` — git reference for remote ref enumeration and `--symref` / `--exit-code` behavior.
- `https://docs.npmjs.com/cli/v10/commands/npm-install` — npm install semantics for git URLs, GitHub shorthand, default-branch resolution, and `#<commit-ish>`.
- `https://docs.npmjs.com/cli/v10/configuring-npm/package-json#git-urls-as-dependencies` — npm package.json reference for git dependency forms and GitHub shorthand.
