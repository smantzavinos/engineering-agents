#!/usr/bin/env bash
# Verify the build-time managed-package vendor contracts:
#   - every git-source declaration has a matching immutable fetchzip pin
#   - declaration spec/installSpec pairs are normalized (no drift)
#   - the vendor package.json does not vendor pi's injected core
#   - the lock is peer-complete (generated with --install-strategy=nested)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node jq >/dev/null

REPO_ROOT="$(repo_root)"
PI_CONFIG="$REPO_ROOT/nix/modules/pi/config.nix"
VENDOR_DIR="$REPO_ROOT/nix/modules/pi/managed-packages"

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

printf 'Pi vendor contract verification\n'
printf '===============================\n\n'

# ------------------------------------------------------------
# Extract declarations: id, type, packageName, spec, installSpec
# ------------------------------------------------------------
DECLS_JSON="$(node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8");
// Extract the managedPackages attrset body by brace matching.
const start = src.indexOf("managedPackages = {");
if (start < 0) { console.error("managedPackages not found"); process.exit(1); }
let depth = 0, end = -1;
for (let i = src.indexOf("{", start); i < src.length; i++) {
  if (src[i] === "{") depth++;
  else if (src[i] === "}") { depth--; if (depth === 0) { end = i; break; } }
}
const body = src.slice(start, end)
  // Strip Nix line comments: a comment between fields would otherwise make the
  // declaration regex below silently skip the whole package, letting a git
  // source escape the immutable-pin check (pi-powerline-footer did exactly that).
  .replace(/^[ \t]*#.*$/gm, "");
const decls = {};
const re = /(\S+)\s*=\s*\{\s*source\s*=\s*\{\s*type\s*=\s*"([^"]+)";\s*packageName\s*=\s*"([^"]+)";\s*spec\s*=\s*"([^"]+)";\s*installSpec\s*=\s*"([^"]+)";/g;
let m;
while ((m = re.exec(body))) {
  decls[m[1]] = { type: m[2], packageName: m[3], spec: m[4], installSpec: m[5] };
}
console.log(JSON.stringify(decls));
' "$PI_CONFIG")"

DECL_COUNT="$(jq 'length' <<<"$DECLS_JSON")"
if [ "$DECL_COUNT" -ge 15 ]; then
  pass "managedPackages declares $DECL_COUNT packages"
else
  fail "managedPackages declares only $DECL_COUNT packages (expected >= 15)"
fi

if grep -Eq 'pi-gitnexus|includeGitNexus|enableGitNexus' "$PI_CONFIG" "$REPO_ROOT/nix/modules/pi/default.nix" "$REPO_ROOT/nix/modules/pi/nixos-user.nix"; then
  fail "retired GitNexus must not remain in Pi declarations or module options"
else
  pass "retired GitNexus is absent from Pi declarations and module options"
fi

if grep -Fq 'pi-session-autoname = {' "$PI_CONFIG" \
  && ! grep -Fq 'pi-auto-rename = {' "$PI_CONFIG" \
  && jq -e '.dependencies["@camillof/pi-session-autoname"] == "0.1.2" and (.dependencies | has("@byteowlz/pi-auto-rename") | not)' \
    "$VENDOR_DIR/package.json" >/dev/null; then
  pass "Copilot-aware session namer replaces old pi-auto-rename exclusively"
else
  fail "session namer declaration and vendor pins must replace old auto-rename"
fi

# pi-tasks: git fork carrying the session_shutdown spinner fix (upstream
# tintinweb/pi-tasks#65). Its vendor dir must not be @tintinweb/pi-tasks, or
# installGitPackage would overwrite the npm copy pi-ext's manifest pulls in.
if jq -e '.["pi-tasks"] | .type == "git" and .packageName == "pi-tasks" and (.spec | startswith("github:smantzavinos/pi-tasks#"))' \
     <<<"$DECLS_JSON" >/dev/null; then
  pass "pi-tasks is pinned to the smantzavinos fork in its own vendor dir"
else
  fail "pi-tasks must be a git declaration on the smantzavinos fork with packageName pi-tasks"
fi
if [[ "$(jq '[.[] | select(.packageName == "@tintinweb/pi-tasks")] | length' <<<"$DECLS_JSON")" == 0 ]]; then
  pass "no managed declaration materializes into the npm @tintinweb/pi-tasks dir"
else
  fail "a managed declaration uses packageName @tintinweb/pi-tasks (would clobber pi-ext's npm copy)"
fi

# pi-guardrails: smantzavinos fork (upstream main + #99 tool registration
# protocol). Its registry deps must be vendored and the npm release removed.
if jq -e '.["pi-guardrails"] | .type == "git" and .packageName == "pi-guardrails" and (.spec | startswith("github:smantzavinos/pi-guardrails#"))' \
     <<<"$DECLS_JSON" >/dev/null \
  && jq -e '(.dependencies | has("@aliou/pi-guardrails") | not) and .dependencies["@aliou/sh"] != null and .dependencies["@aliou/pi-utils-settings"] != null' \
       "$VENDOR_DIR/package.json" >/dev/null; then
  pass "pi-guardrails uses the smantzavinos fork with its registry deps vendored"
else
  fail "pi-guardrails must be the smantzavinos fork git source, with @aliou/sh + @aliou/pi-utils-settings vendored and no npm @aliou/pi-guardrails"
fi

# spec/installSpec normalization
UNNORMALIZED="$(jq '[to_entries[] | select(.value.spec != .value.installSpec)] | length' <<<"$DECLS_JSON")"
if [ "$UNNORMALIZED" = "0" ]; then
  pass "every declaration has spec == installSpec (normalized)"
else
  fail "$UNNORMALIZED declarations have spec != installSpec"
fi

# Git declarations: immutable 40-hex commits with matching fetchzip pins
GIT_IDS="$(jq -r '[to_entries[] | select(.value.type == "git")] | .[] | .key' <<<"$DECLS_JSON")"
for id in $GIT_IDS; do
  spec="$(jq -r --arg id "$id" '.[$id].spec' <<<"$DECLS_JSON")"
  pkg_name="$(jq -r --arg id "$id" '.[$id].packageName' <<<"$DECLS_JSON")"
  rev="${spec##*#}"
  if [[ ! "$rev" =~ ^[0-9a-f]{40}$ ]]; then
    fail "git declaration $id spec is not a 40-hex commit: $spec"
    continue
  fi
  if grep -Fq '"'"$pkg_name"'" = {' "$PI_CONFIG" && \
     grep -Fq "rev = \"$rev\";" "$PI_CONFIG" && \
     grep -Fq "/archive/$rev.tar.gz" "$PI_CONFIG"; then
    pass "git declaration $id has matching immutable fetchzip pin ($rev)"
  else
    fail "git declaration $id ($rev) is missing its gitSources fetchzip pin"
  fi
done

# ------------------------------------------------------------
# Vendor package.json must not vendor pi's injected core
# ------------------------------------------------------------
INJECTED=(
  "@earendil-works/pi-ai" "@earendil-works/pi-agent-core"
  "@earendil-works/pi-coding-agent" "@earendil-works/pi-tui"
  "typebox"
)
for dep in "${INJECTED[@]}"; do
  if jq -e --arg dep "$dep" '.dependencies[$dep] != null' "$VENDOR_DIR/package.json" >/dev/null 2>&1; then
    fail "vendor package.json must not vendor injected core: $dep"
  else
    pass "vendor package.json does not vendor injected core: $dep"
  fi
done

# ------------------------------------------------------------
# Lock shape: nested placement present for at least one managed package
# and lockfile is parseable
# ------------------------------------------------------------
if jq -e '.packages | length > 0' "$VENDOR_DIR/package-lock.json" >/dev/null 2>&1; then
  pass "package-lock.json parses with entries"
else
  fail "package-lock.json missing or malformed"
fi

if jq -e '.packages | keys[] | select(contains("node_modules/@richardgill/pi-preset/node_modules/"))' \
     "$VENDOR_DIR/package-lock.json" >/dev/null 2>&1; then
  pass "lock uses nested placement (self-contained managed packages)"
else
  fail "lock has no nested entries under @richardgill/pi-preset (was it generated without --install-strategy=nested?)"
fi

# Peer entries must remain in the lock (offline npm ci needs complete resolution)
if jq -e '[.packages[].peerDependencies? // empty] | length > 0' "$VENDOR_DIR/package-lock.json" >/dev/null 2>&1; then
  pass "lock keeps peer dependency metadata"
else
  fail "lock has no peerDependencies entries anywhere (peer-stripped locks break offline npm ci)"
fi

# ------------------------------------------------------------
# refresh-lock.sh is executable and documents the nested strategy
# ------------------------------------------------------------
if [[ -x "$VENDOR_DIR/refresh-lock.sh" ]] && grep -Fq -- "--install-strategy=nested" "$VENDOR_DIR/refresh-lock.sh"; then
  pass "refresh-lock.sh is executable and pins the nested install strategy"
else
  fail "refresh-lock.sh missing, not executable, or no longer pins --install-strategy=nested"
fi

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
