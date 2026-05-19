# Repository Quality Process Foundation

**Type:** standard
**Created:** 2026-05-19
**Owner:** pi planning agent

## Goals
- [ ] Make this repo itself a high-quality example of the autonomous engineering process it teaches.
- [ ] Add the missing root-level operating contracts needed for agents to discover architecture, verification, backlog, requirements, and specialized-area guidance without guessing.
- [ ] Establish durable repo mechanisms for backlog capture and requirements handling, with stable IDs and explicit approval boundaries.
- [ ] Turn repo-readiness expectations into executable checks so future drift is caught by the existing test suite.
- [ ] Improve contributor ergonomics with canonical environment, coding, testing, planning, ADR, and learnings documentation.

## Non-Goals
- Rewriting the core process, skill set, or agent architecture defined in the existing docs.
- Performing a broad content rewrite of every existing process document.
- Shipping new end-user features unrelated to repo readiness and process correctness.
- Introducing a tracker or requirements database more complex than this repo currently needs.

## Constraints
- The repo must remain usable throughout the work; documentation and verification changes should be incremental and test-backed.
- Verification commands in new docs must come from existing repo commands and scripts, not invented placeholders.
- The resulting setup should favor simple, durable mechanisms that agents can execute locally without external service dependencies.
- The repo should dogfood its own guidance: routing in `AGENTS.md`, explicit test levels, durable backlog capture, and requirements traceability.
- Existing published structure for skills, agents, Nix modules, and tests should remain recognizable unless a specific inconsistency must be corrected.

## Motivation
This repository teaches teams how to prepare repos for autonomous engineering, but it currently lacks several of the exact repo-level operating contracts it recommends: there is no root `AGENTS.md`, no repo-specific backlog system, no repo-specific requirements mechanism or explicit posture, no canonical testing strategy mapped to standard levels, and no specialized per-directory guidance. That means the repo is strong on process theory but not yet a complete reference implementation of that theory. Bringing the repo up to a high-quality, process-ready baseline will make it easier to maintain, safer for autonomous execution, and more credible as an example for other repos.

## Success Criteria
This work is successful when:
- A root `AGENTS.md` routes agents to architecture, environment, coding rules, testing strategy, backlog, requirements, and per-directory guidance.
- The repo has canonical docs for architecture, coding rules, environment setup, testing strategy, backlog, requirements, ADRs, plans, and learnings.
- The repo has per-directory `AGENTS.md` files for its specialized areas and lightweight `.llm/` instructions where they add value.
- Repo-local tests fail if these contracts disappear or drift.
- Repo-wide verification is reliable enough to act as a real completion gate, including explicit handling of the current Pi proof-set module-path issue.
- Documentation is internally consistent about model overrides, verification commands, backlog capture, and requirements handling.

## Requirement Context
Relevant existing requirements, if the repo maintains them today:
- Actors/personas: none documented yet
- Use cases: none documented yet
- Workflows/scenarios: none documented yet
- Requirements: none documented yet

Requirement questions:
- Should this repo continue without a separate requirements system, or should it maintain one because it publishes durable process contracts and tooling behavior?
- If the repo adopts a requirements system, what is the smallest useful initial baseline for contributor, maintainer, and end-user workflows?

## Plan Level
standard

**Rationale:** This is a cohesive repo-improvement initiative with multiple related documentation and verification surfaces, but it remains one bounded body of work. It needs a structured approach and dependency-aware execution, not epic decomposition.

## Key Decisions Made (during planning setup)
| Decision | Chosen | Rationale |
|----------|--------|-----------|
| Quality bar | Go beyond minimum readiness | The repo should be a reference implementation, not merely barely compliant. |
| Backlog mechanism target | Simple Markdown backlog | Durable, local, agent-executable, and sufficient for this repo's scale. |
| Requirements posture target | Maintain a lightweight Markdown requirements system | This repo has durable public/process contracts and benefits from stable IDs and traceability. |
| Verification philosophy | Make readiness contracts executable in tests | Prevents future documentation drift and dogfoods the process. |
| Specialized guidance | Add per-directory `AGENTS.md` files and lightweight `.llm/` guidance | Improves progressive discovery without overloading the root routing doc. |
