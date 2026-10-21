#!/usr/bin/env bash
# Shared activation filter: declarative settings override runtime preferences;
# retired Powerline editor keys migrate only for declarative native fullscreen.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands jq >/dev/null

MERGE_FILTER="$(repo_root)/nix/modules/pi/merge-settings.jq"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

merge_settings() {
  local description="$1"
  if ! jq -s -f "$MERGE_FILTER" "$TMP_DIR/old.json" "$TMP_DIR/nix.json" \
      >"$TMP_DIR/merged.json" 2>"$TMP_DIR/merge.stderr"; then
    cat "$TMP_DIR/merge.stderr" >&2
    fail "$description: shared settings filter must merge OLD_SETTINGS then NIX_SETTINGS"
  fi
  if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$TMP_DIR/merged.json" >/dev/null; then
    fail "$description: shared settings filter must emit exactly one settings object"
  fi
}

assert_json() {
  local description="$1" filter="$2"
  if jq -e "$filter" "$TMP_DIR/merged.json" >/dev/null; then
    printf 'PASS: %s\n' "$description"
  else
    cat "$TMP_DIR/merged.json" >&2
    fail "$description"
  fi
}

cat >"$TMP_DIR/old.json" <<'JSON'
{
  "packages": ["./packages/pi-zentui", "runtime-only-package"],
  "tuiMode": "regular",
  "theme": "runtime-theme",
  "runtimeOnly": {"enabled": true},
  "powerline": {
    "queue": {"compactPromptMode": "extension", "runtimePreference": false},
    "fixedEditor": true,
    "mouseScroll": false,
    "preset": "runtime-preset",
    "path": {"mode": "full", "maxLength": 12},
    "customItems": ["runtime-item"]
  },
  "powerlineShortcuts": {
    "scrollChatUp": "alt+u",
    "scrollChatDown": "alt+d",
    "toggleWelcome": "alt+w"
  }
}
JSON
cat >"$TMP_DIR/nix.json" <<'JSON'
{
  "packages": ["./packages/pi-powerline-footer"],
  "tuiMode": "fullscreen",
  "theme": "declarative-theme",
  "powerline": {"preset": "nerd", "path": {"maxLength": 36}, "queue": {"compactPromptMode": "native"}},
  "powerlineShortcuts": {}
}
JSON

merge_settings 'declarative Powerline native fullscreen migration'
assert_json 'Nix wins scalars and replaces package arrays while runtime-only preferences survive' \
  '.packages == ["./packages/pi-powerline-footer"] and .tuiMode == "fullscreen"
   and .theme == "declarative-theme" and .runtimeOnly == {enabled: true}'
assert_json 'nested objects merge recursively without losing runtime siblings or unrelated shortcut keys' \
  '.powerline == {preset: "nerd", path: {mode: "full", maxLength: 36}, customItems: ["runtime-item"],
                  queue: {compactPromptMode: "native", runtimePreference: false}}
   and .powerlineShortcuts == {toggleWelcome: "alt+w"}'
assert_json 'fullscreen migration deletes all four retired keys, including a false-valued setting' \
  '(.powerline | has("fixedEditor") or has("mouseScroll") | not)
   and (.powerlineShortcuts | has("scrollChatUp") or has("scrollChatDown") | not)'

# Runtime already selects Powerline+fullscreen: neither inherited selector may
# opt into cleanup when the declarative input omits it or chooses another UI.
jq '.packages = ["./packages/pi-powerline-footer"] | .tuiMode = "fullscreen"' \
  "$TMP_DIR/old.json" >"$TMP_DIR/runtime-native.json"
mv "$TMP_DIR/runtime-native.json" "$TMP_DIR/old.json"
while IFS='|' read -r description declarative; do
  printf '%s\n' "$declarative" >"$TMP_DIR/nix.json"
  merge_settings "$description"
  assert_json "$description preserves retired settings and unrelated preferences" \
    '.powerline == {fixedEditor: true, mouseScroll: false, preset: "runtime-preset",
                    path: {mode: "full", maxLength: 12}, customItems: ["runtime-item"],
                    queue: {compactPromptMode: "extension", runtimePreference: false}}
     and .powerlineShortcuts == {scrollChatUp: "alt+u", scrollChatDown: "alt+d", toggleWelcome: "alt+w"}
     and .runtimeOnly == {enabled: true}'
done <<'CASES'
Zentui fullscreen|{"packages":["./packages/pi-zentui"],"tuiMode":"fullscreen"}
Powerline regular mode|{"packages":["./packages/pi-powerline-footer"],"tuiMode":"regular"}
Fullscreen inherited only from runtime|{"packages":["./packages/pi-powerline-footer"]}
Powerline inherited only from runtime|{"tuiMode":"fullscreen"}
CASES

# Fresh installations have no runtime Powerline objects to clean up.
printf '{}\n' >"$TMP_DIR/old.json"
printf '%s\n' '{"packages":["./packages/pi-powerline-footer"],"tuiMode":"fullscreen","powerline":{"queue":{"compactPromptMode":"native"}},"powerlineShortcuts":{}}' \
  >"$TMP_DIR/nix.json"
merge_settings 'fresh native fullscreen settings'
assert_json 'empty runtime settings accept declarative fullscreen defaults' \
  '.packages == ["./packages/pi-powerline-footer"] and .tuiMode == "fullscreen"
   and .powerline.queue == {compactPromptMode: "native"} and .powerlineShortcuts == {}'

printf 'Pi settings merge spec ok\n'
