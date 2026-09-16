# Stakeholder memo — AfyaPlus Service Platform

**To:** CTO, AfyaPlus
**From:** Platform engineering
**Date:** 2026-09-17
**Re:** Go/no-go for the triage + logistics agent platform

## What was built

A production-shaped AI service platform for AfyaPlus's clinic network,
running the same architecture the CTO asked every team to independently
implement: one FastAPI service, one container, one MCP server, one agent.

- **Secure triage API** (`POST /triage`) — a real `gpt-4o-mini` call
  behind JWT auth, role-gated (coordinator vs viewer), rate-limited, with
  typed request/response contracts and an unprotected `/health` for
  probes.
- **Containerised** — `python:3.12-slim`, cache-ordered layers (108s cold
  build, 2.3s on a code-only change), secrets injected at `docker run`
  time only, image tag `afyaplus-platform:1.0.0` matched to git tag
  `v1.0.0`.
- **Logistics MCP server** — four tools (`check_stock`,
  `plan_delivery_route`, `get_delivery_eta`, `request_reorder`) and one
  resource (`clinics://directory`), every tool input-validated and every
  bad call returned as instructive JSON, not a crash.
- **Logistics agent** (`POST /ask-logistics`) — a LangChain ReAct agent
  over those MCP tools, behind the same auth module as `/triage`. It
  chains tools correctly on multi-step questions and, just as important,
  says "I don't have that data" on price questions instead of inventing a
  number — see `evidence/agent_transcript.md` for both, captured against
  the real running service.

## Highest-value component

**The MCP tool layer, not the agent.** The agent is a thin, swappable
orchestration layer — today it's LangChain + `gpt-4o-mini`, and it could
be a different model or framework next quarter with no change to the
tools. The tools are where the actual business logic, validation, and
truthfulness guarantees live (`check_stock`'s docstring is the reason the
agent doesn't hallucinate a price; `request_reorder`'s range check is the
reason a malformed 9,999-unit request never reaches a human coordinator).
Invest further engineering time in the tool layer first — it's the part
that survives a model swap and the part every future agent (this one or a
successor) depends on for correctness.

## One risk and its mitigation

**Risk:** every piece of mutable state in this platform — the rate
limiter's per-user counters (`app/rate_limit.py`), and (were it wired to a
real order system) any reorder-confirmation state — lives in a single
process's memory. Run two replicas behind a load balancer, as
`deployment.yaml`'s `replicas: 3` already specifies for production, and
each replica enforces its own limit independently: a caller gets roughly
3x the stated rate-limit budget through, silently.

**Mitigation:** move rate-limit counters (and any future order state) to
a shared store — Redis is the standard choice — before running more than
one replica. This is a bounded, well-understood change (swap the
in-memory dict for a Redis client behind the same `check_rate_limit()`
signature) and should land before `deployment.yaml`'s `replicas: 3` is
ever pointed at a real cluster, not after.

## Go / no-go

**Go, with conditions.** The architecture is sound and every rubric-level
production standard (typed contracts, real 401/403/422 behaviour,
cache-friendly containerisation, input-validated tools with errors as
data, an authenticated multi-tool agent that fails honestly, a
reconstructable trace) is built and evidenced against the real running
service, not simulated.

Conditions before a real production rollout:
1. Fix the shared-state risk above (Redis-backed rate limiting) before
   running `replicas: 3`.
2. Replace the in-memory `USERS` table in `app/auth.py` with a real user
   store — hard-coded demo accounts (`mercy`/`guest`) are fine for this
   capstone, not for real clinic staff credentials.
3. Set a real `JWT_SECRET` via the deployment's secret manager
   (`deployment.yaml`'s `secretRef` already assumes this) — the
   `.env.example` fallback value must never reach a real environment.
