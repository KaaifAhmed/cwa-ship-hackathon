#!/usr/bin/env bash
# ============================================================================
# CWA Ship Karachi 2026 — Project Bootstrap (v2)
#
# Scaffolds architecture.md: frontend / main-service (Django, Auth+Core) /
# ai-worker (LangGraph+LangChain+LiteLLM) / background-worker /
# whatsapp-service (Express, prebuilt) / compose.yaml
#
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh [project-name]
#
# Requires: git, python3 (3.11+), node/npm (20+), Docker with the
# `docker compose` plugin (v2 — NOT the standalone docker-compose binary)
# ============================================================================
set -e

PROJECT_NAME="${1:-cwa-hackathon}"
echo "==> Bootstrapping project: $PROJECT_NAME"
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"
mkdir -p docs shared
touch shared/__init__.py

# Cross-platform venv activation (Linux/Mac: bin/, Windows Git Bash: Scripts/)
activate_venv() {
  if [ -f "$1/Scripts/activate" ]; then source "$1/Scripts/activate"
  else source "$1/bin/activate"
  fi
}

stage_done() {
  case "$1" in
    1) [ -f frontend/package.json ] && [ -f frontend/vite.config.ts ] ;;
    2) [ -f main-service/manage.py ] && [ -f main-service/requirements.txt ] ;;
    3) [ -f ai-worker/main.py ] && [ -f ai-worker/requirements.txt ] ;;
    4) [ -f background-worker/main.py ] && [ -f background-worker/requirements.txt ] ;;
    5) [ -f shared/security_guards.py ] && [ -f shared/whatsapp_client.py ] ;;
    6) [ -f whatsapp-service/index.js ] && [ -f whatsapp-service/package.json ] ;;
    7) [ -f compose.yaml ] && [ -f .env.example ] && [ -f .gitignore ] && [ -f SETUP.md ] \
      && [ -f frontend/Dockerfile ] && [ -f main-service/Dockerfile ] \
      && [ -f ai-worker/Dockerfile ] && [ -f background-worker/Dockerfile ] \
      && [ -f whatsapp-service/Dockerfile ] && [ -d .git ] ;;
    *) return 1 ;;
  esac
}

run_stage() {
  local stage="$1"
  if stage_done "$stage"; then
    echo "==> [$stage/7] Already complete; skipping"
    return 1
  fi
  return 0
}

# ============================================================================
# 1. FRONTEND — React + Vite + TypeScript + Tailwind
# ============================================================================
run_stage 1 || true
if ! stage_done 1; then
echo "==> [1/7] Scaffolding frontend"
npm create vite@latest frontend -- --template react-ts
cd frontend
npm install
npm install react-router-dom
npm install tailwindcss @tailwindcss/vite

cat > vite.config.ts << 'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
})
EOF

{ echo '@import "tailwindcss";'; cat src/index.css; } > src/index.css.tmp && mv src/index.css.tmp src/index.css
echo "VITE_API_URL=http://localhost:8000" > .env.example
cd ..
fi

# ============================================================================
# 2. MAIN SERVICE — Django (Auth + Core, only component touching Postgres)
# ============================================================================
run_stage 2 || true
if ! stage_done 2; then
echo "==> [2/7] Scaffolding Main Service (Django)"
python3 -m venv main-service/.venv
activate_venv main-service/.venv
python.exe -m pip install --upgrade pip

pip install django djangorestframework djangorestframework-simplejwt \
  django-cors-headers drf-spectacular "psycopg[binary]" python-dotenv \
  pgvector gunicorn ruff pytest pytest-django

cd main-service
django-admin startproject config .
python manage.py startapp users
python manage.py startapp core

cat > config/settings.py << 'EOF'
import os
from datetime import timedelta
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()
BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-secret-key-change-me")
DEBUG = os.environ.get("DEBUG", "True") == "True"
ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "*").split(",")

