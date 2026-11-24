#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node jq realpath >/dev/null

REPO_ROOT="$(repo_root)"
HELPER_PATH="$REPO_ROOT/nix/modules/pi/compile-managed-packages.mjs"
FIXTURE_DIR="$(tests_dir)/spec-fixtures/compiler"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_compile() {
  local declarations_path="$1"
  local output_dir="$2"
  local stdout_path="$3"
  local stderr_path="$4"

  set +e
  node "$HELPER_PATH" --declarations "$declarations_path" --output-dir "$output_dir" >"$stdout_path" 2>"$stderr_path"
  local status=$?
  set -e

  return "$status"
}

assert_compile_status() {
  local description="$1"
  local declarations_path="$2"
  local expected_status="$3"
  local expected_pattern="${4:-}"
  local case_dir="$TMP_DIR/${description//[^A-Za-z0-9._-]/_}"
  local stdout_path="$case_dir/stdout.json"
  local stderr_path="$case_dir/stderr.txt"
  local output_dir="$case_dir/output"
  local status

  mkdir -p "$output_dir"

  if run_compile "$declarations_path" "$output_dir" "$stdout_path" "$stderr_path"; then
    status=0
  else
    status=$?
  fi

  if [[ "$status" -ne "$expected_status" ]]; then
    printf 'stdout:\n' >&2
    cat "$stdout_path" >&2 || true
    printf 'stderr:\n' >&2
    cat "$stderr_path" >&2 || true
    fail "$description (expected exit $expected_status, got $status)"
  fi

  if [[ -n "$expected_pattern" ]] && ! grep -Eq "$expected_pattern" "$stderr_path" "$stdout_path"; then
    printf 'stdout:\n' >&2
    cat "$stdout_path" >&2 || true
    printf 'stderr:\n' >&2
    cat "$stderr_path" >&2 || true
    fail "$description (missing pattern: $expected_pattern)"
  fi

  printf '%s\n' "$case_dir"
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

SUCCESS_CASE_DIR="$(assert_compile_status \
  'ok fixture compiles successfully' \
  "$FIXTURE_DIR/declarations.ok.json" \
  0)"
SUCCESS_STDOUT="$SUCCESS_CASE_DIR/stdout.json"
SUCCESS_OUTPUT_DIR="$SUCCESS_CASE_DIR/output"

assert_json \
  'success report sorts compiled package ids deterministically' \
  "$SUCCESS_STDOUT" \
  '.packages | map(.packageId) == ["convention-demo", "explicit-ping", "root-skill-pkg", "shared-alpha", "shared-beta"]'

assert_json \
  'shared source declarations reuse one materialized source key and root' \
  "$SUCCESS_STDOUT" \
  '.packages
   | map(select(.packageId == "shared-alpha" or .packageId == "shared-beta"))
   | length == 2
     and .[0].materializedKey == .[1].materializedKey
     and .[0].sourceRoot == .[1].sourceRoot'

assert_json \
  'report preserves deterministic selected-resource ordering' \
  "$SUCCESS_STDOUT" \
  'any(.packages[];
      .packageId == "convention-demo"
      and .selectedResources.skills == ["demo"]
      and .selectedResources.themes == ["demo"]
      and .selectedResources.extensions == []
      and .selectedResources.prompts == []
    )'

EXPLICIT_PACKAGE_DIR="$SUCCESS_OUTPUT_DIR/packages/explicit-ping"
CONVENTION_PACKAGE_DIR="$SUCCESS_OUTPUT_DIR/packages/convention-demo"
SHARED_ALPHA_PACKAGE_DIR="$SUCCESS_OUTPUT_DIR/packages/shared-alpha"
SHARED_BETA_PACKAGE_DIR="$SUCCESS_OUTPUT_DIR/packages/shared-beta"
ROOT_SKILL_PACKAGE_DIR="$SUCCESS_OUTPUT_DIR/packages/root-skill-pkg"

for package_dir in \
  "$EXPLICIT_PACKAGE_DIR" \
  "$CONVENTION_PACKAGE_DIR" \
  "$SHARED_ALPHA_PACKAGE_DIR" \
  "$SHARED_BETA_PACKAGE_DIR" \
  "$ROOT_SKILL_PACKAGE_DIR"; do
  [[ -d "$package_dir" ]] || fail "compiled package directory missing: $package_dir"
  [[ -f "$package_dir/package.json" ]] || fail "generated package.json missing: $package_dir/package.json"
  [[ -L "$package_dir/_source" ]] || fail "generated _source symlink missing: $package_dir/_source"
  [[ -f "$package_dir/meta/source.json" ]] || fail "generated source metadata missing: $package_dir/meta/source.json"
done
printf 'PASS: generated package directories contain package.json, _source, and meta/source.json\n'

assert_json \
  'explicit manifest facade points at the selected extension via _source' \
  "$EXPLICIT_PACKAGE_DIR/package.json" \
  '.name == "explicit-ping"
   and .pi.extensions == ["./_source/extensions/ping.ts"]
   and .pi.skills == []
   and .pi.prompts == []
   and .pi.themes == []'

