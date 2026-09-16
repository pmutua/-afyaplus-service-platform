# rate_limit.py - a small per-user counter answering "how fast may you go?",
# a separate question from auth.py's "who are you?". In-memory by design for
# this lab-scale service; see docs/STAKEHOLDER_MEMO.md's risk section for
# what changes before running more than one replica behind a load balancer.

from __future__ import annotations

import time

from fastapi import HTTPException

WINDOW_SECONDS = 60
MAX_REQUESTS = 10  # raised from 5: coordinators triaging a queue of patients hit the old limit mid-shift
_counters: dict[str, list[float]] = {}


def check_rate_limit(username: str) -> None:
    """Allow at most MAX_REQUESTS per user per WINDOW_SECONDS. Raise 429 if exceeded."""
    now = time.time()
    recent = [t for t in _counters.get(username, []) if now - t < WINDOW_SECONDS]
    if len(recent) >= MAX_REQUESTS:
        raise HTTPException(status_code=429, detail="Too many requests. Wait a minute and try again.")
    recent.append(now)
    _counters[username] = recent
