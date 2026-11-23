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
for harness in pi opencode hermes; do
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

# Skills that declare packaged references in skill-resources.json must render them
for packaged in discover-and-design discover-and-design-simple; do
  for resource in references/brief-template.md references/approach-template.md; do
    if grep -q "skills/discovery/references/brief-template.md\|skills/design/references/approach-template.md" skill-resources.json \
       && [[ -f "$REPO_ROOT/dist/skills/hermes/${packaged}/${resource}" ]]; then
      pass "${packaged} packages ${resource}"
    else
      fail "${packaged} is missing packaged ${resource} — check skill-resources.json entries for discover-and-design*"
    fi
  done
done

# Retired parallel-machinery skills must not be rendered anywhere
for retired in dynamic-create-plan dynamic-execute-plan dynamic-review-plan dynamic-review-code direct-plan create-team-plan review-team-plan create-team-worklog execution-orchestrator-team; do
  if [[ -e "$REPO_ROOT/dist/skills/pi/${retired}" || -e "$REPO_ROOT/dist/skills/opencode/${retired}" ]]; then
    fail "${retired} is retired but still rendered"
  else
    pass "${retired} is not rendered (retired with ADR 0006)"
  fi
done

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

# The Pi tree is the frontier pipeline (ADR 0007): its entry points, its role
# skills and the shared rules must all render, with the check script and the
# catalog contract packaged where the skills say they are.
for frontier in prototype scope run-plan run-epic map-patterns plan implement review \
                architecture-model delegate test-quality; do
  if [[ -f "$REPO_ROOT/dist/skills/pi/${frontier}/SKILL.md" ]]; then
    pass "Pi tree renders ${frontier}"
  else
    fail "Pi tree is missing ${frontier}"
  fi
done
for packaged in architecture-model/tools/model-check.mjs \
                architecture-model/references/pattern-catalog.md \
                map-patterns/references/pattern-catalog.md \
                assess-repo/references/pattern-catalog.md; do
  if [[ -f "$REPO_ROOT/dist/skills/pi/${packaged}" ]]; then
    pass "Pi tree packages ${packaged}"
  else
    fail "Pi tree is missing ${packaged} — check skill-resources.json"
  fi
done

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

# configure-pi is Pi-only, project-scoped, and preserves the spawn-limit boundary.
if [[ -f "$REPO_ROOT/dist/skills/pi/configure-pi/SKILL.md" ]] \
  && grep -Fq '`.pi/settings.json`' "$REPO_ROOT/dist/skills/pi/configure-pi/SKILL.md" \
  && grep -Fq '`.pi/extensions/guardrails.json`' "$REPO_ROOT/dist/skills/pi/configure-pi/SKILL.md" \
  && grep -Fq '`.pi/session-autoname.json`' "$REPO_ROOT/dist/skills/pi/configure-pi/SKILL.md" \
  && grep -Fq 'seeds `github-copilot/gpt-6-luna`' "$REPO_ROOT/dist/skills/pi/configure-pi/SKILL.md" \
  && grep -Fq 'pathAccess.allowedPaths' "$REPO_ROOT/dist/skills/pi/configure-pi/SKILL.md" \
  && grep -Fq 'autoDenyPatterns' "$REPO_ROOT/dist/skills/pi/configure-pi/SKILL.md" \
  && grep -Fq 'maxSubagentSpawnsPerSession' "$REPO_ROOT/dist/skills/pi/configure-pi/SKILL.md" \
  && grep -Fq 'PI_SUBAGENT_MAX_SPAWNS_PER_SESSION=100 pi' "$REPO_ROOT/dist/skills/pi/configure-pi/SKILL.md" \
  && grep -Fq 'outside this project-scoped skill' "$REPO_ROOT/dist/skills/pi/configure-pi/SKILL.md"; then
  pass "configure-pi documents project settings, repository Guardrails, session naming, and spawn-limit boundaries"
else
  fail "configure-pi is missing Pi project settings, repository Guardrails, session naming, or spawn-limit boundaries"
fi
if [[ -e "$REPO_ROOT/dist/skills/opencode/configure-pi" ]]; then
  fail "configure-pi (pi-only) leaked into the OpenCode tree"
else
  pass "configure-pi is excluded from the OpenCode tree"
fi

# Team mode was replaced by code-mode execution: the Pi-only team skills are gone,
# and the retired orchestration skills render for OpenCode only.
for gone in pi-team-plan pi-team-lead pi-team-worker; do
  if [[ ! -e "$REPO_ROOT/dist/skills/pi/${gone}" ]]; then
    pass "${gone} is absent from the Pi tree"
  else
    fail "${gone} must be absent from the Pi tree"
  fi
