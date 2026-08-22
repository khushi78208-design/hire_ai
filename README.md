# HireAI

AI-assisted recruitment platform. Recruiters post vacancies, candidates apply
with a resume, and an LLM screens each application against the job's actual
requirements — returning a score with the reasoning behind it.

**AI screens, ranks and explains. The recruiter decides.** Nothing is
auto-rejected and no hiring action happens without a human pressing the button.

---

## Features

**Candidates** — browse and search vacancies, apply with a resume, track status
through the pipeline.

**Recruiters** — dashboard with pipeline counts, full vacancy management, AI
screening per application (score, matched and missing skills, strengths,
concerns, plain-English summary), filters by status and score, and an assistant
that drafts vacancies from a plain-language description.

---

## Architecture

```
Flutter app  ──HTTPS + JWT──▶  Express API  ──shared secret──▶  FastAPI service
                                    │                                 │
                                    ▼                                 ▼
                          Supabase Postgres + Storage            Gemini API
```

The Flutter app holds no secrets — just the backend URL. The AI service is
internal-only, never touches the database, and holds the LLM key. Authorization
is enforced in the API, not the UI: a candidate calling `POST /jobs` gets a 403
regardless of what the client rendered.

| Layer | Stack |
|---|---|
| Client | Flutter |
| API | Node + Express, bcrypt + JWT |
| AI | Python + FastAPI, Gemini |
| Data | Supabase Postgres + Storage |
| Hosting | Render |

---

## The AI layer

The prompt instructs the model to judge only on evidence in the resume, treat a
skill listed under "interests" as weak evidence rather than a match, and
disregard name, gender, age, religion and marital status.

Every field it returns is clamped before it reaches the database, so a
malformed response degrades instead of corrupting a row. Scores live in a
separate table from the recruiter's decision, so re-running an analysis can
never overwrite a shortlist.

The assistant can only create an unpublished draft, and only after the
recruiter approves the preview. It cannot publish, change a status, or delete.

**Candidates never see their score.** The endpoint excludes it at the query,
not in the UI. A low number is demoralising and invites an argument over a
figure a human may well override. Candidates see their pipeline status, which
is what actually affects them.

---

## Running locally

Needs Node 20+, Python 3.10+, Flutter, and a Supabase project.

```bash
# 1. Database — run database/migrations/*.sql in the Supabase SQL editor,
#    then create a private Storage bucket named "resumes"

# 2. AI service
cd ai-service && pip install -r requirements.txt
cp .env.example .env          # INTERNAL_SECRET, LLM_API_KEY
python -m uvicorn app.main:app --reload --port 8000

# 3. Backend
cd backend && npm install
cp .env.example .env          # Supabase keys, JWT_SECRET, AI_SERVICE_SECRET
npm run dev

# 4. App
cd frontend && flutter run -d chrome
```

`AI_SERVICE_SECRET` must match `INTERNAL_SECRET` exactly, or every AI call
returns 401.

Check it works: `curl localhost:4000/api/v1/health/ready` returns 200 only when
Supabase and the AI service both respond.

---

## Deployment

Two Render web services from one repo, separated by Root Directory:

| Service | Root | Start |
|---|---|---|
| AI | `ai-service` | `uvicorn app.main:app --host 0.0.0.0 --port $PORT` |
| API | `backend` | `npm start` |

Both bind to `$PORT`. `AI_SERVICE_TIMEOUT_MS` is 120000 — a sleeping free
instance needs ~50s to wake, plus 30–60s for the LLM call.

---

## Security

Secrets stay in gitignored `.env` files. The Supabase service role key never
leaves the server. RLS is on with no permissive policies, so a leaked anon key
reads nothing. Refresh tokens are stored hashed. Uploads are namespaced by user
id, size-capped and type-checked. Consequential recruiter actions are written
to `audit_logs`.

---

## Responsible use

Every score ships with its reasoning — a bare number is a black box nobody can
audit. Shortlisting, rejection and selection are all manual and reversible. The
prompt disregards protected attributes, which reduces bias but does not
eliminate it; a real deployment would need bias auditing, which in some
jurisdictions is a legal requirement rather than a nice-to-have.

---

## Not built

Assessments, interview scheduling, email notifications and a RAG knowledge base
were designed but not implemented.
