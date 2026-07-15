# Agent Architecture & Workflow

This document defines the three agent modes, how they interact, when sub-agents are spawned, and the complete flow from idea to implementation.

> **Harness note:** The diagrams below show the Pi roster for sequential execution. OpenCode
> also provides a separate role-based team pipeline after approach review. Category-backed
> team members run through Sisyphus-Junior with category-specific models; direct team members
> may use `sisyphus`, `atlas`, `sisyphus-junior`, or `hephaestus`. See
> [Team-Mode Execution](team-mode-execution.md) and [Skill Rendering](skill-rendering.md).

---

## System Overview

```mermaid
graph TB
    subgraph "Human Interaction Modes (Presets)"
        D["/preset discovery<br/>Frontier reasoning<br/><i>Opus • High Thinking</i>"]
        DE["/preset design<br/>Frontier reasoning<br/><i>Opus • High Thinking</i>"]
        EX["/preset execute<br/>Frontier reasoning<br/><i>Opus • High Thinking</i>"]
    end

    subgraph "Frontier Sub-Agents"
        PL["planner<br/><i>Frontier reasoning</i>"]
        PLR["plan-reviewer<br/><i>Frontier reasoning</i>"]
        CR["code-reviewer<br/><i>Frontier code</i>"]
        OR["oracle<br/><i>Frontier highest</i>"]
    end

    subgraph "Execution Sub-Agents"
        W["worker<br/><i>Execution</i>"]
        UW["ui-worker<br/><i>Execution UI</i>"]
        RE["researcher<br/><i>Execution</i>"]
        VI["vision<br/><i>Visual</i>"]
    end

    D -->|"produces brief.md"| DE
    DE -->|"spawns research"| W
    DE -->|"spawns web research"| RE
    DE -->|"produces approach.md (standard)"| EX
    DE -->|"produces epic.md (epic decomposition)"| EX
    EX -->|"plan creation"| PL
    EX -->|"plan review"| PLR
    EX -->|"code review"| CR
    EX -->|"implementation"| W
    EX -->|"UI implementation"| UW

    style D fill:#e8f4fd,stroke:#2196F3
    style DE fill:#e8f4fd,stroke:#2196F3
    style EX fill:#fff3e0,stroke:#FF9800
    style PL fill:#f3e5f5,stroke:#9C27B0
    style PLR fill:#f3e5f5,stroke:#9C27B0
    style CR fill:#fce4ec,stroke:#E91E63
    style OR fill:#f3e5f5,stroke:#9C27B0
    style W fill:#e8f5e9,stroke:#4CAF50
    style UW fill:#e8f5e9,stroke:#4CAF50
    style RE fill:#e8f5e9,stroke:#4CAF50
    style VI fill:#e0f7fa,stroke:#00BCD4
```

---

## Complete Process Flow

