#!/usr/bin/env bash
# Build generated settings through both public configuration entry points.
# Build only: never run Home Manager activation or touch the user's Pi config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands nix jq >/dev/null

REPO_LITERAL="$(printf '%s' "$(repo_root)" | jq -Rs .)"
PASS=0 FAIL=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

store_file_from_activate() {
  local activate_path="$1" suffix="$2"
  grep -o "/nix/store/[^\" ]*-${suffix}" "$activate_path" | head -1 || true
}

assert_json() {
  local description="$1" path="$2" filter="$3"
  if jq -e "$filter" "$path" >/dev/null; then
    PASS=$((PASS + 1))
    printf 'PASS: %s\n' "$description"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\nSettings: %s\n' "$description" "$path" >&2
    jq '{tuiMode, powerline}' "$path" >&2 || true
  fi
}

printf 'Building Home Manager partial Powerline override (without activation)...\n'
HM_OUT="$(nix build --impure --no-link --print-out-paths --expr "
  let f = builtins.getFlake $REPO_LITERAL;
  in (f.inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      f.homeManagerModules.pi
      {
        home.username = \"pi-powerline-test\";
        home.homeDirectory = \"/tmp/pi-powerline-test\";
        home.stateVersion = \"25.05\";
        engineering-agents.pi = {
          enable = true;
          powerline.config = { preset = \"full\"; path.mode = \"full\"; };
        };
      }
    ];
  }).activationPackage
")" || fail 'Home Manager partial Powerline override must build'
HM_SETTINGS="$(store_file_from_activate "$HM_OUT/activate" 'pi-agent-config')/agent/settings.json"

printf 'Building shared makePiConfig partial and explicit queue overrides...\n'
SHARED_OUT="$(nix build --impure --no-link --print-out-paths --expr "
  let f = builtins.getFlake $REPO_LITERAL;
  in f.lib.x86_64-linux.makePiConfig { powerline.preset = \"full\"; }
")" || fail 'shared makePiConfig partial Powerline override must build'
EXPLICIT_OUT="$(nix build --impure --no-link --print-out-paths --expr "
  let f = builtins.getFlake $REPO_LITERAL;
  in f.lib.x86_64-linux.makePiConfig {
    powerline.preset = \"full\";
    powerline.queue.compactPromptMode = \"queue\";
  }
")" || fail 'shared makePiConfig explicit queue override must build'

assert_json 'Home Manager partial preset/path overrides preserve native queue, visual defaults, and fullscreen' \
  "$HM_SETTINGS" \
  '.powerline.preset == "full" and .powerline.path.mode == "full"
   and .powerline.path.maxLength == 36 and .powerline.queue.compactPromptMode == "native"
   and .powerline.cost.subscriptionDisplay == "reported-cost" and .tuiMode == "fullscreen"'
assert_json 'shared makePiConfig partial preset override preserves native queue' \
  "$SHARED_OUT/agent/settings.json" \
  '.powerline.preset == "full" and .powerline.queue.compactPromptMode == "native"'
assert_json 'explicit Powerline queue mode remains honored' \
  "$EXPLICIT_OUT/agent/settings.json" \
  '.powerline.preset == "full" and .powerline.queue.compactPromptMode == "queue"'

printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
