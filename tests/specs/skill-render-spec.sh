#!/usr/bin/env bash
# Verify the skill render pipeline: dist/ is up to date with canonical sources,
# and each harness tree uses the correct harness-specific delegation syntax.
# Requirement: FR-007
# Requirement: FR-008
# Requirement: NFR-003
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node >/dev/null

REPO_ROOT="$(repo_root)"
PASS=0 FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# ============================================================
printf 'Skill render pipeline verification\n'
printf '==================================\n\n'

# Harness profiles exist and are valid JSON
for harness in pi opencode; do
  profile="$REPO_ROOT/harnesses/${harness}.json"
  if node -e "JSON.parse(require('fs').readFileSync('$profile','utf8'))" 2>/dev/null; then
    pass "Harness profile '${harness}.json' is valid JSON"
  else
    fail "Harness profile '${harness}.json' is missing or invalid JSON"
  fi
done

# Renderer has valid syntax
if node --check "$REPO_ROOT/tools/render-skills.mjs" 2>/dev/null; then
  pass "render-skills.mjs has valid syntax"
else
  fail "render-skills.mjs has syntax errors"
fi

# dist/ must match a fresh render (drift gate). This is the core contract:
# canonical skills + harness profiles are the single source of truth.
if node "$REPO_ROOT/tools/render-skills.mjs" --check >/dev/null 2>&1; then
  pass "dist/skills/ is up to date with canonical sources + harness profiles"
else
  fail "dist/skills/ is stale — run: node tools/render-skills.mjs --write"
fi

# Canonical sources must NOT hardcode compatibility in their frontmatter block
# (the renderer injects it per harness). Body documentation may still mention it.
if node -e '
  const fs=require("fs"),path=require("path");
  const dir=path.join(process.argv[1],"skills");
  let bad=[];
  for(const name of fs.readdirSync(dir)){
    const f=path.join(dir,name,"SKILL.md");
    if(!fs.existsSync(f))continue;
    const src=fs.readFileSync(f,"utf8");
    if(!src.startsWith("---\n"))continue;
    const end=src.indexOf("\n---\n",4);
    const fm=src.slice(4,end);
    if(/^compatibility:/m.test(fm))bad.push(name);
  }
  if(bad.length){console.error(bad.join(","));process.exit(1);}
' "$REPO_ROOT" 2>/dev/null; then
  pass "canonical skills/ leave compatibility to the renderer"
else
  fail "canonical skills/ hardcode 'compatibility:' in frontmatter (renderer injects it)"
fi

# No unexpanded macros may survive into any rendered tree
if grep -rn '{{' "$REPO_ROOT/dist/skills/" >/dev/null 2>&1; then
  fail "rendered dist/ contains unexpanded {{...}} macros"
else
  pass "rendered dist/ has no unexpanded macros"
fi

# Pi tree uses Pi delegation syntax (subagent), never the OpenCode task tool
if grep -rn 'task(category=\|task({' "$REPO_ROOT/dist/skills/pi/" >/dev/null 2>&1; then
  fail "Pi tree must not contain OpenCode 'task(...)' delegation"
else
  pass "Pi tree uses only Pi-style delegation"
fi
if grep -rln 'subagent({' "$REPO_ROOT/dist/skills/pi/execution-orchestrator/SKILL.md" >/dev/null 2>&1; then
  pass "Pi execution-orchestrator renders subagent({...}) delegation"
else
  fail "Pi execution-orchestrator is missing subagent({...}) delegation"
fi

# OpenCode tree must not contain Pi-style subagent() calls
if grep -rn 'subagent(' "$REPO_ROOT/dist/skills/opencode/" >/dev/null 2>&1; then
  fail "OpenCode tree must not contain Pi 'subagent(...)' delegation"
else
  pass "OpenCode tree uses only OpenCode-style delegation"
fi

# The review/oracle roles must render as category delegation in OpenCode
# (replacing the former plan-reviewer / code-reviewer / oracle subagents).
for skill_check in \
  "execution-orchestrator:review-plan" \
  "execution-orchestrator:review-code" \
  "design:review-approach"; do
  skill="${skill_check%%:*}"
  loadskill="${skill_check##*:}"
  if grep -q "task(category=\"deep\", load_skills=\[\"${loadskill}\"\]" \
      "$REPO_ROOT/dist/skills/opencode/${skill}/SKILL.md"; then
    pass "OpenCode ${skill} delegates ${loadskill} via category"
  else
    fail "OpenCode ${skill} does not delegate ${loadskill} via category"
  fi
