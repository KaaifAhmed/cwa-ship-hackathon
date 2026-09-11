#Requires -Version 5.1
<#
============================================================================
 CWA Ship Karachi 2026 - Project Bootstrap (Windows / PowerShell, v3)

 Scaffolds architecture.md: frontend / main-service (Django, Auth+Core) /
 ai-worker (LangGraph+LangChain+LiteLLM) / background-worker /
 whatsapp-service (Express + TypeScript, Baileys) / compose.yaml

 Usage:
   bootstrap.bat [project-name]
   (or directly: powershell -ExecutionPolicy Bypass -File bootstrap.ps1 -ProjectName myproj)

 Requires: git, python (3.11+, on PATH as "python"), node/npm (20+),
 Docker Desktop with the `docker compose` plugin (v2 - NOT the standalone
 docker-compose.exe)
============================================================================
#>

param(
    [string]$ProjectName = "cwa-hackathon"
)

$ErrorActionPreference = "Stop"

function Invoke-Native {
    <# Runs a native command and throws if it exits non-zero, mirroring bash's `set -e`. #>
    param([Parameter(Mandatory)][string]$Command)
    Write-Host ">> $Command"
    & cmd /c $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed (exit $LASTEXITCODE): $Command"
    }
}

Write-Host "==> Bootstrapping project: $ProjectName"
New-Item -ItemType Directory -Force -Path $ProjectName | Out-Null
Set-Location $ProjectName
New-Item -ItemType Directory -Force -Path "docs", "shared" | Out-Null
New-Item -ItemType File -Force -Path "shared\__init__.py" | Out-Null

# ----------------------------------------------------------------------------
# Stage completion checks (mirrors stage_done() in the bash version)
# ----------------------------------------------------------------------------
function Stage-Done {
    param([int]$Stage)
    switch ($Stage) {
        1 { return (Test-Path "frontend\package.json") -and (Test-Path "frontend\vite.config.ts") }
        2 { return (Test-Path "main-service\manage.py") -and (Test-Path "main-service\requirements.txt") }
        3 { return (Test-Path "ai-worker\main.py") -and (Test-Path "ai-worker\requirements.txt") }
        4 { return (Test-Path "background-worker\main.py") -and (Test-Path "background-worker\requirements.txt") }
        5 { return (Test-Path "shared\security_guards.py") -and (Test-Path "shared\whatsapp_client.py") }
        6 {
            return (Test-Path "whatsapp-service\src\server.ts") -and (Test-Path "whatsapp-service\src\whatsapp.ts") `
                -and (Test-Path "whatsapp-service\src\config.ts") -and (Test-Path "whatsapp-service\package.json") `
                -and (Test-Path "whatsapp-service\tsconfig.json")
        }
        7 {
            return (Test-Path "compose.yaml") -and (Test-Path ".env.example") -and (Test-Path ".gitignore") `
                -and (Test-Path "SETUP.md") -and (Test-Path "frontend\Dockerfile") `
                -and (Test-Path "main-service\Dockerfile") -and (Test-Path "ai-worker\Dockerfile") `
                -and (Test-Path "background-worker\Dockerfile") -and (Test-Path "whatsapp-service\Dockerfile") `
                -and (Test-Path ".git")
        }
        default { return $false }
    }
}

# ============================================================================
# 1. FRONTEND - React + Vite + TypeScript + Tailwind
# ============================================================================
if (Stage-Done 1) {
    Write-Host "==> [1/7] Already complete; skipping"
} else {
    Write-Host "==> [1/7] Scaffolding frontend"
    Invoke-Native "npm create vite@latest frontend -- --template react-ts"
    Push-Location frontend
    Invoke-Native "npm install"
    Invoke-Native "npm install react-router-dom"
    Invoke-Native "npm install tailwindcss @tailwindcss/vite"

    @'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
})
'@ | Set-Content -Path "vite.config.ts" -Encoding UTF8

    $existingCss = Get-Content "src\index.css" -Raw -ErrorAction SilentlyContinue
    ('@import "tailwindcss";' + "`r`n" + $existingCss) | Set-Content -Path "src\index.css" -Encoding UTF8

    "VITE_API_URL=http://localhost:8000" | Set-Content -Path ".env.example" -Encoding UTF8
    Copy-Item ".env.example" ".env" -Force
    Pop-Location
}

# ============================================================================
# 2. MAIN SERVICE - Django (Auth + Core, only component touching Postgres)
# ============================================================================
if (Stage-Done 2) {
    Write-Host "==> [2/7] Already complete; skipping"
} else {
    Write-Host "==> [2/7] Scaffolding Main Service (Django)"

    Invoke-Native "python -m venv main-service\.venv"
    $venvPython = "main-service\.venv\Scripts\python.exe"
    $venvPip = "main-service\.venv\Scripts\pip.exe"

    Invoke-Native "$venvPython -m pip install --upgrade pip"
    Invoke-Native "$venvPip install django djangorestframework djangorestframework-simplejwt django-cors-headers drf-spectacular ""psycopg[binary]"" python-dotenv pgvector gunicorn ruff pytest pytest-django ""redis[hiredis]"""

    Push-Location main-service
    $venvPythonRel = ".venv\Scripts\python.exe"
    $venvPipRel = ".venv\Scripts\pip.exe"

    Invoke-Native "$venvPythonRel -m django startproject config ."
    Invoke-Native "$venvPythonRel manage.py startapp users"
    Invoke-Native "$venvPythonRel manage.py startapp core"

    @'
import os
from datetime import timedelta
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()
BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-secret-key-change-me")
DEBUG = os.environ.get("DEBUG", "True") == "True"
ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "*").split(",")
CSRF_TRUSTED_ORIGINS = os.environ.get("CSRF_TRUSTED_ORIGINS", "http://localhost:5173").split(",")


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

MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
'@ | Set-Content -Path "config\settings.py" -Encoding UTF8

    @'
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
'@ | Set-Content -Path "config\urls.py" -Encoding UTF8

    # --- users app: register/login/refresh/me + phone_number candidate key ---
    @'
from django.contrib.auth.models import User
from django.db import models


class UserProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="profile")
    phone_number = models.CharField(max_length=20, unique=True, blank=True, null=True)

    def __str__(self):
        return f"{self.user.username} ({self.phone_number})"