INSTALLED_APPS = [
    "django.contrib.admin", "django.contrib.auth", "django.contrib.contenttypes",
    "django.contrib.sessions", "django.contrib.messages", "django.contrib.staticfiles",
    "rest_framework", "rest_framework_simplejwt", "corsheaders", "drf_spectacular",
    "users", "core",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
TEMPLATES = [{
    "BACKEND": "django.template.backends.django.DjangoTemplates",
    "DIRS": [], "APP_DIRS": True,
    "OPTIONS": {"context_processors": [
        "django.template.context_processors.debug",
        "django.template.context_processors.request",
        "django.contrib.auth.context_processors.auth",
        "django.contrib.messages.context_processors.messages",
    ]},
}]
WSGI_APPLICATION = "config.wsgi.application"

DATABASES = {"default": {
    "ENGINE": "django.db.backends.postgresql",
    "NAME": os.environ.get("POSTGRES_DB", "main_db"),
    "USER": os.environ.get("POSTGRES_USER", "postgres"),
    "PASSWORD": os.environ.get("POSTGRES_PASSWORD", "postgres"),
    "HOST": os.environ.get("POSTGRES_HOST", "localhost"),
    "PORT": os.environ.get("POSTGRES_PORT", "5432"),
}}

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True
STATIC_URL = "static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": ("rest_framework_simplejwt.authentication.JWTAuthentication",),
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
}
SPECTACULAR_SETTINGS = {"TITLE": "Main Service API", "VERSION": "1.0.0"}
SIMPLE_JWT = {"ACCESS_TOKEN_LIFETIME": timedelta(minutes=30), "REFRESH_TOKEN_LIFETIME": timedelta(days=1)}
CORS_ALLOWED_ORIGINS = os.environ.get("CORS_ALLOWED_ORIGINS", "http://localhost:5173").split(",")
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
EOF

cat > config/urls.py << 'EOF'
from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView


def health(request):
    return JsonResponse({"success": True, "data": {"status": "ok"}, "error": None})


urlpatterns = [
    path("admin/", admin.site.urls),
    path("health", health),
    path("auth/", include("users.urls")),
    path("api/", include("core.urls")),
    path("schema", SpectacularAPIView.as_view(), name="schema"),
    path("docs", SpectacularSwaggerView.as_view(url_name="schema")),
]
EOF

# --- users app: register/login/refresh/me + phone_number candidate key ---
cat > users/models.py << 'EOF'
from django.contrib.auth.models import User
from django.db import models


class UserProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="profile")
    phone_number = models.CharField(max_length=20, unique=True, blank=True, null=True)

    def __str__(self):
        return f"{self.user.username} ({self.phone_number})"
EOF

cat > users/admin.py << 'EOF'
from django.contrib import admin
from .models import UserProfile

admin.site.register(UserProfile)
EOF

cat > users/serializers.py << 'EOF'
from django.contrib.auth.models import User
from rest_framework import serializers


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ["username", "email", "password"]

    def create(self, validated_data):
        return User.objects.create_user(**validated_data)


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "username", "email"]
EOF

cat > users/views.py << 'EOF'
from django.contrib.auth.models import User
from rest_framework import generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .serializers import RegisterSerializer, UserSerializer


def envelope(data=None, error=None):
    return {"success": error is None, "data": data, "error": error}


class RegisterView(generics.CreateAPIView):
    queryset = User.objects.all()
    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(envelope(data={"id": user.id, "username": user.username}), status=201)


class EnvelopeTokenObtainPairView(TokenObtainPairView):
    def post(self, request, *args, **kwargs):
        response = super().post(request, *args, **kwargs)
        if response.status_code == 200:
            response.data = envelope(data=response.data)
        else:
            response.data = envelope(error={"code": "invalid_credentials", "message": "Invalid username or password"})
        return response


class EnvelopeTokenRefreshView(TokenRefreshView):
    def post(self, request, *args, **kwargs):
        response = super().post(request, *args, **kwargs)
        if response.status_code == 200:
            response.data = envelope(data=response.data)
        else:
            response.data = envelope(error={"code": "invalid_token", "message": "Refresh token invalid or expired"})
        return response


