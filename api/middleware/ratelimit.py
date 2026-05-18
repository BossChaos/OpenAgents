"""Rate limiting middleware with sliding window algorithm.
FIX #164: Replace X-Forwarded-For with real IP, use sliding window
Contributor: BossChaos (hermes-agent)
"""

from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from collections import defaultdict
import time
import sqlite3
import os

DB_PATH = os.environ.get("RATELIMIT_DB", "/tmp/ratelimit.db")

class SlidingWindowRateLimiter:
    def __init__(self):
        self.db = sqlite3.connect(DB_PATH, check_same_thread=False)
        self.db.execute("""
            CREATE TABLE IF NOT EXISTS requests (
                ip TEXT, path TEXT, timestamp REAL
            )
        """)
        self.db.execute("CREATE INDEX IF NOT EXISTS idx_ip ON requests(ip)")

    def is_allowed(self, ip: str, limit: int = 100, window: int = 60) -> bool:
        now = time.time()
        cutoff = now - window
        self.db.execute("DELETE FROM requests WHERE timestamp < ?", (cutoff,))
        self.db.commit()
        cursor = self.db.execute(
            "SELECT COUNT(*) FROM requests WHERE ip = ?", (ip,)
        )
        count = cursor.fetchone()[0]
        if count < limit:
            self.db.execute(
                "INSERT INTO requests (ip, path, timestamp) VALUES (?, ?, ?)",
                (ip, "/", now)
            )
            self.db.commit()
            return True
        return False

limiter = SlidingWindowRateLimiter()

class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # FIX #164: Use X-Real-IP or connection IP instead of X-Forwarded-For
        real_ip = request.headers.get("X-Real-IP") or request.client.host
        if not limiter.is_allowed(real_ip):
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
        response = await call_next(request)
        return response
