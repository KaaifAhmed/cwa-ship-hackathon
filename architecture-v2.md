# System Architecture

**Project:** CWA Ship Karachi 2026
**Status:** Pre-hackathon baseline — domain-agnostic, filled in at kickoff

## Diagram

```
                ┌─────────────┐
                │   React     │
                │  Frontend   │
                └──────┬──────┘
                       │  HTTPS + CORS
                ┌──────▼──────┐
                │ Main Django │
                │   Service   │
                └──┬───────┬──┘
                   │       │
                   ▼       ▼
      ┌───────────────┐ ┌───────────────┐
      │   AI Queue    │ │  Tasks Queue  │      (Redis)
      └───────┬───────┘ └───────┬───────┘
              │                 │
       ┌──────▼──────┐   ┌──────▼──────┐
       │ AI Workers  │   │ BG Workers  │
       │ (x3, async) │   │    (TBD)    │
       └──────┬──────┘   └──────┬──────┘
              │                 │
              └────────┬────────┘
                       │
                ┌──────▼──────┐
                │ Postgres DB │
                │    (TBD)    │
                └─────────────┘
```

## Components

**Frontend** — React (Vite build), served as static files by a lightweight static server (e.g. `serve`), its own container. Talks directly to Main Service over HTTPS — no reverse proxy. Client-side routing (React Router) is fully separate from the backend's API routes.

**Main Service** — Django. Merges Auth and Core Domain into one project (`users` app + `core` app), one shared Postgres DB. Single point of contact for the frontend: exposes `/auth/*` and `/api/*`, enqueues jobs to Redis, exposes `GET /api/jobs/{job_id}` for polling status/results. CORS enabled (`django-cors-headers`) for the frontend's origin.

**AI Worker Pool** — async Python, no web framework (never receives HTTP — only consumes `ai_queue`). Orchestration via LangGraph/LangChain, model calls via LiteLLM (see LLMOps section below for the full stack). 3 replicas. Guardrails: per-replica concurrency cap, per-job timeout, one retry with backoff on transient failures.

**Background Worker** — same pattern, consumes `tasks_queue` for non-AI async work (e.g. PDF generation). Task handlers defined at kickoff once the domain is known.

**Redis** — two plain lists, `ai_queue` and `tasks_queue` (`RPUSH`/`BLPOP`), plus worker heartbeat keys for liveness. No Celery, no channel layer.

**Postgres** — one shared database. Domain schema (tables, fields) defined at kickoff — not fixed in advance. Exception: AI config tables (prompts, model-tier mapping, fallback order — see Dynamic Configuration below) are decided now, owned by Main Service, and read directly by the AI Worker Pool.

## Communication

- Frontend ↔ Main Service: REST/JSON over HTTPS, CORS-enabled.
- Main Service → workers: Redis queues, not REST — avoids blocking a request thread on slow work.
- Job status: frontend polls `GET /api/jobs/{job_id}`.
- **Optional, not mandated:** Django Channels + WebSockets could replace polling with push-based updates if a specific need justifies it later. Not part of the baseline.

## Contract-First Workflow

1. Lock endpoint contracts (request/response shape, error cases) once the theme is known.
2. Build against the contract in parallel.
3. Integration is wiring real calls, not discovering shapes.

## Deployment

Single VM, `docker-compose up -d` — one command for every container (frontend, Main Service, AI Worker Pool ×3, Background Worker, Redis, Postgres).

## Production-Readiness Checklist

- [ ] Health/liveness signal per component (Main Service `/health`; workers via Redis heartbeat)
- [ ] CI: lint + tests on push
- [ ] Structured logging
- [ ] `.env`-based config, no hardcoded secrets
- [ ] API docs auto-served (DRF + `drf-spectacular`)
- [ ] One-command local spin-up and deploy

## AI Service Production-Readiness (LLMOps)

**Orchestration:** LangGraph (built on LangChain) is the default for multi-step/agentic work — state graphs handle cycles and multi-agent coordination directly. Adopted as baseline, not just an escape hatch: the code is AI-agent-authored, not hand-typed, so the framework's learning curve costs far less here than it would for a human team, and LangGraph's cycle/multi-agent support is genuinely hard to replicate by hand in the time available.

