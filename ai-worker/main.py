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
