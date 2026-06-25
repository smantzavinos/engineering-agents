# <Project Name> Architecture

**Status:** Draft
**Audience:** Engineering, product, maintainers
**Related:** `README.md`, `docs/glossary.md`, `docs/requirements.md`, `docs/testing-strategy.md`, `docs/adr/0001-foundation.md`

## 1. Why this document exists
This document defines the high-level architecture of the project so contributors can understand the major boundaries, data flows, constraints, and tradeoffs.

## 2. System context
- **Project purpose:** <what the system exists to do>
- **Primary users:** <who uses it>
- **Primary workflows supported:** <workflow names>
- **External systems:** <systems/services/tools integrated with>

## 3. Architectural goals
- <goal>
- <goal>
- <goal>

## 4. Constraints
- <technical constraint>
- <operational constraint>
- <compliance/security/performance constraint>

## 5. Core concepts
See also: `docs/glossary.md`

- **<concept>** — <definition>
- **<concept>** — <definition>

## 6. Top-level module / subsystem map
| Module / subsystem | Responsibility | Key inputs | Key outputs | Notes |
|---|---|---|---|---|
| <module> | <responsibility> | <inputs> | <outputs> | <notes> |
| <module> | <responsibility> | <inputs> | <outputs> | <notes> |

## 7. Core data / control flow
1. <entry point or workflow trigger>
2. <processing step>
3. <state transition or transformation>
4. <output or downstream handoff>

## 8. User-workflow-to-architecture mapping
| Workflow | Primary user | Architectural areas involved | Notes |
|---|---|---|---|
| <workflow> | <persona> | <areas> | <notes> |

## 9. Integration boundaries
| Integration | Direction | Purpose | Failure mode | Mitigation |
|---|---|---|---|---|
| <system/tool> | inbound/outbound | <purpose> | <failure mode> | <mitigation> |

## 10. Key design decisions and tradeoffs
| Decision | Options considered | Chosen | Rationale | Consequences |
|---|---|---|---|---|
| <decision> | <options> | <choice> | <why> | <tradeoffs> |

## 11. Operational assumptions
- <deployment/runtime assumption>
- <observability/logging assumption>
- <security/secrets assumption>

## 12. Open questions
- <question>
- <question>
