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