**Model access:** LiteLLM is the calling layer underneath, wired into LangChain via `ChatLiteLLMRouter` (`langchain-litellm` package) — LangGraph nodes use it as a normal LangChain chat model, while LiteLLM's fallback chains and cost tracking run underneath.

**Model tiers + fallback**, as a LiteLLM `Router` config: `fast` / `smart` tiers, each mapped to a primary model with an ordered fallback list. Swapping a rate-limited model mid-demo is a config change, not a code change.

**Prompts:** LangChain `PromptTemplate`s, versioned as named files (e.g. `prompts/v1_summarize.py`). No separate templating library — LangChain covers it.

**Structured output:** LangChain's native `.with_structured_output(PydanticModel)` handles validation and parsing directly — a dedicated library (Instructor) would now be redundant, dropped.

**Tool calling:** LangChain's tool interface (`@tool` decorator + `.bind_tools()`) — native provider function-calling underneath, LangChain's parsing on top instead of a hand-rolled loop.

**RAG:** pgvector remains the vector store (already in Postgres); use LangChain's `PGVector` retriever so retrieval plugs directly into a graph node — consistent now that the rest of the pipeline is LangChain-native.

**Streaming:** flagged as a probable stretch feature, not baseline. Channels/WebSockets (or SSE) to be decided once the rest of the system is stable and if time allows — genuinely differentiating if it lands, not required for a working demo.

**Guardrails (unchanged from earlier):** per-replica concurrency cap, per-job timeout, one retry with backoff, full call telemetry in Postgres (`prompt_version`, `model`, `tokens`, `latency_ms`, `cost_estimate`).

## Dynamic Configuration

Made dynamic because it's cheap and high-value — not "everything," scoped deliberately:

- **Prompt text + version**, **model tier → provider/model mapping**, **fallback chain order**, **per-prompt temperature/max_tokens** — stored as DB-backed config models owned by Main Service, edited via **Django Admin** (free CRUD UI, no custom dashboard needed).
- AI Worker Pool reads current config directly from Postgres at call time — a fresh query per call is negligible overhead at this scale, so no caching/invalidation layer is needed.
- **Deliberately NOT dynamic:** the orchestration graph structure, tool functions, and RAG chunking logic stay in code. Making those admin-editable would mean building a workflow editor — a different, much larger project than a hackathon can absorb. Config values are dynamic; orchestration logic isn't.

## Repository Structure

```
repo/
├── docker-compose.yml
├── frontend/
│   ├── Dockerfile
│   └── src/
├── main-service/
│   ├── Dockerfile
│   ├── manage.py
│   ├── users/
│   └── core/
├── ai-worker/
│   ├── Dockerfile
│   └── main.py
├── background-worker/
│   ├── Dockerfile
│   └── main.py
└── docs/
    ├── architecture.md
    ├── sdlc.md
    ├── coding-guidelines.md
    ├── testing-guidelines.md
    ├── documentation-guide.md
    ├── ux-guide.md
    └── ui-guide.md
```

## Ownership Map

| Component | Owner |
|---|---|
| Main Service (Auth + Core) | TBD |
| AI Worker Pool | TBD |
| Background Worker | TBD |
| Frontend | TBD |

## Hackathon-Day Timeline

| Time | Phase | Duration |
|---|---|---|
| 9:30–10:00 | Discovery & SRS | 30 min |
| 10:00–10:30 | Solution Design | 30 min |
| 10:30–10:45 | Component Design | 15 min |
| 10:45–12:30 | Implementation | 105 min |
| 12:30–13:00 | Component Testing | 30 min |
| 13:00–14:00 | *Lunch* | — |
| 14:00–15:00 | Integration & System Testing | 60 min |
| 15:00–15:20 | Refinement | 20 min |
| 15:20–15:45 | Documentation | 25 min |
| 15:45–16:00 | Presentation & Submission | 15 min |
