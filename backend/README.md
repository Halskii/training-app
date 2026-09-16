# Training App Backend

FastAPI service that owns the data model and the AI coaching layer (macrocycle
planning, block generation, injury-feedback adjustment).

## Setup

1. Create a free [Supabase](https://supabase.com) project.
2. In the Supabase SQL editor, run `migrations/001_init.sql`.
3. Copy `.env.example` to `.env` and fill in:
   - `SUPABASE_URL` / `SUPABASE_SERVICE_KEY` (Project Settings → API)
   - `ANTHROPIC_API_KEY` (Anthropic Console)
4. Install dependencies and run:

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

5. Visit `http://localhost:8000/docs` for the interactive API.

## Structure

- `app/schemas/` — Pydantic models shared between the API and the AI layer
  (`AthleteFile`, `MacrocycleSkeleton`, `DetailedBlock`).
- `app/services/ai/` — the coach persona, and the two-stage planner: a
  macrocycle *skeleton* (shape only, all 3 blocks) generated once, then each
  block *detailed* individually right before it's needed, using real logged
  data from prior blocks.
- `app/routers/` — HTTP endpoints.
- `migrations/` — raw SQL run against Supabase, one file per change.
