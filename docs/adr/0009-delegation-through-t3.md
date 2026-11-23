# ADR 0009: Delegation through T3

Status: Accepted
Date: 2026-11-23

## Context

Pi runs the frontier pipeline in both a terminal and T3. Loading terminal UI
extensions in T3 adds noise, and exposing two delegation tools makes role
routing ambiguous. Mixed-provider defaults also do not work on machines that
have only Copilot access.

## Decision

- Terminal Pi keeps `pi-subagents`, the tasks bridge and terminal UI packages.
  A T3 RPC launch with an installed profile uses explicit extensions and T3's
  `delegate_task` instead. Remove `pi-hooks` and `pi-agent-guidance` from both.
- Keep one installed definition per role. Use `delegate` → Launching a role
  for dispatch and lifecycle operations. T3 resolves the installed role and
  the same repo/user overrides the terminal launcher uses. A fresh review
  always gets a new launch.
- Select a per-machine model set: direct (OpenAI Codex plus optional z.ai) or
  Copilot. The z.ai switch also controls the MCP adapter. Repository-specific
  overrides still take precedence at runtime.
- Keep process skills visible, while occasional authoring and package guides
  stay installed but manual-only. See [Skill Rendering](../skill-rendering.md).

## Consequences

T3 children are visible threads; record their IDs so the same author can
continue after a review. T3 prepares isolated lane worktrees from committed
state; the orchestrator integrates their branches. Terminal Pi continues to
use its existing worktree and child-session controls. A missing role model
is a configuration error, not permission to switch to another provider.
