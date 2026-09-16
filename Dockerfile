# Dockerfile - Deliverable 2. Slim base image, dependency layer ordered
# ahead of the code layer so an edit to app/ or mcp_server/ reuses the
# cached pip install and rebuilds in seconds instead of minutes.
#
# Build from the REPO ROOT (this file's own directory):
#   docker build -t afyaplus-platform:1.0.0 .
#
# Secrets (JWT_SECRET, OPENAI_API_KEY, ...) are never baked into this
# image -- app/auth.py and app/triage_model.py read them from the process
# environment at runtime. Run with:
#   docker run --rm -p 8000:8000 --env-file .env afyaplus-platform:1.0.0

FROM python:3.12-slim

WORKDIR /app

# Dependencies before code: this layer only invalidates when
# requirements-api.txt changes.
COPY requirements-api.txt .
RUN pip install --no-cache-dir -r requirements-api.txt

# Code layer -- the one that changes on every edit.
COPY app/ ./app/
COPY mcp_server/ ./mcp_server/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
