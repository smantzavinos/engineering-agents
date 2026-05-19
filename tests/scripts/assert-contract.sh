#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

EXIT_CONTRACT=1
EXIT_ENVIRONMENT=2
EXIT_INTERNAL=3

fail_contract() {
  printf '%s\n' "$1" >&2
  exit "$EXIT_CONTRACT"
}

fail_environment() {
  printf '%s\n' "$1" >&2
  exit "$EXIT_ENVIRONMENT"
}

fail_internal() {
  printf '%s\n' "$1" >&2
  exit "$EXIT_INTERNAL"
}

usage() {
  cat <<'EOF' >&2
Usage: tests/pi/scripts/assert-contract.sh --fixture <proof-set.json> --snapshot <resource-snapshot.json>
EOF
  exit "$EXIT_ENVIRONMENT"
}

parse_args() {
  FIXTURE_PATH=''
  SNAPSHOT_PATH=''

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fixture)
        FIXTURE_PATH="${2:-}"
        shift 2
        ;;
      --snapshot)
        SNAPSHOT_PATH="${2:-}"
        shift 2
        ;;
      --help)
        usage
        ;;
      *)
        fail_environment "Unsupported argument: $1"
        ;;
    esac
  done

  if [[ -z "$FIXTURE_PATH" || -z "$SNAPSHOT_PATH" ]]; then
    usage
  fi
}

require_readable_json() {
  local path="$1"
  local label="$2"

  if [[ ! -r "$path" ]]; then
    fail_environment "$label is not readable: $path"
  fi

  if ! jq -e '.' "$path" >/dev/null 2>&1; then
    fail_internal "$label is not valid JSON: $path"
  fi
}

validate_fixture_contract() {
  if ! jq -e '
    .schemaVersion == 2 and
    (.packages | type == "array") and
    all(.packages[];
      (.packageId | type == "string") and
      (.sourceManifestName | type == "string") and
      (.sourceSpec | type == "string") and
      ((has("sharedSourceKey") | not) or (.sharedSourceKey | type == "string" and length > 0)) and
      (.resourceExpectations | type == "object") and
      (.resourceExpectations.extensions | type == "array") and
      (.resourceExpectations.skills | type == "array") and
      (.resourceExpectations.themes | type == "array")
    )
  ' "$FIXTURE_PATH" >/dev/null; then
    fail_internal "Proof-set fixture does not match schemaVersion 2 contract: $FIXTURE_PATH"
  fi
}

validate_snapshot_contract() {
  if ! jq -e '
    .schemaVersion == 2 and
    (.settings | type == "object") and
    (.proofSet | type == "array") and
    (.diagnostics | type == "array") and
    (.warnings | type == "array")
  ' "$SNAPSHOT_PATH" >/dev/null; then
    fail_internal "Snapshot does not match schemaVersion 2 contract: $SNAPSHOT_PATH"
  fi
}

assert_snapshot_settings_contract() {
  if ! jq -e '.settings.isRegularFile == true and .settings.isSymlink == false' "$SNAPSHOT_PATH" >/dev/null; then
    fail_contract 'Snapshot settings contract failed: settings.json must be a writable regular file'
  fi
}

assert_package_present() {
  local package_id="$1"

  if ! jq -e --arg package_id "$package_id" '
    [ .proofSet[] | select(.packageId == $package_id) ] | length == 1
  ' "$SNAPSHOT_PATH" >/dev/null; then
    fail_contract "Package $package_id is missing from the proof-set snapshot"
  fi
}

assert_configured_package_path() {
  local package_id="$1"
  local expected_path="./packages/$package_id"

  if ! jq -e --arg package_id "$package_id" --arg expected_path "$expected_path" '
    any(.proofSet[];
      .packageId == $package_id and
      .configuredPackagePath == $expected_path
    )
  ' "$SNAPSHOT_PATH" >/dev/null; then
    fail_contract "Package $package_id is missing the expected configured package path: $expected_path"
  fi
}

assert_facade_metadata() {
  local package_id="$1"
  local expected_manifest_name="$2"
  local expected_source_spec="$3"

  if ! jq -e --arg package_id "$package_id" --arg expected_manifest_name "$expected_manifest_name" --arg expected_source_spec "$expected_source_spec" '
    any(.proofSet[];
      .packageId == $package_id and
      (.facadePath | type == "string") and
      (.facadePath | length > 0) and
      (.sourceProvenance | type == "object") and
      (.sourceProvenance.schemaVersion == 1) and
      (.sourceProvenance.packageId == $package_id) and
      (.sourceManifestName == $expected_manifest_name) and
      (.sourceProvenance.sourceManifestName == $expected_manifest_name) and
      (.sourceProvenance.source.spec == $expected_source_spec)
    )
  ' "$SNAPSHOT_PATH" >/dev/null; then
    fail_contract "Package $package_id is missing readable facade provenance metadata"
  fi
}