class MeView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(envelope(data=UserSerializer(request.user).data))
EOF

cat > users/urls.py << 'EOF'
from django.urls import path
from .views import EnvelopeTokenObtainPairView, EnvelopeTokenRefreshView, MeView, RegisterView

urlpatterns = [
    path("register", RegisterView.as_view()),
    path("login", EnvelopeTokenObtainPairView.as_view()),
    path("refresh", EnvelopeTokenRefreshView.as_view()),
    path("me", MeView.as_view()),
]
EOF

# --- core app: AI config + WhatsApp inbound endpoints (stubs — real logic at kickoff) ---
cat > core/views.py << 'EOF'
from django.http import JsonResponse
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny


@api_view(["GET"])
def ai_config(request):
    # TODO (kickoff): back with a real DB-backed config model + Django Admin
    # — see "Dynamic Configuration" in docs/architecture.md.
    return JsonResponse({
        "success": True,
        "data": {"tiers": {"fast": None, "smart": None}, "fallback_order": []},
        "error": None,
    })


@api_view(["POST"])
@permission_classes([AllowAny])
def whatsapp_inbound(request):
    # TODO (kickoff): resolve request.data["phone"] via UserProfile,
    # enqueue onto ai_queue or tasks_queue depending on intent.
    return JsonResponse({"success": True, "data": {"received": True}, "error": None})


@api_view(["POST"])
def log_ai_call(request):
    # TODO (kickoff): persist to a real AICall model instead of just printing
    # — see docs/ai-system.md §4.4 (agent identities) and §6.2 (audit trail).
    print(f"[ai_call telemetry] {request.data}")
    return JsonResponse({"success": True, "data": {"logged": True}, "error": None})
EOF

cat > core/urls.py << 'EOF'
from django.urls import path
from .views import ai_config, log_ai_call, whatsapp_inbound

urlpatterns = [
    path("internal/ai-config", ai_config),
    path("internal/ai-calls", log_ai_call),
    path("whatsapp/inbound", whatsapp_inbound),
]
EOF

cat > pytest.ini << 'EOF'
[pytest]
DJANGO_SETTINGS_MODULE = config.settings
python_files = tests.py test_*.py *_tests.py
EOF

cat > .env.example << 'EOF'
DJANGO_SECRET_KEY=change-me
DEBUG=True
ALLOWED_HOSTS=*
POSTGRES_DB=main_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
CORS_ALLOWED_ORIGINS=http://localhost:5173
REDIS_URL=redis://redis:6379/0
EOF

python manage.py makemigrations users
pip freeze > requirements.txt
deactivate
cd ..
echo "==> Main Service scaffolded (auth working, phone_number field, AI-config + WhatsApp-inbound stubs)"
fi

# ============================================================================
# 3. AI WORKER — async, LangGraph/LangChain/LiteLLM, no direct DB access
# ============================================================================
run_stage 3 || true
if ! stage_done 3; then
echo "==> [3/7] Scaffolding AI Worker"
mkdir -p ai-worker
python3 -m venv ai-worker/.venv
activate_venv ai-worker/.venv
python.exe -m pip install --upgrade pip

pip install langgraph langchain langchain-litellm litellm \
  "redis[hiredis]" httpx pydantic python-dotenv ruff pytest pytest-asyncio

cat > ai-worker/main.py << 'EOF'
"""
AI Worker — consumes ai_queue, orchestrates via LangGraph/LangChain,
calls models via LiteLLM (docs/ai-system.md).

Infra skeleton: queue loop, concurrency cap, timeout, retry, heartbeat,
AI-config fetch, agent roles (PLA/RBAC), input/output guards, and
telemetry — all decided pre-hackathon per docs/ai-system.md. The
LangGraph workflow in run_graph() is domain-specific, defined at kickoff.
"""
import asyncio
import json
import os
import time

import httpx
import redis.asyncio as redis
from dotenv import load_dotenv

from shared.security_guards import input_guard, output_guard

