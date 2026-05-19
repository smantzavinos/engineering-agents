#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node jq >/dev/null

REPO_ROOT="$(repo_root)"
HELPER_PATH="$REPO_ROOT/nix/modules/pi/build-managed-package-install-state.mjs"
FIXTURE_DIR="$(tests_dir)/spec-fixtures/managed-package-install-state"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_helper() {
  local declarations_path="$1"
  local stdout_path="$2"
  local stderr_path="$3"

  set +e
  node "$HELPER_PATH" \
    --declarations "$declarations_path" \
    --generated-at '2026-05-19T12:00:00.000Z' \
    >"$stdout_path" 2>"$stderr_path"
  local status=$?
  set -e

  return "$status"
}

assert_json() {
  local description="$1"
  local path="$2"
  local filter="$3"

  if jq -e "$filter" "$path" >/dev/null; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'File under test: %s\n' "$path" >&2
    cat "$path" >&2 || true
    fail "$description"
  fi
}

STDOUT_PATH="$TMP_DIR/install-state.json"
STDERR_PATH="$TMP_DIR/helper.stderr"

if ! run_helper "$FIXTURE_DIR/declarations.ok.json" "$STDOUT_PATH" "$STDERR_PATH"; then
  printf 'stdout:\n' >&2
  cat "$STDOUT_PATH" >&2 || true
  printf 'stderr:\n' >&2
  cat "$STDERR_PATH" >&2 || true
  fail 'helper should emit the install-state manifest for the fixture declarations'
fi

assert_json \
  'manifest uses schemaVersion 1 with deterministic generatedAt' \
  "$STDOUT_PATH" \
  '.schemaVersion == 1 and .generatedAt == "2026-05-19T12:00:00.000Z"'

assert_json \
  'sources are sorted deterministically by sourceKey' \
  "$STDOUT_PATH" \
  '.sources == (.sources | sort_by(.sourceKey))'

assert_json \
  'local declarations are omitted from runtime install-state output' \
  "$STDOUT_PATH" \
  '(.sources | length) == 5 and all(.sources[]; .source.type != "local")'

assert_json \
  'npm source persists stable source identity and installedVersion facts' \
  "$STDOUT_PATH" \
  'any(.sources[];
      .source.type == "npm"
      and .source.spec == "pi-fancy-tool@1.2.3"
      and .source.installSpec == "pi-fancy-tool@1.2.3"
      and .source.packageName == "pi-fancy-tool"
      and .materializedPath == ("'"$FIXTURE_DIR"'" + "/sources/pi-fancy-tool")
      and (.materializedKey | startswith("src-"))
      and .sourceKey == .materializedKey
      and .packageIds == ["npm-fancy-tool"]
      and .installedVersion == "1.2.3"
    )'

assert_json \
  'git default-ref source persists installedCommit and ref classification' \
  "$STDOUT_PATH" \
  'any(.sources[];
      .source.type == "git"
      and .source.spec == "github:demo/default-branch-plugin"
      and .source.installSpec == "github:demo/default-branch-plugin"
      and .source.packageName == "default-branch-plugin"
      and .packageIds == ["git-default-branch"]
      and .installedCommit == "1111111111111111111111111111111111111111"
      and .gitRef.kind == "default"
      and .gitRef.value == null
    )'

assert_json \
  'shared git sources fan out deterministically to sorted packageIds with pinned classification' \
  "$STDOUT_PATH" \
  'any(.sources[];
      .source.type == "git"
      and .source.spec == "github:demo/shared-plugin#515352c80bc1ee7e22ed08add915efa220c4c822"
      and .source.installSpec == "github:demo/shared-plugin#515352c80bc1ee7e22ed08add915efa220c4c822"
      and .source.packageName == "shared-plugin"
      and .packageIds == ["git-shared-alpha", "git-shared-beta"]
      and .installedCommit == "515352c80bc1ee7e22ed08add915efa220c4c822"
      and .gitRef.kind == "pinned"
      and .gitRef.value == "515352c80bc1ee7e22ed08add915efa220c4c822"
      and .gitRef.refType == "commit"
    )'

assert_json \
  'git tag sources preserve pinned tag intent instead of degrading to branch refs' \
  "$STDOUT_PATH" \
  'any(.sources[];
      .source.type == "git"
      and .source.spec == "github:demo/tag-plugin#v1.2.3"
      and .source.installSpec == "github:demo/tag-plugin#v1.2.3"
      and .source.packageName == "tag-plugin"
      and .packageIds == ["git-tag-release"]
      and .installedCommit == "1234123412341234123412341234123412341234"
      and .gitRef.kind == "pinned"
      and .gitRef.value == "v1.2.3"
      and .gitRef.refType == "tag"
    )'

assert_json \
  'non-version git tag names also preserve pinned tag intent' \
  "$STDOUT_PATH" \
  'any(.sources[];
      .source.type == "git"
      and .source.spec == "github:demo/stable-tag-plugin#stable"
      and .source.installSpec == "github:demo/stable-tag-plugin#stable"
      and .source.packageName == "stable-tag-plugin"
      and .packageIds == ["git-tag-stable"]
      and .installedCommit == "abababababababababababababababababababab"
      and .gitRef.kind == "pinned"
      and .gitRef.value == "stable"
      and .gitRef.refType == "tag"
    )'

printf 'managed package install-state spec ok\n'
