# AfyaPlus Service Platform

A production-shaped AI service platform for AfyaPlus's clinic network:
a JWT-secured FastAPI triage service wrapping a real `gpt-4o-mini` call,
containerised on a slim base image, an MCP server exposing clinic
logistics tools, and a LangChain agent over those tools behind its own
authenticated endpoint. Built for the Week 6 capstone, reusing the exact
architecture from this cohort's Week 6 Monday/Tuesday/Thursday labs
(`../afyaplus/week6_{monday,tuesday,thursday}`), re-implemented from
scratch in this standalone repo.

No fallback paths were needed: Docker Desktop and a real `OPENAI_API_KEY`
were both available, so every piece of evidence in `evidence/` is a real
run against the real running service — no stub-model or Inspector-only
substitutions.

## Architecture

```
                    JWT (app/auth.py)
                          |
   client --> FastAPI (app/main.py) ------------------------.
                  |            |                             |
             GET /health   POST /token   POST /triage   POST /ask-logistics
             (unprotected)  (login)      (coordinator     (any authenticated
                                          role only,        user; LangChain
                                          real gpt-4o-mini   ReAct agent)
                                          call)                   |
                                                                   v
                                          MultiServerMCPClient (stdio)
                                                                   |
                                                                   v
                                          mcp_server/logistics_mcp.py
                                          4 tools + 1 resource over
                                          mcp_server/clinics.json
```

## Repo layout

```
app/                  FastAPI service (Deliverable 1) + agent endpoint (Deliverable 4)
  auth.py               JWT login, current_user dependency, require_role
  rate_limit.py          per-user request budget
  models.py               typed Pydantic request/response models
  triage_model.py           real gpt-4o-mini call behind POST /triage
  agent_service.py           LangChain ReAct agent over the MCP tools
  main.py                      routes: /health /token /triage /ask-logistics
mcp_server/            MCP server (Deliverable 3)
  logistics_mcp.py       4 tools + 1 resource, input-checked, errors as data
  clinics.json             the dataset every tool reads
tests/                 offline pytest suite (23 tests, no network calls)
evidence/              captured real-run evidence for Deliverables 1/2/3/4
docs/                  engineering report pieces (Deliverable 5)
Dockerfile             Deliverable 2
deployment.yaml        read-only k8s manifest (no cluster; see brief's own fallback note)
CONTRIBUTING.md        gitflow branch policy + semver release policy
```

## Run it locally

```
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt
cp .env.example .env   # fill in JWT_SECRET and OPENAI_API_KEY
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

```
pytest tests/ -q          # 23 tests, offline, no billed calls
```

## Run it containerised

```
docker build -t afyaplus-platform:1.0.0 .
docker run -d -p 8000:8000 --env-file .env afyaplus-platform:1.0.0
curl http://127.0.0.1:8000/health
```

See `evidence/docker_build.md` for the full build/run/size transcript.

## Deliverable evidence index

| Deliverable | Code | Evidence |
|---|---|---|
| 1. Secure FastAPI service | `app/auth.py`, `app/models.py`, `app/triage_model.py`, `app/main.py` | `evidence/curl_transcript.md` (real 200/401/403/422), `tests/test_api.py` (8 offline tests) |
| 2. Containerisation | `Dockerfile`, `.dockerignore`, `requirements-api.txt` | `evidence/docker_build.md` (real build, cache proof, size, runtime secret injection) |
| 3. MCP server | `mcp_server/logistics_mcp.py` | `evidence/mcp_test_output.md` (12 tests incl. deliberate invalid calls), `logs/mcp.log` |
| 4. Agent integration | `app/agent_service.py`, `POST /ask-logistics` in `app/main.py` | `evidence/agent_transcript.md` (real multi-tool answer + real honest refusal), `tests/test_agent_endpoint.py` |
| 5. Engineering report | — | `CONTRIBUTING.md`, `docs/MERGE_CONFLICT_LOG.md`, `docs/TRACE_RECONSTRUCTION.md`, `docs/STAKEHOLDER_MEMO.md` |

## Cost actuals vs. budget

The brief budgets ~$0.10-0.40 total in real `gpt-4o-mini` calls across the
capstone. This repo's evidence was captured with:

- Deliverable 1: 2 real triage calls (`evidence/curl_transcript.md` #8,
  plus one more captured for the containerised run in
  `evidence/docker_build.md`) — within the $0.01-0.05 / 5-15 calls band.
- Deliverable 4: 5 real chat calls total across the two agent questions
  (4 for the multi-tool question's think/act/observe loop, 1 for the
  honest-refusal question) — within the $0.05-0.25 / 10-40 calls band.
- No further live calls were made once transcripts were captured; the
  offline `pytest` suite (23 tests) is what's re-run for regression
  checking, and it never touches the network.

## Development workflow

Gitflow: `main` (releasable, tagged) <- `develop` (integration) <-
`feature/*` branches, merged with `--no-ff`. See `CONTRIBUTING.md` for the
full branch/version/release policy, and `docs/MERGE_CONFLICT_LOG.md` for a
real conflict hit and resolved during this build.

## Verify the release

```
git show v1.0.0 --stat
docker images afyaplus-platform:1.0.0
```

The image tag and the git tag describe the same commit — see
`CONTRIBUTING.md`'s release policy.
