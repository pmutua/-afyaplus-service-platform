# Architecture

This is the detailed companion to the README's architecture overview: the
same system broken into its request-lifecycle sequences, plus the release
flow. Every diagram below matches a real, captured run — see the linked
evidence for the exact bytes each diagram summarizes.

## System architecture

```mermaid
flowchart TD
    Client(["Client / curl"])

    subgraph API["FastAPI app — app/main.py (afyaplus-platform:1.0.0)"]
        Health["GET /health<br/>unprotected"]
        Token["POST /token<br/>login"]
        Triage["POST /triage<br/>coordinator role only"]
        Ask["POST /ask-logistics<br/>any authenticated user"]
    end

    Auth["app/auth.py<br/>issue JWT · verify JWT · role check"]
    RateLimit["app/rate_limit.py<br/>per-user request budget"]
    TriageModel["app/triage_model.py"]
    AgentService["app/agent_service.py<br/>LangGraph ReAct agent"]
    OpenAI[("OpenAI gpt-4o-mini")]

    subgraph MCP["mcp_server/logistics_mcp.py — spawned per request over stdio"]
        Tools["check_stock · plan_delivery_route<br/>get_delivery_eta · request_reorder"]
        Resource["clinics://directory (resource)"]
    end
    Clinics[("mcp_server/clinics.json")]

    Client --> Health
    Client --> Token --> Auth
    Client --> Triage --> Auth
    Client --> Ask --> Auth

    Triage --> RateLimit --> TriageModel --> OpenAI
    Ask --> AgentService --> OpenAI
    AgentService <-->|stdio| MCP
    Tools --> Clinics
    Resource --> Clinics
```

**Component walkthrough:**

- **`app/main.py`** — the single FastAPI app. Four routes, one import of
  `app/auth.py` for every protected one, so authentication is enforced
  identically everywhere instead of re-implemented per route.
- **`app/auth.py`** — issues and verifies JWTs (`HS256`, 30-minute
  lifetime) and answers two separate questions as two separate dependency
  layers: `current_user()` (who is calling — 401 if unverifiable) and
  `require_role()` (what that identity may do — 403 if the wrong role).
- **`app/rate_limit.py`** — an in-memory per-user request budget in front
  of `/triage`, the one route that spends real money per call.
- **`app/triage_model.py`** — the single real `gpt-4o-mini` call behind
  `/triage`; a `RuntimeError` from the provider becomes a 503 the caller
  can retry, never a raw 500.
- **`app/agent_service.py`** — builds a fresh LangGraph ReAct agent per
  request: a `ChatOpenAI` model plus the MCP tools fetched through
  `MultiServerMCPClient`, which spawns `mcp_server/logistics_mcp.py` as a
  stdio child process for the lifetime of that one request.
- **`mcp_server/logistics_mcp.py`** — four tools and one resource, each
  input-validated against `clinics.json`, each bad call returned as a JSON
  `"error"` key (data an LLM can read and recover from) rather than a raised
  exception.

## Request lifecycle: the auth ladder (`/triage`)

The 401 → 403 → 200 progression exactly as captured in
[`evidence/curl_transcript.md`](../evidence/curl_transcript.md).

```mermaid
sequenceDiagram
    participant C as Client
    participant API as FastAPI (/triage)
    participant Auth as app/auth.py
    participant RL as rate_limit.py
    participant Model as triage_model.py
    participant AI as OpenAI gpt-4o-mini

    C->>API: POST /triage (no Authorization header)
    API-->>C: 401 Not authenticated

    C->>API: POST /token {guest, lookaround}
    API->>Auth: check_password + create_token
    Auth-->>C: 200 {access_token}

    C->>API: POST /triage (Bearer guest token)
    API->>Auth: current_user() + require_role("coordinator")
    Auth-->>API: role=viewer != coordinator
    API-->>C: 403 Your role may not use this endpoint

    C->>API: POST /token {mercy, logistics2026}
    API-->>C: 200 {access_token}

    C->>API: POST /triage (Bearer mercy token)
    API->>Auth: current_user() + require_role("coordinator")
    Auth-->>API: role=coordinator OK
    API->>RL: check_rate_limit("mercy")
    API->>Model: triage_model(patient_message)
    Model->>AI: chat.completions.create(...)
    AI-->>Model: urgency + advice
    Model-->>API: result
    API-->>C: 200 {urgency, advice, handled_for, model_used}
```

## Request lifecycle: the multi-tool agent (`/ask-logistics`)

Trace `775c6e6e` — the same request reconstructed with real timestamps in
[`docs/TRACE_RECONSTRUCTION.md`](TRACE_RECONSTRUCTION.md), shown here as a
sequence diagram.

