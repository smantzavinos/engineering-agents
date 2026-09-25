#!/usr/bin/env bash
# Contract for the paired @richardgill/pi-preset + pi-config 0.0.9 vendor refresh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node jq >/dev/null

REPO_ROOT="$(repo_root)"
PI_CONFIG="$REPO_ROOT/nix/modules/pi/config.nix"
VENDOR_DIR="$REPO_ROOT/nix/modules/pi/managed-packages"
EXPECTED_VERSION="0.0.9"

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

assert_value() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label is $expected"
  else
    fail "$label is '$actual' (expected $expected)"
  fi
}

printf 'Pi preset/config paired refresh contract\n'
printf '=======================================\n\n'

# The Nix source stanza is checked as data, not as a whole-file formatting snapshot.
NIX_PRESET_JSON="$(node - "$PI_CONFIG" <<'NODE'
const fs = require("node:fs");
const source = fs.readFileSync(process.argv[2], "utf8");

function attrsetAt(marker) {
  const markerAt = source.indexOf(marker);
  if (markerAt < 0) return null;
  const open = source.indexOf("{", markerAt);
  if (open < 0) return null;
  let depth = 0;
  let inString = false;
  let escaped = false;
  let inLineComment = false;
  for (let i = open; i < source.length; i++) {
    const ch = source[i];
    if (inLineComment) {
      if (ch === "\n") inLineComment = false;
      continue;
    }
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === "#") inLineComment = true;
    else if (ch === "{") depth++;
    else if (ch === "}" && --depth === 0) return source.slice(open + 1, i);
  }
  return null;
}

function stringField(body, name) {
  const match = body && body.match(new RegExp(`(?:^|\\n)\\s*${name}\\s*=\\s*"([^"]*)"\\s*;`));
  return match ? match[1] : null;
}

const declaration = attrsetAt("pi-preset = {");
const sourceBlock = declaration && (() => {
  const sourceAt = declaration.indexOf("source = {");
  if (sourceAt < 0) return null;
  // Reuse the balanced scanner against the source block's opening brace.
  const sourceText = declaration.slice(sourceAt);
  let depth = 0, inString = false, escaped = false, inLineComment = false;
  const open = sourceText.indexOf("{");
  for (let i = open; i < sourceText.length; i++) {
    const ch = sourceText[i];
    if (inLineComment) { if (ch === "\n") inLineComment = false; continue; }
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === "#") inLineComment = true;
    else if (ch === "{") depth++;
    else if (ch === "}" && --depth === 0) return sourceText.slice(open + 1, i);
  }
  return null;
})();

console.log(JSON.stringify({
  type: stringField(sourceBlock, "type"),
  packageName: stringField(sourceBlock, "packageName"),
  spec: stringField(sourceBlock, "spec"),
  installSpec: stringField(sourceBlock, "installSpec"),
  version: stringField(declaration, "version"),
}));
NODE
)"

MANIFEST="$VENDOR_DIR/package.json"
LOCK="$VENDOR_DIR/package-lock.json"
for package in config preset; do
  package_name="@richardgill/pi-$package"
  assert_value "$(jq -r --arg name "$package_name" '.dependencies[$name] // "<missing>"' "$MANIFEST")" \
    "$EXPECTED_VERSION" "package.json dependency $package_name"
  assert_value "$(jq -r --arg name "$package_name" '.packages[""].dependencies[$name] // "<missing>"' "$LOCK")" \
    "$EXPECTED_VERSION" "package-lock root dependency $package_name"
  assert_value "$(jq -r --arg name "$package_name" '.packages["node_modules/" + $name].version // "<missing>"' "$LOCK")" \
    "$EXPECTED_VERSION" "package-lock installed root $package_name"
done

assert_value "$(jq -r '.packages["node_modules/@richardgill/pi-preset"].dependencies["@richardgill/pi-config"] // "<missing>"' "$LOCK")" \
  "$EXPECTED_VERSION" "package-lock pi-preset dependency on pi-config"

# Nested lock placements, if npm emits one for pi-config, must not retain a stale version.
NESTED_CONFIG_VERSIONS="$(jq -r '[.packages | to_entries[] | select(.key | endswith("/node_modules/@richardgill/pi-config")) | .value.version] | unique | join(",")' "$LOCK")"
if [[ -z "$NESTED_CONFIG_VERSIONS" || "$NESTED_CONFIG_VERSIONS" == "$EXPECTED_VERSION" ]]; then
  pass "nested pi-config lock placements are absent or $EXPECTED_VERSION"
else
  fail "nested pi-config lock placements have version(s) '$NESTED_CONFIG_VERSIONS' (expected only $EXPECTED_VERSION)"
fi

for field in type packageName spec installSpec version; do
  actual="$(jq -r --arg field "$field" '.[$field] // "<missing>"' <<<"$NIX_PRESET_JSON")"
  case "$field" in
    type) expected="npm" ;;
    packageName) expected="@richardgill/pi-preset" ;;
    spec|installSpec) expected="@richardgill/pi-preset@$EXPECTED_VERSION" ;;
    version) expected="$EXPECTED_VERSION" ;;
  esac
  assert_value "$actual" "$expected" "config.nix pi-preset source $field"
done

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