assert_source_root() {
  local package_id="$1"

  if ! jq -e --arg package_id "$package_id" '
    any(.proofSet[];
      .packageId == $package_id and
      (.sourceRoot | type == "string") and
      (.sourceRoot | length > 0) and
      (.sourceProvenance.sourceRoot == .sourceRoot)
    )
  ' "$SNAPSHOT_PATH" >/dev/null; then
    fail_contract "Package $package_id is missing readable source root information"
  fi
}

assert_expected_resources() {
  local package_id="$1"
  local expectation_key="$2"
  local discovered_key="$3"
  local field_name="$4"
  local singular_label="$5"
  local expected_value

  while IFS= read -r expected_value; do
    if [[ -z "$expected_value" ]]; then
      continue
    fi

    if ! jq -e --arg package_id "$package_id" --arg expected_value "$expected_value" --arg discovered_key "$discovered_key" --arg field_name "$field_name" '
      any(.proofSet[];
        .packageId == $package_id and
        any(.discovered[$discovered_key][]?; .[$field_name] == $expected_value)
      )
    ' "$SNAPSHOT_PATH" >/dev/null; then
      fail_contract "Package $package_id is missing required $singular_label: $expected_value"
    fi
  done < <(jq -r --arg package_id "$package_id" --arg expectation_key "$expectation_key" '
    .packages[]
    | select(.packageId == $package_id)
    | .resourceExpectations[$expectation_key][]?
  ' "$FIXTURE_PATH")
}

assert_no_package_diagnostics() {
  local package_id="$1"
  local diagnostics_key="$2"
  local singular_label="$3"
  local diagnostic_count

  diagnostic_count="$(jq -r --arg package_id "$package_id" --arg diagnostics_key "$diagnostics_key" '
    [
      .proofSet[]
      | select(.packageId == $package_id)
      | .diagnostics[$diagnostics_key][]?
    ]
    | length
  ' "$SNAPSHOT_PATH")"

  if [[ "$diagnostic_count" != '0' ]]; then
    fail_contract "Package $package_id has unexpected $singular_label diagnostics"
  fi
}

assert_shared_source_key() {
  local package_id="$1"
  local expected_key="$2"

  if [[ -z "$expected_key" ]]; then
    return 0
  fi

  if ! jq -e --arg package_id "$package_id" --arg expected_key "$expected_key" '
    any(.proofSet[];
      .packageId == $package_id and
      (.sourceProvenance.source.materializedKey == $expected_key)
    )
  ' "$SNAPSHOT_PATH" >/dev/null; then
    fail_contract "Package $package_id did not preserve the expected shared source key: $expected_key"
  fi
}

main() {
  parse_args "$@"
  pi_require_commands jq >/dev/null
  require_readable_json "$FIXTURE_PATH" 'Proof-set fixture'
  require_readable_json "$SNAPSHOT_PATH" 'Snapshot'
  validate_fixture_contract
  validate_snapshot_contract
  assert_snapshot_settings_contract

  local package_id source_manifest_name source_spec shared_source_key
  while IFS=$'\t' read -r package_id source_manifest_name source_spec shared_source_key; do
    [[ -z "$package_id" ]] && continue
    assert_package_present "$package_id"
    assert_configured_package_path "$package_id"
    assert_facade_metadata "$package_id" "$source_manifest_name" "$source_spec"
    assert_source_root "$package_id"
    assert_shared_source_key "$package_id" "$shared_source_key"
    assert_expected_resources "$package_id" 'extensions' 'extensions' 'sourceRelativePath' 'extension'
    assert_expected_resources "$package_id" 'skills' 'skills' 'name' 'skill'
    assert_expected_resources "$package_id" 'themes' 'themes' 'name' 'theme'
    assert_no_package_diagnostics "$package_id" 'extensions' 'extension'
    assert_no_package_diagnostics "$package_id" 'skills' 'skill'
    assert_no_package_diagnostics "$package_id" 'themes' 'theme'
  done < <(jq -r '.packages[] | [.packageId, .sourceManifestName, .sourceSpec, (.sharedSourceKey // "")] | @tsv' "$FIXTURE_PATH")

  local warning_count
  warning_count="$(jq -r '.warnings | length' "$SNAPSHOT_PATH")"
  printf 'Pi proof-set contract ok (warnings observed: %s)\n' "$warning_count"
}

main "$@"