```mermaid
sequenceDiagram
    participant C as Client (mercy)
    participant API as FastAPI (/ask-logistics)
    participant Agent as agent_service.py (ReAct loop)
    participant AI as OpenAI gpt-4o-mini
    participant MCP as logistics_mcp.py (stdio)

    C->>API: POST /ask-logistics (Bearer mercy token)<br/>"Which clinics need a reorder + ETA?"
    API->>Agent: run_logistics_agent(question, trace_id=775c6e6e)
    Agent->>MCP: spawn subprocess, list_tools()
    Agent->>AI: call 1 — decide next action
    AI-->>Agent: call check_stock(amoxicillin)
    Agent->>MCP: check_stock(amoxicillin)
    MCP-->>Agent: C02=8 units, C04=0 units (below threshold)
    Agent->>AI: call 2 — read result, decide next action
    AI-->>Agent: call get_delivery_eta(C01, C02)
    Agent->>MCP: get_delivery_eta(C01, C02)
    MCP-->>Agent: 16.5 km / 25 min
    Agent->>AI: call 3 — decide next action
    AI-->>Agent: call get_delivery_eta(C01, C04)
    Agent->>MCP: get_delivery_eta(C01, C04)
    MCP-->>Agent: 59.3 km / 89 min
    Agent->>AI: call 4 — synthesise final answer
    AI-->>Agent: final answer text
    Agent-->>API: answer
    API-->>C: 200 {question, answer, trace_id, asked_by}
```

Four LLM round-trips over ~11.4 seconds — matches
`logs/app.log`/`logs/mcp.log` exactly (see the trace doc for the raw log
lines). The honest-failure case (a price question) stops after `list_tools`
with zero `CallToolRequest` lines — the model looked at what was available
and correctly declined instead of guessing.

## Containerisation and deployment shape

```mermaid
flowchart LR
    Dockerfile["Dockerfile<br/>python:3.12-slim base"] -->|docker build| Image[("afyaplus-platform:1.0.0")]
    Image -->|docker run --env-file .env| Container1["Container"]
    Image -.->|deployment.yaml, read-only, no live cluster| Deploy

    subgraph Deploy["k8s Deployment (replicas: 3)"]
        Pod1["Pod 1"]
        Pod2["Pod 2"]
        Pod3["Pod 3"]
    end
    Secret[("Secret: JWT_SECRET, OPENAI_API_KEY<br/>injected via secretRef, never baked in")] --> Deploy
```

`requirements-api.txt` is copied and installed before `app/` and
`mcp_server/` so an application-code edit only invalidates the cheap `COPY`
layers, not the ~100s `pip install` layer (proven in
[`evidence/docker_build.md`](../evidence/docker_build.md): 108s cold build,
2.3s on a code-only rebuild). `deployment.yaml` is read-only per the
brief's own fallback (no cluster this week) — its `replicas: 3` is exactly
why `app/rate_limit.py`'s in-memory counters are flagged as a risk in
[`docs/STAKEHOLDER_MEMO.md`](STAKEHOLDER_MEMO.md): three replicas each
enforcing their own limit independently lets a caller through roughly 3x
the stated budget until that state moves to a shared store.

## Release flow (gitflow)

```mermaid
gitGraph
   commit id: "129bafb-deliverable-1"
   branch develop
   checkout develop
   branch feature/mcp-server
   commit id: "d3-mcp-tools"
   checkout develop
   merge feature/mcp-server
   branch feature/agent-integration
   commit id: "d4-agent"
   checkout develop
   merge feature/agent-integration
   branch feature/containerisation
   commit id: "d2-docker"
   checkout develop
   merge feature/containerisation
   branch feature/rate-limit-tuning
   commit id: "raise-cap-to-10"
   checkout develop
   branch feature/stricter-window
   commit id: "tighten-window-to-30s"
   checkout develop
   merge feature/rate-limit-tuning
   merge feature/stricter-window tag: "CONFLICT resolved"
   branch feature/engineering-report
   commit id: "d5-report"
   checkout develop
   merge feature/engineering-report
   branch feature/readme
   commit id: "readme"
   checkout develop
   merge feature/readme
   checkout main
   merge develop tag: "v1.0.0"
```

Every `feature/*` branch is one deliverable (or one sub-change), branched
from `develop`, merged back with `--no-ff` so its own history stays
visible in `git log --graph` instead of being squashed away — see
[`d5-01-git-log-graph-gitflow.png`](../screenshots/d5-01-git-log-graph-gitflow.png).
`develop` is merged into `main` and tagged only once every deliverable is
in and the full suite passes. See
[`CONTRIBUTING.md`](../CONTRIBUTING.md) for the branch/version/release
rules and [`docs/MERGE_CONFLICT_LOG.md`](MERGE_CONFLICT_LOG.md) for the one
real conflict this history contains, resolved in full.