```mermaid
flowchart TD
    %% Discovery Phase
    subgraph DISCOVERY["🔍 DISCOVERY — /preset discovery"]
        direction TB
        D1[Human has idea/problem]
        D2[Discovery Agent challenges assumptions<br/>surfaces tradeoffs, identifies blind spots]
        D3[Determine plan level<br/>simple / standard / epic]
        D4["✅ Produce brief.md"]
        D1 --> D2 --> D3 --> D4
    end

    %% Design Phase
    subgraph DESIGN["🎨 DESIGN — /preset design"]
        direction TB
        DE1[Read brief.md]
        DE2[Propose research topics → human confirms]
        DE3["Spawn sub-agents for research<br/><b>codebase:</b> worker + research skill<br/><b>web:</b> researcher<br/><b>visual:</b> vision<br/><b>output:</b> findings/*.md"]
        DE4[Synthesize findings]
        DE5[Present design options + tradeoffs<br/>→ human decides]
        DE6["✅ Produce approach.md"]
        DE7["✅ For epics: produce epic.md\n(workstreams + child plans)"]
        DE1 --> DE2 --> DE3 --> DE4 --> DE5 --> DE6 --> DE7
    end

    %% Sequential Execution Phase
    subgraph EXECUTION["⚡ SEQUENTIAL EXECUTION — /preset execute"]
        direction TB

        %% Plan Creation
        E1["<b>Create Plan</b><br/>agent: planner<br/>skill: create-plan<br/>output: plan.md"]

        %% Plan Review Loop
        E2["<b>Review Plan</b><br/>agent: plan-reviewer<br/>skill: review-plan<br/>output: plan_review.md"]
        E2check{COMPLETE?}
        E2 --> E2check
        E2check -->|No, max 5x| E2

        %% Approval Gate
        E3{"🛑 APPROVAL GATE<br/>(skip if auto-continue)"}

        %% Worklog
        E4["<b>Create Worklog</b><br/>agent: worker<br/>skill: create-worklog<br/>output: worklog.md"]

        %% Task Execution Loop
        E5["<b>Execute Task N</b><br/>agent: worker or ui-worker<br/>skill: execute-task<br/>reads: worklog.md"]
        E5review["<b>Per-Task Review</b> (optional)<br/>agent: code-reviewer<br/>skill: review-code"]
        E5fix["<b>Fix Issues</b><br/>agent: worker or ui-worker<br/>max 2x per task"]
        E5check{More tasks?}

        E5 --> E5review
        E5review -->|issues| E5fix --> E5review
        E5review -->|clean| E5check
        E5check -->|Yes| E5

        %% Final Code Review
        E6["<b>Final Code Review</b><br/>agent: code-reviewer<br/>skill: review-code<br/>scope: full branch diff"]
        E6fix["<b>Fix Issues</b><br/>agent: worker or ui-worker"]
        E6check{COMPLETE?}
        E6 --> E6check
        E6check -->|No, max 5x| E6fix --> E6

        %% Done
        E7["✅ Complete<br/>state.json → complete"]

        E1 --> E2
        E2check -->|Yes| E3
        E3 -->|Approved| E4
        E4 --> E5
        E5check -->|No| E6
        E6check -->|Yes| E7
    end

    subgraph TEAM["⚡ TEAM EXECUTION — OpenCode"]
        direction TB
        T1[Create team_plan.md from reviewed approach]
        T2[Review team_plan.md]
        T3[Contracts + fast implementers]
        T4[Live review + remediation + rescue]
        T5[Lead gates + integration commits]
        T6[Close team + fresh strong final review]
        T1 --> T2 --> T3 --> T4 --> T5 --> T6
    end

    %% Connections between phases
    DISCOVERY -->|"brief.md written<br/>Human starts Design"| DESIGN
    DESIGN -->|"standard: approach.md written<br/>Human switches to Execute"| EXECUTION
    DESIGN -->|"team mode selected after reviewed approach"| TEAM
    DESIGN -->|"epic: approach.md + epic.md + epic_review.md written<br/>Human switches to Execute child plans"| EXECUTION
```

---

## Sub-Agent Call Reference

```mermaid
graph LR
    subgraph "Execution Orchestrator Calls"
        direction TB

        C1["subagent(agent: planner,<br/>skill: create-plan)"]
        C2["subagent(agent: plan-reviewer,<br/>skill: review-plan)"]
        C3["subagent(agent: worker,<br/>skill: create-worklog)"]
        C4["subagent(agent: worker/ui-worker,<br/>skill: execute-task)"]
        C5["subagent(agent: code-reviewer,<br/>skill: review-code)"]
        C6["subagent(agent: worker/ui-worker,<br/>no skill — fix mode)"]
    end

    subgraph "Design Agent Calls"
        direction TB
        C7["subagent(agent: worker,<br/>skill: research)"]
        C8["subagent(agent: researcher)"]
        C9["subagent(agent: vision)"]
    end

    C1 -->|produces| P1[plan.md]
    C2 -->|produces| P2[plan_review.md]
    C3 -->|produces| P3[worklog.md]
    C4 -->|updates| P4[worklog.md + code + commit]
    C5 -->|produces| P5[code_review.md]
    C6 -->|updates| P6[code + commit]
    C7 -->|produces| P7["findings/*.md"]
    C8 -->|produces| P8[research.md]
    C9 -->|produces| P9[visual analysis]

    style C1 fill:#f3e5f5,stroke:#9C27B0
    style C2 fill:#f3e5f5,stroke:#9C27B0
    style C3 fill:#e8f5e9,stroke:#4CAF50
    style C4 fill:#e8f5e9,stroke:#4CAF50
    style C5 fill:#fce4ec,stroke:#E91E63
    style C6 fill:#e8f5e9,stroke:#4CAF50
    style C7 fill:#e8f5e9,stroke:#4CAF50
    style C8 fill:#e8f5e9,stroke:#4CAF50
    style C9 fill:#e0f7fa,stroke:#00BCD4
```

---

## Artifact Flow

```mermaid
graph LR
    subgraph "Discovery"
        B[brief.md]
    end

    subgraph "Design"
        F["findings/<br/>current_state.md<br/>code_structure.md<br/>dependencies.md"]
        A[approach.md]
    end

    subgraph "Sequential Execution"
        P[plan.md]
        PR2[plan_review.md]
        W[worklog.md]
        CR[code_review.md]
        S[state.json]
    end

    subgraph "Team Execution"
        TP[team_plan.md]
        TPR[team_plan_review.md]
        TW[team-worklog.md]
    end

    subgraph "Implementation"
        CODE[Source code + tests]
        COMMITS[Git commits]
    end

    B --> F
    B --> A
    F --> A
    A --> P
    A --> TP
    TP --> TPR
    TPR --> TW
    TW --> CODE
    P --> PR2
    PR2 -->|fixes| P
    P --> W
    W --> CODE
    CODE --> COMMITS
    CODE --> CR
    CR -->|findings| CODE

    style B fill:#e8f4fd
    style A fill:#e8f4fd
    style P fill:#fff3e0
    style CODE fill:#e8f5e9
```