assert_json \
  'convention facade emits skill and theme paths discovered from conventions' \
  "$CONVENTION_PACKAGE_DIR/package.json" \
  '.name == "convention-demo"
   and .pi.extensions == []
   and .pi.skills == ["./_source/skills/demo/SKILL.md"]
   and .pi.prompts == []
   and .pi.themes == ["./_source/themes/demo.json"]'

# Root-level SKILL.md must be redirected through a facade skill directory
# so Pi's parent-directory-must-match-name rule is satisfied.
assert_json \
  'root-level SKILL.md is redirected through facade skills/<name>/ directory' \
  "$ROOT_SKILL_PACKAGE_DIR/package.json" \
  '.name == "root-skill-pkg"
   and .pi.skills == ["./skills/pi-root-skill-source/SKILL.md"]
   and .pi.extensions == ["./_source/index.ts"]'

# The facade must have a symlinked skills directory that resolves correctly
if [[ -L "$ROOT_SKILL_PACKAGE_DIR/skills/pi-root-skill-source/SKILL.md" ]]; then
  RESOLVED_SKILL="$(realpath "$ROOT_SKILL_PACKAGE_DIR/skills/pi-root-skill-source/SKILL.md")"
  EXPECTED_SKILL="$(realpath "$ROOT_SKILL_PACKAGE_DIR/_source/SKILL.md")"
  if [[ "$RESOLVED_SKILL" == "$EXPECTED_SKILL" ]]; then
    printf 'PASS: root-level SKILL.md symlink resolves to the source SKILL.md\n'
  else
    fail "root-level SKILL.md symlink resolves to $RESOLVED_SKILL, expected $EXPECTED_SKILL"
  fi
else
  fail 'root-level SKILL.md facade skill directory symlink missing'
fi

assert_json \
  'source metadata uses schemaVersion 1 with sourceManifestName and selectedResources' \
  "$EXPLICIT_PACKAGE_DIR/meta/source.json" \
  '.schemaVersion == 1
   and .packageId == "explicit-ping"
   and .source.type == "npm"
   and .source.spec == "pi-explicit-manifest@1.2.3"
   and (.source.materializedKey | type == "string" and length > 0)
   and .sourceManifestName == "pi-explicit-manifest-source"
   and .selectedResources.extensions == ["./extensions/ping.ts"]
   and .selectedResources.skills == []
   and .selectedResources.prompts == []
   and .selectedResources.themes == []
   and (.sourceRoot | type == "string" and startswith("/"))'

EXPLICIT_SOURCE_ROOT="$(jq -r '.sourceRoot' "$EXPLICIT_PACKAGE_DIR/meta/source.json")"
if [[ "$(realpath "$EXPLICIT_PACKAGE_DIR/_source")" == "$(realpath "$EXPLICIT_SOURCE_ROOT")" ]]; then
  printf 'PASS: _source symlink resolves to the sourceRoot recorded in metadata\n'
else
  fail '_source symlink does not resolve to the metadata sourceRoot'
fi

LOCAL_CASE_DIR="$(assert_compile_status \
  'local declarations are structurally recognized without requiring materialization in v1' \
  "$FIXTURE_DIR/declarations.local-recognized.json" \
  0)"
LOCAL_STDOUT="$LOCAL_CASE_DIR/stdout.json"

assert_json \
  'local declarations are skipped from compiled package/source outputs instead of crashing' \
  "$LOCAL_STDOUT" \
  '.packages == [] and .sources == [] and (.warnings | type == "array")'

NEGATIVE_CASE_DIR="$(assert_compile_status \
  'missing source precondition returns exit code 2' \
  "$FIXTURE_DIR/declarations.missing-source.json" \
  2 \
  'missing materialized source')"
: "$NEGATIVE_CASE_DIR"
printf 'PASS: missing source precondition returns exit code 2\n'

NEGATIVE_CASE_DIR="$(assert_compile_status \
  'malformed declaration contract returns exit code 3' \
  "$FIXTURE_DIR/declarations.malformed-contract.json" \
  3 \
  'malformed declaration contract')"
: "$NEGATIVE_CASE_DIR"
printf 'PASS: malformed declaration contract returns exit code 3\n'

NEGATIVE_CASE_DIR="$(assert_compile_status \
  'missing selected resource returns exit code 3' \
  "$FIXTURE_DIR/declarations.missing-resource.json" \
  3 \
  'missing selected resource')"
: "$NEGATIVE_CASE_DIR"
printf 'PASS: missing selected resource returns exit code 3\n'

NEGATIVE_CASE_DIR="$(assert_compile_status \
  'overlapping selected resources return exit code 3' \
  "$FIXTURE_DIR/declarations.overlap.json" \
  3 \
  'overlapping selected resource')"
: "$NEGATIVE_CASE_DIR"
printf 'PASS: overlapping selected resources return exit code 3\n'