load_dotenv()

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
MAIN_SERVICE_URL = os.environ.get("MAIN_SERVICE_URL", "http://main-service:8000")
QUEUE_NAME = "ai_queue"
CONCURRENCY_LIMIT = int(os.environ.get("AI_WORKER_CONCURRENCY", "5"))
JOB_TIMEOUT_SECONDS = int(os.environ.get("AI_JOB_TIMEOUT", "60"))
RESULT_TTL_SECONDS = 3600
CONFIG_CACHE_TTL_SECONDS = 30
HEARTBEAT_KEY = f"heartbeat:ai-worker:{os.environ.get('HOSTNAME', 'unknown')}"

semaphore = asyncio.Semaphore(CONCURRENCY_LIMIT)
_config_cache = {"data": None, "fetched_at": 0.0}

# --- Agent roles (RBAC) — docs/ai-system.md §4.2. Code, not Dynamic
# Config: permissions shouldn't be one Django-Admin click away from
# being loosened. Tool names filled in at kickoff; each graph node is
# bound to exactly one role's tool list, never the full registry.
AGENT_ROLES = {
    "retriever":       {"tools": [], "can_act_externally": False},
    "responder":       {"tools": [], "can_act_externally": False},
    "action_executor": {"tools": [], "can_act_externally": True},
}


async def get_ai_config() -> dict:
    """Fetched from Main Service, not Postgres directly — cached briefly to avoid a round-trip per call."""
    now = time.time()
    if _config_cache["data"] is None or now - _config_cache["fetched_at"] > CONFIG_CACHE_TTL_SECONDS:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{MAIN_SERVICE_URL}/api/internal/ai-config")
            response.raise_for_status()
            _config_cache["data"] = response.json()["data"]
            _config_cache["fetched_at"] = now
    return _config_cache["data"]


async def log_ai_call(**fields) -> None:
    """Telemetry — docs/ai-system.md §4.4/§6.2. Posted to Main Service, not
    written to Postgres directly (only Main Service touches Postgres)."""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            await client.post(f"{MAIN_SERVICE_URL}/api/internal/ai-calls", json=fields)
    except Exception as exc:  # noqa: BLE001 — telemetry failure must never break the job
        print(f"telemetry log failed (non-fatal): {exc}")


async def run_graph(job: dict, role: str):
    """TODO (kickoff): build the LangGraph workflow for this job's task type,
    using AGENT_ROLES[role]["tools"] to bind only that role's permitted tools."""
    raise NotImplementedError("Define the LangGraph workflow at kickoff")


async def process_job(r: redis.Redis, job: dict):
    job_id = job["job_id"]
    agent_role = job.get("agent_role", "responder")
    started_at = time.time()

    async with semaphore:
        try:
            guard = input_guard(job.get("input", ""))
            if not guard["ok"]:
                raise ValueError(f"input rejected: {guard['reason']}")
            if guard.get("flagged"):
                print(f"[security] input flagged for job {job_id}: {guard['reason']}")

            result = await asyncio.wait_for(run_graph(job, role=agent_role), timeout=JOB_TIMEOUT_SECONDS)

            out_text = result if isinstance(result, str) else json.dumps(result)
            out_guard = output_guard(out_text)
            if not out_guard["ok"]:
                raise ValueError(f"output blocked: {out_guard['reason']}")

            await r.set(f"result:{job_id}", json.dumps({"status": "done", "result": result}), ex=RESULT_TTL_SECONDS)
            await log_ai_call(
                job_id=job_id, agent_role=agent_role, status="done",
                latency_ms=int((time.time() - started_at) * 1000),
                flagged_input=guard.get("flagged", False),
            )
        except Exception as exc:  # noqa: BLE001 — boundary catch, reported to caller
            await r.set(f"result:{job_id}", json.dumps({"status": "error", "error": str(exc)}), ex=RESULT_TTL_SECONDS)
            await log_ai_call(
                job_id=job_id, agent_role=agent_role, status="error",
                latency_ms=int((time.time() - started_at) * 1000), error=str(exc),
            )