---

## Model & Cost Allocation

```mermaid
pie title Token Cost Distribution (typical standard plan)
    "Implementation (worker/ui-worker)" : 40
    "Code Review (code-reviewer)" : 20
    "Plan Creation (planner)" : 15
    "Plan Review (plan-reviewer)" : 10
    "Research (worker/researcher)" : 10
    "Orchestration (execute preset)" : 5
```

| Agent | Model Tier | Role | Cost Tier |
|-------|-----------|------|-----------|
| Discovery preset | Frontier (reasoning) | Interactive challenge mode | High (but brief sessions) |
| Design preset | Frontier (reasoning) | Interactive + research delegation | High (medium sessions) |
| Execute preset | Frontier (reasoning) | Orchestration (no implementation) | High (low token use) |
| planner | Frontier (reasoning) | Plan creation | High (one-shot) |
| plan-reviewer | Frontier (reasoning) | Plan quality gate | High (moderate, iterative) |
| code-reviewer | Frontier (code) | Code quality gate | High (moderate, iterative) |
| worker | Execution | Backend implementation | Medium (highest volume) |
| ui-worker | Execution (UI) | Frontend implementation | Medium (high volume for UI work) |
| researcher | Execution | Web/external research | Medium (low volume) |
| vision | Visual | Screenshot/mockup analysis | Medium (low volume) |
| oracle | Frontier (highest) | Read-only second opinion | High (rare, deep) |

---

## Three Agent Modes — Comparison

| | Discovery | Design | Execution |
|---|---|---|---|
| **Invocation** | `/preset discovery` | `/preset design` | `/preset execute` |
| **Human interaction** | High — dialogue | Medium — approve decisions | Low — approval gate only |
| **Personality** | Socratic, challenging | Collaborative, structured | Autonomous, systematic |
| **Spawns sub-agents?** | No | Yes (worker, researcher, vision) | Yes (all agents) |
| **Produces** | brief.md | standard: findings/ + approach.md<br/>epic: findings/ + approach.md + epic.md + epic_review.md | plan → code → review |
| **Model** | Frontier (reasoning) | Frontier (reasoning) | Frontier (reasoning) + delegates to all tiers |
| **Tools** | read, bash | read, bash, edit, write, subagent, web_search | read, bash, edit, write, subagent |
| **Duration** | Minutes | 10-30 min | 30 min - hours |

---

## Handoff Between Modes

The modes are explicitly separated. Each produces artifacts that serve as input for the next:

```mermaid
sequenceDiagram
    participant H as Human
    participant D as Discovery<br/>(preset)
    participant DE as Design<br/>(preset)
    participant EX as Execute<br/>(preset)
    participant PL as planner
    participant PLR as plan-reviewer
    participant CR as code-reviewer
    participant W as worker
    participant UW as ui-worker

    H->>D: "I want to add notifications..."
    D->>H: Challenges, questions, tradeoffs
    H->>D: Answers, decisions
    D->>H: Here's your brief.md ✅

    H->>DE: "Design this. Here's the brief."
    DE->>W: research(current_state)
    W-->>DE: findings/current_state.md
    DE->>W: research(dependencies)
    W-->>DE: findings/dependencies.md
    DE->>H: "Three options. Tradeoffs are..."
    H->>DE: "Go with Option B"
    DE->>H: approach.md written ✅

    H->>EX: "Execute. Auto-continue."
    EX->>PL: create-plan
    PL-->>EX: plan.md ✅
    EX->>PLR: review-plan
    PLR-->>EX: NEEDS_ANOTHER_PASS
    EX->>PLR: review-plan
    PLR-->>EX: COMPLETE ✅
    EX->>W: create-worklog
    W-->>EX: worklog.md ✅

    loop Each Task (backend)
        EX->>W: execute-task
        W-->>EX: task done ✅
        EX->>CR: review-code (task diff)
        CR-->>EX: clean ✅
    end

    loop Each Task (frontend)
        EX->>UW: execute-task
        UW-->>EX: task done ✅
        EX->>CR: review-code (task diff)
        CR-->>EX: clean ✅
    end

    EX->>CR: review-code (full branch)
    CR-->>EX: COMPLETE ✅
    EX->>H: Implementation complete ✅
```
