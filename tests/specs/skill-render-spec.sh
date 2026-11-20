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
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
