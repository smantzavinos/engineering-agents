# <Project Name> Testing Strategy

**Status:** Draft
**Audience:** Engineering, QA, maintainers
**Related:** `docs/requirements.md`, `docs/workflows/README.md`, `CONTRIBUTING.md`

## 1. Why this document exists
This document defines how the project will be verified and what each testing level is responsible for proving.

## 2. Testing principles
- Tests should map back to tagged requirements whenever practical.
- Workflow-critical behavior should not rely on unit tests alone.
- Documentation examples and user-facing commands should be kept honest.
- Manual verification is allowed, but only when the reason is explicit.

## 3. Test levels
| Level | Purpose | Tools / frameworks | Command | What it proves | Typical requirement types |
|---|---|---|---|---|---|
| Unit | <isolated logic> | <tool> | `<command>` | <what it proves> | FR-* |
| Integration | <boundary behavior> | <tool> | `<command>` | <what it proves> | FR-*, WF-* |
| End-to-end | <full user workflow> | <tool> | `<command>` | <what it proves> | WF-* |
| Contract / golden | <stable outputs / schemas> | <tool> | `<command>` | <what it proves> | FR-*, NFR-* |
| Docs validation | <docs/examples stay correct> | <tool> | `<command>` | <what it proves> | WF-*, OPS-* |
| Manual verification | <human-reviewed behaviors> | N/A | <manual checklist> | <what it proves> | any |

## 4. Requirement traceability matrix
| Requirement ID | Test levels | Primary tool | Notes |
|---|---|---|---|
| WF-001 | E2E + Manual | <tool> | <notes> |
| FR-001 | Unit + Integration | <tool> | <notes> |
| NFR-001 | Contract + Manual | <tool> | <notes> |

## 5. Workflow verification approach
| Workflow | Primary persona | Main proof path | Supporting checks |
|---|---|---|---|
| <workflow> | <persona> | <e2e/manual/integration> | <additional coverage> |

## 6. Test data / fixtures strategy
- <where fixtures live>
- <how golden outputs are stored>
- <how representative user scenarios are selected>

## 7. Manual verification checklist
- [ ] <manual check>
- [ ] <manual check>

## 8. Exit criteria by delivery stage
| Stage | Required checks |
|---|---|
| Local development | <checks> |
| Pull request | <checks> |
| Release candidate | <checks> |

## 9. Known gaps / deferred coverage
- <gap>
- <gap>
