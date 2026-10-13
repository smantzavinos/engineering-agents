# Auditing existing tests

Use this for a test-audit work item, never inside a feature child. The rules for judging each test are in the `test-quality` skill.

- Read the history, callers and owners first. Work in batches by subsystem, and never toward a deletion count.
- For each candidate:
  - record the proof that remains;
  - delete it, consolidate it into a table, or move it to the real boundary;
  - delete any seam that only the test used.
- Use mutation testing where the repo has it. Tests that kill no mutants are candidates, and a batch must not lower the mutation score.
- Run the owning and sibling tests, and get a fresh review.
- Report the causes found, the contracts retained, and test LOC before and after.