'@ | Set-Content -Path "users\models.py" -Encoding UTF8

    @'
from django.contrib import admin
from .models import UserProfile

admin.site.register(UserProfile)
'@ | Set-Content -Path "users\admin.py" -Encoding UTF8

    @'
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
'@ | Set-Content -Path "users\serializers.py" -Encoding UTF8

    @'
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
'@ | Set-Content -Path "users\views.py" -Encoding UTF8

    @'
from django.urls import path
from .views import EnvelopeTokenObtainPairView, EnvelopeTokenRefreshView, MeView, RegisterView

urlpatterns = [
    path("register", RegisterView.as_view()),
    path("login", EnvelopeTokenObtainPairView.as_view()),
    path("refresh", EnvelopeTokenRefreshView.as_view()),
    path("me", MeView.as_view()),
]
'@ | Set-Content -Path "users\urls.py" -Encoding UTF8

    # --- core app: AI config + WhatsApp inbound endpoints (stubs - real logic at kickoff) ---
    @'
import json
import uuid
import os

import redis
from django.conf import settings
from django.http import JsonResponse , FileResponse
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny


# Redis connection
redis_client = redis.from_url(
    settings.REDIS_URL,
    decode_responses=True,
)


def envelope(data=None, error=None):
    return {
        "success": error is None,
        "data": data,
        "error": error,
    }


@api_view(["GET"])
@permission_classes([AllowAny])
def ai_config(request):
    return JsonResponse({
        "success": True,
        "data": {
            "tiers": {
                "fast": None,
                "smart": None,
            },
            "fallback_order": [],
        },
        "error": None,
    })

from rest_framework.response import Response


@api_view(["POST"])
@permission_classes([AllowAny])
def whatsapp_inbound(request):
    data = request.data
    print("here")

    phone = data.get("from")
    jid = data.get("jid")
    sender_name = data.get("senderName")
    text = data.get("text", "")
    message_id = data.get("messageId")
    timestamp = data.get("timestamp")

    if not phone:
        return Response(
            {
                "success": False,
                "error": "from is required"
            },
            status=404
        )

    if not text:
        return Response(
            {
                "success": False,
                "error": "text is required"
            },
            status=404
        )


@api_view(["POST"])
@permission_classes([AllowAny])
def log_ai_call(request):
    print(f"[ai_call telemetry] {request.data}")

    return JsonResponse({
        "success": True,
        "data": {
            "logged": True,
        },
        "error": None,
    })


# ============================================================
# TEST JOB API
# ============================================================

@api_view(["POST"])
@permission_classes([AllowAny])
def create_test_job(request):
    """
    Creates a test job and pushes it into Redis ai_queue.
    """

    job_id = str(uuid.uuid4())

    message = request.data.get("message", "Hello from Postman")

    job = {
        "job_id": job_id,
        "type": "test",
        "agent_role": "responder",
        "input": message,
    }

    # Push job into Redis queue
    redis_client.rpush(
        "ai_queue",
        json.dumps(job),
    )

    print(f"[TEST] Job pushed to Redis: {job_id}")

    return JsonResponse(
        envelope(
            data={
                "job_id": job_id,
                "status": "queued",
                "message": message,
            }
        ),
        status=202,
    )


@api_view(["GET"])
@permission_classes([AllowAny])
def get_test_job(request, job_id):
    """
    Gets the result produced by the worker.
    """

    result = redis_client.get(f"result:{job_id}")

    if result is None:
        return JsonResponse(
            envelope(
                data={
                    "job_id": job_id,
                    "status": "processing",
                }
            ),
            status=202,
        )

    return JsonResponse(
        envelope(
            data=json.loads(result)
        )
    )


@api_view(["POST"])
@permission_classes([AllowAny])
def worker_result(request, job_id):
    """
    Worker calls this endpoint after completing a job.
    """

    payload = request.data

    result = {
        "status": payload.get("status", "done"),
        "result": payload.get("result"),
    }

    redis_client.set(
        f"result:{job_id}",
        json.dumps(result),
        ex=3600,
    )

    print(f"[TEST] Worker result received for job: {job_id}")

    return JsonResponse(
        envelope(
            data={
                "job_id": job_id,
                "received": True,
            }
        )
    )

# ============================================================
# PDF JOB API
# ============================================================

@api_view(["POST"])
@permission_classes([AllowAny])
def create_pdf_job(request):
    """
    Creates a PDF generation job and pushes it to tasks_queue.
    """

    job_id = str(uuid.uuid4())

    name = request.data.get("name", "Hamza")
    message = request.data.get(
        "message",
        "Hello from CWA Ship Karachi 2026"
    )

    job = {
        "job_id": job_id,
        "type": "generate_pdf",
        "input": {
            "name": name,
            "message": message,
        },
    }

    redis_client.rpush(
        "tasks_queue",
        json.dumps(job),
    )

    print(f"[PDF] Job pushed to Redis: {job_id}")

    return JsonResponse(
        envelope(
            data={
                "job_id": job_id,
                "status": "queued",
            }
        ),
        status=202,
    )

@api_view(["GET"])
@permission_classes([AllowAny])
def get_pdf_job(request, job_id):
    """
    Returns PDF job status.
    """

    result = redis_client.get(
        f"result:{job_id}"
    )

    if result is None:
        return JsonResponse(
            envelope(
                data={
                    "job_id": job_id,
                    "status": "processing",
                }
            ),
            status=202,
        )

    data = json.loads(result)

    return JsonResponse(
        envelope(
            data={
                "job_id": job_id,
                **data,
            }
        )
    )

@api_view(["GET"])
@permission_classes([AllowAny])
def download_pdf(request, job_id):
    """
    Downloads the PDF generated by the worker.

    AllowAny is intentional for the hackathon test.
    Later replace with IsAuthenticated + ownership check.
    """

    result = redis_client.get(
        f"result:{job_id}"
    )

    if result is None:
        return JsonResponse(
            {
                "success": False,
                "data": None,
                "error": {
                    "code": "job_not_found",
                    "message": "Job is still processing or does not exist",
                },
            },
            status=404,
        )

    data = json.loads(result)

    if data.get("status") != "done":
        return JsonResponse(
            {
                "success": False,
                "data": None,
                "error": {
                    "code": "job_not_completed",
                    "message": "PDF is not ready yet",
                },
            },
            status=409,
        )

    file_path = data.get("file_path")

    if not file_path:
        return JsonResponse(
            {
                "success": False,
                "data": None,
                "error": {
                    "code": "file_missing",
                    "message": "PDF path not available",
                },
            },
            status=404,
        )

    if not os.path.exists(file_path):
        return JsonResponse(
            {
                "success": False,
                "data": None,
                "error": {
                    "code": "file_not_found",
                    "message": "PDF file does not exist",
                },
            },
            status=404,
        )

    return FileResponse(
        open(file_path, "rb"),
        content_type="application/pdf",
        as_attachment=True,
        filename=f"{job_id}.pdf",
    )

