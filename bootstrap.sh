#!/usr/bin/env bash
# ============================================================================
# CWA Ship Karachi 2026 — Project Bootstrap
#
# Scaffolds the entire architecture decided in architecture.md:
#   frontend (React+Vite+Tailwind) / main-service (Django, Auth+Core)
#   ai-worker (LangGraph/LangChain/LiteLLM) / background-worker / docker-compose
#
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh [project-name]
#
# Requires on the host: git, python3 (3.11+), node/npm (20+), docker, docker-compose
# ============================================================================
set -e

PROJECT_NAME="${1:-cwa-hackathon}"
echo "==> Bootstrapping project: $PROJECT_NAME"
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

mkdir -p docs

# ============================================================================
# 1. FRONTEND — React + Vite + TypeScript + Tailwind
# ============================================================================
echo "==> [1/6] Scaffolding frontend"
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

cat > .env.example << 'EOF'
VITE_API_URL=http://localhost:8000
EOF

cd ..
echo "==> Frontend scaffolded"

# ============================================================================
# 2. MAIN SERVICE — Django (Auth + Core, merged)
# ============================================================================
echo "==> [2/6] Scaffolding Main Service (Django)"
python3 -m venv main-service/.venv
source main-service/.venv/Scripts/activate
# pip install --upgrade pip
pip install django djangorestframework djangorestframework-simplejwt \
  django-cors-headers drf-spectacular "psycopg[binary]" python-dotenv \
  pgvector gunicorn ruff pytest pytest-django

cd main-service
django-admin startproject config .
python manage.py startapp users
python manage.py startapp core

# --- settings.py ---
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
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework_simplejwt",
    "corsheaders",
    "drf_spectacular",
    "users",
    "core",
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

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ.get("POSTGRES_DB", "main_db"),
        "USER": os.environ.get("POSTGRES_USER", "postgres"),
        "PASSWORD": os.environ.get("POSTGRES_PASSWORD", "postgres"),
        "HOST": os.environ.get("POSTGRES_HOST", "localhost"),
        "PORT": os.environ.get("POSTGRES_PORT", "5432"),
    }
}

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
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
}

SPECTACULAR_SETTINGS = {
    "TITLE": "Main Service API",
    "VERSION": "1.0.0",
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=30),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=1),
}

CORS_ALLOWED_ORIGINS = os.environ.get(
    "CORS_ALLOWED_ORIGINS", "http://localhost:5173"
).split(",")

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
EOF

# --- urls.py (adds /health, /auth, /api, /docs) ---
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

# --- users app: register / login / refresh / me, wrapped in the standard envelope ---
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
        return Response(
            envelope(data={"id": user.id, "username": user.username}), status=201
        )


class EnvelopeTokenObtainPairView(TokenObtainPairView):
    def post(self, request, *args, **kwargs):
        response = super().post(request, *args, **kwargs)
        if response.status_code == 200:
            response.data = envelope(data=response.data)
        else:
            response.data = envelope(
                error={"code": "invalid_credentials", "message": "Invalid username or password"}
            )
        return response


class EnvelopeTokenRefreshView(TokenRefreshView):
    def post(self, request, *args, **kwargs):
        response = super().post(request, *args, **kwargs)
        if response.status_code == 200:
            response.data = envelope(data=response.data)
        else:
            response.data = envelope(
                error={"code": "invalid_token", "message": "Refresh token invalid or expired"}
            )
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

# --- core app: left empty on purpose, domain decided at kickoff ---
cat > core/urls.py << 'EOF'
# Domain endpoints defined at kickoff, once the theme is known.
urlpatterns = []
EOF

# --- pytest config ---
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

pip freeze > requirements.txt
deactivate
cd ..
echo "==> Main Service scaffolded (register/login/refresh/me working, core app empty by design)"

# ============================================================================
# 3. AI WORKER — async, LangGraph/LangChain/LiteLLM, no web framework
# ============================================================================
echo "==> [3/6] Scaffolding AI Worker"
mkdir -p ai-worker
python3 -m venv ai-worker/.venv
source ai-worker/.venv/Scripts/activate
pip install --upgrade pip
pip install langgraph langchain langchain-litellm litellm \
  "redis[hiredis]" "psycopg[binary]" pgvector pydantic python-dotenv \
  ruff pytest pytest-asyncio

cat > ai-worker/main.py << 'EOF'
"""
AI Worker — consumes ai_queue, orchestrates via LangGraph/LangChain,
calls models via LiteLLM (see docs/architecture.md, LLMOps section).

This file is the infra skeleton (queue loop, concurrency cap, timeout,
retry, heartbeat) decided pre-hackathon. The actual LangGraph workflow
in run_graph() is domain-specific and defined at kickoff.
"""
import asyncio
import json
import os
import time

import redis.asyncio as redis
from dotenv import load_dotenv

load_dotenv()

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
QUEUE_NAME = "ai_queue"
CONCURRENCY_LIMIT = int(os.environ.get("AI_WORKER_CONCURRENCY", "5"))
JOB_TIMEOUT_SECONDS = int(os.environ.get("AI_JOB_TIMEOUT", "60"))
RESULT_TTL_SECONDS = 3600
HEARTBEAT_KEY = f"heartbeat:ai-worker:{os.environ.get('HOSTNAME', 'unknown')}"

semaphore = asyncio.Semaphore(CONCURRENCY_LIMIT)


async def run_graph(job: dict):
    """TODO (kickoff): build the LangGraph workflow for this job's task type."""
    raise NotImplementedError("Define the LangGraph workflow at kickoff")


