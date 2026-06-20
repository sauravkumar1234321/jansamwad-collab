# Cloud Deploy Guide

This deploys the full app — FastAPI backend, React dashboard (served as
static files from the same process), and a managed PostgreSQL database — to
**Render** using the `render.yaml` blueprint in the repo root.

Render was chosen because:

- One YAML file provisions **both** the web service and the database
  atomically.
- `DATABASE_URL` is auto-injected into the web service — no manual wiring.
- The existing `Dockerfile` is used as-is (now patched to honour `$PORT`,
  the only code change).
- Free tier covers a working demo end-to-end.

> Approximate cost — free for the first 90 days. After that, the database
> moves to the **Starter** plan (~$7/mo). The web service stays free with
> cold-starts after 15 min idle; upgrade it to Starter (~$7/mo) to keep it
> always-on.

---

## Prerequisites

1. The repo is pushed to a GitHub/GitLab/Bitbucket account that Render can
   read. (Render pulls the code directly — there is no separate Docker
   registry to manage.)
2. A free **Render** account: <https://render.com>.
3. *(Optional but recommended)* A **Gemini API key** for the high-quality
   AI engine: <https://aistudio.google.com/apikey>. Without it the app
   falls back to the offline deterministic engine — every API still works,
   the health badge just reports `provider: "rules"`.

---

## Deploy (one-time, ~5 minutes)

1. **Push the repo to GitHub** (skip if already pushed). The two new files
   `Dockerfile` (patched) and `render.yaml` must be on the default branch.

   ```bash
   git add Dockerfile render.yaml DEPLOY.md
   git commit -m "Add Render blueprint and DEPLOY guide"
   git push
   ```

2. **Create the blueprint on Render.**
   - Sign in → **New +** → **Blueprint**.
   - Connect the GitHub repo containing this project.
   - Render detects `render.yaml` and shows the two resources it will
     create: `jansamvaad-db` (PostgreSQL) and `jansamvaad` (web service).
   - It will prompt for the two secrets marked `sync: false`:
     - `GEMINI_API_KEY` — paste your key (or leave blank to run on the
       offline rule engine).
     - `ANTHROPIC_API_KEY` — leave blank unless you also want the Claude
       engine.
   - Click **Apply**.

3. **Wait for the first build.** Render will:
   1. Provision the Postgres instance (~1 min).
   2. Build the Docker image from `Dockerfile` (~3-5 min the first time).
   3. Start the container, which on boot:
      - Connects to Postgres via the injected `DATABASE_URL`.
      - Runs `Base.metadata.create_all(...)` to create the three tables
        (`complaints`, `triage_results`, `audit_log`).
      - Seeds the historical synthetic records on first run (idempotent —
        subsequent restarts skip the seed because the table is non-empty).
      - Rebuilds the in-memory embedding index from the seeded rows.
   4. Hits `/api/health` until it returns `200`.

4. **Open the app.** Render shows the public URL on the service page —
   something like `https://jansamvaad.onrender.com`. The React dashboard
   loads at `/`; the JSON API is under `/api/*`.

---

## Verifying the deploy

```bash
# Replace with your Render URL
BASE=https://jansamvaad.onrender.com

# Health — should report provider and time
curl -s "$BASE/api/health" | jq

# Sample triage — should return a structured advisory result
curl -s -X POST "$BASE/api/triage" \
  -H 'Content-Type: application/json' \
  -d '{"text":"bijli ka transformer chingari maar raha hai near sector 14","district":"Gurugram","persist":true}' | jq

# Queue — should include the row you just persisted
curl -s "$BASE/api/queue" | jq '.items[0]'
```

If `/api/health` returns `provider: "gemini"`, the Gemini key is wired
correctly. If it returns `provider: "rules"`, the offline engine is active
— either the key is missing, invalid, or quota-throttled.

---

## What got created in your cloud account

| Resource | Purpose | Render service name |
|---|---|---|
| PostgreSQL 15, 256 MB / 1 GB storage | Persistent store for complaints, triage results, audit log | `jansamvaad-db` |
| Docker web service (Python 3.11 / FastAPI / Uvicorn) | Serves API + static dashboard | `jansamvaad` |

The web service connects to the database over Render's private network —
the DB is **not** exposed to the public internet by default. You can grant
your laptop's IP temporary access from the database page if you want to
connect with `psql` for debugging.

---

## Day-2 operations

- **Update the app.** Push to the default branch — `autoDeploy: true` in
  `render.yaml` triggers a rebuild and zero-downtime rollout.
- **Roll back.** Render → service → **Events** → **Rollback** to a prior
  successful deploy.
- **Logs.** Render → service → **Logs** (live tail, full history).
- **Run a one-off command** (e.g. inspect data). Render → service →
  **Shell** opens a tty inside the running container.
- **Reset / reseed data.** Connect to Postgres (`psql $DATABASE_URL`) and
  `TRUNCATE complaints, triage_results, audit_log;` — on the next restart
  the seed records will be reinserted automatically.
- **Rotate the Gemini key.** Render → service → **Environment** → edit
  `GEMINI_API_KEY` → Save. Render restarts the service with the new value.

---

## Alternative platforms (if you change your mind later)

The Dockerfile change makes the same image deployable on any platform that
injects `$PORT`. Quick pointers:

- **Heroku** — `Procfile` is already present. Create a Heroku app, add the
  **Heroku Postgres** add-on (`heroku addons:create heroku-postgresql`),
  set `LLM_PROVIDER` and `GEMINI_API_KEY`, then `git push heroku main`.
  Heroku's `DATABASE_URL` uses the legacy `postgres://` scheme, which
  `backend/app/database.py` already rewrites to `postgresql://`.
- **Google Cloud Run + Cloud SQL** — `gcloud run deploy --source .` for
  the app, create a Cloud SQL Postgres instance, then set `DATABASE_URL`
  to its connection string (use the Cloud SQL Auth Proxy or
  `--add-cloudsql-instances`).
- **AWS App Runner + RDS** — push the image to ECR, create an App Runner
  service from it, create an RDS Postgres instance in the same VPC, and
  set `DATABASE_URL` as a runtime env var.
- **Fly.io** — `fly launch` (it will detect the Dockerfile), then
  `fly postgres create` and `fly postgres attach` to wire the database.

In every case the only required env vars are `DATABASE_URL` and
(optionally) `GEMINI_API_KEY` or `ANTHROPIC_API_KEY`.
