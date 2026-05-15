# SmarterTraining Backend

FastAPI backend for SmarterTraining. Provides JWT-authenticated sync API with Sign in with Apple and PostgreSQL storage.

## Local Setup

Requires Python 3.11+.

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Create a `.env` file from the example:

```bash
cp .env.example .env
```

Edit `.env` with your local values.

## Database Setup

Start PostgreSQL locally or via Docker:

```bash
docker run -d --name smartertraining-pg \
  -e POSTGRES_USER=smartertraining \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=smartertraining \
  -p 5432:5432 \
  postgres:16
```

Or create the database manually:

```bash
createdb smartertraining
```

Run migrations:

```bash
alembic upgrade head
```

## Running Locally

```bash
uvicorn app.main:app --reload
```

The API will be available at `http://localhost:8000`. Interactive docs at `http://localhost:8000/docs`.

## Running Tests

Tests use an in-memory SQLite database (via aiosqlite) and do not require PostgreSQL.

```bash
pytest
```

## Render Deployment

Set the following environment variables on Render:

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string (provided by Render Postgres) |
| `JWT_SECRET` | A secure random string for signing JWTs |
| `APPLE_BUNDLE_ID` | Your Apple app bundle ID (default: `com.timforan.SmarterTraining`) |

Start command:

```bash
uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

Run migrations on deploy (add as a pre-deploy command or run manually):

```bash
alembic upgrade head
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `DATABASE_URL` | Yes | `postgresql://smartertraining:password@localhost:5432/smartertraining` | PostgreSQL connection URL |
| `JWT_SECRET` | Yes | `change-me-to-a-real-secret` | Secret key for JWT signing (HS256) |
| `APPLE_BUNDLE_ID` | No | `com.timforan.SmarterTraining` | Apple app bundle identifier for token verification |
