---
name: prototype
description: Human-paired build-to-learn session. Produce a fast, throwaway prototype that shows the behavior we want, handed off as a pushed branch plus PROTOTYPE.md. Use when the quickest way to specify the work is to see it working.
---

# Prototype

Build a working demo with the human, as fast as possible. It answers "is this what we want?". It is the spec for behavior, not the implementation. The real build comes later, through `scope` and `orchestrate`.

## Session
- Restate the target as 2–3 bullets of visible behavior. Confirm them before building.
- Optimize for speed only: hardcode, fake, skip error handling, no tests, no refactoring.
- Keep a running change list as C1, C2 and so on, each with its objective, before/after and files. Note every hack as you make it.
- When the human reacts, change the code and update the list. Record the accepted behavior, not the first attempt.
- Timebox it to one session. If it needs more, cut the scope.

## Exit (required)
- Branch `prototype/<slug>`, taken off the default branch, committed and pushed.
- A runnable demo. For UI work, add screenshots under `prototype-evidence/`.
- `PROTOTYPE.md` at the repo root, containing:
  - **Verdict:** build / build with changes / don't build.
  - **What was prototyped:** each change, with its objective and where it lives.
  - **Acceptance scenarios:** numbered, each tied to a change. These become the definition of done.
  - **How to run it, what's faked, and the shortcuts taken.**
  - **Disposal recommendation:**
    - wipe-and-rebuild (default), or
    - clean up in place, when the structure is sound.

    Give the reason.
  - **Open questions, and the backlog item ID.**
- A linked backlog item (via the `backlog` skill) carrying the verdict and the branch. Create one if none exists.

A "don't build" verdict is a success. Still write it up.

## Don't
- Deploy anything, use real secrets or customer data, or do anything irreversible.
- Merge the prototype branch.
- Clean up as you go. Note the mess instead.
