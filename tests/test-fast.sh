#!/usr/bin/env bash
# Read-only proof-set verification against the active ~/.pi state
# Adapted from dotfiles/nix/tests/pi/test-fast.sh
#
# This test verifies that the managed Pi packages are correctly installed
# with proper facade structure, provenance metadata, and source roots.
#
# Prerequisites: home-manager switch must have been run at least once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

EXIT_CONTRACT=1
EXIT_ENVIRONMENT=2
EXIT_INTERNAL=3

fail_contract() { printf '%s\n' "$1" >&2; exit "$EXIT_CONTRACT"; }
fail_environment() { printf '%s\n' "$1" >&2; exit "$EXIT_ENVIRONMENT"; }
fail_internal() { printf '%s\n' "$1" >&2; exit "$EXIT_INTERNAL"; }

require_commands node jq >/dev/null

SETTINGS_PATH="$(settings_path)"
SNAPSHOT_SCRIPT="${PI_SNAPSHOT_SCRIPT_PATH:-$SCRIPT_DIR/scripts/resource-snapshot.mjs}"
ASSERT_SCRIPT="${PI_ASSERT_CONTRACT_SCRIPT_PATH:-$SCRIPT_DIR/scripts/assert-contract.sh}"
FIXTURE_PATH="$SCRIPT_DIR/fixtures/proof-set.json"

# Verify settings.json is a writable regular file (not a Nix symlink)
assert_writable_regular_file "$SETTINGS_PATH" 'Pi settings file'

TMP_DIR="$(mktemp -d)"
SNAPSHOT_PATH="$TMP_DIR/resource-snapshot.json"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -r "$SNAPSHOT_SCRIPT" ]]; then
  fail_internal "Snapshot helper is not readable: $SNAPSHOT_SCRIPT"
fi

if [[ ! -r "$ASSERT_SCRIPT" ]]; then
  fail_internal "Assertion helper is not readable: $ASSERT_SCRIPT"
fi

# Generate snapshot from live Pi state
snapshot_status=0
PI_OFFLINE=1 node "$SNAPSHOT_SCRIPT" --fixture "$FIXTURE_PATH" >"$SNAPSHOT_PATH" || snapshot_status=$?

if [[ "$snapshot_status" -ne 0 ]]; then
  exit "$snapshot_status"
fi

if ! jq -e '.proofSet | type == "array"' "$SNAPSHOT_PATH" >/dev/null 2>&1; then
  fail_internal 'Snapshot helper returned malformed proof-set JSON'
fi

# Verify each proof-set package has valid facade + source root
proof_paths="$(jq -r '.proofSet[] | [.packageId, .facadePath, .sourceRoot] | @tsv' "$SNAPSHOT_PATH")" \
  || fail_internal 'Unable to read proof-set paths from snapshot'

while IFS=$'\t' read -r package_id facade_path source_root; do
  [[ -z "${package_id:-}" ]] && continue

  [[ -z "${facade_path:-}" || "$facade_path" == 'null' ]] \
    && fail_contract "Package $package_id did not resolve to a generated facade path"
  [[ ! -d "$facade_path" ]] \
    && fail_contract "Package $package_id facade path does not exist: $facade_path"

  [[ -z "${source_root:-}" || "$source_root" == 'null' ]] \
    && fail_contract "Package $package_id did not resolve to a source root"
  [[ ! -d "$source_root" ]] \
    && fail_contract "Package $package_id source root does not exist: $source_root"
done <<<"$proof_paths"

# Run contract assertions
bash "$ASSERT_SCRIPT" --fixture "$FIXTURE_PATH" --snapshot "$SNAPSHOT_PATH"
printf 'Pi read-only verification ok\n'