async def heartbeat_loop(r: redis.Redis):
    while True:
        await r.set(HEARTBEAT_KEY, str(time.time()), ex=15)
        await asyncio.sleep(5)


async def main():
    r = redis.from_url(REDIS_URL)
    asyncio.create_task(heartbeat_loop(r))
    print(f"AI worker started, listening on '{QUEUE_NAME}'")
    while True:
        _, raw_job = await r.blpop(QUEUE_NAME)
        job = json.loads(raw_job)
        asyncio.create_task(process_job(r, job))


if __name__ == "__main__":
    asyncio.run(main())
EOF

cat > ai-worker/.env.example << 'EOF'
REDIS_URL=redis://redis:6379/0
MAIN_SERVICE_URL=http://main-service:8000
WHATSAPP_SERVICE_URL=http://whatsapp-service:3001
AI_WORKER_CONCURRENCY=5
AI_JOB_TIMEOUT=60
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
EOF

pip freeze > ai-worker/requirements.txt
deactivate
echo "==> AI Worker scaffolded"
fi

# ============================================================================
# 4. BACKGROUND WORKER — async, non-AI tasks (PDF gen, WhatsApp notify, OTP)
# ============================================================================
run_stage 4 || true
if ! stage_done 4; then
echo "==> [4/7] Scaffolding Background Worker"
mkdir -p background-worker
python3 -m venv background-worker/.venv
activate_venv background-worker/.venv
python.exe -m pip install --upgrade pip

pip install "redis[hiredis]" httpx weasyprint pydantic python-dotenv ruff pytest pytest-asyncio

cat > background-worker/main.py << 'EOF'
"""
Background Worker — consumes tasks_queue. One queue, many job types,
dispatched internally by TASK_HANDLERS (the correct version of "one
queue shared across job types" — see docs/architecture.md). Handlers
(generate_pdf, send_whatsapp_notification, send_otp, ...) are
registered at kickoff; this file is the infra skeleton.
"""
import asyncio
import json
import os
import time

import redis.asyncio as redis
from dotenv import load_dotenv

load_dotenv()

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
QUEUE_NAME = "tasks_queue"
RESULT_TTL_SECONDS = 3600
HEARTBEAT_KEY = f"heartbeat:background-worker:{os.environ.get('HOSTNAME', 'unknown')}"

TASK_HANDLERS = {
    # "generate_pdf": handle_generate_pdf,
    # "send_whatsapp_notification": handle_send_whatsapp_notification,  # uses
    #     shared.whatsapp_client.send_whatsapp_message() — the output guard
    #     (docs/ai-system.md §5.1) is enforced inside that shared client, so
    #     handlers here don't need to call it separately.
    # "send_otp": handle_send_otp,
    # registered at kickoff
}


async def process_job(r: redis.Redis, job: dict):
    job_id = job["job_id"]
    handler = TASK_HANDLERS.get(job.get("type"))
    if handler is None:
        await r.set(f"result:{job_id}", json.dumps({"status": "error", "error": f"unknown task type: {job.get('type')}"}), ex=RESULT_TTL_SECONDS)
        return
    try:
        result = await handler(job)
        await r.set(f"result:{job_id}", json.dumps({"status": "done", "result": result}), ex=RESULT_TTL_SECONDS)
    except Exception as exc:  # noqa: BLE001 — boundary catch, reported to caller
        await r.set(f"result:{job_id}", json.dumps({"status": "error", "error": str(exc)}), ex=RESULT_TTL_SECONDS)


async def heartbeat_loop(r: redis.Redis):
    while True:
        await r.set(HEARTBEAT_KEY, str(time.time()), ex=15)
        await asyncio.sleep(5)


async def main():
    r = redis.from_url(REDIS_URL)
    asyncio.create_task(heartbeat_loop(r))
    print(f"Background worker started, listening on '{QUEUE_NAME}'")
    while True:
        _, raw_job = await r.blpop(QUEUE_NAME)
        job = json.loads(raw_job)
        asyncio.create_task(process_job(r, job))


if __name__ == "__main__":
    asyncio.run(main())
EOF