@api_view(["POST"])
@permission_classes([AllowAny])
def worker_pdf_result(request, job_id):
    """
    Background worker uploads the generated PDF here.

    The worker sends:
        multipart/form-data
        file=<pdf>

    Django stores the file locally.
    """

    uploaded_file = request.FILES.get("file")

    if not uploaded_file:
        return JsonResponse(
            {
                "success": False,
                "data": None,
                "error": {
                    "code": "file_missing",
                    "message": "No PDF file received",
                },
            },
            status=400,
        )

    # Create directory:
    # /app/media/jobs/
    jobs_dir = os.path.join(
        settings.MEDIA_ROOT,
        "jobs",
    )

    os.makedirs(
        jobs_dir,
        exist_ok=True,
    )

    file_path = os.path.join(
        jobs_dir,
        f"{job_id}.pdf",
    )

    # Save uploaded PDF
    with open(file_path, "wb+") as destination:
        for chunk in uploaded_file.chunks():
            destination.write(chunk)

    result_payload = {
        "status": "done",
        "file_path": file_path,
        "filename": uploaded_file.name,
        "content_type": uploaded_file.content_type,
    }

    # Save job result
    redis_client.set(
        f"result:{job_id}",
        json.dumps(result_payload),
        ex=3600,
    )

    print(
        f"[PDF] Worker uploaded PDF for job: {job_id}"
    )

    return JsonResponse(
        envelope(
            data={
                "job_id": job_id,
                "status": "done",
                "received": True,
            }
        )
    )




'@ | Set-Content -Path "core\views.py" -Encoding UTF8

    @'
from django.urls import path

from .views import (
    ai_config,
    create_test_job,
    get_test_job,
    log_ai_call,
    whatsapp_inbound,
    worker_result,

    create_pdf_job,
    get_pdf_job,
    download_pdf,
    worker_pdf_result,
)


urlpatterns = [
    path("internal/ai-config", ai_config),
    path("internal/ai-calls", log_ai_call),

    path("whatsapp/inbound", whatsapp_inbound),

    # Test worker system
    path("test-job", create_test_job),
    path("test-job/<str:job_id>", get_test_job),

    # Worker -> Django callback
    path(
        "internal/worker-result/<str:job_id>",
        worker_result,
    ),

    # ========================================================
    # PDF JOB
    # ========================================================

    path(
        "pdf-job",
        create_pdf_job
    ),

    path(
        "pdf-job/<str:job_id>",
        get_pdf_job
    ),

    path(
        "pdf-job/<str:job_id>/download",
        download_pdf
    ),

    # Worker -> Django PDF upload
    path(
        "internal/worker-pdf-result/<str:job_id>",
        worker_pdf_result
    ),
    path("whatsapp/inbound" , whatsapp_inbound, name="whatsapp_inbound"),
]


'@ | Set-Content -Path "core\urls.py" -Encoding UTF8

    @'
[pytest]
DJANGO_SETTINGS_MODULE = config.settings
python_files = tests.py test_*.py *_tests.py
'@ | Set-Content -Path "pytest.ini" -Encoding UTF8

    @'
DJANGO_SECRET_KEY=change-me
DEBUG=True
ALLOWED_HOSTS=*
POSTGRES_DB=main_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
CORS_ALLOWED_ORIGINS=http://localhost:5173
CSRF_TRUSTED_ORIGINS = http://localhost:5173
REDIS_URL=redis://redis_server:6379/0
'@ | Set-Content -Path ".env.example" -Encoding UTF8
    Copy-Item ".env.example" ".env" -Force

    Invoke-Native "$venvPythonRel manage.py makemigrations users"
    Invoke-Native "$venvPipRel freeze > requirements.txt"
    Pop-Location
    Write-Host "==> Main Service scaffolded (auth working, phone_number field, AI-config + WhatsApp-inbound stubs)"
}

