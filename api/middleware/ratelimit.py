"""Rate limiting middleware with real IP validation.
FIX #78: Reject spoofable X-Forwarded-For, use connection IP only
Contributor: BossChaos (hermes-agent)
"""

from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from collections import defaultdict
import time

class RateLimiter:
    def __init__(self, limit: int = 100, window: int = 60):
        self.limit = limit
        self.window = window
        self.requests: dict = defaultdict(list)

    def is_allowed(self, ip: str) -> bool:
        now = time.time()
        cutoff = now - self.window
        self.requests[ip] = [t for t in self.requests[ip] if t > cutoff]
        if len(self.requests[ip]) >= self.limit:
            return False
        self.requests[ip].append(now)
        return True

limiter = RateLimiter()

class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # FIX #78: Use ONLY the direct connection IP, ignore X-Forwarded-For
        real_ip = request.client.host
        if not limiter.is_allowed(real_ip):
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
        response = await call_next(request)
        return response