async def process_job(r: redis.Redis, job: dict):
    job_id = job["job_id"]
    async with semaphore:
        try:
            result = await asyncio.wait_for(run_graph(job), timeout=JOB_TIMEOUT_SECONDS)
            await r.set(
                f"result:{job_id}",
                json.dumps({"status": "done", "result": result}),
                ex=RESULT_TTL_SECONDS,
            )
        except Exception as exc:  # noqa: BLE001 — boundary catch, reported to caller
            await r.set(
                f"result:{job_id}",
                json.dumps({"status": "error", "error": str(exc)}),
                ex=RESULT_TTL_SECONDS,
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
AI_WORKER_CONCURRENCY=5
AI_JOB_TIMEOUT=60
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
EOF

pip freeze > ai-worker/requirements.txt
deactivate
echo "==> AI Worker scaffolded (queue loop + guardrails wired, graph logic TODO at kickoff)"

# ============================================================================
# 4. BACKGROUND WORKER — async, non-AI tasks (PDF generation, etc.)
# ============================================================================
echo "==> [4/6] Scaffolding Background Worker"
mkdir -p background-worker
python3 -m venv background-worker/.venv
source background-worker/.venv/Scripts/activate
pip install --upgrade pip
pip install "redis[hiredis]" "psycopg[binary]" weasyprint pydantic \
  python-dotenv ruff pytest pytest-asyncio

cat > background-worker/main.py << 'EOF'
"""
Background Worker — consumes tasks_queue for non-AI async work
(e.g. PDF generation). Task handlers are registered at kickoff
once the domain is known; this file is the infra skeleton.
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
    # "generate_pdf": handle_generate_pdf,  # registered at kickoff
}


async def process_job(r: redis.Redis, job: dict):
    job_id = job["job_id"]
    handler = TASK_HANDLERS.get(job.get("type"))
    if handler is None:
        await r.set(
            f"result:{job_id}",
            json.dumps({"status": "error", "error": f"unknown task type: {job.get('type')}"}),
            ex=RESULT_TTL_SECONDS,
        )
        return
    try:
        result = await handler(job)
        await r.set(
            f"result:{job_id}",
            json.dumps({"status": "done", "result": result}),
            ex=RESULT_TTL_SECONDS,
        )
    except Exception as exc:  # noqa: BLE001 — boundary catch, reported to caller
        await r.set(
            f"result:{job_id}",
            json.dumps({"status": "error", "error": str(exc)}),
            ex=RESULT_TTL_SECONDS,
        )


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
EOF

pip freeze > background-worker/requirements.txt
deactivate
echo "==> Background Worker scaffolded (queue loop wired, task handlers TODO at kickoff)"

# ============================================================================
# 5. DOCKER — Dockerfiles + docker-compose.yml
# ============================================================================
echo "==> [5/6] Writing Dockerfiles and docker-compose.yml"

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

cat > ai-worker/Dockerfile << 'EOF'
FROM python:3.12-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev gcc \
  && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "main.py"]
EOF

cat > background-worker/Dockerfile << 'EOF'
FROM python:3.12-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends \
  libpq-dev gcc libpango-1.0-0 libpangocairo-1.0-0 libcairo2 \
  libgdk-pixbuf2.0-0 libffi-dev shared-mime-info \
  && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "main.py"]
EOF

cat > docker-compose.yml << 'EOF'
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
    build: ./ai-worker
    env_file: .env
    environment:
      REDIS_URL: redis://redis:6379/0
      POSTGRES_HOST: postgres
    depends_on:
      - redis
      - postgres

  background-worker:
    build: ./background-worker
    env_file: .env
    environment:
      REDIS_URL: redis://redis:6379/0
      POSTGRES_HOST: postgres
    depends_on:
      - redis
      - postgres

  frontend:
    build: ./frontend
    ports:
      - "5173:3000"
    depends_on:
      - main-service

volumes:
  pgdata:
EOF

echo "==> Docker setup written (ai-worker has no container_name — scale it with --scale ai-worker=3)"

# ============================================================================
# 6. ROOT FILES — .env.example, .gitignore, SETUP.md, git init
# ============================================================================
echo "==> [6/6] Writing root files and initializing git"

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
EOF

cat > SETUP.md << 'EOF'
# Local Setup

This is the scaffold reference, not the final project README
(that's a Phase 8 deliverable — see docs/documentation-guide.md).

1. Copy `.env.example` to `.env` and fill in real values (LLM API keys especially).
2. Place the pre-hackathon docs into `docs/`:
   architecture.md, sdlc.md, coding-guidelines.md, testing-guidelines.md,
   documentation-guide.md, ux-guide.md, ui-guide.md
3. Build and run everything (3 AI worker replicas, per architecture.md):
   docker-compose up -d --build --scale ai-worker=3
4. Apply migrations:
   docker-compose exec main-service python manage.py migrate
5. Create an admin user (Django Admin is where prompts / model config /
   fallback chains get edited — see docs/architecture.md, Dynamic Configuration):
   docker-compose exec main-service python manage.py createsuperuser
6. Verify:
   - http://localhost:8000/health
   - http://localhost:8000/docs   (Swagger UI)
   - http://localhost:5173        (frontend)
EOF

echo ""
echo "============================================================"
echo " Done. Project scaffolded at ./$PROJECT_NAME"
echo ""
echo " Next steps:"
echo "  1. cd $PROJECT_NAME"
echo "  2. Drop the 7 doc files into docs/"
echo "  3. cp .env.example .env   (then fill in real secrets/keys)"
echo "  4. docker-compose up -d --build --scale ai-worker=3"
echo "  5. docker-compose exec main-service python manage.py migrate"
echo "  6. docker-compose exec main-service python manage.py createsuperuser"
echo "============================================================"
