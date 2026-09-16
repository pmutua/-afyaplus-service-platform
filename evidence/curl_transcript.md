# Deliverable 1 -- curl evidence (Secure FastAPI Service)

Captured against `uvicorn app.main:app` running locally.

## 1. GET /health -- unprotected, 200
```
$ curl -i http://127.0.0.1:8000/health
HTTP/1.1 200 OK
date: Wed, 16 Sep 2026 22:02:17 GMT
server: uvicorn
content-length: 71
content-type: application/json

{"service":"afyaplus-service-platform","version":"1.0.0","status":"ok"}```

## 2. POST /triage with no token -- 401
```
$ curl -i -X POST http://127.0.0.1:8000/triage -H 'Content-Type: application/json' -d '{"patient_message": "I have a mild headache", "county": "Kisumu"}'
HTTP/1.1 401 Unauthorized
date: Wed, 16 Sep 2026 22:02:17 GMT
server: uvicorn
www-authenticate: Bearer
content-length: 30
content-type: application/json

{"detail":"Not authenticated"}```

## 3. POST /token with an invalid body (password too short) -- 422
```
$ curl -i -X POST http://127.0.0.1:8000/token -H 'Content-Type: application/json' -d '{"username": "mercy", "password": "ab"}'
HTTP/1.1 422 Unprocessable Content
date: Wed, 16 Sep 2026 22:02:17 GMT
server: uvicorn
content-length: 151
content-type: application/json

{"detail":[{"type":"string_too_short","loc":["body","password"],"msg":"String should have at least 6 characters","input":"ab","ctx":{"min_length":6}}]}```

## 4. POST /token with wrong credentials -- 401
```
$ curl -i -X POST http://127.0.0.1:8000/token -H 'Content-Type: application/json' -d '{"username": "mercy", "password": "wrongpassword"}'
HTTP/1.1 401 Unauthorized
date: Wed, 16 Sep 2026 22:02:17 GMT
server: uvicorn
content-length: 40
content-type: application/json

{"detail":"Wrong username or password."}```

## 5. POST /token with valid guest credentials -- 200 (token issued)
```
$ curl -i -X POST http://127.0.0.1:8000/token -H 'Content-Type: application/json' -d '{"username": "guest", "password": "lookaround"}'
HTTP/1.1 200 OK
date: Wed, 16 Sep 2026 22:02:30 GMT
server: uvicorn
content-length: 186
content-type: application/json

{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJndWVzdCIsInJvbGUiOiJ2aWV3ZXIiLCJleHAiOjE3ODk1OTc5NTF9.5mkwT-QRxVu5Ct6unSZ3QA8CVDlYn5TihcytvEpRtME","token_type":"bearer"}```

## 6. POST /triage with a valid guest token (wrong role) -- 403
```
$ curl -i -X POST http://127.0.0.1:8000/triage -H 'Content-Type: application/json' -H 'Authorization: Bearer <guest token>' -d '{"patient_message": "I have a mild headache", "county": "Kisumu"}'
HTTP/1.1 403 Forbidden
date: Wed, 16 Sep 2026 22:02:30 GMT
server: uvicorn
content-length: 74
content-type: application/json

{"detail":"Your role may not use this endpoint (requires 'coordinator')."}```

## 7. POST /token with valid mercy (coordinator) credentials -- 200
```
$ curl -i -X POST http://127.0.0.1:8000/token -H 'Content-Type: application/json' -d '{"username": "mercy", "password": "logistics2026"}'
HTTP/1.1 200 OK
date: Wed, 16 Sep 2026 22:02:30 GMT
server: uvicorn
content-length: 193
content-type: application/json

{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJtZXJjeSIsInJvbGUiOiJjb29yZGluYXRvciIsImV4cCI6MTc4OTU5Nzk1MX0._F7DETyqWT6cMpoQsIwj-TYujDM3qkpJc0fidOcvU8o","token_type":"bearer"}```

## 8. POST /triage with a valid mercy (coordinator) token -- 200, real gpt-4o-mini call
```
$ curl -i -X POST http://127.0.0.1:8000/triage -H 'Content-Type: application/json' -H 'Authorization: Bearer <mercy token>' -d '{"patient_message": "I have chest pain and feel dizzy", "county": "Kisumu"}'
HTTP/1.1 200 OK
date: Wed, 16 Sep 2026 22:02:30 GMT
server: uvicorn
content-length: 123
content-type: application/json

{"urgency":"high","advice":"Please go to the nearest clinic immediately.","handled_for":"mercy","model_used":"gpt-4o-mini"}```