cat > background-worker/.env.example << 'EOF'
REDIS_URL=redis://redis:6379/0
MAIN_SERVICE_URL=http://main-service:8000
WHATSAPP_SERVICE_URL=http://whatsapp-service:3001
EOF

pip freeze > background-worker/requirements.txt
deactivate
echo "==> Background Worker scaffolded"
fi

# ============================================================================
# 5. SHARED — security guards + WhatsApp HTTP client, imported by both workers
# ============================================================================
run_stage 5 || true
if ! stage_done 5; then
echo "==> [5/7] Writing shared security guards + WhatsApp client"

cat > shared/security_guards.py << 'EOF'
"""
Input/output guards for AI-generated content — docs/ai-system.md §5.1.
Imported by ai-worker and background-worker. Anything reaching an
external channel (WhatsApp) or stored as a job result goes through
these first. Pattern-based, not a full injection/DLP scanner — flags
the common cases, doesn't try to catch everything.
"""
import re

MAX_INPUT_LENGTH = 8000

INJECTION_PATTERNS = [
    r"ignore (all|any|previous) instructions",
    r"disregard (the )?system prompt",
    r"reveal (your|the) system prompt",
    r"you are now",
]

SECRET_PATTERNS = [
    r"sk-[a-zA-Z0-9]{20,}",      # generic API-key-shaped string
    r"AIza[0-9A-Za-z\-_]{35}",   # Google-style key
]


def input_guard(text: str) -> dict:
    """Flags likely prompt injection. Flags + logs by default rather than
    hard-blocking — tighten to a hard block at kickoff if the theme's
    risk profile warrants it."""
    if not text or len(text) > MAX_INPUT_LENGTH:
        return {"ok": False, "flagged": True, "reason": "empty_or_too_long"}
    for pattern in INJECTION_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            return {"ok": True, "flagged": True, "reason": f"matched: {pattern}"}
    return {"ok": True, "flagged": False, "reason": None}


def output_guard(text: str) -> dict:
    """Blocks obvious credential/secret leakage before anything leaves the system."""
    if not text:
        return {"ok": True, "reason": None}
    for pattern in SECRET_PATTERNS:
        if re.search(pattern, text):
            return {"ok": False, "reason": "possible_secret_leak"}
    return {"ok": True, "reason": None}
EOF

cat > shared/whatsapp_client.py << 'EOF'
"""
Shared HTTP client for the WhatsApp Service's outbound send endpoint.
Imported directly by ai-worker and background-worker (see architecture.md —
outbound goes worker -> WhatsApp Service directly, never through Main Service).

Every send is gated by the output guard (docs/ai-system.md §5.1) here,
at the choke point — so no call site can forget the check.
"""
import os
import httpx

from shared.security_guards import output_guard

WHATSAPP_SERVICE_URL = os.environ.get("WHATSAPP_SERVICE_URL", "http://whatsapp-service:3001")


async def send_whatsapp_message(phone: str, text: str) -> dict:
    guard = output_guard(text)
    if not guard["ok"]:
        raise ValueError(f"blocked by output guard: {guard['reason']}")

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(f"{WHATSAPP_SERVICE_URL}/whatsapp/send", json={"phone": phone, "text": text})
        response.raise_for_status()
        return response.json()
EOF
fi

# ============================================================================
# 6. WHATSAPP SERVICE — Express, prebuilt, unofficial library
# ============================================================================
run_stage 6 || true
if ! stage_done 6; then
echo "==> [6/7] Scaffolding WhatsApp Service"
mkdir -p whatsapp-service
cd whatsapp-service
npm init -y > /dev/null
npm pkg set type="commonjs"
npm install express @whiskeysockets/baileys

cat > index.js << 'EOF'
/**
 * WhatsApp Service — small HTTP API, not a queue consumer.
 * Outbound: POST /whatsapp/send, called directly by the AI Worker Pool
 *   and Background Worker (via shared/whatsapp_client.py).
 * Inbound: forwards a lightweight payload (phone, text, media reference —
 *   never raw file bytes) to Main Service's /api/whatsapp/inbound.
 *
 * Pre-authenticate before the demo: run this once ahead of time, scan the
 * QR code, and the ./auth session folder keeps it logged in — don't scan
 * live during judging.
 */
