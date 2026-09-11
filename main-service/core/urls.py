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


