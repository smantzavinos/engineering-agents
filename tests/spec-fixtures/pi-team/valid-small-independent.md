# Valid small independent plan
Plan schema: 1
Intent: Deliver three bounded independent changes without artificial dependency chains.
Approval: auto

## Contracts
| ID | Behavior | Evidence |
|---|---|---|
| C1 | Preserve each bounded behavior | Targeted spec |

## Decisions
| ID | Decision | Resolution |
|---|---|---|
| D1 | Keep independent work parallel | No dependencies between tasks |

## Checks
| ID | Scope | Command | Cost | Worker-safe |
|---|---|---|---|---|
| K1 | worker | node --check tools/pi-team.mjs | low | yes |
| K2 | integration:G1 | bash tests/specs/pi-team-tool-spec.sh | medium | no |
| K3 | final | ./tests/run-tests.sh fast | high | no |

## Tasks
| ID | Deps | Lane | Estimate min | Risk labels | Integration | Deliverable | Write set | Contracts | Decisions | Check |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | — | cheap | 20 | — | G1 | Add the first bounded change | sandbox/small-1.txt | C1 | D1 | K1 |
| T2 | — | std | 20 | — | G1 | Add the second bounded change | sandbox/small-2.txt | C1 | D1 | K1 |
| T3 | — | complex | 20 | — | G1 | Add the third bounded change | sandbox/small-3.txt | C1 | D1 | K1 |