# ADR 0009: per-package hiddenSkills. A hidden skill's facade gets a facade-local
# copy of SKILL.md with disable-model-invocation: true; the shared source is
# never edited, and the copy's sibling files stay reachable.
if grep -RFq 'disable-model-invocation' "$SUCCESS_OUTPUT_DIR"; then
  fail 'ok fixture without hiddenSkills must not hide any skill'
else
  printf 'PASS: ok fixture without hiddenSkills hides no skill\n'
fi

HIDDEN_CASE_DIR="$(assert_compile_status \
  'hiddenSkills declarations compile successfully' \
  "$FIXTURE_DIR/declarations.hidden-skills.json" \
  0)"
HIDDEN_STDOUT="$HIDDEN_CASE_DIR/stdout.json"
HIDDEN_OUTPUT_DIR="$HIDDEN_CASE_DIR/output"
HIDDEN_CONVENTION_DIR="$HIDDEN_OUTPUT_DIR/packages/hidden-convention"
HIDDEN_ROOT_DIR="$HIDDEN_OUTPUT_DIR/packages/hidden-root-skill"

assert_json \
  'hiddenSkills leaves the compiler skill ids unchanged in the report' \
  "$HIDDEN_STDOUT" \
  'any(.packages[]; .packageId == "hidden-convention" and .selectedResources.skills == ["demo"])
   and any(.packages[]; .packageId == "hidden-root-skill" and .selectedResources.skills == ["./SKILL.md"])'

hidden_skill_file() {
  local package_dir="$1"
  local relative
  relative="$(jq -r '.pi.skills[0]' "$package_dir/package.json")"
  printf '%s/%s\n' "$package_dir" "${relative#./}"
}

HIDDEN_CONVENTION_SKILL="$(hidden_skill_file "$HIDDEN_CONVENTION_DIR")"
if [[ -f "$HIDDEN_CONVENTION_SKILL" && ! -L "$HIDDEN_CONVENTION_SKILL" ]] \
  && grep -Fxq 'disable-model-invocation: true' "$HIDDEN_CONVENTION_SKILL" \
  && grep -Fq 'Used to prove convention-based skill discovery.' "$HIDDEN_CONVENTION_SKILL"; then
  printf 'PASS: hidden convention skill is a facade-local copy with disable-model-invocation: true\n'
else
  fail 'hidden convention skill must be a facade-local SKILL.md copy with disable-model-invocation: true'
fi
if [[ -f "$(dirname "$HIDDEN_CONVENTION_SKILL")/reference.md" ]]; then
  printf 'PASS: hidden skill keeps its sibling reference.md reachable\n'
else
  fail 'hidden skill lost its sibling reference.md in the facade'
fi
if grep -Fq '[Docs](../../_source/docs/x.md#anchor), [local](#demo-skill), and [external](https://example.com/docs).' "$HIDDEN_CONVENTION_SKILL" \
  && [[ -f "$(dirname "$HIDDEN_CONVENTION_SKILL")/../../_source/docs/x.md" ]]; then
  printf 'PASS: hidden skill rebases package-relative links and preserves anchors and external URLs\n'
else
  fail 'hidden skill must rebase relative links to vendored assets'
fi

HIDDEN_ROOT_SKILL="$(hidden_skill_file "$HIDDEN_ROOT_DIR")"
if [[ -f "$HIDDEN_ROOT_SKILL" && ! -L "$HIDDEN_ROOT_SKILL" ]] \
  && grep -Fxq 'disable-model-invocation: true' "$HIDDEN_ROOT_SKILL"; then
  printf 'PASS: hidden root-level skill is redirected to a facade-local flagged copy\n'
else
  fail 'hidden root-level SKILL.md must be a facade-local copy with disable-model-invocation: true'
fi

if grep -Fq 'disable-model-invocation' "$FIXTURE_DIR/sources/convention/skills/demo/SKILL.md" \
  || grep -Fq 'disable-model-invocation' "$FIXTURE_DIR/sources/root-skill/SKILL.md"; then
  fail 'hiddenSkills must not edit the shared source SKILL.md'
else
  printf 'PASS: hiddenSkills leaves the shared source SKILL.md untouched\n'
fi

NEGATIVE_CASE_DIR="$(assert_compile_status \
  'hiddenSkills naming an unknown skill returns exit code 3' \
  "$FIXTURE_DIR/declarations.hidden-skills-unknown.json" \
  3 \
  'hiddenSkills')"
: "$NEGATIVE_CASE_DIR"
printf 'PASS: hiddenSkills naming an unknown skill returns exit code 3\n'

NEGATIVE_CASE_DIR="$(assert_compile_status \
  'hiddenSkills that is not an array returns exit code 3' \
  "$FIXTURE_DIR/declarations.hidden-skills-not-array.json" \
  3 \
  'hiddenSkills')"
: "$NEGATIVE_CASE_DIR"
printf 'PASS: hiddenSkills that is not an array returns exit code 3\n'

printf 'compiler contract spec ok\n'
