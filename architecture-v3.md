# System Architecture

**Project:** CWA Ship Karachi 2026
**Status:** Pre-hackathon baseline — domain-agnostic, filled in at kickoff

## Diagram

```
                    ┌───────────────────┐
                    │   React Frontend  │
                    └─────────┬─────────┘
                              │ HTTPS + CORS
                              ▼
    ┌───────────────────────────────────────────────────┐
 ┌──│                   Main Service (Django)           │
 │  │   /auth/*   /api/*   /api/whatsapp/inbound        │◄──────────────┐
 │  └───────────────────┬───────────────────────────────┘               │
 │                      │ enqueues                                      │ inbound webhook
 │            ┌─────────┴─────────┐                                     │ (metadata only,
 │            ▼                   ▼                                     │  no file bytes)
 │    ┌───────────────┐   ┌───────────────┐                             │
 │    │   ai_queue    │   │  tasks_queue  │   Redis                     │
 │    └───────┬───────┘   └───────┬───────┘                             │
 │            ▼                   ▼                                     │
 │ ┌────────────────────┐ ┌─────────────────────┐                ┌──────────────────┐
 │ │  AI Worker Pool    │ │  Background Worker  │                │ WhatsApp Service │
 │ │  (×3, async)       │ │  (async, dispatches │                │(Express, prebuilt│
 │ │ LangGraph +        │ │   by job type via   │                │  unofficial lib) │
 │ │ LangChain + LiteLLM│ │   TASK_HANDLERS)    │                └────────┬─────────┘
 │ └────────────────────┘ └──────────┬──────────┘                         ▲
 │                                   │         direct HTTP (outbound send,│
 │                                   └────────────────────────────────────┘
 │                                             via shared helper module)           
 │            
 │ ┌───────────────────────────────────────────────────┐
 │ │                     Postgres                      │
 └►│     schema defined at kickoff — only Main Service │
   │             ever reads/writes to it               │
   └───────────────────────────────────────────────────┘
```

## Components

**Frontend** — React (Vite build), served as static files by a lightweight static server (e.g. `serve`), its own container. Talks directly to Main Service over HTTPS — no reverse proxy. Client-side routing (React Router) is fully separate from the backend's API routes.

**Main Service** — Django. Merges Auth and Core Domain into one project (`users` app + `core` app). The **only** component that touches Postgres — every other component that needs data goes through a Main Service endpoint, no exceptions. Exposes `/auth/*`, `/api/*`, enqueues jobs to Redis, exposes `GET /api/jobs/{job_id}` for polling, and `POST /api/whatsapp/inbound` for the WhatsApp webhook path. CORS enabled (`django-cors-headers`) for the frontend's origin. User model carries `phone_number` as a candidate key, so inbound WhatsApp messages can be resolved to a user. (Phone verification flagged as a possible addition, not committed — likely more complexity than the hackathon needs.)

**AI Worker Pool** — async Python, no web framework (never receives HTTP — only consumes `ai_queue`). Orchestration via LangGraph/LangChain, model calls via LiteLLM (see LLMOps section). 3 replicas. Guardrails: per-replica concurrency cap, per-job timeout, one retry with backoff. Fetches AI config (prompts, model tiers, fallback order) via a small internal Main Service endpoint, not direct DB access (see Dynamic Configuration).

**Background Worker** — same async pattern, consumes `tasks_queue`. One queue, many job types, dispatched internally by a `TASK_HANDLERS` map keyed on `job["type"]` — e.g. `generate_pdf`, `send_whatsapp_notification`, `send_otp`. This is the correct version of "one queue, filtered by worker": one homogeneous worker pool, multiple job types, not multiple worker pools sharing one queue. Handler implementations defined at kickoff; the dispatch pattern is fixed now.

**WhatsApp Service** — Express.js, pre-built ahead of the hackathon (unofficial library — official Business API approval lag ruled it out; session kept logged in and warm before the demo, since QR re-scans mid-demo are a real risk). A small HTTP API, not a queue consumer:
- **Outbound:** `POST /whatsapp/send`, called **directly** by AI Worker Pool and Background Worker — not through Main Service. Two reasons: (1) large payloads (PDFs, media) never need to touch Main Service's request thread, and (2) an unofficial library is inherently flaky, so a hung WhatsApp session should never be able to degrade Main Service's own request/response cycle. Both workers call it through one shared helper module (avoids duplicating the HTTP client).
- **Inbound:** WhatsApp webhook → WhatsApp Service → forwards a lightweight payload (sender phone number, text, a **media reference**, never raw file bytes) to Main Service's `/api/whatsapp/inbound`. Main Service validates it, resolves the phone number to a user, and enqueues a job — the untrusted-input boundary, so it's the one path that goes through Main Service. Whichever worker picks up that job fetches the actual media directly from the WhatsApp Service when it processes the job, not through Django.
- A light per-phone-number rate limit sits on the inbound webhook — cheap protection against a flood of junk before the demo even starts.

**Redis** — one queue per worker pool: `ai_queue` (AI Worker Pool only) and `tasks_queue` (Background Worker only, multi-type via internal dispatch), plus worker heartbeat keys. `RPUSH`/`BLPOP`, no Celery, no channel layer.

**Postgres** — one shared database, owned exclusively by Main Service. Domain schema defined at kickoff. AI config tables (prompts, model-tier mapping, fallback order) and the WhatsApp `phone_number` field are decided now.

## Communication

