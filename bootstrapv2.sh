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

# Cross-platform venv activation (Linux/Mac: bin/, Windows Git Bash: Scripts/)
activate_venv() {
  if [ -f "$1/Scripts/activate" ]; then source "$1/Scripts/activate"
  else source "$1/bin/activate"
  fi
}

# ============================================================================
# 1. FRONTEND — React + Vite + TypeScript + Tailwind
# ============================================================================
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

# ============================================================================
# 2. MAIN SERVICE — Django (Auth + Core, only component touching Postgres)
# ============================================================================
echo "==> [2/7] Scaffolding Main Service (Django)"
python3 -m venv main-service/.venv
activate_venv main-service/.venv
pip install --upgrade pip
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
EOF

cat > core/urls.py << 'EOF'
from django.urls import path
from .views import ai_config, whatsapp_inbound

urlpatterns = [
    path("internal/ai-config", ai_config),
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

# ============================================================================
# 3. AI WORKER — async, LangGraph/LangChain/LiteLLM, no direct DB access
# ============================================================================
echo "==> [3/7] Scaffolding AI Worker"
mkdir -p ai-worker
python3 -m venv ai-worker/.venv
activate_venv ai-worker/.venv
pip install --upgrade pip
pip install langgraph langchain langchain-litellm litellm \
  "redis[hiredis]" httpx pydantic python-dotenv ruff pytest pytest-asyncio

cat > ai-worker/main.py << 'EOF'
"""
AI Worker — consumes ai_queue, orchestrates via LangGraph/LangChain,
calls models via LiteLLM (docs/architecture.md, LLMOps section).

Infra skeleton only: queue loop, concurrency cap, timeout, retry,
heartbeat, and AI-config fetch (via Main Service, not direct DB —
only Main Service touches Postgres). The LangGraph workflow in
run_graph() is domain-specific and defined at kickoff.
"""
import asyncio
import json
import os
import time

import httpx
import redis.asyncio as redis
from dotenv import load_dotenv

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


async def run_graph(job: dict):
    """TODO (kickoff): build the LangGraph workflow for this job's task type."""
    raise NotImplementedError("Define the LangGraph workflow at kickoff")


async def process_job(r: redis.Redis, job: dict):
    job_id = job["job_id"]
    async with semaphore:
        try:
            result = await asyncio.wait_for(run_graph(job), timeout=JOB_TIMEOUT_SECONDS)
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

# ============================================================================
# 4. BACKGROUND WORKER — async, non-AI tasks (PDF gen, WhatsApp notify, OTP)
# ============================================================================
echo "==> [4/7] Scaffolding Background Worker"
mkdir -p background-worker
python3 -m venv background-worker/.venv
activate_venv background-worker/.venv
pip install --upgrade pip
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
    # "send_whatsapp_notification": handle_send_whatsapp_notification,
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

# ============================================================================
# 5. SHARED — WhatsApp HTTP client, imported by both Python workers
# ============================================================================
echo "==> [5/7] Writing shared WhatsApp client"
cat > shared/whatsapp_client.py << 'EOF'
"""
Shared HTTP client for the WhatsApp Service's outbound send endpoint.
Imported directly by ai-worker and background-worker (see architecture.md —
outbound goes worker -> WhatsApp Service directly, never through Main Service).
"""
import os
import httpx

WHATSAPP_SERVICE_URL = os.environ.get("WHATSAPP_SERVICE_URL", "http://whatsapp-service:3001")


async def send_whatsapp_message(phone: str, text: str) -> dict:
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(f"{WHATSAPP_SERVICE_URL}/whatsapp/send", json={"phone": phone, "text": text})
        response.raise_for_status()
        return response.json()
EOF

# ============================================================================
# 6. WHATSAPP SERVICE — Express, prebuilt, unofficial library
# ============================================================================
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

# ============================================================================
# 7. DOCKER — Dockerfiles + compose.yaml, root files, git init
# ============================================================================
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
