# System Architecture

**Project:** CWA Ship Karachi 2026 — Production-Grade AI Product
**Status:** Pre-hackathon baseline (domain-agnostic; filled in at kickoff)

## 1. Philosophy

Our edge isn't the feature set — it's that the system is actually production-ready: real service boundaries, real contracts, real tests, real deploy pipeline. Currently, everything in this document is written to be domain-agnostic so it can absorb whatever problem we're given at kickoff without re-architecting.

## 2. High-Level Architecture

```
                         ┌─────────────┐
                         │   React     │
                         │  Frontend   │
                         └──────┬──────┘
                                │  HTTPS
                         ┌──────▼──────┐
                         │    Nginx    │
                         │   Gateway   │
                         └──┬───┬───┬──┘
              ┌─────────────┘   │   └─────────────┐
              ▼                 ▼                 ▼
      ┌───────────────┐ ┌───────────────┐ ┌───────────────┐
      │ Auth Service  │ │  AI Service   │ │ Core Domain    │
      │   (Django)    │ │   (Django)    │ │ Service (Django)│
      └───────┬───────┘ └───────┬───────┘ └───────┬───────┘
              ▼                 ▼                 ▼
        ┌──────────┐      ┌──────────┐      ┌──────────┐
        │ auth_db  │      │  ai_db   │      │ core_db  │
        │(Postgres)│      │(Postgres)│      │(Postgres)│
        └──────────┘      └──────────┘      └──────────┘
```

All services and the gateway run as separate containers via one `docker-compose.yml`. One Postgres instance, three logical databases.

## 3. Services

### 3.1 Auth Service
- **Owns:** users, credentials, sessions, JWT issuance
- **Stack:** Django + `djangorestframework-simplejwt`
- **Key endpoints:** `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `GET /auth/me`
- **Notes:** Built pre-hackathon. Signs JWTs with a shared secret; other services verify locally.

### 3.2 AI Service
- **Owns:** all LLM/agent calls, prompt logic, AI response formatting, and other AI services as per project.
- **Stack:** FastAPI
- **Key endpoints:** TBD (eg. `POST /ai/generate`, `POST /ai/analyze` (renamed/extended once the domain is known))
- **Notes:** Isolating this behind one internal API means prompt/model changes never touch other services.

### 3.3 Core Domain Service
- **Owns:** the actual product logic — TBD until kickoff
- **Stack:** Django + DRF, scaffolded as an empty app with the contract pattern pre-wired
- **Key endpoints:** TBD
- **Notes:** None.

### 3.4 Gateway
- **Owns:** single entry point, routing, TLS termination
- **Stack:** Nginx reverse proxy (simple routing)
- **Routes:** `/auth/* → Auth Service`, `/ai/* → AI Service`, `/api/* → Core Domain Service`
- **Frontend serving:** Nginx also serves the built React static assets at `/`. Any request that isn't `/auth/*`, `/ai/*`, or `/api/*` falls through to `index.html`, and React Router takes over client-side routing from there. This keeps frontend and backend on a single origin (no CORS to configure) while cleanly separating the two route namespaces: backend routes are API contracts, frontend routes (`/dashboard`, `/about`, etc.) are pure UX navigation and never touch Nginx's routing logic.

### 3.5 (Optional) Async Worker
- Celery + Redis, added only if the theme requires background/async work (notifications, long-running jobs). Not part of the baseline.

## 4. Data Layer

- One Postgres instance, one database per service (`auth_db`, `ai_db`, `core_db`) — logical isolation without separate DB servers.
- Each service owns its own migrations; no service reads another's database directly. Cross-service data needs go through that service's API.

## 5. Authentication & Authorization

1. Client logs in via Auth Service → receives JWT (access + refresh).
2. Client sends JWT on every request to the Gateway.
3. Each downstream service validates the JWT signature locally using the shared secret/public key — no call back to Auth Service.
4. Service-to-service calls (if needed) pass the original JWT through, or use a separate internal service token.

## 6. Inter-Service Communication

- Plain REST over HTTP/JSON. No gRPC, no message queue.
- **Standard response envelope** (all services):
```json
{
  "success": true,
  "data": { },
  "error": null
}
```
- **Standard error format:**
```json
{
  "success": false,
  "data": null,
  "error": { "code": "string", "message": "string" }
}
```

## 7. Contract-First Workflow

1. At kickoff, spend ~20–30 min writing OpenAPI-style contracts for every service endpoint (request/response shape, status codes, error cases). Lock them before writing implementation.
2. Each service is implemented against its own contract, in parallel, by AI agents.
3. Gateway and React frontend build against the contract using mocked responses before real services are ready.
4. DRF auto-generates OpenAPI schemas (`drf-spectacular`) — Swagger UI served per service, no hand-written docs.
5. Afternoon integration = swapping mocks for live calls, not discovering what an API returns.

## 8. Containerization & Local Dev

- `docker-compose.yml` at repo root: one container per service + Postgres + Nginx.
- `docker-compose up` is the entire onboarding step for any teammate.
- Each service has its own `Dockerfile`, `.env.example`, and `requirements.txt`.

## 9. Deployment

- Single VM (DigitalOcean/Linode droplet or equivalent), running the same `docker-compose up -d` used locally.
- One predictable deploy command over multiple fragile PaaS deployments.

## 10. Production-Readiness Checklist

- [ ] `/health` endpoint on every service
- [ ] CI (GitHub Actions): lint + test on every push, per service
- [ ] Structured, consistent logging format across services
- [ ] Sentry integration for error tracking
- [ ] `.env`-based config everywhere, no hardcoded secrets, `.env.example` committed
- [ ] Swagger/OpenAPI docs served and browsable per service
- [ ] One-command local spin-up (`docker-compose up`)
- [ ] One-command deploy (`docker-compose up -d` on the VM)

## 11. Repository Structure

```
repo/
├── docker-compose.yml
├── nginx/
│   └── nginx.conf
├── auth-service/
│   ├── Dockerfile
│   ├── manage.py
│   └── ...
├── ai-service/
│   ├── Dockerfile
│   ├── manage.py
│   └── ...
├── core-service/
│   ├── Dockerfile
│   ├── manage.py
│   └── ...
├── frontend/
│   ├── Dockerfile
│   └── src/
└── docs/
    ├── architecture.md      (this file)
    ├── sdlc.md
    ├── coding-guidelines.md
    ├── testing-guidelines.md
    └── ui-guide.md
```

## 12. Ownership Map

| Component | Owner |
|---|---|
| Auth Service | TBD |
| AI Service | TBD |
| Core Domain Service | TBD |
| Gateway / Nginx | TBD |
| React Frontend | TBD |
| CI/CD, Deploy, Docs | TBD |

## 13. Hackathon-Day Timeline

| Time | Activity |
|---|---|
| 10:00–10:30 | Theme absorbed → lock domain model + API contracts |
| 10:30–11:00 | Each owner scaffolds their service from boilerplate; gateway routes wired |
| 11:00–1:00 | Parallel implementation against contracts (AI-agent-driven) |
| 1:00–2:00 | Lunch — informal integration debugging as needed |
| 2:00–3:00 | Real integration: swap mocks for live inter-service calls |
| 3:00–3:30 | End-to-end system test, deploy to VM |
| 3:30–4:00 | Buffer, polish, final docs, submit |
