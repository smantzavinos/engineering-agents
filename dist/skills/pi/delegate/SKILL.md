---
name: delegate
description: Offload read-heavy, low-judgment work to fast, cheap subagents so your own context and tokens go to judgment. Use whenever a job means reading a lot to learn a little.
compatibility: pi
---

# Delegate

You are the expensive model. Spend your tokens on decisions, and hand the legwork to fast subagents. A fast subagent can read fifty files and return twenty lines.

## Delegate when
- The work is read-heavy or output-heavy.
- You can check the result easily.
- A wrong answer would be cheap to catch.

## Keep it when
- It decides what to build, how to structure it, or whether something is correct.
- Explaining the errand would take longer than doing it.
- It depends on context only you hold.

## Patterns
These are examples; invent others.
- **Scout:** "Where is X handled? List every call site of Y with file:line. Trace Z end to end."
- **Research:** external docs, library behavior, version changes, prior art. Ask for sources.
- **Run and digest:** run a long test suite or gate and report:
  - pass or fail and duration per command;
  - the failing tests and their key assertion lines;
  - the log paths, kept outside git.

  The same errand, run on an untouched tree, is the baseline that makes "pre-existing" a checkable fact.
- **Sweep:** apply a change you have already decided and done once, such as a rename, a component adopted at N call sites, or updated imports. Give it the pattern, your finished example and the list of sites, then review the diff.
- **Verify a claim:** "Does this still exist? Is this route registered? Which docs mention this path?"
- **Look:** read screenshots; compare the prototype with the real UI.
- **History:** "Why did this change? When did this behavior appear?"

Run independent errands in parallel. Run long ones, such as a baseline gate run, in the background and carry on.

## Writing the errand
- One clear job, its scope (paths, commands), the shape and length of the answer you want, and a deadline.
- Ask for file:line or URLs, and for "not found" rather than guesses.
- Say whether edits are allowed. The default is read-only.

## Don't
- Accept a delegated conclusion unread. Spot-check it.
- Redo the helper's work to check it.
- Paste raw helper output into artifacts. Distill it first.
- Delegate a lookup you can do in one command.
