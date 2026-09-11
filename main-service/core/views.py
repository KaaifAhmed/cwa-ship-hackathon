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