done
# The sequential pipeline is retired for Pi (ADR 0007), which runs the
# frontier pipeline instead. OpenCode and Hermes still run it, so its skills
# render for those two and must not reach the Pi tree. Still harness-scoped:
# configure-* and the Hermes-process skills (skill-sync, software-development).
for sequential in discovery design research review-approach review-epic \
                  create-plan review-plan create-worklog execute-task \
                  execution-orchestrator review-code prototype-first work-item; do
  if [[ -f "$REPO_ROOT/dist/skills/opencode/${sequential}/SKILL.md" ]] \
     && [[ -f "$REPO_ROOT/dist/skills/hermes/${sequential}/SKILL.md" ]]; then
    pass "${sequential} renders for OpenCode and Hermes"
  else
    fail "${sequential} must render for OpenCode and Hermes (they still run the sequential pipeline)"
  fi
  if [[ -e "$REPO_ROOT/dist/skills/pi/${sequential}" ]]; then
    fail "${sequential} is retired for Pi (ADR 0007) but still rendered there"
  else
    pass "${sequential} is not rendered for Pi (retired with ADR 0007)"
  fi
done
for hermes_seq in discover-and-design discover-and-design-simple; do
  if [[ -e "$REPO_ROOT/dist/skills/pi/${hermes_seq}" ]]; then
    fail "${hermes_seq} is retired for Pi (ADR 0007) but still rendered there"
  else
    pass "${hermes_seq} is not rendered for Pi (retired with ADR 0007)"
  fi
done
for hermes_only in skill-sync software-development; do
  if [[ -e "$REPO_ROOT/dist/skills/pi/${hermes_only}" || -e "$REPO_ROOT/dist/skills/opencode/${hermes_only}" ]]; then
    fail "${hermes_only} (hermes-only) leaked into pi/opencode trees"
  else
    pass "${hermes_only} is excluded from the pi/opencode trees"
  fi
  if [[ -f "$REPO_ROOT/dist/skills/hermes/${hermes_only}/SKILL.md" ]]; then
    pass "${hermes_only} is present in the Hermes tree"
  else
    fail "${hermes_only} is missing from the Hermes tree"
  fi
done

# Per-harness discoverability: hiddenSkills in harnesses/pi.json must render
# disable-model-invocation for Pi only, never for OpenCode.
for hidden in configure-pi create-skills; do
  if grep -Fq 'disable-model-invocation: true' "$REPO_ROOT/dist/skills/pi/${hidden}/SKILL.md"; then
    pass "${hidden} is hidden from the Pi system prompt"
  else
    fail "${hidden} should be hidden from the Pi system prompt"
  fi
  if [[ -f "$REPO_ROOT/dist/skills/opencode/${hidden}/SKILL.md" ]] \
     && grep -Fq 'disable-model-invocation' "$REPO_ROOT/dist/skills/opencode/${hidden}/SKILL.md"; then
    fail "${hidden} discoverability must not leak into the OpenCode tree"
  else
    pass "${hidden} discoverability does not leak into the OpenCode tree"
  fi
done
for shown in assess-repo; do
  if grep -Fq 'disable-model-invocation' "$REPO_ROOT/dist/skills/pi/${shown}/SKILL.md"; then
    fail "${shown} must remain discoverable in Pi"
  else
    pass "${shown} remains discoverable in Pi"
  fi
done

# The team-mode execution skills are OpenCode-only and must not leak into Pi
# Retired team skills must not appear in either harness tree (covered above), and
# the retired parallel resources must not be referenced by any rendered skill.
if grep -rqE 'dynamic-(create|execute|review)|execution-orchestrator-team|create-team-plan' "$REPO_ROOT/dist/skills/pi" "$REPO_ROOT/dist/skills/opencode" 2>/dev/null; then
  fail "rendered skills must not reference retired parallel machinery"
else
  pass "rendered skills reference no retired parallel machinery"
fi

# Every rendered SKILL.md must carry the harness-correct compatibility value
for harness in pi opencode hermes; do
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
# Every rendered Pi delegation block must be syntactically valid JavaScript.
# Prompts are prose and may contain quotes or backslashes; raw interpolation
# silently emitted broken snippets before the renderer encoded them properly.
if node -e '
const fs = require("fs"), path = require("path");
let bad = 0, n = 0;
const root = path.join(process.argv[1], "dist", "skills", "pi");
for (const d of fs.readdirSync(root)) {
  const f = path.join(root, d, "SKILL.md");
  if (!fs.existsSync(f)) continue;
  for (const m of fs.readFileSync(f, "utf8").matchAll(/^subagent\(\{[\s\S]*?^\}\)$/gm)) {
    n += 1;
    try { new Function("subagent", "return " + m[0]); }
    catch (e) { bad += 1; console.error(`invalid subagent block in ${d}: ${e.message}`); }
  }
}
// No Pi skill renders a delegation block today: the frontier skills describe
// delegation in prose. Any block a later skill adds is still checked here.
process.exit(bad === 0 ? 0 : 1);
' "$REPO_ROOT"; then
  pass "every rendered Pi subagent block is valid JavaScript"
