#!/usr/bin/env bash
# Verify flake checks pass: modules instantiate and produce valid activation packages
# Requirement: FR-007
# Requirement: FR-008
# Requirement: OPR-003
#
# This is the critical gate: it proves that home-manager can actually import
# and build with these modules. `nix flake check` builds the activation
# packages without applying them, so this is a build-without-apply test.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands nix jq >/dev/null

REPO_ROOT="$(repo_root)"
PASS=0 FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

store_file_from_activate() {
  local activate_path="$1"
  local suffix="$2"

  grep -o "/nix/store/[^\" ]*-${suffix}" "$activate_path" | head -1 || true
}

# S12 helpers. package_skill_visibility prints {skillName: hidden} for the
# skills each managed package facade exposes (hidden = disable-model-invocation).
package_skill_visibility() {
  node - "$@" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const out = {};
for (const pkgDir of process.argv.slice(2)) {
  const pkg = JSON.parse(fs.readFileSync(path.join(pkgDir, 'package.json'), 'utf8'));
  for (const rel of pkg.pi?.skills ?? []) {
    const file = path.join(pkgDir, rel);
    out[path.basename(path.dirname(file))] = /^disable-model-invocation: true$/m.test(fs.readFileSync(file, 'utf8'));
  }
}
process.stdout.write(JSON.stringify(out));
JS
}

# agent_model_expect FILES AGENT MODEL THINKING: installed agent file frontmatter.
agent_model_expect() {
  local files="$1" agent="$2" model="$3" thinking="$4"
  local path="$files/.pi/agent/agents/$agent.md"
  if [[ -f "$path" ]] && grep -Fqx "model: $model" "$path" && grep -Fqx "thinking: $thinking" "$path"; then
    pass "installed agent $agent runs $model ($thinking)"
  else
    fail "installed agent $agent must run $model ($thinking)"
  fi
}