const express = require("express");
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason } = require("@whiskeysockets/baileys");

const app = express();
app.use(express.json());

const MAIN_SERVICE_URL = process.env.MAIN_SERVICE_URL || "http://main-service:8000";
let sock;

async function startWhatsApp() {
  const { state, saveCreds } = await useMultiFileAuthState("./auth");
  sock = makeWASocket({ auth: state, printQRInTerminal: true });
  sock.ev.on("creds.update", saveCreds);

  sock.ev.on("connection.update", (update) => {
    const { connection, lastDisconnect } = update;
    if (connection === "close") {
      const shouldReconnect = lastDisconnect?.error?.output?.statusCode !== DisconnectReason.loggedOut;
      console.log("WhatsApp connection closed, reconnecting:", shouldReconnect);
      if (shouldReconnect) startWhatsApp();
    } else if (connection === "open") {
      console.log("WhatsApp connected");
    }
  });

  sock.ev.on("messages.upsert", async ({ messages }) => {
    for (const msg of messages) {
      if (!msg.message || msg.key.fromMe) continue;
      const phone = msg.key.remoteJid?.split("@")[0];
      const text = msg.message.conversation || msg.message.extendedTextMessage?.text || "";
      const mediaRef = msg.key.id; // reference only — worker fetches full media when it processes the job

      try {
        await fetch(`${MAIN_SERVICE_URL}/api/whatsapp/inbound`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ phone, text, media_ref: mediaRef }),
        });
      } catch (err) {
        console.error("Failed to forward inbound message:", err);
      }
    }
  });
}

app.post("/whatsapp/send", async (req, res) => {
  const { phone, text } = req.body;
  try {
    await sock.sendMessage(`${phone}@s.whatsapp.net`, { text });
    res.json({ success: true, data: { sent: true }, error: null });
  } catch (err) {
    res.status(500).json({ success: false, data: null, error: { code: "send_failed", message: err.message } });
  }
});

app.get("/health", (req, res) => {
  res.json({ success: true, data: { status: "ok" }, error: null });
});

startWhatsApp();
app.listen(3001, () => console.log("WhatsApp Service listening on :3001"));
EOF

cat > .env.example << 'EOF'
MAIN_SERVICE_URL=http://main-service:8000
EOF

cd ..
echo "==> WhatsApp Service scaffolded (run it once standalone to scan the QR before the demo)"
fi

# ============================================================================
# 7. DOCKER — Dockerfiles + compose.yaml, root files, git init
# ============================================================================
run_stage 7 || true
if ! stage_done 7; then
echo "==> [7/7] Writing Docker setup and root files"

cat > frontend/Dockerfile << 'EOF'
FROM node:20-slim AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM node:20-slim
WORKDIR /app
RUN npm install -g serve
COPY --from=build /app/dist ./dist
EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000"]
EOF

cat > main-service/Dockerfile << 'EOF'
FROM python:3.12-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev gcc \
  && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]
EOF

