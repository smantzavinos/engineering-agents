# OpenCode team-mode capabilities and constraints

**Created:** 2026-07-14
**Topic:** What team mode provides and the constraints that shape a wave-based execution design
**Plan:** ../brief.md

## Summary
Team mode gives a lead plus member child-sessions parallel coordination through a shared task list and message passing. Teams are ephemeral; the lead owns spawning and closure. Members are category-backed workers (routed through `sisyphus-junior`) or a small set of eligible named subagents. Members cannot load skills — they get behavior only through their prompt. Bounds cap real concurrency at 4 workers / 8 members. These properties directly shape the design: skill injection via prompt, a lead-owned single committer, a task-list coordination substrate, and mandatory teardown.

## Findings

### Team shape and declaration
- A team is declared at `~/.omo/teams/{name}/config.json` or passed inline to `team_create({ inline_spec })`. It has a `lead` plus a `members` list; every member has a `kind` discriminator (`category` or `subagent_type`).
- Category members must include both `category` and `prompt`; they always route through `sisyphus-junior` (documented as D-40). This is the same tier the sequential OpenCode path already uses for delegated roles, so using it here is **not** a quality downgrade.
- Eligible `subagent_type` members: `sisyphus`, `atlas`, `sisyphus-junior`, `hephaestus`. **Hard rejects:** `oracle`, `prometheus`, and other non-eligible agents. For an oracle-grade opinion, the lead fires a one-off `task(subagent_type="oracle")` outside the team.

### Skills are NOT loaded for members — behavior comes from the prompt
- The skill states plainly: "`loadSkills` is ignored because team members receive their behavior through `prompt`." This is the single most important constraint for this design: the whole engineering process relies on `load_skills=["execute-task"]` / `["review-code"]`, which team members cannot use.
- Mitigation adopted in the approach: the member prompt instructs the member to **read the canonical skill file first** and follow it, keeping the discipline in one canonical place.

### Coordination is a shared task list plus auto-delivered messages
- `team_task_create` / `team_task_update` / `team_task_list` / `team_task_get` manage a shared task board. Tasks support `blockedBy` (dependency IDs) and `owner`.
- Members claim unassigned, unblocked tasks by setting `owner` + `status` (`claimed`/`in_progress`), preferring lowest ID first, and re-check the list after completing each task.
- `team_send_message` delivers messages as new conversation turns automatically (queued if the recipient is mid-turn). Broadcast is lead-only. This is the channel for live coordination (e.g. "I'm editing `src/a.ts`").

### Lifecycle: ephemeral, lead-driven, must be closed
- Teams are ephemeral; there is no in-place reshape (restructuring = delete-then-create).
- **Closure Contract:** a team is closable when every task is terminal (`completed`/`failed`), no shutdown request is pending, and the user hasn't asked to keep it open. Closure is the lead's responsibility and should happen in the same turn the contract becomes true.
- **Closure Sequence:** for each active member → `team_shutdown_request` then `team_approve_shutdown`; then `team_delete`. `force: true` only for unrecoverable states, never to skip member shutdown.
- "Lingering teams burn sessions, mailbox quota, and member-turn budget every idle minute" — so idle windows between waves have a real cost.

### Bounds and failure modes
- Max 8 members, **max 4 parallel workers**, max 32KB/message, max 256KB unread inbox.
- No nested teams; no peer sync wait (work is asynchronous); broadcast is lead-only.
- Teammates go idle after every turn — idle is normal, not an error, and a message wakes them.

### Visualization / isolation modes
- The skill mentions "worktree mode for isolated code changes, or tmux visualization when you want live session layout." Worktree isolation is available but is **explicitly rejected** for this design in favor of a shared tree + single committer (see approach for rationale).

## Constraints that shape the design
| Constraint | Design consequence |
|------------|--------------------|
| `loadSkills` ignored for members | Member prompt must point to the canonical skill file and require reading it first. |
| Category members = `sisyphus-junior`; `oracle`/`prometheus` rejected | Reviewer is a `category="ultrabrain"` member (same tier as today's reviews); oracle stays a one-off outside the team. |
| Max 4 parallel workers | Wave width cap = 4; wider ready-sets spill into later waves. |
| Async, no peer sync wait, shared state | Single committer (lead) avoids git races; file-disjoint waves avoid content races; the task list is the live cursor. |
| Ephemeral + Closure Contract + idle cost | Lead must run the Closure Sequence when waves finish; minimize idle by rebalancing or shutting down idle members. |
| No nested teams | Wave orchestration is flat: one lead, one member pool, iterated across waves. |

## References
- `team-mode` skill (builtin; not in this repo's `skills/` tree; loaded via the skill tool) — team declaration, member schema, lifecycle, closure contract/sequence, task-list coordination, message delivery, bounds, failure modes.
- `docs/orchestration.md` — harness note confirming category→sisyphus-junior tiering already used by the sequential path.
