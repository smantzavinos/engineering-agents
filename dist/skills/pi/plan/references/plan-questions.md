# Plan questions

Each question is answered where it applies, in a line or two in the named section, or with "n/a". A good answer is specific enough for a reviewer to check against the code.

## Access and visibility (Design, Tests)
- **Good:** names each actor and what they may see and do, including hidden, archived, locked or other-tenant items, and where each rule is enforced. Tests name the owning test for each guard, at the boundary `test-quality` prescribes.
- **n/a:** the child adds no read path, write path or UI that depends on who the user is or on an item's state.
- A missing answer where the child has this concern is a review major.

## Failure and concurrency (Design, Tests)
- **Good:** what the user sees when each call fails; whether a retry is safe; what happens when two users change the same thing; how live updates behave when data changes underneath.
- **n/a:** read-only, single-step changes with no external call.
- A missing answer where the child has this concern is a review major.

## Assumptions checked against the code (Context, Gates)
- **Good:** each thing the plan relies on (a function, field, index, route, fixture) is named with its path, as checked. Specs, docs and files outside the edit list that the change affects are named, and T1 selects those specs.
- **n/a:** rarely; most plans rely on something.

## Limits and load (Design, Risks)
- **Good:** for read-heavy features, the platform limits that apply (query size, fan-out, payload, rate) and how the design stays within them at the expected data size.
- **n/a:** no new reads that grow with data.

## Deviations (Design)
- **Good:** each departure from the prototype or from an earlier decision, with the reason.
- **n/a:** none.

## Deliverables (Done when)
- **Good:** the outcomes the build must contain: each scenario, each spec, each visible UI behaviour. Outcomes, not tasks; the implementer maps each to the file or test that delivers it.
- **n/a:** never.
- A missing list is a review major.
