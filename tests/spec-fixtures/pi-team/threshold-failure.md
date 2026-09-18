# Valid diamond
Plan schema: 1
Intent: Exercise the deterministic compiler while leaving unrelated behavior unchanged.
Approval: auto

## Contracts
| ID | Behavior | Evidence |
|---|---|---|
| C1 | Preserve the contract | Targeted spec |

## Decisions
| ID | Decision | Resolution |
|---|---|---|
| D1 | Use deterministic order | Numeric task IDs |

## Checks
| ID | Scope | Command | Cost | Worker-safe |
|---|---|---|---|---|
| K1 | worker | node --check tools/pi-team.mjs | low | yes |
| K2 | integration:G1 | bash tests/specs/pi-team-tool-spec.sh | medium | no |
| K3 | final | ./tests/run-tests.sh fast | high | no |

## Tasks
| ID | Deps | Lane | Estimate min | Risk labels | Integration | Deliverable | Write set | Contracts | Decisions | Check |
|---|---|---|---|---|---|---|---|---|---|---|
| T10 | — | cheap | 1 | — | G1 | Add tenth support file | sandbox/t10.txt | C1 | D1 | K1 |
| T3 | T2 | std | 1 | — | G1 | Implement branch alpha | sandbox/t3.txt | C1 | D1 | K1 |
| T1 | — | complex | 21 | api-contract | G1 | Establish the oversized root behavior | sandbox/t1.txt | C1 | D1 | K1 |
| T9 | — | visual | 1 | — | G1 | Add ninth support file | sandbox/t9.txt | C1 | D1 | K1 |
| T5 | T2 | visual-complex | 1 | auth | G1 | Implement branch beta | sandbox/t5.txt | C1 | D1 | K1 |
| T2 | T1 | std | 1 | — | G1 | Extend the root behavior | sandbox/t2.txt | C1 | D1 | K1 |
| T6 | T5 | cheap | 1 | — | G1 | Complete branch beta | sandbox/t6.txt | C1 | D1 | K1 |
| T4 | T3 | visual | 1 | — | G1 | Complete branch alpha | sandbox/t4.txt | C1 | D1 | K1 |
| T8 | T7 | complex | 1 | destructive,migration | G1 | Complete the joined behavior | sandbox/t8.txt | C1 | D1 | K1 |
| T7 | T4,T6 | std | 1 | — | G1 | Join both branches | sandbox/t7.txt | C1 | D1 | K1 |