- Frontend ↔ Main Service: REST/JSON over HTTPS, CORS-enabled.
- Main Service → AI/Background workers: Redis queues, not REST — avoids blocking a request thread on slow work.
- AI/Background workers → WhatsApp Service: direct HTTP (outbound), via one shared client helper — no queue, no Main Service hop; nothing to validate on content you already decided.
- WhatsApp Service → Main Service: HTTP webhook (inbound only) — the one path with untrusted external input, so it's the one path that goes through Main Service for validation before anything is enqueued.
- AI Worker Pool → Main Service: internal HTTP endpoint for AI config, in place of direct Postgres access — keeps "only Main Service touches Postgres" true without exceptions. Cached briefly in-worker (~30–60s) so this isn't a round-trip on every single call.
- Job status: frontend polls `GET /api/jobs/{job_id}`.
- **Optional, not mandated:** Django Channels + WebSockets could replace polling with push-based updates if a specific need justifies it later. Not part of the baseline.

## Contract-First Workflow

1. Lock endpoint contracts (request/response shape, error cases) once the theme is known.
2. Build against the contract in parallel.
3. Integration is wiring real calls, not discovering shapes.

## Deployment

Single VM, `docker-compose up -d` — one command for every container (frontend, Main Service, AI Worker Pool ×3, Background Worker, WhatsApp Service, Redis, Postgres). WhatsApp Service runs as a normal service like everything else — no gating needed now that it's already built.

## Production-Readiness Checklist

- [ ] Health/liveness signal per component (Main Service `/health`; workers via Redis heartbeat; WhatsApp Service `/health`)
- [ ] CI: lint + tests on push
- [ ] Structured logging
- [ ] `.env`-based config, no hardcoded secrets
- [ ] API docs auto-served (DRF + `drf-spectacular`)
- [ ] One-command local spin-up and deploy
- [ ] WhatsApp session pre-authenticated and warm before the demo — not scanned live

## AI Service Production-Readiness (LLMOps)

**Orchestration:** LangGraph (built on LangChain) is the default for multi-step/agentic work — state graphs handle cycles and multi-agent coordination directly. Adopted as baseline: the code is AI-agent-authored, not hand-typed, so the framework's learning curve costs far less here than for a human team, and LangGraph's cycle/multi-agent support is genuinely hard to replicate by hand in the time available.

**Model access:** LiteLLM is the calling layer underneath, wired into LangChain via `ChatLiteLLMRouter` (`langchain-litellm` package) — LangGraph nodes use it as a normal LangChain chat model, while LiteLLM's fallback chains and cost tracking run underneath.

**Model tiers + fallback**, as a LiteLLM `Router` config: `fast` / `smart` tiers, each mapped to a primary model with an ordered fallback list. Swapping a rate-limited model mid-demo is a config change, not a code change.

**Prompts:** LangChain `PromptTemplate`s, versioned as named files (e.g. `prompts/v1_summarize.py`). No separate templating library — LangChain covers it.

**Structured output:** LangChain's native `.with_structured_output(PydanticModel)` handles validation and parsing directly — Instructor would be redundant, dropped.

**Tool calling:** LangChain's tool interface (`@tool` decorator + `.bind_tools()`) — native provider function-calling underneath, LangChain's parsing on top instead of a hand-rolled loop.

**RAG:** pgvector remains the vector store (already in Postgres); use LangChain's `PGVector` retriever so retrieval plugs directly into a graph node.

**Streaming:** flagged as a probable stretch feature, not baseline. Channels/WebSockets (or SSE) to be decided once the rest of the system is stable and if time allows.

**Guardrails:** per-replica concurrency cap, per-job timeout, one retry with backoff, full call telemetry in Postgres (`prompt_version`, `model`, `tokens`, `latency_ms`, `cost_estimate`).

## Dynamic Configuration

Made dynamic because it's cheap and high-value — not "everything," scoped deliberately:

- **Prompt text + version**, **model tier → provider/model mapping**, **fallback chain order**, **per-prompt temperature/max_tokens** — stored as DB-backed config models owned by Main Service, edited via **Django Admin** (free CRUD UI, no custom dashboard needed).
- AI Worker Pool fetches current config via a small internal Main Service endpoint (e.g. `GET /api/internal/ai-config`), not direct Postgres access — keeps "only Main Service touches Postgres" true. Cached in-worker for ~30–60s so this isn't a round-trip on every call.
- **Deliberately NOT dynamic:** the orchestration graph structure, tool functions, and RAG chunking logic stay in code. Config values are dynamic; orchestration logic isn't.

## Repository Structure

```
repo/
├── docker-compose.yml
├── shared/
│   └── whatsapp_client.py      # imported by ai-worker and background-worker
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
├── whatsapp-service/
│   ├── Dockerfile
│   └── index.js
└── docs/
    ├── architecture.md
    ├── sdlc.md
    ├── coding-guidelines.md
    ├── testing-guidelines.md
    ├── documentation-guide.md
    ├── ux-guide.md
    └── ui-guide.md
```

`ai-worker` and `background-worker` build with the repo root as Docker build context (not their own subfolder) specifically so their Dockerfiles can `COPY shared/` in — that's what makes one real shared module possible instead of two copies of the same HTTP client.

## Ownership Map

| Component | Owner |
|---|---|
| Main Service (Auth + Core) | TBD |
| AI Worker Pool | TBD |
| Background Worker | TBD |
| WhatsApp Service | TBD |
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