# ai-worker / background-worker build from the REPO ROOT so they can COPY shared/
cat > ai-worker/Dockerfile << 'EOF'
FROM python:3.12-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends gcc \
  && rm -rf /var/lib/apt/lists/*
COPY ai-worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY shared/ ./shared/
COPY ai-worker/ .
CMD ["python", "main.py"]
EOF

cat > background-worker/Dockerfile << 'EOF'
FROM python:3.12-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends \
  gcc libpango-1.0-0 libpangocairo-1.0-0 libcairo2 \
  libgdk-pixbuf-2.0-0 libffi-dev shared-mime-info \
  && rm -rf /var/lib/apt/lists/*
COPY background-worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY shared/ ./shared/
COPY background-worker/ .
CMD ["python", "main.py"]
EOF

cat > whatsapp-service/Dockerfile << 'EOF'
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3001
CMD ["node", "index.js"]
EOF

cat > compose.yaml << 'EOF'
services:
  postgres:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-main_db}
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  main-service:
    build: ./main-service
    env_file: .env
    environment:
      POSTGRES_HOST: postgres
      REDIS_URL: redis://redis:6379/0
    depends_on:
      - postgres
      - redis
    ports:
      - "8000:8000"

  ai-worker:
    build:
      context: .
      dockerfile: ai-worker/Dockerfile
    env_file: .env
    environment:
      REDIS_URL: redis://redis:6379/0
      MAIN_SERVICE_URL: http://main-service:8000
      WHATSAPP_SERVICE_URL: http://whatsapp-service:3001
    depends_on:
      - redis
      - main-service

  background-worker:
    build:
      context: .
      dockerfile: background-worker/Dockerfile
    env_file: .env
    environment:
      REDIS_URL: redis://redis:6379/0
      MAIN_SERVICE_URL: http://main-service:8000
      WHATSAPP_SERVICE_URL: http://whatsapp-service:3001
    depends_on:
      - redis
      - main-service

  whatsapp-service:
    build: ./whatsapp-service
    env_file: .env
    environment:
      MAIN_SERVICE_URL: http://main-service:8000
    ports:
      - "3001:3001"
    depends_on:
      - main-service

  frontend:
    build: ./frontend
    ports:
      - "5173:3000"
    depends_on:
      - main-service

volumes:
  pgdata:
EOF

cat > .env.example << 'EOF'
# Postgres
POSTGRES_DB=main_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres

# Django
DJANGO_SECRET_KEY=change-me
DEBUG=True
ALLOWED_HOSTS=*
CORS_ALLOWED_ORIGINS=http://localhost:5173

# Redis
REDIS_URL=redis://redis:6379/0

# LLM providers (fill in at kickoff)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
EOF

cat > .gitignore << 'EOF'
__pycache__/
*.pyc
.venv/
venv/
node_modules/
dist/
.env
*.sqlite3
.DS_Store
whatsapp-service/auth/
EOF

cat > SETUP.md << 'EOF'
# Local Setup

Scaffold reference, not the final project README (that's a Phase 8
deliverable — see docs/documentation-guide.md).

1. Copy `.env.example` to `.env` and fill in real values (LLM API keys especially).
2. Place the pre-hackathon docs into `docs/` (architecture.md, sdlc.md,
   coding-guidelines.md, testing-guidelines.md, documentation-guide.md,
   ux-guide.md, ui-guide.md).
3. Pre-authenticate WhatsApp once, before the demo:
   cd whatsapp-service && node index.js
   (scan the QR code; ./auth/ then keeps the session logged in — don't scan live)
4. Build and run everything (3 AI worker replicas, per architecture.md):
   docker compose up -d --build --scale ai-worker=3
5. Apply migrations:
   docker compose exec main-service python manage.py migrate
6. Create an admin user (Django Admin is where AI config eventually lives):
   docker compose exec main-service python manage.py createsuperuser
7. Verify:
   - http://localhost:8000/health
   - http://localhost:8000/docs        (Swagger UI)
   - http://localhost:3001/health      (WhatsApp Service)
   - http://localhost:5173             (frontend)
EOF

git init -q
git add -A
git commit -q -m "chore: bootstrap project scaffold from architecture.md"
fi

echo ""
echo "============================================================"
echo " Done. Project scaffolded at ./$PROJECT_NAME"
echo ""
echo " Next steps:"
echo "  1. cd $PROJECT_NAME"
echo "  2. Drop the 7 doc files into docs/"
echo "  3. cp .env.example .env   (then fill in real secrets/keys)"
echo "  4. Pre-auth WhatsApp: cd whatsapp-service && node index.js (scan QR, then Ctrl+C)"
echo "  5. docker compose up -d --build --scale ai-worker=3"
echo "  6. docker compose exec main-service python manage.py migrate"
echo "  7. docker compose exec main-service python manage.py createsuperuser"
echo "============================================================"
