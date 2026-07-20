#!/usr/bin/env bash
# Launch Pi from this checkout with an isolated, repo-local Home Manager state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST_HOME="${HOME:?HOME must be set}"
DEV_ROOT="${PI_DEV_ROOT:-$REPO_ROOT/.pi-dev}"
DEV_HOME="$DEV_ROOT/home"
DEV_STATE_HOME="$DEV_ROOT/state"
DEV_CACHE_HOME="$DEV_ROOT/cache"
DEV_AUTH_SOURCE="${PI_DEV_AUTH_SOURCE:-$HOST_HOME/.pi/agent/auth.json}"
NIX_BIN="${PI_DEV_NIX_BIN:-nix}"

copy_auth=false
mode="launch"
pi_args=()

usage() {
  cat <<'EOF'
Usage: scripts/pi-dev.sh [--copy-auth] [--verify] [--reset] [-- <pi arguments>]

Builds and activates this checkout's Pi module into .pi-dev/, then starts Pi
with that sandbox as HOME. The real ~/.pi state is never modified.

Options:
  --copy-auth  Copy ~/.pi/agent/auth.json into the sandbox after activation.
               The copy is private to .pi-dev/ and may be refreshed on demand.
  --verify     Activate the sandbox and run tests/test-fast.sh against it.
  --reset      Remove the selected .pi-dev sandbox without building or launching.
  --help        Show this help. Pass Pi's help after --, for example: -- --help.

Environment:
  PI_DEV_ROOT             Alternate sandbox location (requires PI_DEV_ALLOW_CUSTOM_ROOT=1).
  PI_DEV_AUTH_SOURCE      Alternate auth.json source for --copy-auth.
  PI_DEV_NIX_BIN          Nix executable (default: nix).
  PI_DEV_ACTIVATION_PATH  Override activation script for tests.
  PI_DEV_WRAPPER_PATH     Override pi-launch-wrapper package root for tests.
EOF
}

fail() {
  printf 'pi-dev: %s\n' "$1" >&2
  exit 2
}

require_safe_dev_root() {
  if [[ "$DEV_ROOT" == "$REPO_ROOT/.pi-dev" ]]; then
    return 0
  fi

  if [[ "${PI_DEV_ALLOW_CUSTOM_ROOT:-}" == "1" ]]; then
    return 0
  fi

  fail "PI_DEV_ROOT must be $REPO_ROOT/.pi-dev unless PI_DEV_ALLOW_CUSTOM_ROOT=1"
}

build_output() {
  local attribute="$1"
  "$NIX_BIN" build "$REPO_ROOT#$attribute" --no-link --print-out-paths | tail -n 1
}

resolve_activation() {
  if [[ -n "${PI_DEV_ACTIVATION_PATH:-}" ]]; then
    printf '%s\n' "$PI_DEV_ACTIVATION_PATH"
    return 0
  fi

  local activation_package
  activation_package="$(build_output pi-dev-activation)" || fail 'failed to build pi-dev activation package'
  printf '%s/activate\n' "$activation_package"
}

resolve_wrapper() {
  if [[ -n "${PI_DEV_WRAPPER_PATH:-}" ]]; then
    printf '%s\n' "$PI_DEV_WRAPPER_PATH"
    return 0
  fi

  build_output pi-launch-wrapper || fail 'failed to build pi launch wrapper'
}

activate_sandbox() {
  local activation_path="$1"

  [[ -x "$activation_path" ]] || fail "activation script is not executable: $activation_path"
  mkdir -p "$DEV_HOME" "$DEV_STATE_HOME/nix/profiles" "$DEV_CACHE_HOME"

  HOME="$DEV_HOME" \
  XDG_STATE_HOME="$DEV_STATE_HOME" \
  XDG_CACHE_HOME="$DEV_CACHE_HOME" \
  PI_CODING_AGENT_DIR="$DEV_HOME/.pi/agent" \
  SKIP_SANITY_CHECKS=1 \
  "$activation_path"
}

copy_auth_into_sandbox() {
  [[ -f "$DEV_AUTH_SOURCE" ]] || fail "auth file does not exist: $DEV_AUTH_SOURCE"

  mkdir -p "$DEV_HOME/.pi/agent"
  install -m 600 "$DEV_AUTH_SOURCE" "$DEV_HOME/.pi/agent/auth.json"
  printf 'Copied Pi credentials into %s\n' "$DEV_HOME/.pi/agent/auth.json"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --copy-auth)
      copy_auth=true
      ;;
    --verify)
      [[ "$mode" == "launch" ]] || fail '--verify cannot be combined with --reset'
      mode="verify"
      ;;
    --reset)
      [[ "$mode" == "launch" ]] || fail '--reset cannot be combined with --verify'
      mode="reset"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      pi_args=("$@")
      break
      ;;
    *)
      pi_args+=("$1")
      ;;
  esac
  shift
done

require_safe_dev_root

if [[ "$mode" == "reset" ]]; then
  rm -rf "$DEV_ROOT"
  printf 'Removed Pi development sandbox: %s\n' "$DEV_ROOT"
  exit 0
fi

activation_path="$(resolve_activation)"
wrapper_root="$(resolve_wrapper)"
wrapper_bin="$wrapper_root/bin/pi"
[[ -x "$wrapper_bin" ]] || fail "Pi wrapper is not executable: $wrapper_bin"

activate_sandbox "$activation_path"

if [[ "$copy_auth" == true ]]; then
  copy_auth_into_sandbox
fi

if [[ "$mode" == "verify" ]]; then
  HOME="$DEV_HOME" \
  XDG_STATE_HOME="$DEV_STATE_HOME" \
  XDG_CACHE_HOME="$DEV_CACHE_HOME" \
  PI_CODING_AGENT_DIR="$DEV_HOME/.pi/agent" \
  PI_SETTINGS_PATH="$DEV_HOME/.pi/agent/settings.json" \
  PATH="$wrapper_root/bin:$PATH" \
  bash "$REPO_ROOT/tests/test-fast.sh"
  exit $?
fi

exec env \
  HOME="$DEV_HOME" \
  XDG_STATE_HOME="$DEV_STATE_HOME" \
  XDG_CACHE_HOME="$DEV_CACHE_HOME" \
  PI_CODING_AGENT_DIR="$DEV_HOME/.pi/agent" \
  PATH="$wrapper_root/bin:$PATH" \
  "$wrapper_bin" "${pi_args[@]}"
