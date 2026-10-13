---
name: test-quality
description: Decide which tests to write, keep or remove, and judge tests in review. Used by plan authors, implementers and reviewers, and by test audit campaigns.
compatibility: pi
---

# Test quality

A test earns its place by catching a credible regression that nothing else catches. More tests are not more proof.

## Before adding or changing a test
1. What observable behavior, invariant or independent contract does it protect?
2. What credible regression would make it fail?
3. Why doesn't existing proof catch it?
   - Each contract has one primary owner, at the strongest boundary that can see it.
   - A second layer needs a distinct risk, such as transport, lifecycle or rendering.
   - Extend table cases and shared fixtures instead of adding near-copies.
4. Does it need an export, flag, wrapper or hook that production doesn't use? Then prove it at the real boundary instead.

## Choose the layer
- **Unit:** pure logic, invariants, parsers, security normalization, data rules.
- **Backend, through the real path:** authorization, visibility, persistence, API contracts.
- **E2E:** user flows and acceptance scenarios.
- **Page or component:** interaction logic that E2E can't reach cheaply, such as keyboard handling, validation states, URL state and focus.

**Banned:** page or component tests whose point is "it renders what the mocked queries return", typically mock queues ordered by call. Prove that wiring in E2E.

## Harmful
Each of these is a *major* review finding:
- **Tautological:** the expected value is produced by the code under test, a mock supplies the behavior being asserted, or the test asserts what it set up itself.
- **Change detector:** assertions on implementation or call shape, call-order mock queues, exact class names or computed styles, copied inventories, source greps, re-export identity. A refactor that preserves behavior must not break a test.
- **Duplicate:** a contract already owned at the same layer or another one.
- **Test-only seam:** production code that exists only for the test.

These are *minor*:
- fabricated fixtures that the real path never writes;
- negative controls that don't fail at the intended guard;
- names that don't match the behavior exercised.

## Keep
- Keep API, SDK, protocol, config, migration, storage, security, platform, default-value, prompt-byte, generated-output, package, release, architecture and observable-ordering contracts.
- Being slow or static doesn't make a test disposable.
- A baseline failure may be a bug.

## Integrity
- **Regression tests:**
  - A regression test fails before the fix, for the intended reason, and passes after it. Say so if you couldn't show that.
  - Write one test, at the owning layer.
- Don't edit an existing assertion or fixture to get green unless the plan changes that contract. Say so in the ledger.
- Don't delete a test without naming what it protected and where that proof now lives.

## Auditing existing tests
Audit only as a separate work item, never inside a feature child.
- Read the history, callers and owners first. Work in batches by subsystem, and never toward a deletion count.
- For each candidate:
  - record the proof that remains;
  - delete it, consolidate it into a table, or move it to the real boundary;
  - delete any seam that only the test used.
- Use mutation testing where the repo has it. Tests that kill no mutants are candidates, and a batch must not lower the mutation score.
- Run the owning and sibling tests, and get a fresh review.
- Report the causes found, the contracts retained, and test LOC before and after.
