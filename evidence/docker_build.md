# Deliverable 2 — containerisation evidence

Built and run locally with Docker Desktop (`docker version 29.5.3`) from
the repo root.

## Build

```
$ docker build -t afyaplus-platform:1.0.0 .
...
#8 [4/6] RUN pip install --no-cache-dir -r requirements-api.txt
#8 96.11 Successfully installed PyJWT-2.14.0 ... fastapi-0.141.1 mcp-1.30.0
    langchain-openai-1.6.2 langgraph-1.2.11 openai-3.14.1 ...
#8 DONE 98.2s

#9 [5/6] COPY app/ ./app/
#9 DONE 0.3s
#10 [6/6] COPY mcp_server/ ./mcp_server/
#10 DONE 0.1s
#11 naming to docker.io/library/afyaplus-platform:1.0.0
```

First build: ~108s total, almost all of it the `pip install` layer.

## Cache-friendly layer order, proven

`requirements-api.txt` is copied and installed *before* `app/` and
`mcp_server/` are copied — editing application code should never
invalidate the dependency layer. Proven by touching `app/main.py` and
rebuilding:

```
$ echo "# cache-layer probe" >> app/main.py && docker build -t afyaplus-platform:1.0.0 .
#8 [4/6] RUN pip install --no-cache-dir -r requirements-api.txt
#8 CACHED
#9 [5/6] COPY app/ ./app/
#9 DONE 0.0s
...
real    0m2.310s
```

108s -> 2.3s: only the two `COPY` layers re-ran; the `pip install` layer
was reused byte-for-byte.

## Image size

```
$ docker images afyaplus-platform:1.0.0 --format "{{.Repository}}:{{.Tag}}  {{.Size}}"
afyaplus-platform:1.0.0  400MB
```

(`docker images` also reports a 88.3MB "content size" — the unique layers
this image adds on top of the shared `python:3.12-slim` base, which most
of the 400MB disk figure comes from. `python:3.12-slim` plus the
langchain/langgraph/mcp dependency stack this platform needs is
unavoidably heavier than a bare FastAPI-only image.)

## Runtime secret injection, never baked in

The image is built with no `.env` in the build context (see
`.dockerignore`) and no `ARG`/`ENV` secret in the `Dockerfile`. Running the
image with **no** `--env-file` proves nothing is baked in:

```
$ docker run --rm afyaplus-platform:1.0.0 python -c "import os; print('JWT_SECRET in image env:', os.getenv('JWT_SECRET'))"
JWT_SECRET in image env: None
```

Running it for real, secrets injected at `docker run` time:

```
$ docker run -d --name afyaplus-platform-test -p 8001:8000 --env-file .env afyaplus-platform:1.0.0

$ curl -s http://127.0.0.1:8001/health
{"service":"afyaplus-service-platform","version":"1.0.0","status":"ok"}

$ curl -i -X POST http://127.0.0.1:8001/triage -H 'Content-Type: application/json' \
    -d '{"patient_message":"I feel unwell","county":"Kisumu"}'
HTTP/1.1 401 Unauthorized

$ TOKEN=$(curl -s -X POST http://127.0.0.1:8001/token -H 'Content-Type: application/json' \
    -d '{"username":"mercy","password":"logistics2026"}' | python -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

$ curl -s -X POST http://127.0.0.1:8001/triage -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" -d '{"patient_message":"I have a mild fever","county":"Kisii"}'
{"urgency":"medium","advice":"Monitor your temperature and rest. Stay hydrated and consider seeking medical advice if it persists or worsens.","handled_for":"mercy","model_used":"gpt-4o-mini"}
```

A real `gpt-4o-mini` call succeeded from inside the container, proving
`OPENAI_API_KEY` was correctly injected via `--env-file .env` at runtime.

## Image tag matches the git tag

`afyaplus-platform:1.0.0` is built from, and only from, the commit tagged
`v1.0.0` on `main` — see `CONTRIBUTING.md`'s release policy for the rule
and the top-level README's "Verify the release" section for the exact
`git tag`/`git show v1.0.0` transcript run against that commit.