done

# OpenCode plan creation and implementation roles delegate via task categories
if grep -q 'task(category="deep", load_skills=\["create-plan"\]' \
    "$REPO_ROOT/dist/skills/opencode/execution-orchestrator/SKILL.md"; then
  pass "OpenCode execution-orchestrator delegates planning via category"
else
  fail "OpenCode execution-orchestrator does not delegate planning via category"
fi
if grep -q 'task(category="unspecified-high", load_skills=\["execute-task"\]' \
    "$REPO_ROOT/dist/skills/opencode/execution-orchestrator/SKILL.md"; then
  pass "OpenCode execution-orchestrator delegates task execution via category"
else
  fail "OpenCode execution-orchestrator does not delegate task execution via category"
fi

# OpenCode research roles delegate to built-in explore/librarian subagent types
if grep -q 'task(subagent_type="explore", load_skills=\["research"\]' \
    "$REPO_ROOT/dist/skills/opencode/design/SKILL.md"; then
  pass "OpenCode design delegates codebase research to the explore subagent"
else
  fail "OpenCode design does not delegate codebase research to explore"
fi
if grep -q 'task(subagent_type="librarian", load_skills=\["research"\]' \
    "$REPO_ROOT/dist/skills/opencode/design/SKILL.md"; then
  pass "OpenCode design delegates external research to the librarian subagent"
else
  fail "OpenCode design does not delegate external research to librarian"
fi

# Pi keeps named subagents for those same roles
if grep -q 'agent: "worker"' "$REPO_ROOT/dist/skills/pi/design/SKILL.md"; then
  pass "Pi design keeps the worker subagent for research"
else
  fail "Pi design lost the worker subagent for research"
fi

# configure-opencode is OpenCode-only and must not leak into the Pi tree
if [[ -e "$REPO_ROOT/dist/skills/pi/configure-opencode" ]]; then
  fail "configure-opencode (opencode-only) leaked into the Pi tree"
else
  pass "configure-opencode is excluded from the Pi tree"
fi
if [[ -f "$REPO_ROOT/dist/skills/opencode/configure-opencode/SKILL.md" ]]; then
  pass "configure-opencode is present in the OpenCode tree"
else
  fail "configure-opencode is missing from the OpenCode tree"
fi

# The team-mode execution skills are OpenCode-only and must not leak into Pi
for oc_only in execution-orchestrator-team create-team-plan review-team-plan create-team-worklog; do
  if [[ -e "$REPO_ROOT/dist/skills/pi/${oc_only}" ]]; then
    fail "${oc_only} (opencode-only) leaked into the Pi tree"
  else
    pass "${oc_only} is excluded from the Pi tree"
  fi
  if [[ -f "$REPO_ROOT/dist/skills/opencode/${oc_only}/SKILL.md" ]]; then
    pass "${oc_only} is present in the OpenCode tree"
  else
    fail "${oc_only} is missing from the OpenCode tree"
  fi
done

if grep -Fq 'team_plan.md' "$REPO_ROOT/dist/skills/opencode/create-team-plan/SKILL.md" \
  && grep -Fq 'team_plan_review.md' "$REPO_ROOT/dist/skills/opencode/review-team-plan/SKILL.md" \
  && grep -Fq 'Do not poll' "$REPO_ROOT/dist/skills/opencode/execution-orchestrator-team/SKILL.md"; then
  pass "OpenCode team pipeline renders separate planning artifacts and no-polling execution"
else
  fail "OpenCode team pipeline rendering is incomplete"
fi

# Every rendered SKILL.md must carry the harness-correct compatibility value
for harness in pi opencode; do
  bad=0
  while IFS= read -r f; do
    if ! grep -q "^compatibility: ${harness}$" "$f"; then bad=$((bad + 1)); fi
  done < <(find "$REPO_ROOT/dist/skills/${harness}" -name SKILL.md)
  if [[ "$bad" -eq 0 ]]; then
    pass "All ${harness} skills declare compatibility: ${harness}"
  else
    fail "${bad} ${harness} skill(s) have wrong compatibility frontmatter"
  fi
done

# ============================================================
printf '\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