# agent_models_within FILES PROVIDER_REGEX: every installed agent model is in the set.
agent_models_within() {
  local files="$1" providers="$2" path bad=0
  for path in "$files"/.pi/agent/agents/*.md; do
    if ! grep -Eq "^model: (${providers})/" "$path"; then
      bad=1
      printf '    model outside the set: %s\n' "$path" >&2
    fi
  done
  [[ "$bad" == 0 ]]
}

build_pi_out() {
  nix build "$REPO_ROOT#checks.x86_64-linux.$1.activationPackage" --no-link --print-out-paths 2>&1 \
    | grep '^/nix/store' | head -1 || true
}

# ============================================================
printf 'Flake module instantiation verification\n'
printf '========================================\n\n'

# 1. Build the Pi module check (activation package)
printf 'Building Pi module activation package...\n'
PI_OUT=$(nix build "$REPO_ROOT#checks.x86_64-linux.pi-module.activationPackage" \
  --no-link --print-out-paths 2>&1) || true
# Strip any stderr warnings from nix output
PI_OUT=$(echo "$PI_OUT" | grep '^/nix/store' | head -1 || true)

# The files are in home-manager-files, not home-path
PI_FILES=$(readlink -f "$PI_OUT/home-files" 2>/dev/null || echo "")

if [[ -n "$PI_OUT" && -d "$PI_OUT" ]]; then
  pass "Pi module activation package builds"

  if [[ -z "$PI_FILES" || ! -d "$PI_FILES" ]]; then
    fail "Pi module: cannot find home-manager-files derivation"
  else
    pass "Pi module: home-manager-files derivation exists"
  fi

  # Verify the activation package contains expected file structure
  if [[ -f "$PI_FILES/.pi/agent/models.json" ]]; then
    pass "Pi module produces models.json"
  else
    fail "Pi module missing models.json in activation package"
  fi

  PI_MANAGED_PACKAGES_JSON="$(store_file_from_activate "$PI_OUT/activate" 'pi-managed-packages')/agent/managed-packages.declarations.json"
  if [[ -n "$PI_MANAGED_PACKAGES_JSON" && -f "$PI_MANAGED_PACKAGES_JSON" ]] \
    && jq -e 'all(.packages[]; .packageId != "pi-gitnexus")' "$PI_MANAGED_PACKAGES_JSON" >/dev/null 2>&1; then
    pass "Pi module has no retired pi-gitnexus managed package"
  else
    fail "Pi module still declares retired pi-gitnexus in managed packages"
  fi

  PI_SETTINGS_STORE_JSON="$(store_file_from_activate "$PI_OUT/activate" 'pi-agent-config')/agent/settings.json"
  if [[ -n "$PI_SETTINGS_STORE_JSON" && -f "$PI_SETTINGS_STORE_JSON" ]] \
    && jq -e 'all(.packages[]; . != "./packages/pi-gitnexus")' "$PI_SETTINGS_STORE_JSON" >/dev/null 2>&1; then
    pass "Pi module has no retired pi-gitnexus runtime package"
  else
    fail "Pi module still configures retired ./packages/pi-gitnexus"
  fi

  if [[ -f "$PI_FILES/.pi/agent/mcp-adapter.json" ]]; then
    pass "Pi module produces mcp-adapter.json"
  else
    fail "Pi module missing mcp-adapter.json in activation package"
  fi

  if [[ -f "$PI_FILES/.pi/agent/keybindings.json" ]]; then
    pass "Pi module produces keybindings.json"
  else
    fail "Pi module missing keybindings.json in activation package"
  fi

  # T3 keeps the common tools but not terminal-only packages or the bridge.
  PI_T3_ARGS="$PI_FILES/.pi/agent/t3-profile.args"
  # Compare the entire -e list, including duplicates. For index.ts entrypoints
  # use the containing extension directory as the identifying basename.
  expected_t3_extensions=$(printf '%s\n' direnv.ts pi-checkpoint pi-guardrails pi-lens \
    pi-lens-policy pi-mcp-adapter pi-subdir-context pi-tasks pi-web-access startup-staleness-warning | LC_ALL=C sort)
  if [[ -f "$PI_T3_ARGS" ]] && grep -Fqx -- '-ne' "$PI_T3_ARGS" \
    && grep -Fqx -- '--exclude-tools' "$PI_T3_ARGS" \
    && grep -Fxq 'TaskExecute,TaskOutput,TaskStop' "$PI_T3_ARGS"; then
    pass "T3 profile opts out of discovery and excludes the terminal delegation tools"
    actual_t3_extensions=$(awk '$0 == "-e" { getline; n = split($0, parts, "/"); print (parts[n] == "index.ts" ? parts[n-1] : parts[n]) }' "$PI_T3_ARGS" | LC_ALL=C sort)
    if [[ "$actual_t3_extensions" == "$expected_t3_extensions" ]]; then
      pass "T3 profile loads exactly the shared, repo, direnv and z.ai extensions"
    else
      fail "unexpected T3 extension list: $actual_t3_extensions"
    fi
    if grep -Eq '/(pi-ding|pi-notify|pi-ext-leader-key|pi-session-autoname|pi-zentui|pi-powerline-footer|pi-subagents|pi-btw|pi-preset)(/|$)' "$PI_T3_ARGS"; then
      fail "T3 profile must not load terminal-only packages"
    else
      pass "T3 profile excludes all terminal-only packages"
    fi
  else
    fail "T3 profile args must opt out of discovery and leave terminal delegation in terminal Pi"
  fi

  # pi-tasks: repo-clean storage default, the forked shutdown fix in the
  # built facade, and pi-ext's npm copy left in place.
  if jq -e '.taskScope == "session-global"' "$PI_FILES/.pi/agent/tasks-config.json" >/dev/null 2>&1; then
    pass "Pi module sets pi-tasks taskScope to session-global"
  else
    fail "Pi module missing tasks-config.json with taskScope session-global"
  fi
  PI_MANAGED_AGENT="$(dirname "$PI_MANAGED_PACKAGES_JSON")"
  PI_TASKS_INDEX="$PI_MANAGED_AGENT/packages/pi-tasks/_source/src/index.ts"
  if [[ -f "$PI_TASKS_INDEX" ]] \
    && grep -Fq 'pi.on("session_shutdown"' "$PI_TASKS_INDEX" \
    && grep -Fq 'widget.dispose();' "$PI_TASKS_INDEX"; then
    pass "Pi module pi-tasks facade carries the session_shutdown spinner fix"
  else
    fail "Pi module pi-tasks facade missing or lacks the session_shutdown widget dispose"
  fi
  if jq -e '.version == "0.4.3"' "$(dirname "$PI_MANAGED_AGENT")/vendor/node_modules/@tintinweb/pi-tasks/package.json" >/dev/null 2>&1; then
    pass "Pi module leaves pi-ext's npm @tintinweb/pi-tasks 0.4.3 untouched"
  else
    fail "Pi module vendor @tintinweb/pi-tasks is not the locked npm 0.4.3 (git fork overwrote it?)"
  fi
  # S12: pi-hooks (the whole git package) and pi-agent-guidance are removed from
  # every profile: no declaration, no settings entry, no installed package.
  if jq -e 'all(.packages[]; .packageId != "pi-hooks" and .packageId != "pi-agent-guidance")' "$PI_MANAGED_PACKAGES_JSON" >/dev/null 2>&1 \
    && jq -e 'all(.packages[]; test("pi-hooks|pi-agent-guidance") | not)' "$PI_SETTINGS_STORE_JSON" >/dev/null 2>&1 \
    && [[ ! -e "$PI_MANAGED_AGENT/packages/pi-hooks" && ! -e "$PI_MANAGED_AGENT/packages/pi-agent-guidance" ]]; then
    pass "Pi module removes pi-hooks and pi-agent-guidance from every profile"
  else
    fail "Pi module still declares, configures or installs pi-hooks or pi-agent-guidance"
  fi
  # pi-lens owns LSP: narrow facade, managed config, in-process install policy.
  # S12: the two write-rule skills are hidden per package; the LSP and ast-grep
  # skills stay visible.
  PI_LENS_VISIBILITY="$(package_skill_visibility "$PI_MANAGED_AGENT/packages/pi-lens")"
  if jq -e '. == {"pi-lens-ast-grep": false, "pi-lens-lsp-navigation": false, "pi-lens-write-ast-grep-rule": true, "pi-lens-write-tree-sitter-rule": true}' <<<"$PI_LENS_VISIBILITY" >/dev/null 2>&1 \
    && jq -e '.pi.extensions == ["./_source/dist/index.js"]' "$PI_MANAGED_AGENT/packages/pi-lens/package.json" >/dev/null 2>&1 \
    && jq -e '.packages | index("./packages/pi-lens") != null' "$PI_SETTINGS_STORE_JSON" >/dev/null 2>&1; then
    pass "Pi module enables pi-lens with its extension; write-rule skills hidden, LSP/ast-grep visible"
  else
    fail "Pi module pi-lens facade/runtime package selection or skill visibility is wrong"
  fi
  # The source is a global-config template, not a project policy. A lens
  # project basename here is auto-discovered when working in this module,
  # producing deprecation warnings (undotted) or wrong-tier warnings (dotted).
  if [[ ! -e "$REPO_ROOT/nix/modules/pi/pi-lens.json" && ! -e "$REPO_ROOT/nix/modules/pi/.pi-lens.json" ]]; then
    pass "Pi lens global template is not discoverable as module project policy"
  else
    fail "Pi lens global template must not use a project-config basename"
  fi
  PI_LENS_CONFIG="$PI_FILES/.pi/agent/pi-lens.json"
  # Everything on except the two mutation paths (format/autofix stay a
  # per-project .pi-lens.json opt-in); no servers disabled; every tool on.
  if jq -e '.lsp == {enabled: true} and .format.enabled == false and .autofix.enabled == false
            and ([.tests, .opengrep, .knip, .jscpd, .madge, .gitleaks, .govulncheck, .deadCode, .complexity, .readGuard, .contextInjection] | all(.enabled == true))
            and .tools.lazy == false
            and ([.tools | to_entries[] | select(.key != "lazy" and .value.enabled != true)] | length == 0)' \
       "$PI_LENS_CONFIG" >/dev/null 2>&1; then
    pass "Pi module ships the full pi-lens config (format/autofix per-project opt-in)"
  else
    fail "Pi module pi-lens.json missing or not the expected full config"
  fi
  # Nix-supplied pi-lens tools: present, no formatter-only binaries, and
  # appended to pi's PATH by the policy extension.
  PI_LENS_TOOLS_BIN="$PI_FILES/.pi/agent/pi-lens-tools/bin"
  PI_LENS_TOOLS_OK=1
  for tool in typescript-language-server svelteserver typos-lsp marksman yaml-language-server bash-language-server pyright-langserver nixd \
              biome ruff oxlint shellcheck shfmt yamllint actionlint zizmor gitleaks govulncheck ast-grep opengrep knip jscpd madge; do
    [[ -x "$PI_LENS_TOOLS_BIN/$tool" ]] || { PI_LENS_TOOLS_OK=0; printf '    missing pi-lens tool: %s\n' "$tool" >&2; }
  done
  for tool in nixfmt config; do
    [[ ! -e "$PI_LENS_TOOLS_BIN/$tool" ]] || { PI_LENS_TOOLS_OK=0; printf '    unexpected pi-lens tool: %s\n' "$tool" >&2; }
  done
  # The tool env must not keep the whole npm vendor tree alive (it already
  # ships inside the managed-packages output).
  if nix path-info -r "$(readlink -f "$PI_FILES/.pi/agent/pi-lens-tools")" 2>/dev/null | grep -q -- '-pi-managed-vendor-'; then
    PI_LENS_TOOLS_OK=0
    printf '    pi-lens-tools closure references the full pi-managed-vendor tree\n' >&2
  fi
  if [[ "$PI_LENS_TOOLS_OK" == "1" ]] && grep -Fq 'join(getAgentDir(), "pi-lens-tools", "bin")' "$PI_FILES/.pi/agent/extensions/pi-lens-policy/index.ts"; then
    pass "Pi module ships Nix pi-lens tools (no nixfmt) on pi's PATH"
  else
    fail "Pi module pi-lens-tools environment is missing tools, ships formatter-only binaries, or is not on PATH"
  fi
  PI_LENS_POLICY="$PI_FILES/.pi/agent/extensions/pi-lens-policy/index.ts"
  if [[ -f "$PI_LENS_POLICY" ]] \
    && grep -Fq 'PI_LENS_DISABLE_LSP_INSTALL ??= "1"' "$PI_LENS_POLICY" \
    && grep -Fq 'PI_LENS_DISABLE_TOOL_INSTALL ??= "1"' "$PI_LENS_POLICY" \
    && grep -Fq 'PI_LENS_CONFIG_PATH ??= join(getAgentDir(), "pi-lens.json")' "$PI_LENS_POLICY" \
    && grep -Fq 'PI_LENS_HOME ??= join(homedir(), ".pi-lens")' "$PI_LENS_POLICY"; then
    pass "Pi module links the pi-lens-policy extension (no auto-install, managed config, fixed home)"
  else
    fail "Pi module pi-lens-policy extension missing or incomplete"
  fi
  # pi-tasks TaskExecute bridge onto the managed pi-subagents RPC.
  PI_TASKS_BRIDGE="$PI_FILES/.pi/agent/extensions/pi-tasks-subagents-bridge/index.ts"
  if [[ -f "$PI_TASKS_BRIDGE" ]] && grep -Fq 'subagents:rpc:v1:request' "$PI_TASKS_BRIDGE" \
    && grep -Fq '"subagents:rpc:spawn"' "$PI_TASKS_BRIDGE"; then
    pass "Pi module links the pi-tasks -> pi-subagents bridge extension"
  else
    fail "Pi module pi-tasks-subagents-bridge extension missing or incomplete"
  fi
  # Guardrails tool registration protocol (#99): the Guardrails fork consumes
  # registrations; pi-lens-policy registers pi-lens tools.
  PI_GUARDRAILS_SRC="$PI_MANAGED_AGENT/packages/pi-guardrails/_source"
  if grep -Fq 'GUARDRAILS_REGISTER_TOOL_EVENT = "guardrails:register-tool"' "$PI_GUARDRAILS_SRC/src/shared/tool-registry.ts" 2>/dev/null \
    && [[ -e "$PI_GUARDRAILS_SRC/node_modules/@aliou/sh" && -e "$PI_GUARDRAILS_SRC/node_modules/@aliou/pi-utils-settings" ]] \
    && grep -Fq 'REGISTER_TOOL_EVENT = "guardrails:register-tool"' "$PI_LENS_POLICY" \
    && grep -Fq 'ast_grep_replace:' "$PI_LENS_POLICY" && grep -Fq 'lsp_navigation:' "$PI_LENS_POLICY"; then
    pass "Pi module wires the guardrails tool registration protocol (guardrails and pi-lens-policy)"
  else
    fail "Pi module guardrails tool registration protocol wiring is incomplete"
  fi

  # Pi >=1.2 validates themes at startup. HTML export accepts background
  # overrides only; foreground roles belong under colors, not export.
  if jq -e '(.export | type == "object")
            and ((.export | keys) - ["pageBg", "cardBg", "infoBg"] == [])
            and (.colors.text != null) and (.colors.muted != null)' \
       "$PI_FILES/.pi/agent/themes/catppuccin-mocha.json" >/dev/null 2>&1; then
    pass "Pi Catppuccin theme uses supported HTML export roles"
  else
    fail "Pi Catppuccin theme contains unsupported HTML export roles or lacks foreground colors"
  fi

  if [[ -f "$PI_FILES/.pi/agent/CLAUDE.md" ]]; then
    pass "Pi module produces CLAUDE.md"
  else
    fail "Pi module missing CLAUDE.md in activation package"
  fi

  if [[ -f "$PI_FILES/.pi/agent/CODEX.md" ]]; then
    pass "Pi module produces CODEX.md"
  else
    fail "Pi module missing CODEX.md in activation package"
  fi

  # Verify skills are linked
  for skill in prototype scope run-plan run-epic map-patterns \
               plan implement review architecture-model delegate test-quality \
               assess-repo create-skills; do
    if [[ -f "$PI_FILES/.pi/agent/skills/$skill/SKILL.md" ]]; then
      pass "Pi module links skill: $skill"
    else
      fail "Pi module missing skill: $skill"
    fi
  done

  # The check script must be installed with the skill that ships it.
  if [[ -f "$PI_FILES/.pi/agent/skills/architecture-model/tools/model-check.mjs" ]]; then
    pass "Pi module installs the model check with architecture-model"
  else
    fail "Pi module does not install architecture-model/tools/model-check.mjs"
  fi

  # Retired: pi-team-* went away with team mode, and the sequential pipeline
  # with ADR 0007 (Pi runs the frontier pipeline; OpenCode and Hermes keep the
  # sequential one). Pi installs every skill in dist/skills/pi, so none of
  # these may be rendered there.
  for skill in pi-team-plan pi-team-lead pi-team-worker \
               discovery design discover-and-design discover-and-design-simple \
               research review-approach review-epic create-plan review-plan \
               create-worklog execute-task execution-orchestrator review-code \
               prototype-first work-item; do
    if [[ -e "$PI_FILES/.pi/agent/skills/$skill" ]]; then
      fail "Pi module must not link retired skill: $skill"
    else
      pass "Pi module omits retired skill: $skill"
    fi
  done

  # Verify visual-explainer is installed from the pinned flake input (not a
  # runtime git clone) and that slash-command prompts come from commands/.
  PI_VISUAL_SKILL="$(store_file_from_activate "$PI_OUT/activate" 'pi-manual-skill-visual-explainer')"
  if [[ -f "$PI_VISUAL_SKILL/SKILL.md" ]]; then
    pass "Pi module installs visual-explainer from the build-time store copy"
  else
    fail "Pi module does not install visual-explainer from the build-time store copy"
  fi
  if ! grep -q 'git clone .*visual-explainer' "$PI_OUT/activate"; then
    pass "Pi module no longer clones visual-explainer at activation"
  else
    fail "Pi module still clones visual-explainer at activation"
  fi
  if grep -q 'VISUAL_EXPLAINER_DIR/commands/' "$PI_OUT/activate"; then
    pass "Pi module installs visual-explainer prompts from commands/"
  else
    fail "Pi module does not install visual-explainer prompts from commands/"
  fi

  # Managed packages are materialized at BUILD time: activation must not run
  # npm or git at all — facades link from the store tree.
  if ! grep -Eq 'npm (install|uninstall|ci)|git (ls-remote|clone)' "$PI_OUT/activate" \
     && grep -q 'managed Pi packages materialized from /nix/store' "$PI_OUT/activate"; then
    pass "Pi activation materializes managed packages from the store without npm/git"
  else
    fail "Pi activation runs npm/git or no longer materializes store facades"
  fi

  # Verify every managed git source is pinned to an immutable 40-hex commit so
  # the vendor build resolves offline (no git ls-remote / npm install).
  PI_MANAGED_PACKAGES_ALL="$(store_file_from_activate "$PI_OUT/activate" 'pi-managed-packages')/agent/managed-packages.declarations.json"
  if [[ -n "$PI_MANAGED_PACKAGES_ALL" && -f "$PI_MANAGED_PACKAGES_ALL" ]] \
    && jq -e 'all(.packages[] | select(.source.type == "git") | .source.installSpec; test("#[0-9a-fA-F]{40}$"))' "$PI_MANAGED_PACKAGES_ALL" >/dev/null 2>&1; then
    pass "Pi module pins every git-source package to an immutable commit"
  else
    fail "Pi module has a git-source package using a mutable ref (branch/tag)"
  fi

  if [[ -n "$PI_MANAGED_PACKAGES_ALL" && -f "$PI_MANAGED_PACKAGES_ALL" ]] \
    && jq -e 'any(.packages[]; .packageId == "pi-powerline-footer" and .source.type == "git" and .source.packageName == "pi-powerline-footer" and (.source.installSpec | test("^github:nicobailon/pi-powerline-footer#[0-9a-fA-F]{40}$"))) and any(.packages[]; .packageId == "pi-zentui" and .source.type == "git" and .source.packageName == "pi-zentui" and (.source.installSpec | test("^github:lmilojevicc/pi-zentui#[0-9a-fA-F]{40}$")))' "$PI_MANAGED_PACKAGES_ALL" >/dev/null 2>&1; then
    pass "Pi module manages pinned Powerline and Zentui sources"
  else
    fail "Pi module must manage pinned Powerline and Zentui sources"
  fi

  if [[ -n "$PI_SETTINGS_STORE_JSON" && -f "$PI_SETTINGS_STORE_JSON" ]] \
    && jq -e '.packages | index("./packages/pi-powerline-footer") != null and index("./packages/pi-zentui") == null' "$PI_SETTINGS_STORE_JSON" >/dev/null 2>&1; then
    pass "Pi module defaults to the Powerline footer profile"
  else
    fail "Pi module must load only Powerline by default"
  fi

  PI_MANAGED_TREE="$(store_file_from_activate "$PI_OUT/activate" 'pi-managed-packages')"
  if [[ -n "$PI_SETTINGS_STORE_JSON" && -f "$PI_SETTINGS_STORE_JSON" ]] \
    && jq -e '.powerline | .preset == "nerd" and .fixedEditor == true and .mouseScroll == true and .welcome == true and .cost.subscriptionDisplay == "reported-cost" and .path.mode == "abbreviated" and .path.maxLength == 36' "$PI_SETTINGS_STORE_JSON" >/dev/null 2>&1 \
    && jq -e '.powerlineShortcuts.scrollChatUp == "ctrl+alt+u" and .powerlineShortcuts.scrollChatDown == "ctrl+alt+d"' "$PI_SETTINGS_STORE_JSON" >/dev/null 2>&1 \
    && jq -e '.colors.model == "#cba6f7"' "$PI_MANAGED_TREE/vendor/node_modules/pi-powerline-footer/theme.json" >/dev/null 2>&1 \
    && grep -q 'export POWERLINE_NERD_FONTS="1"' "$PI_OUT/home-path/etc/profile.d/hm-session-vars.sh"; then
    pass "Powerline profile applies the declarative visual configuration"
  else
    fail "Powerline profile must apply its declarative visual configuration"
  fi

  # Verify agent-kit installs from the pinned flake input (no runtime clone)
  # and that its extension symlink targets resolve to real files in the store
  # (guards against the historical pi/extensions/ dangling-symlink bug).
  if ! grep -q 'git clone\|git fetch' "$PI_OUT/activate"; then
    pass "Pi module no longer clones agent-kit at activation"
  else
    fail "Pi module still clones/fetches agent-kit at activation"
  fi
  AK_OK=1
  for target in $(grep -oE 'ln -sf /nix/store/[^ ]*extensions/direnv/direnv\.ts' "$PI_OUT/activate" | awk '{print $3}'); do
    if [[ ! -e "$target" ]]; then
      AK_OK=0
      printf '    dangling agent-kit target: %s\n' "$target" >&2
    fi
  done
  AK_COUNT=$(grep -cE 'ln -sf /nix/store/[^ ]*extensions/direnv/direnv\.ts' "$PI_OUT/activate" || true)
  if [[ "$AK_OK" == "1" && "$AK_COUNT" == "1" ]]; then
    pass "Pi module links the agent-kit direnv extension from pinned store source (no dangling target)"
  else
    fail "Pi module agent-kit direnv symlink is missing or dangling (found $AK_COUNT/1 valid)"
  fi
  # ast-grep is served by pi-lens: agent-kit's tool/skill are no longer
  # linked and stale links from earlier activations are removed.
  if ! grep -qE 'extensions/ast-grep/ast-grep\.ts|agent-kit[^ ]*/skills/ast-grep' "$PI_OUT/activate" \
    && grep -Fq 'rm -rf "$HOME/.pi/agent/extensions/ast-grep" "$HOME/.pi/agent/skills/ast-grep"' "$PI_OUT/activate"; then
    pass "Pi module retires the agent-kit ast-grep tool/skill (pi-lens ast_grep_* instead)"
  else
    fail "Pi module still links agent-kit ast-grep or does not remove stale links"
  fi

  # Verify agents are linked
  for agent in planner plan-reviewer code-reviewer worker worker-high worker-low ui-worker researcher vision oracle \
               plan-author implementer reviewer helper; do
    if [[ -f "$PI_FILES/.pi/agent/agents/$agent.md" ]]; then
      pass "Pi module links agent: $agent"
    else
      fail "Pi module missing agent: $agent"
    fi
  done

  # Verify preset
  if [[ -f "$PI_FILES/.pi/agent/preset.jsonc" ]]; then
    pass "Pi module links preset.jsonc"
  else
    fail "Pi module missing preset.jsonc"
  fi

  # Verify models.json contains expected providers
  if jq -e '.providers | has("zai-coding-plan")' "$PI_FILES/.pi/agent/models.json" >/dev/null 2>&1; then
    pass "models.json contains zai-coding-plan provider"
  else
    fail "models.json missing zai-coding-plan provider"
  fi

  if jq -e '.providers["zai-coding-plan"].models | any(.id == "glm-5.3" and .contextWindow == 1000000 and .maxTokens == 131072 and .reasoning == true) and any(.id == "glm-5.3-flash" and .name == "GLM 5.3 Flash" and .contextWindow == 1000000 and .maxTokens == 131072 and .reasoning == true and .input == ["text", "image"])' "$PI_FILES/.pi/agent/models.json" >/dev/null 2>&1; then
    pass "models.json includes GLM 5.3 and GLM 5.3 Flash"
  else
    fail "models.json is missing GLM 5.3 or GLM 5.3 Flash metadata"
  fi

  if [[ -n "$PI_SETTINGS_STORE_JSON" && -f "$PI_SETTINGS_STORE_JSON" ]] \
    && jq -e '.enabledModels | index("zai-coding-plan/glm-5.3") != null and index("zai-coding-plan/glm-5.3-flash") != null' "$PI_SETTINGS_STORE_JSON" >/dev/null 2>&1; then
    pass "Pi enabledModels includes GLM 5.3 and GLM 5.3 Flash"
  else
    fail "Pi enabledModels is missing GLM 5.3 or GLM 5.3 Flash"
  fi

  if jq -e '.providers["github-copilot"].models | any(.id == "claude-opus-5" and .api == "anthropic-messages" and .contextWindow == 1048576 and .maxTokens == 128000 and .compat.forceAdaptiveThinking == true and .headers["Editor-Version"] == "vscode/1.107.0")' "$PI_FILES/.pi/agent/models.json" >/dev/null 2>&1; then
    pass "models.json extends github-copilot with Claude Opus 5"
  else
    fail "models.json missing Claude Opus 5 github-copilot model"
  fi

  if jq -e '.providers["github-copilot"].models | any(.id == "grok-4.7" and .api == "openai-responses" and .contextWindow == 500000 and .maxTokens == 128000 and .headers["Editor-Version"] == "vscode/1.107.0")' "$PI_FILES/.pi/agent/models.json" >/dev/null 2>&1; then
    pass "models.json extends github-copilot with Grok 4.7"
  else
    fail "models.json missing Grok 4.7 github-copilot model"
  fi

  # S12 model set, direct (default): OpenAI Codex, plus GLM while z.ai is on.
  # The installed role agents carry the approved table's models and thinking.
  if jq -e '.defaultProvider == "openai-codex" and .defaultModel == "gpt-5.6-sol" and .defaultThinkingLevel == "medium"' "$PI_SETTINGS_STORE_JSON" >/dev/null 2>&1 \
    && jq -e 'all(.enabledModels[]; test("^(openai-codex|zai-coding-plan)/")) and (.enabledModels | index("zai-coding-plan/glm-5.3") != null)' "$PI_SETTINGS_STORE_JSON" >/dev/null 2>&1; then
    pass "direct model set: default OpenAI Codex gpt-5.6-sol; enabledModels are OpenAI Codex and GLM only"
  else
    fail "direct model set: default or enabledModels are wrong (Fireworks, xAI or Copilot present?)"
  fi
  if agent_models_within "$PI_FILES" 'openai-codex|zai-coding-plan'; then
    pass "direct model set: every installed agent names an OpenAI Codex or GLM model"
  else
    fail "direct model set: an installed agent names a model outside OpenAI Codex and GLM"
  fi
  agent_model_expect "$PI_FILES" plan-author openai-codex/gpt-5.6-sol high
  agent_model_expect "$PI_FILES" implementer openai-codex/gpt-5.6-sol medium
  agent_model_expect "$PI_FILES" reviewer zai-coding-plan/glm-5.3 high
  agent_model_expect "$PI_FILES" helper zai-coding-plan/glm-5.3-flash low
  agent_model_expect "$PI_FILES" oracle openai-codex/gpt-5.6-sol xhigh
  agent_model_expect "$PI_FILES" researcher zai-coding-plan/glm-5.3-flash low
  agent_model_expect "$PI_FILES" planner openai-codex/gpt-5.6-sol high
  agent_model_expect "$PI_FILES" vision openai-codex/gpt-5.6-sol medium
  agent_model_expect "$PI_FILES" code-reviewer zai-coding-plan/glm-5.3 high
  agent_model_expect "$PI_FILES" worker-low zai-coding-plan/glm-5.3-flash low
  if grep -v '^[[:space:]]*//' "$PI_FILES/.pi/agent/preset.jsonc" \
     | jq -e '.presets | length == 3 and all(.[]; .provider == "openai-codex" and .model == "gpt-5.6-sol")' >/dev/null; then
    pass "presets take the plan-author model of the direct set"
  else
    fail "preset.jsonc must take the direct set's plan-author model"
  fi
  # S12 hidden skills: pi-subagents, council-mode, btw and librarian are manual-only;
  # visual-explainer is hidden by a build-time copy.
  PI_HIDDEN_SKILLS="$(package_skill_visibility "$PI_MANAGED_AGENT/packages/pi-subagents" "$PI_MANAGED_AGENT/packages/pi-btw" "$PI_MANAGED_AGENT/packages/pi-web-access")"
  if jq -e '[.["pi-subagents"], .["council-mode"], .["btw"], .["librarian"]] | all(. == true)' <<<"$PI_HIDDEN_SKILLS" >/dev/null 2>&1; then
    pass "package skills pi-subagents, council-mode, btw and librarian are manual-only"
  else
    fail "package skills pi-subagents, council-mode, btw or librarian are still visible to the model"
  fi
  if grep -Fxq 'disable-model-invocation: true' "$PI_VISUAL_SKILL/SKILL.md" 2>/dev/null; then
    pass "visual-explainer is installed as a manual-only skill"
  else
    fail "visual-explainer must be installed with disable-model-invocation: true"
  fi
  if jq -e '.packages | any(test("pi-mcp-adapter"))' "$PI_SETTINGS_STORE_JSON" >/dev/null 2>&1 \
    && [[ -f "$PI_FILES/.pi/agent/mcp-adapter.json" ]]; then
    pass "direct set with z.ai on keeps pi-mcp-adapter and its config"
  else
    fail "direct set with z.ai on must keep pi-mcp-adapter and mcp-adapter.json"
  fi

  if jq -e '.providers | has("fireworks")' "$PI_FILES/.pi/agent/models.json" >/dev/null 2>&1; then
    fail "models.json must not define fireworks provider (use built-in + FIREWORKS_API_KEY)"
  else
    pass "models.json omits fireworks (built-in provider)"
  fi
else
  fail "Pi module activation package failed to build"
  printf '  Output: %s\n' "$PI_OUT" >&2
fi

# S12 model sets. pi-copilot-module is the g3660 machine: modelSet copilot with
# zai.enable = false. pi-direct-no-zai-module is the direct set with z.ai off.
# Each names only its own providers; z.ai off drops GLM and the adapter.
printf '\nBuilding Copilot model-set activation package (z.ai off)...\n'
COPILOT_OUT="$(build_pi_out pi-copilot-module)"
if [[ -n "$COPILOT_OUT" && -d "$COPILOT_OUT" ]]; then
  pass "Copilot model-set Pi module builds"
  COPILOT_FILES="$(readlink -f "$COPILOT_OUT/home-files")"
  COPILOT_SETTINGS="$(store_file_from_activate "$COPILOT_OUT/activate" 'pi-agent-config')/agent/settings.json"
  if jq -e '.defaultProvider == "github-copilot" and .defaultModel == "claude-sonnet-5.5" and .defaultThinkingLevel == "medium" and (.enabledModels | length > 0) and all(.enabledModels[]; startswith("github-copilot/"))' "$COPILOT_SETTINGS" >/dev/null 2>&1; then
    pass "Copilot model set: default and enabledModels are Copilot only"
  else
    fail "Copilot model set: default or enabledModels name a non-Copilot model"
  fi
  if agent_models_within "$COPILOT_FILES" 'github-copilot'; then
    pass "Copilot model set: every installed agent names a Copilot model"
  else
    fail "Copilot model set: an installed agent names a non-Copilot model"
  fi
  agent_model_expect "$COPILOT_FILES" plan-author github-copilot/claude-opus-5.5 high
  agent_model_expect "$COPILOT_FILES" implementer github-copilot/gpt-6.2-sol medium
  agent_model_expect "$COPILOT_FILES" reviewer github-copilot/claude-opus-5.5 high
  agent_model_expect "$COPILOT_FILES" helper github-copilot/claude-haiku-5.5 low
  agent_model_expect "$COPILOT_FILES" oracle github-copilot/claude-fable-5.2 high
  agent_model_expect "$COPILOT_FILES" researcher github-copilot/claude-sonnet-5.5 low
  if grep -v '^[[:space:]]*//' "$COPILOT_FILES/.pi/agent/preset.jsonc" \
     | jq -e '.presets | length == 3 and all(.[]; .provider == "github-copilot" and .model == "claude-opus-5.5")' >/dev/null; then
    pass "presets take the plan-author model of the Copilot set"
  else
    fail "preset.jsonc must take the Copilot set's plan-author model"
  fi
  if ! jq -e '.packages | any(test("pi-mcp-adapter"))' "$COPILOT_SETTINGS" >/dev/null 2>&1 \
    && [[ ! -e "$COPILOT_FILES/.pi/agent/mcp-adapter.json" ]]; then
    pass "Copilot model set with z.ai off has no pi-mcp-adapter and no mcp-adapter.json"
  else
    fail "Copilot model set with z.ai off still ships pi-mcp-adapter or mcp-adapter.json"
  fi
else
  fail "Copilot model-set Pi module (checks.pi-copilot-module) is missing or fails to build"
fi

printf '\nBuilding direct model-set activation package (z.ai off)...\n'
NOZAI_OUT="$(build_pi_out pi-direct-no-zai-module)"
if [[ -n "$NOZAI_OUT" && -d "$NOZAI_OUT" ]]; then
  pass "direct model-set Pi module with z.ai off builds"
  NOZAI_FILES="$(readlink -f "$NOZAI_OUT/home-files")"
  NOZAI_SETTINGS="$(store_file_from_activate "$NOZAI_OUT/activate" 'pi-agent-config')/agent/settings.json"
  if jq -e '.defaultProvider == "openai-codex" and .defaultModel == "gpt-5.6-sol" and all(.enabledModels[]; startswith("openai-codex/"))' "$NOZAI_SETTINGS" >/dev/null 2>&1; then
    pass "direct set with z.ai off: enabledModels are OpenAI Codex only"
  else
    fail "direct set with z.ai off: enabledModels name a non-OpenAI-Codex model"
  fi
  if agent_models_within "$NOZAI_FILES" 'openai-codex'; then
    pass "direct set with z.ai off: every installed agent names an OpenAI Codex model"
  else
    fail "direct set with z.ai off: an installed agent names a non-OpenAI-Codex model"
  fi
  agent_model_expect "$NOZAI_FILES" reviewer openai-codex/gpt-5.6-sol high
  agent_model_expect "$NOZAI_FILES" helper openai-codex/gpt-5.6-luna low
  agent_model_expect "$NOZAI_FILES" researcher openai-codex/gpt-5.6-luna low
  NOZAI_PACKAGES="$(store_file_from_activate "$NOZAI_OUT/activate" 'pi-managed-packages')/agent/packages"
  if jq -e '.packages | all(.[]; contains("pi-mcp-adapter") | not)' "$NOZAI_SETTINGS" >/dev/null \
    && jq -e '.providers | has("zai-coding-plan") | not' "$NOZAI_FILES/.pi/agent/models.json" >/dev/null \
    && [[ -d "$NOZAI_PACKAGES" && ! -e "$NOZAI_PACKAGES/pi-mcp-adapter" && ! -e "$NOZAI_FILES/.pi/agent/mcp-adapter.json" ]] \
    && [[ -f "$NOZAI_FILES/.pi/agent/t3-profile.args" ]] \
    && ! grep -Fq '/packages/pi-mcp-adapter' "$NOZAI_FILES/.pi/agent/t3-profile.args"; then
    pass "z.ai off drops GLM config and the adapter from both profiles and the managed facades"
  else
    fail "z.ai off still ships GLM config or the adapter in at least one profile"
  fi
else
  fail "direct model-set Pi module with z.ai off (checks.pi-direct-no-zai-module) is missing or fails to build"
fi

# The alternate footer profile must build independently and configure only
# Zentui. This prevents two UI-owning extensions from loading together.
printf '\nBuilding Zentui footer-profile activation package...\n'
PI_ZENTUI_OUT=$(nix build "$REPO_ROOT#checks.x86_64-linux.pi-zentui-module.activationPackage" \
  --no-link --print-out-paths 2>&1) || true
PI_ZENTUI_OUT=$(echo "$PI_ZENTUI_OUT" | grep '^/nix/store' | head -1 || true)
PI_ZENTUI_SETTINGS_STORE_JSON=""
if [[ -n "$PI_ZENTUI_OUT" && -x "$PI_ZENTUI_OUT/activate" ]]; then
  pass "Zentui footer-profile activation package builds"
  PI_ZENTUI_SETTINGS_STORE_JSON="$(store_file_from_activate "$PI_ZENTUI_OUT/activate" 'pi-agent-config')/agent/settings.json"
  if [[ -n "$PI_ZENTUI_SETTINGS_STORE_JSON" && -f "$PI_ZENTUI_SETTINGS_STORE_JSON" ]] \
    && jq -e '.packages | index("./packages/pi-zentui") != null and index("./packages/pi-powerline-footer") == null' "$PI_ZENTUI_SETTINGS_STORE_JSON" >/dev/null 2>&1; then
    pass "Zentui footer profile loads only Zentui"
  else
    fail "Zentui footer profile must not load Powerline"
  fi
else
  fail "Zentui footer-profile activation package is missing or has no activation script"
fi

# The repo-local Pi development script activates this dedicated package with an
# isolated HOME. Keep it independently buildable so contributors can test the
# checkout without changing their active Home Manager generation.
printf '\nBuilding Pi development activation package...\n'
PI_DEV_OUT=$(nix build "$REPO_ROOT#pi-dev-activation" --no-link --print-out-paths 2>&1) || true
PI_DEV_OUT=$(echo "$PI_DEV_OUT" | grep '^/nix/store' | head -1 || true)
if [[ -n "$PI_DEV_OUT" && -x "$PI_DEV_OUT/activate" ]]; then
  pass "Pi development activation package builds"
else
  fail "Pi development activation package is missing or has no activation script"
fi

# 2. Build the OpenCode module check
printf '\nBuilding OpenCode module activation package...\n'
OC_OUT=$(nix build "$REPO_ROOT#checks.x86_64-linux.opencode-module.activationPackage" \
  --no-link --print-out-paths 2>&1) || true
OC_OUT=$(echo "$OC_OUT" | grep '^/nix/store' | head -1 || true)
OC_FILES=$(readlink -f "$OC_OUT/home-files" 2>/dev/null || echo "")

if [[ -n "$OC_OUT" && -d "$OC_OUT" ]]; then
  pass "OpenCode module activation package builds"

  if [[ -f "$OC_FILES/.config/opencode/opencode.json" ]]; then
    pass "OpenCode module produces opencode.json"
  else
    fail "OpenCode module missing opencode.json"
  fi

  if [[ -f "$OC_FILES/.config/opencode/oh-my-openagent.json" ]]; then
    pass "OpenCode module produces oh-my-openagent.json"
  else
    fail "OpenCode module missing oh-my-openagent.json"
  fi

  # Verify opencode.json has expected structure
  if jq -e '.plugin | type == "array"' "$OC_FILES/.config/opencode/opencode.json" >/dev/null 2>&1; then
    pass "opencode.json has plugin array"
  else
    fail "opencode.json missing plugin array"
  fi

  if jq -e '.plugin | index("oh-my-openagent@4.13.0") != null' "$OC_FILES/.config/opencode/opencode.json" >/dev/null 2>&1; then
    pass "opencode.json pins oh-my-openagent 4.13.0"
  else
    fail "opencode.json does not pin oh-my-openagent 4.13.0"
  fi

  if jq -e '.mcp | has("web-search-prime")' "$OC_FILES/.config/opencode/opencode.json" >/dev/null 2>&1; then
    pass "opencode.json has MCP servers"
  else
    fail "opencode.json missing MCP servers"
  fi

  if jq -e '.provider.openai.models | has("gpt-5.5") and has("gpt-5.2") and has("gpt-5.2-codex")' "$OC_FILES/.config/opencode/opencode.json" >/dev/null 2>&1; then
    pass "opencode.json configures ChatGPT Pro OAuth OpenAI models"
  else
    fail "opencode.json missing ChatGPT Pro OAuth OpenAI models"
  fi

  if jq -e '.provider | has("openai-api") | not' "$OC_FILES/.config/opencode/opencode.json" >/dev/null 2>&1; then
    pass "opencode.json has no separate openai-api provider"
  else
    fail "opencode.json unexpectedly contains openai-api provider"
  fi

  if jq -e '.model == "zai-coding-plan/glm-5.2"' "$OC_FILES/.config/opencode/opencode.json" >/dev/null 2>&1; then
    pass "opencode.json defaults to GLM 5.2"
  else
    fail "opencode.json default model is not GLM 5.2"
  fi

  if jq -e '.agent.build.model == "openai/gpt-5.5" and .agent.plan.model == "openai/gpt-5.5" and .agent.plan.mode == "primary"' "$OC_FILES/.config/opencode/opencode.json" >/dev/null 2>&1; then
    pass "opencode.json keeps built-in plan primary on GPT 5.5"
  else
    fail "opencode.json does not keep built-in plan primary on GPT 5.5"
  fi

  if jq -e '.sisyphus_agent.planner_enabled == true and .sisyphus_agent.replace_plan == false' "$OC_FILES/.config/opencode/oh-my-openagent.json" >/dev/null 2>&1; then
    pass "oh-my-openagent enables Prometheus without replacing plan"
  else
    fail "oh-my-openagent planner settings do not preserve plan visibility"
  fi

  if jq -e '.agents."multimodal-looker".model == "zai-coding-plan/glm-5v-turbo" and .agents."multimodal-looker".fallback_models == ["zai-coding-plan/glm-5.2"]' "$OC_FILES/.config/opencode/oh-my-openagent.json" >/dev/null 2>&1; then
    pass "oh-my-openagent routes multimodal tasks to GLM 5V turbo"
  else
    fail "oh-my-openagent multimodal model routing is incorrect"
  fi

  if jq -e '.team_mode.enabled == true and .team_mode.max_parallel_members == 4' "$OC_FILES/.config/opencode/oh-my-openagent.json" >/dev/null 2>&1; then
    pass "oh-my-openagent enables team mode"
  else
    fail "oh-my-openagent team mode is not enabled"
  fi

  # Verify OpenCode ships only the three primary mode agents
  for agent in discovery design execute; do
    if [[ -f "$OC_FILES/.config/opencode/agents/$agent.md" ]]; then
      pass "OpenCode agent: $agent"
    else
      fail "OpenCode missing agent: $agent"
    fi
  done

  # All engineering sub-roles are delegated via task categories or built-in
  # subagent types in OpenCode, NOT shipped as custom subagents.
  for agent in planner worker ui-worker researcher plan-reviewer code-reviewer oracle; do
    if [[ -f "$OC_FILES/.config/opencode/agents/$agent.md" ]]; then
      fail "OpenCode should not ship '$agent' as a subagent (category/subagent_type-delegated)"
    else
      pass "OpenCode does not ship '$agent' subagent (category/subagent_type-delegated)"
    fi
  done

  # Verify engineering workflow skills (OpenCode-rendered set)
  for skill in discovery design execution-orchestrator research create-plan create-worklog execute-task review-plan review-code review-approach review-epic assess-repo create-skills configure-opencode; do
    if [[ -f "$OC_FILES/.config/opencode/skills/$skill/SKILL.md" ]]; then
      pass "OpenCode skill: $skill"
    else
      fail "OpenCode missing skill: $skill"
    fi
  done


  if jq -e '.categories.quick.model == "zai-coding-plan/glm-5.2" and .categories.deep.model == "openai/gpt-5.5" and .categories.ultrabrain.model == "openai/gpt-5.5" and .agents.hephaestus.model == "openai/gpt-5.5"' "$OC_FILES/.config/opencode/oh-my-openagent.json" >/dev/null 2>&1; then
    pass "oh-my-openagent exposes cheap implementation, strong rescue, and strong review tiers"
  else
    fail "oh-my-openagent team role model tiers are incorrect"
  fi

  # Verify the visual-explainer skill is installed by default (external
  # pinned skill wired via the visualExplainer flake input + extraSkills).
  if [[ -f "$OC_FILES/.config/opencode/skills/visual-explainer/SKILL.md" ]]; then
    pass "OpenCode installs visual-explainer skill by default"
  else
    fail "OpenCode missing visual-explainer skill"
  fi

  # Verify adapted skills have opencode compatibility
  for skill in discovery design execution-orchestrator; do
    if grep -q 'compatibility: opencode' "$OC_FILES/.config/opencode/skills/$skill/SKILL.md" 2>/dev/null; then
      pass "Adapted skill $skill has opencode compatibility"
    else
      fail "Adapted skill $skill missing opencode compatibility"
    fi
  done

  # Verify discovery agent references the Design agent (not Pi preset)
  if grep -q 'press Tab' "$OC_FILES/.config/opencode/agents/discovery.md"; then
    pass "Discovery agent uses Tab switching (not Pi presets)"
  else
    fail "Discovery agent has incorrect switching reference"
  fi

  # Verify execution orchestrator uses the task tool (not Pi subagent calls)
  if grep -q 'task(category=\|task(subagent_type=\|task({' "$OC_FILES/.config/opencode/skills/execution-orchestrator/SKILL.md" \
     && ! grep -q 'subagent(' "$OC_FILES/.config/opencode/skills/execution-orchestrator/SKILL.md"; then
    pass "Execution orchestrator uses task tool delegation"
  else
    fail "Execution orchestrator missing task tool delegation"
  fi

else
  fail "OpenCode module activation package failed to build"
fi

# 3. Build both modules together
printf '\nBuilding both modules together...\n'
BOTH_OUT=$(nix build "$REPO_ROOT#checks.x86_64-linux.both-modules.activationPackage" \
  --no-link --print-out-paths 2>&1) || true
BOTH_OUT=$(echo "$BOTH_OUT" | grep '^/nix/store' | head -1 || true)
BOTH_FILES=$(readlink -f "$BOTH_OUT/home-files" 2>/dev/null || echo "")

if [[ -n "$BOTH_OUT" && -d "$BOTH_OUT" ]]; then
  pass "Both modules together build successfully"

  # Quick sanity: both Pi and OpenCode files present
  if [[ -f "$BOTH_FILES/.pi/agent/models.json" ]] && \
     [[ -f "$BOTH_FILES/.config/opencode/opencode.json" ]]; then
    pass "Combined build contains both Pi and OpenCode files"
  else
    fail "Combined build missing Pi or OpenCode files"
  fi
else
  fail "Both modules together failed to build"
fi

# ============================================================
printf '\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
