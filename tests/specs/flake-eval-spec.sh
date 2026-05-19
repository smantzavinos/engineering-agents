#!/usr/bin/env bash
# Verify flake checks pass: modules instantiate and produce valid activation packages
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

  if [[ -f "$PI_FILES/.pi/agent/mcp.json" ]]; then
    pass "Pi module produces mcp.json"
  else
    fail "Pi module missing mcp.json in activation package"
  fi

  if [[ -f "$PI_FILES/.pi/agent/keybindings.json" ]]; then
    pass "Pi module produces keybindings.json"
  else
    fail "Pi module missing keybindings.json in activation package"
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
  for skill in discovery design research create-plan review-plan create-worklog \
               execute-task execution-orchestrator review-code review-approach \
               assess-repo create-skills create-new-repo-docs; do
    if [[ -f "$PI_FILES/.pi/agent/skills/$skill/SKILL.md" ]]; then
      pass "Pi module links skill: $skill"
    else
      fail "Pi module missing skill: $skill"
    fi
  done

  # Verify agents are linked
  for agent in planner plan-reviewer code-reviewer worker ui-worker researcher vision oracle; do
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

  if jq -e '.providers | has("fireworks")' "$PI_FILES/.pi/agent/models.json" >/dev/null 2>&1; then
    pass "models.json contains fireworks provider"
  else
    fail "models.json missing fireworks provider"
  fi
else
  fail "Pi module activation package failed to build"
  printf '  Output: %s\n' "$PI_OUT" >&2
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

  if [[ -f "$OC_FILES/.config/opencode/oh-my-opencode.json" ]]; then
    pass "OpenCode module produces oh-my-opencode.json"
  else
    fail "OpenCode module missing oh-my-opencode.json"
  fi

  # Verify opencode.json has expected structure
  if jq -e '.plugin | type == "array"' "$OC_FILES/.config/opencode/opencode.json" >/dev/null 2>&1; then
    pass "opencode.json has plugin array"
  else
    fail "opencode.json missing plugin array"
  fi

  if jq -e '.mcp | has("web-search-prime")' "$OC_FILES/.config/opencode/opencode.json" >/dev/null 2>&1; then
    pass "opencode.json has MCP servers"
  else
    fail "opencode.json missing MCP servers"
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