else
  fail "a rendered Pi subagent block is not valid JavaScript"
fi

# Hermes alignment (PR #25 follow-up): every skill the Hermes pipeline routes
# to must render for Hermes; pi delegations must select model + skill and keep
# reviewer sessions distinct; packaged references must exist.
H="$REPO_ROOT/dist/skills/hermes"
for s in discover-and-design discover-and-design-simple babysit-pr software-development skill-sync; do
  if [[ -f "$H/$s/SKILL.md" ]]; then pass "hermes tree renders $s"; else fail "hermes tree is missing $s"; fi
done
for r in execution-modes.md testing-strategy.md agent-roles.md; do
  if [[ -f "$H/software-development/references/$r" ]]; then pass "software-development packages $r"; else fail "software-development lacks references/$r"; fi
done
if grep -rq -- '--session-id <session-id>' "$H"; then fail "hermes pi delegation uses a shared <session-id> placeholder"; else pass "hermes pi delegations use stage-specific session ids"; fi
if grep -rh '^pi -p ' "$H" | grep -v -- '--model <model-for-' | grep -q .; then fail "a hermes pi delegation lacks --model"; else pass "every hermes pi delegation selects a model"; fi
if grep -rh '^pi -p .*--name "[a-z-]*reviewer"' "$H" | grep -v -- '-review-<N>' | grep -q .; then fail "a hermes review delegation reuses a non-review session id"; else pass "hermes review delegations get -review-<N> session ids"; fi

printf '\n'
# ============================================================
# S12 delegation through T3: one launcher reference in delegate, a role
# resolver, process skills that say "launch role X", and the visibility split.
# Requirement: FR-008

DELEGATE_DIST="$REPO_ROOT/dist/skills/pi/delegate"
if [[ -f "$DELEGATE_DIST/references/launching-a-role.md" ]] \
  && grep -Fq 'delegate_task' "$DELEGATE_DIST/references/launching-a-role.md" \
  && grep -Fq 't3_thread_send' "$DELEGATE_DIST/references/launching-a-role.md" \
  && grep -Fq 'task_cancel' "$DELEGATE_DIST/references/launching-a-role.md" \
  && grep -Fq 'childThreadId' "$DELEGATE_DIST/references/launching-a-role.md" \
  && grep -Fq 'role.mjs' "$DELEGATE_DIST/references/launching-a-role.md" \
  && grep -Fq 'subagent' "$DELEGATE_DIST/references/launching-a-role.md"; then
  pass "delegate ships references/launching-a-role.md with both launcher forms and run ids"
else
  fail "delegate/references/launching-a-role.md is missing or lacks the T3 and terminal launcher forms"
fi
if [[ -f "$DELEGATE_DIST/role.mjs" ]]; then
  pass "delegate renders role.mjs next to its SKILL.md"
else
  fail "delegate does not render role.mjs"
fi
if grep -Eq '^#+ Launching a role$' "$DELEGATE_DIST/SKILL.md" \
  && grep -Fq 'references/launching-a-role.md' "$DELEGATE_DIST/SKILL.md"; then
  pass "delegate SKILL.md has a Launching a role section pointing at the reference"
else
  fail "delegate SKILL.md lacks the Launching a role section"
fi

for process in scope run-plan run-epic plan implement review map-patterns; do
  f="$REPO_ROOT/dist/skills/pi/${process}/SKILL.md"
  if [[ -f "$f" ]] && grep -Fqi 'launch role' "$f" && grep -Fq 'Launching a role' "$f" \
     && ! grep -Eq '`subagent`|subagent\(|pi-subagents' "$f"; then
    pass "${process} launches roles through delegate, not the subagent tool"
  else
    fail "${process} must say 'launch role X' pointing at delegate → Launching a role, and name no subagent tool"
  fi
done

# Visibility split (S12 decision 3): process skills stay visible; the hidden
# list in harnesses/pi.json stays exactly the two authoring skills.
if node -e 'const h=require(process.argv[1]);process.exit(JSON.stringify(h.hiddenSkills)==="[\"configure-pi\",\"create-skills\"]"?0:1)' "$REPO_ROOT/harnesses/pi.json"; then
  pass "harnesses/pi.json hiddenSkills is exactly configure-pi and create-skills"
else
  fail "harnesses/pi.json hiddenSkills must stay exactly configure-pi and create-skills"
fi
for visible in scope run-plan run-epic prototype map-patterns assess-repo delegate backlog \
               triage-backlog pull-request babysit-pr plan implement review architecture-model test-quality; do
  if [[ -f "$REPO_ROOT/dist/skills/pi/${visible}/SKILL.md" ]] \
     && ! grep -Fq 'disable-model-invocation' "$REPO_ROOT/dist/skills/pi/${visible}/SKILL.md"; then
    pass "${visible} stays visible to the model in Pi"
  else
    fail "${visible} must stay visible to the model in Pi"
  fi