# ============================================================================
# 3. AI WORKER - async, LangGraph/LangChain/LiteLLM, no direct DB access
# ============================================================================
if (Stage-Done 3) {
    Write-Host "==> [3/7] Already complete; skipping"
} else {
    Write-Host "==> [3/7] Scaffolding AI Worker"
    New-Item -ItemType Directory -Force -Path "ai-worker" | Out-Null
    Invoke-Native "python -m venv ai-worker\.venv"
    $venvPython = "ai-worker\.venv\Scripts\python.exe"
    $venvPip = "ai-worker\.venv\Scripts\pip.exe"

    Invoke-Native "$venvPython -m pip install --upgrade pip"
    Invoke-Native "$venvPip install langgraph langchain langchain-litellm litellm ""redis[hiredis]"" httpx pydantic python-dotenv ruff pytest pytest-asyncio"

    @'
"""
AI Worker - consumes ai_queue, orchestrates via LangGraph/LangChain,
calls models via LiteLLM (docs/ai-system.md).

Infra skeleton: queue loop, concurrency cap, timeout, retry, heartbeat,
AI-config fetch, agent roles (PLA/RBAC), input/output guards, and
telemetry - all decided pre-hackathon per docs/ai-system.md. The
LangGraph workflow in run_graph() is domain-specific, defined at kickoff.
"""
import asyncio
import json
import os
import time

import httpx
import redis.asyncio as redis
from redis.exceptions import TimeoutError as RedisTimeoutError  # Added for exception handling
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
JOB_CALLBACK_URL = os.environ.get(
    "JOB_CALLBACK_URL",
    "http://main-service:8000/api/internal/worker-result"
)

semaphore = asyncio.Semaphore(CONCURRENCY_LIMIT)
_config_cache = {"data": None, "fetched_at": 0.0}

# --- Agent roles (RBAC) - docs/ai-system.md par 4.2. Code, not Dynamic
# Config: permissions shouldn't be one Django-Admin click away from
# being loosened. Tool names filled in at kickoff; each graph node is
# bound to exactly one role's tool list, never the full registry.
AGENT_ROLES = {
    "retriever":       {"tools": [], "can_act_externally": False},
    "responder":       {"tools": [], "can_act_externally": False},
    "action_executor": {"tools": [], "can_act_externally": True},
}


async def get_ai_config() -> dict:
    """Fetched from Main Service, not Postgres directly - cached briefly to avoid a round-trip per call."""
    now = time.time()
    if _config_cache["data"] is None or now - _config_cache["fetched_at"] > CONFIG_CACHE_TTL_SECONDS:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{MAIN_SERVICE_URL}/api/internal/ai-config")
            response.raise_for_status()
            _config_cache["data"] = response.json()["data"]
            _config_cache["fetched_at"] = now
    return _config_cache["data"]


async def log_ai_call(**fields) -> None:
    """Telemetry - docs/ai-system.md par 4.4/6.2. Posted to Main Service, not
    written to Postgres directly (only Main Service touches Postgres)."""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            await client.post(f"{MAIN_SERVICE_URL}/api/internal/ai-calls", json=fields)
    except Exception as exc:  # noqa: BLE001 - telemetry failure must never break the job
        print(f"telemetry log failed (non-fatal): {exc}")



async def run_graph(job: dict, role: str):
    """
    Temporary test task.

    Later this function will contain the real LangGraph workflow.
    """

    if job.get("type") == "test":
        message = job.get("input", "")

        # Simulate doing some work
        await asyncio.sleep(3)

        return {
            "message": f"Worker successfully processed: {message}",
            "worker": "ai-worker",
            "task_type": "test",
            "processed": True,
        }

    raise ValueError(
        f"Unknown job type: {job.get('type')}"
    )





async def process_job(r: redis.Redis, job: dict):
    job_id = job["job_id"]
    agent_role = job.get("agent_role", "responder")

    started_at = time.time()

    async with semaphore:
        try:
            print(f"[WORKER] Processing job: {job_id}")

            # -----------------------------
            # Input security check
            # -----------------------------

            guard = input_guard(
                job.get("input", "")
            )

            if not guard["ok"]:
                raise ValueError(
                    f"input rejected: {guard['reason']}"
                )

            if guard.get("flagged"):
                print(
                    f"[security] input flagged for job "
                    f"{job_id}: {guard['reason']}"
                )

            # -----------------------------
            # Run worker task
            # -----------------------------

            result = await asyncio.wait_for(
                run_graph(
                    job,
                    role=agent_role,
                ),
                timeout=JOB_TIMEOUT_SECONDS,
            )

            out_text = (
                result
                if isinstance(result, str)
                else json.dumps(result)
            )

            # -----------------------------
            # Output security check
            # -----------------------------

            out_guard = output_guard(out_text)

            if not out_guard["ok"]:
                raise ValueError(
                    f"output blocked: {out_guard['reason']}"
                )

            # -----------------------------
            # Save result in Redis
            # -----------------------------

            result_payload = {
                "status": "done",
                "result": result,
            }

            await r.set(
                f"result:{job_id}",
                json.dumps(result_payload),
                ex=RESULT_TTL_SECONDS,
            )

            # -----------------------------
            # Send result back to Django
            # -----------------------------

            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.post(
                    f"{JOB_CALLBACK_URL}/{job_id}",
                    json=result_payload,
                )

                response.raise_for_status()

            latency = int(
                (time.time() - started_at) * 1000
            )

            print(
                f"[WORKER] Job {job_id} completed "
                f"in {latency}ms"
            )

            await log_ai_call(
                job_id=job_id,
                agent_role=agent_role,
                status="done",
                latency_ms=latency,
                flagged_input=guard.get(
                    "flagged",
                    False,
                ),
            )

        except Exception as exc:
            error_payload = {
                "status": "error",
                "error": str(exc),
            }

            # Save error in Redis
            await r.set(
                f"result:{job_id}",
                json.dumps(error_payload),
                ex=RESULT_TTL_SECONDS,
            )

            # Send error back to Django
            try:
                async with httpx.AsyncClient(
                    timeout=5.0
                ) as client:
                    await client.post(
                        f"{JOB_CALLBACK_URL}/{job_id}",
                        json=error_payload,
                    )
            except Exception as callback_error:
                print(
                    f"[WORKER] Callback failed: "
                    f"{callback_error}"
                )

            print(
                f"[WORKER] Job {job_id} failed: {exc}"
            )

            await log_ai_call(
                job_id=job_id,
                agent_role=agent_role,
                status="error",
                latency_ms=int(
                    (time.time() - started_at) * 1000
                ),
                error=str(exc),
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
        try:
            # Replaced the infinite block with a timeout to prevent socket hangs
            job_data = await r.blpop(QUEUE_NAME, timeout=5)

            # If the queue was empty for 5 seconds, loop and try again
            if not job_data:
                continue

            _, raw_job = job_data
            job = json.loads(raw_job)
            asyncio.create_task(process_job(r, job))

        except (RedisTimeoutError, TimeoutError):
            # Suppress socket timeouts and just restart the polling loop
            continue
        except Exception as e:
            # Catch transient network errors so the worker doesn't die completely
            print(f"Worker polling error: {e}")
            await asyncio.sleep(1)


if __name__ == "__main__":
    asyncio.run(main())
'@ | Set-Content -Path "ai-worker\main.py" -Encoding UTF8

    @'
REDIS_URL=redis://redis_server:6379/0
MAIN_SERVICE_URL=http://main-service:8000
WHATSAPP_SERVICE_URL=http://whatsapp-service:3001
AI_WORKER_CONCURRENCY=5
AI_JOB_TIMEOUT=60
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
'@ | Set-Content -Path "ai-worker\.env.example" -Encoding UTF8
    Copy-Item "ai-worker\.env.example" "ai-worker\.env" -Force

    Invoke-Native "$venvPip freeze > ai-worker\requirements.txt"
    Write-Host "==> AI Worker scaffolded"
}

# ============================================================================
# 4. BACKGROUND WORKER - async, non-AI tasks (PDF gen, WhatsApp notify, OTP)
# ============================================================================
if (Stage-Done 4) {
    Write-Host "==> [4/7] Already complete; skipping"
} else {
    Write-Host "==> [4/7] Scaffolding Background Worker"
    New-Item -ItemType Directory -Force -Path "background-worker" | Out-Null
    Invoke-Native "python -m venv background-worker\.venv"
    $venvPython = "background-worker\.venv\Scripts\python.exe"
    $venvPip = "background-worker\.venv\Scripts\pip.exe"

    Invoke-Native "$venvPython -m pip install --upgrade pip"
    Invoke-Native "$venvPip install ""redis[hiredis]"" httpx reportlab pydantic python-dotenv ruff pytest pytest-asyncio"

    @'
"""
Background Worker

Consumes tasks_queue.

Current implementation:
    generate_pdf

Worker generates PDF and uploads it to Django.
"""

import asyncio
import json
import os
import time

import httpx
import redis.asyncio as redis

from redis.exceptions import TimeoutError as RedisTimeoutError
from dotenv import load_dotenv

from reportlab.pdfgen import canvas

load_dotenv()


REDIS_URL = os.environ.get(
    "REDIS_URL",
    "redis://localhost:6379/0"
)

MAIN_SERVICE_URL = os.environ.get(
    "MAIN_SERVICE_URL",
    "http://main-service:8000"
)

QUEUE_NAME = "tasks_queue"

RESULT_TTL_SECONDS = 3600

HEARTBEAT_KEY = (
    f"heartbeat:background-worker:"
    f"{os.environ.get('HOSTNAME', 'unknown')}"
)


# ============================================================
# PDF GENERATION
# ============================================================

def generate_pdf(
    job_id: str,
    name: str,
    message: str,
) -> str:

    output_dir = "/tmp/generated_pdfs"

    os.makedirs(
        output_dir,
        exist_ok=True,
    )

    file_path = os.path.join(
        output_dir,
        f"{job_id}.pdf",
    )

    pdf = canvas.Canvas(
        file_path
    )

    pdf.setTitle(
        f"Job {job_id}"
    )

    pdf.setFont(
        "Helvetica-Bold",
        20,
    )

    pdf.drawString(
        100,
        750,
        "CWA Ship Karachi 2026",
    )

    pdf.setFont(
        "Helvetica",
        14,
    )

    pdf.drawString(
        100,
        700,
        f"Name: {name}",
    )

    pdf.drawString(
        100,
        670,
        f"Message: {message}",
    )

    pdf.drawString(
        100,
        620,
        f"Job ID: {job_id}",
    )

    pdf.drawString(
        100,
        570,
        "Generated by Background Worker",
    )

    pdf.save()

    return file_path


# ============================================================
# PROCESS JOB
# ============================================================

async def process_job(
    r: redis.Redis,
    job: dict,
):

    job_id = job["job_id"]

    task_type = job.get(
        "type"
    )

    try:

        print(
            f"[BACKGROUND WORKER] "
            f"Processing job: {job_id}"
        )

        # ====================================================
        # GENERATE PDF
        # ====================================================

        if task_type == "generate_pdf":

            input_data = job.get(
                "input",
                {}
            )

            name = input_data.get(
                "name",
                "Unknown"
            )

            message = input_data.get(
                "message",
                "Hello"
            )

            file_path = generate_pdf(
                job_id=job_id,
                name=name,
                message=message,
            )

            print(
                f"[PDF] Generated: {file_path}"
            )

            # =================================================
            # SEND PDF TO DJANGO
            # =================================================

            callback_url = (
                f"{MAIN_SERVICE_URL}"
                f"/api/internal/"
                f"worker-pdf-result/"
                f"{job_id}"
            )

            async with httpx.AsyncClient(
                timeout=30
            ) as client:

                with open(
                    file_path,
                    "rb"
                ) as pdf_file:

                    response = await client.post(
                        callback_url,

                        files={
                            "file": (
                                f"{job_id}.pdf",
                                pdf_file,
                                "application/pdf",
                            )
                        },
                    )

                response.raise_for_status()

            print(
                f"[PDF] Uploaded to Django: "
                f"{job_id}"
            )

            # =================================================
            # DON'T STORE THE WORKER PATH
            # =================================================
            #
            # Django now owns the PDF.
            #
            # We only store metadata in Redis.


            print(
                f"[BACKGROUND WORKER] "
                f"Completed: {job_id}"
            )

            return

        # ====================================================
        # UNKNOWN JOB
        # ====================================================

        raise ValueError(
            f"Unknown task type: {task_type}"
        )

    except Exception as exc:

        print(
            f"[BACKGROUND WORKER] "
            f"Job failed: {job_id}: {exc}"
        )

        await r.set(
            f"result:{job_id}",

            json.dumps(
                {
                    "status": "error",
                    "error": str(exc),
                }
            ),

            ex=RESULT_TTL_SECONDS,
        )


# ============================================================
# HEARTBEAT
# ============================================================

async def heartbeat_loop(
    r: redis.Redis
):

    while True:

        await r.set(
            HEARTBEAT_KEY,
            str(time.time()),
            ex=15,
        )

        await asyncio.sleep(5)


# ============================================================
# MAIN LOOP
# ============================================================

async def main():

    r = redis.from_url(
        REDIS_URL
    )

    asyncio.create_task(
        heartbeat_loop(r)
    )

    print(
        f"Background worker started, "
        f"listening on '{QUEUE_NAME}'"
    )

    while True:

        try:

            job_data = await r.blpop(
                QUEUE_NAME,
                timeout=5,
            )

            if not job_data:
                continue

            _, raw_job = job_data

            job = json.loads(
                raw_job
            )

            asyncio.create_task(
                process_job(
                    r,
                    job,
                )
            )

        except (
            RedisTimeoutError,
            TimeoutError,
        ):

            continue

        except Exception as exc:

            print(
                f"Worker polling error: {exc}"
            )

            await asyncio.sleep(1)


if __name__ == "__main__":

    asyncio.run(
        main()
    )
'@ | Set-Content -Path "background-worker\main.py" -Encoding UTF8

    @'
REDIS_URL=redis://redis_server:6379/0
MAIN_SERVICE_URL=http://main-service:8000
WHATSAPP_SERVICE_URL=http://whatsapp-service:3001
'@ | Set-Content -Path "background-worker\.env.example" -Encoding UTF8
    Copy-Item "background-worker\.env.example" "background-worker\.env" -Force

    Invoke-Native "$venvPip freeze > background-worker\requirements.txt"
    Write-Host "==> Background Worker scaffolded"
}

# ============================================================================
# 5. SHARED - security guards + WhatsApp HTTP client, imported by both workers
# ============================================================================
if (Stage-Done 5) {
    Write-Host "==> [5/7] Already complete; skipping"
} else {
    Write-Host "==> [5/7] Writing shared security guards + WhatsApp client"

    @'
"""
Input/output guards for AI-generated content - docs/ai-system.md par 5.1.
Imported by ai-worker and background-worker. Anything reaching an
external channel (WhatsApp) or stored as a job result goes through
these first. Pattern-based, not a full injection/DLP scanner - flags
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
    hard-blocking - tighten to a hard block at kickoff if the theme's
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
'@ | Set-Content -Path "shared\security_guards.py" -Encoding UTF8

    @'
"""
Shared HTTP client for the WhatsApp Service's outbound send endpoint.
Imported directly by ai-worker and background-worker (see architecture.md --
outbound goes worker -> WhatsApp Service directly, never through Main Service).

Every send is gated by the output guard (docs/ai-system.md par 5.1) here,
at the choke point - so no call site can forget the check.

The gateway itself now exposes both POST /whatsapp/send and the legacy alias
POST /api/whatsapp/send, and accepts {to|phone|recipient} / {message|text} -
we send the canonical {phone, text} shape shown below.
"""
import os
import httpx

from shared.security_guards import output_guard

WHATSAPP_SERVICE_URL = os.environ.get("WHATSAPP_SERVICE_URL", "http://whatsapp-service:3000")


async def send_whatsapp_message(phone: str, text: str) -> dict:
    guard = output_guard(text)
    if not guard["ok"]:
        raise ValueError(f"blocked by output guard: {guard['reason']}")

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(f"{WHATSAPP_SERVICE_URL}/whatsapp/send", json={"phone": phone, "text": text})
        response.raise_for_status()
        return response.json()
'@ | Set-Content -Path "shared\whatsapp_client.py" -Encoding UTF8
}

# ============================================================================
# 6. WHATSAPP SERVICE - Express + TypeScript, Baileys, unofficial library
# ============================================================================
if (Stage-Done 6) {
    Write-Host "==> [6/7] Already complete; skipping"
} else {
    Write-Host "==> [6/7] Scaffolding WhatsApp Service (TypeScript / Express)"
    New-Item -ItemType Directory -Force -Path "whatsapp-service\src" | Out-Null
    Push-Location whatsapp-service

    @'
{
  "name": "whatsapp_geteway",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "dev": "tsx src/server.ts",
    "build": "tsc",
    "start": "npm run build && node dist/server.js"
  },
  "keywords": [],
  "author": "",
  "license": "ISC",
  "type": "module",
  "dependencies": {
    "@hapi/boom": "^10.0.1",
    "@whiskeysockets/baileys": "^7.0.0-rc14",
    "axios": "^1.19.0",
    "dotenv": "^17.4.2",
    "express": "^5.2.1",
    "pino": "^10.3.1",
    "qrcode-terminal": "^0.12.0"
  },
  "devDependencies": {
    "@types/express": "^5.0.6",
    "@types/node": "^26.2.0",
    "@types/qrcode-terminal": "^0.12.2",
    "tsx": "^4.23.12",
    "typescript": "^7.0.2"
  }
}
'@ | Set-Content -Path "package.json" -Encoding UTF8

    @'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
'@ | Set-Content -Path "tsconfig.json" -Encoding UTF8

    @'
import dotenv from "dotenv";

dotenv.config();

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

const port = Number(requiredEnv("PORT"));

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be an integer between 1 and 65535");
}

export const config = {
  port,
  authDir: requiredEnv("AUTH_DIR"),
  mainServiceInboundUrl: requiredEnv("MAIN_SERVICE_INBOUND_URL"),
};
'@ | Set-Content -Path "src\config.ts" -Encoding UTF8

    @'
import makeWASocket, {
  DisconnectReason,
  useMultiFileAuthState,
  WASocket,
} from "@whiskeysockets/baileys";
import { Boom } from "@hapi/boom";
import qrcode from "qrcode-terminal";
import pino from "pino";
import axios from "axios";
import fs from "fs";

import { config } from "./config.js";

class WhatsAppService {
  private sock: WASocket | null = null;
  private qr: string | null = null;
  private isConnecting = false;

  public isConnected(): boolean {
    return Boolean(this.sock && this.sock.user);
  }

  public getQr(): string | null {
    return this.isConnected() ? null : this.qr;
  }

  public getUser() {
    if (!this.sock?.user) return null;
    return {
      id: this.sock.user.id,
      phone: this.sock.user.id?.split(":")?.[0] || this.sock.user.id,
      name: this.sock.user.name || null,
    };
  }

  public async init(): Promise<void> {
    if (this.isConnecting) return;
    this.isConnecting = true;

    try {
      const { state, saveCreds } = await useMultiFileAuthState(config.authDir);

      this.sock = makeWASocket({
        auth: state,
        logger: pino({ level: "silent" }),
        markOnlineOnConnect: false,
      });

      this.sock.ev.on("creds.update", saveCreds);

      this.sock.ev.on("connection.update", (update) => {
        const { connection, lastDisconnect, qr } = update;

        if (qr) {
          this.qr = qr;
          console.log("\n====================================");
          console.log("SCAN THIS QR CODE WITH WHATSAPP:");
          console.log("====================================");
          qrcode.generate(qr, { small: true });
          console.log("Raw QR String available at GET /qr\n");
        }

        if (connection === "open") {
          console.log("Connected as:", this.sock?.user?.id);
          this.qr = null;
          this.isConnecting = false;
        }

        if (connection === "close") {
          this.isConnecting = false;
          this.sock = null;

          const statusCode = (lastDisconnect?.error as Boom)?.output?.statusCode;
          console.log(`WhatsApp disconnected (status code: ${statusCode || "unknown"})`);

          if (statusCode === DisconnectReason.loggedOut) {
            console.log("Logged out. Resetting auth directory for new QR generation.");
            this.qr = null;
            try {
              fs.rmSync(config.authDir, { recursive: true, force: true });
            } catch (err) {
              console.error("Error clearing auth directory:", err);
            }
            setTimeout(() => this.init(), 3000);
            return;
          }

          console.log("Reconnecting in 5 seconds...");
          setTimeout(() => this.init(), 5000);
        }
      });

      this.sock.ev.on("messages.upsert", async ({ messages }) => {
        for (const msg of messages) {
          await this.handleInboundMessage(msg);
        }
      });
    } catch (error) {
      this.isConnecting = false;
      this.sock = null;
      console.error("Failed to initialize WhatsApp connection:", error);
      setTimeout(() => this.init(), 5000);
    }
  }

  private async handleInboundMessage(msg: any): Promise<void> {
    try {
      if (!msg.message || msg.key.fromMe) return;

      const remoteJid = msg.key.remoteJid || "";

      // 1-on-1 direct messaging only: ignore groups & status broadcasts
      if (remoteJid.endsWith("@g.us") || remoteJid.includes("broadcast")) return;

      const text =
        msg.message.conversation ||
        msg.message.extendedTextMessage?.text ||
        msg.message.imageMessage?.caption ||
        msg.message.videoMessage?.caption ||
        "";

      const phone = remoteJid.replace("@s.whatsapp.net", "");

      const payload = {
        from: phone,
        jid: remoteJid,
        senderName: msg.pushName || null,
        text,
        messageId: msg.key.id,
        timestamp: Number(msg.messageTimestamp),
      };

      console.log(`Inbound message from ${phone}: "${text.slice(0, 60)}"`);

      await axios.post(config.mainServiceInboundUrl, payload, { timeout: 5000 });
    } catch (error: any) {
      if (error.config?.url) {
        console.error(
          `Failed to dispatch inbound message to ${config.mainServiceInboundUrl}:`,
          error.message
        );
      } else {
        console.error("Error processing inbound message:", error);
      }
    }
  }

  public async sendMessage(
    to: string,
    message: string
  ): Promise<{ messageId: string | null; to: string }> {
    if (!this.sock || !this.sock.user) {
      const err: any = new Error("WhatsApp is not connected or authenticated.");
      err.statusCode = 503;
      throw err;
    }

    const digits = to.replace(/[^0-9]/g, "");
    if (!digits) {
      const err: any = new Error("Invalid phone number provided.");
      err.statusCode = 400;
      throw err;
    }

    const jid = to.includes("@") ? to : `${digits}@s.whatsapp.net`;
    const result = await this.sock.sendMessage(jid, { text: message });

    console.log(`Outbound message sent to ${digits} (ID: ${result?.key?.id})`);

    return {
      messageId: result?.key?.id || null,
      to: digits,
    };
  }
}

export const whatsapp = new WhatsAppService();
'@ | Set-Content -Path "src\whatsapp.ts" -Encoding UTF8

    @'
import express, { Request, Response } from "express";
import { config } from "./config.js";
import { whatsapp } from "./whatsapp.js";

const app = express();
app.use(express.json({ limit: "256kb" }));

/**
 * Health & WhatsApp connection status
 */
app.get("/health", (_req: Request, res: Response) => {
  const isConnected = whatsapp.isConnected();

  res.json({
    status: "ok",
    connected: isConnected,
    authenticated: isConnected,
    user: whatsapp.getUser(),
    inboundWebhook: config.mainServiceInboundUrl,
  });
});

/**
 * Raw QR string for pairing via main backend / frontend UI
 */
app.get("/qr", (_req: Request, res: Response) => {
  const isConnected = whatsapp.isConnected();
  const qr = whatsapp.getQr();

  res.json({
    success: true,
    authenticated: isConnected,
    connected: isConnected,
    qr,
    message: isConnected
      ? "WhatsApp is already connected."
      : qr
      ? "QR code available."
      : "QR code is generating, please retry shortly.",
  });
});

/**
 * Outbound 1-on-1 message sending
 */
app.post(["/whatsapp/send", "/api/whatsapp/send"], async (req: Request, res: Response) => {
  const to = (req.body.to || req.body.phone || req.body.recipient || "").toString().trim();
  const message = (req.body.message || req.body.text || "").toString();

  if (!to) {
    return res.status(400).json({
      success: false,
      error: "Recipient phone number ('to') is required.",
    });
  }

  if (!message || message.trim().length === 0) {
    return res.status(400).json({
      success: false,
      error: "Message content ('message') cannot be empty.",
    });
  }

  try {
    const result = await whatsapp.sendMessage(to, message);
    return res.json({ success: true, ...result });
  } catch (error: any) {
    const status = error.statusCode || 500;
    return res.status(status).json({
      success: false,
      error: error.message || "Failed to send WhatsApp message.",
    });
  }
});

// Start Express server and initialize WhatsApp Web
app.listen(config.port, () => {
  console.log(`WhatsApp Gateway running on port ${config.port}`);
  console.log(`Inbound Webhook configured to: ${config.mainServiceInboundUrl}`);
  whatsapp.init();
});
'@ | Set-Content -Path "src\server.ts" -Encoding UTF8

    @'
# Server Port
PORT=3000

# WhatsApp Multi-file Auth Directory
AUTH_DIR=./auth/whatsapp

# Main Service Inbound Webhook URL (dispatches lightweight metadata payload)
MAIN_SERVICE_INBOUND_URL=http://main-service:8000/api/whatsapp/inbound
'@ | Set-Content -Path ".env.example" -Encoding UTF8
    Copy-Item ".env.example" ".env" -Force

    Invoke-Native "npm install"

    Pop-Location
    Write-Host "==> WhatsApp Service scaffolded (TypeScript, run 'npm run dev' once standalone to scan the QR before the demo)"
}

# ============================================================================
# 7. DOCKER - Dockerfiles + compose.yaml, root files, git init
# ============================================================================
if (Stage-Done 7) {
    Write-Host "==> [7/7] Already complete; skipping"
} else {
    Write-Host "==> [7/7] Writing Docker setup and root files"

    @'
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
'@ | Set-Content -Path "frontend\Dockerfile" -Encoding UTF8

    @'
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
'@ | Set-Content -Path "main-service\Dockerfile" -Encoding UTF8

    # ai-worker / background-worker build from the REPO ROOT so they can COPY shared/
    @'
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
'@ | Set-Content -Path "ai-worker\Dockerfile" -Encoding UTF8

    @'
FROM python:3.12-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    python3-dev \
    libcairo2-dev \
    libpango1.0-dev \
    libgdk-pixbuf-2.0-dev \
    libffi-dev \
    shared-mime-info \
    && rm -rf /var/lib/apt/lists/*

COPY background-worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY shared/ ./shared/
COPY background-worker/ .

CMD ["python", "main.py"]
'@ | Set-Content -Path "background-worker\Dockerfile" -Encoding UTF8

    # WhatsApp Service is now TypeScript: compile with tsc, run the built JS.
    # Baileys auth state (./auth) is a runtime volume, not baked into the image.
    @'
FROM node:20-slim AS build
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm install
COPY src/ ./src/
RUN npm run build

FROM node:20-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm install --omit=dev
COPY --from=build /app/dist ./dist
EXPOSE 3000
CMD ["node", "dist/server.js"]
'@ | Set-Content -Path "whatsapp-service\Dockerfile" -Encoding UTF8

    @'
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
    container_name: redis_server
    ports:
      - "6379:6379"

  main-service:
    build: ./main-service
    env_file: .env
    environment:
      POSTGRES_HOST: postgres
      REDIS_URL: redis://redis_server:6379/0
    depends_on:
      - postgres
      - redis
    ports:
      - "8000:8000"
    volumes:
      - ./main-service:/app
      - media_data:/app/media
    command: ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--reload"]

  ai-worker:
    build:
      context: .
      dockerfile: ai-worker/Dockerfile
    env_file: .env
    environment:
      REDIS_URL: redis://redis_server:6379/0
      MAIN_SERVICE_URL: http://main-service:8000
      WHATSAPP_SERVICE_URL: http://whatsapp-service:3000
      JOB_CALLBACK_URL: http://main-service:8000/api/internal/worker-result
    volumes:
      - ./ai-worker:/app
      - ./shared:/app/shared
    depends_on:
      - redis
      - main-service
    command: ["python", "main.py"]

  background-worker:
    build:
      context: .
      dockerfile: background-worker/Dockerfile
    env_file: .env
    environment:
      REDIS_URL: redis://redis_server:6379/0
      MAIN_SERVICE_URL: http://main-service:8000
      WHATSAPP_SERVICE_URL: http://whatsapp-service:3000
    volumes:
      - ./background-worker:/app
      - ./shared:/app/shared
    depends_on:
      - redis
      - main-service
    command: ["python", "main.py"]

  whatsapp-service:
    build: ./whatsapp-service
    env_file: ./whatsapp-service/.env
    environment:
      PORT: 3000
      AUTH_DIR: /app/auth/whatsapp
      MAIN_SERVICE_INBOUND_URL: http://main-service:8000/api/whatsapp/inbound
    ports:
      - "3000:3000"
    volumes:
      - whatsapp_auth:/app/auth
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
  media_data:
  whatsapp_auth:
'@ | Set-Content -Path "compose.yaml" -Encoding UTF8

    @'
# Postgres
POSTGRES_DB=main_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres

# Django
DJANGO_SECRET_KEY=change-me
DEBUG=True
ALLOWED_HOSTS=*
CORS_ALLOWED_ORIGINS=http://localhost:5173
CSRF_TRUSTED_ORIGINS=http://localhost:5173

# Redis
REDIS_URL=redis://redis_server:6379/0

# AI Worker callback
JOB_CALLBACK_URL=http://main-service:8000/api/internal/worker-result

# LLM providers (fill in at kickoff)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
'@ | Set-Content -Path ".env.example" -Encoding UTF8
    Copy-Item ".env.example" ".env" -Force

    @'
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
'@ | Set-Content -Path ".gitignore" -Encoding UTF8

    @'
# Local Setup

Scaffold reference, not the final project README (that's a Phase 8
deliverable - see docs/documentation-guide.md).

1. `.env` files are auto-generated (copied from each `.env.example`) by this
   script. Open each one and fill in real values (LLM API keys especially) --
   root `.env`, `main-service\.env`, `ai-worker\.env`, `background-worker\.env`,
   `whatsapp-service\.env`, `frontend\.env`.
2. Place the pre-hackathon docs into `docs/` (architecture.md, sdlc.md,
   coding-guidelines.md, testing-guidelines.md, documentation-guide.md,
   ux-guide.md, ui-guide.md).
3. Pre-authenticate WhatsApp once, before the demo:
   cd whatsapp-service; npm run dev
   (scan the QR code printed in the terminal, or GET /qr for the raw string;
   ./auth/whatsapp then keeps the session logged in -- don't scan live)
4. Build and run everything (3 AI worker replicas, per architecture.md):
   docker compose up -d --build --scale ai-worker=3
5. Apply migrations:
   docker compose exec main-service python manage.py migrate
6. Create an admin user (Django Admin is where AI config eventually lives):
   docker compose exec main-service python manage.py createsuperuser
7. Verify:
   - http://localhost:8000/health
   - http://localhost:8000/docs        (Swagger UI)
   - http://localhost:3000/health      (WhatsApp Service)
   - http://localhost:3000/qr          (WhatsApp pairing QR, if not yet linked)
   - http://localhost:5173             (frontend)
'@ | Set-Content -Path "SETUP.md" -Encoding UTF8

    Invoke-Native "git init -q"
    Invoke-Native "git add -A"
    Invoke-Native "git commit -q -m ""chore: bootstrap project scaffold from architecture.md"""
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Done. Project scaffolded at .\$ProjectName"
Write-Host ""
Write-Host " Next steps:"
Write-Host "  1. cd $ProjectName"
Write-Host "  2. Drop the 7 doc files into docs\"
Write-Host "  3. .env files were auto-generated in each service folder -- open them and fill in real secrets/keys"
Write-Host "  4. Pre-auth WhatsApp: cd whatsapp-service; npm run dev (scan QR, then Ctrl+C)"
Write-Host "  5. docker compose up -d --build --scale ai-worker=3"
Write-Host "  6. docker compose exec main-service python manage.py migrate"
Write-Host "  7. docker compose exec main-service python manage.py createsuperuser"
Write-Host "============================================================"