done

# ------------------------------------------------------------
# role.mjs resolver regression. Run as `node skills/delegate/role.mjs <role>`
# from a project directory, with PI_CODING_AGENT_DIR pointing at the user
# config. Precedence: project .pi/settings.json subagents.agentOverrides, then
# the user's settings.json, then the agents/<role>.md frontmatter.
ROLE_TMP="$(mktemp -d)"
trap 'rm -rf "$ROLE_TMP"' EXIT
ROLE_PROJECT="$ROLE_TMP/project"
ROLE_AGENT_DIR="$ROLE_TMP/agent"
mkdir -p "$ROLE_PROJECT/.pi" "$ROLE_PROJECT/skills/delegate" "$ROLE_AGENT_DIR/agents"
ln -s "$REPO_ROOT/skills/delegate/role.mjs" "$ROLE_PROJECT/skills/delegate/role.mjs"
cat >"$ROLE_PROJECT/.pi/settings.json" <<'JSON'
{"subagents":{"agentOverrides":{"reviewer":{"model":"zai-coding-plan/glm-5.3","thinking":"low"}}}}
JSON
cat >"$ROLE_AGENT_DIR/settings.json" <<'JSON'
{"subagents":{"agentOverrides":{"planner":{"model":"openai-codex/gpt-5.6-sol","thinking":"high"},"reviewer":{"model":"openai-codex/gpt-5.6-luna","thinking":"medium"}}}}
JSON
cat >"$ROLE_AGENT_DIR/agents/reviewer.md" <<'MD'
---
name: reviewer
description: fixture reviewer
model: github-copilot/claude-opus-5.5
thinking: high
skill: review, test-quality, delegate
---
Fixture body.
MD
cat >"$ROLE_AGENT_DIR/agents/planner.md" <<'MD'
---
name: planner
description: fixture planner
model: github-copilot/gpt-6.1-sol
thinking: medium
---
Fixture body.
MD
cat >"$ROLE_AGENT_DIR/agents/helper.md" <<'MD'
---
name: helper
description: fixture helper
model: zai-coding-plan/glm-5.3-flash
thinking: low
skill: test-quality
---
Fixture body.
MD

role_json() {
  (cd "$ROLE_PROJECT" && PI_CODING_AGENT_DIR="$ROLE_AGENT_DIR" node skills/delegate/role.mjs "$1" 2>/dev/null) || true
}

json_expect() {
  local description="$1" json="$2" expression="$3"
  if printf '%s' "$json" | node -e 'const j = JSON.parse(require("fs").readFileSync(0, "utf8")); process.exit((('"$expression"')) ? 0 : 1);' 2>/dev/null; then
    pass "$description"
  else
    printf '    resolver output: %s\n' "${json:-<empty>}" >&2
    fail "$description"
  fi
}

REVIEWER_JSON="$(role_json reviewer)"
json_expect 'role.mjs: project override beats user settings and frontmatter' "$REVIEWER_JSON" \
  'j.role === "reviewer" && j.model === "zai-coding-plan/glm-5.3" && j.thinking === "low"'
json_expect 'role.mjs: frontmatter skills and skill paths are reported' "$REVIEWER_JSON" \
  'JSON.stringify(j.skills) === JSON.stringify(["review", "test-quality", "delegate"]) && j.skillPaths.length === 3 && j.skillPaths.every((p) => p.endsWith("/SKILL.md"))'

PLANNER_JSON="$(role_json planner)"
json_expect 'role.mjs: user settings override beats frontmatter when no project entry exists' "$PLANNER_JSON" \
  'j.model === "openai-codex/gpt-5.6-sol" && j.thinking === "high"'

HELPER_JSON="$(role_json helper)"
json_expect 'role.mjs: frontmatter is used when no override exists' "$HELPER_JSON" \
  'j.model === "zai-coding-plan/glm-5.3-flash" && j.thinking === "low" && JSON.stringify(j.skills) === JSON.stringify(["test-quality"])'

json_expect 'role.mjs: delegate skill grants mayDelegate' "$REVIEWER_JSON" 'j.mayDelegate === true'
json_expect 'role.mjs: roles without delegate skill do not get mayDelegate' "$HELPER_JSON" 'j.mayDelegate === false'

if (cd "$ROLE_PROJECT" && PI_CODING_AGENT_DIR="$ROLE_AGENT_DIR" node skills/delegate/role.mjs no-such-role >/dev/null 2>&1); then
  fail 'role.mjs must exit non-zero for a role with no agent file or override'
else
  pass 'role.mjs exits non-zero for an unknown role'
fi

printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
