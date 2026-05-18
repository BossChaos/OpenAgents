"""Rate limiting middleware for the OpenAgents API."""

import time
import hashlib
from collections import defaultdict
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse
from typing import Dict, Tuple


class RateLimitConfig:
    def __init__(
        self,
        requests_per_window: int = 100,
        window_seconds: int = 60,
        burst_limit: int = 20,
    ):
        self.requests_per_window = requests_per_window
        self.window_seconds = window_seconds
        self.burst_limit = burst_limit


_request_counts: Dict[str, Tuple[int, float]] = defaultdict(lambda: (0, time.time()))
_request_timestamps: Dict[str, list] = defaultdict(list)


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, config: RateLimitConfig = None):
        super().__init__(app)
        self.config = config or RateLimitConfig()
        self._trusted_proxies = set()  # FIX: Only trust IPs in this list

    def _get_client_ip(self, request: Request) -> str:
        # FIX: Never trust X-Forwarded-For from untrusted sources.
        # Use the direct connection IP unless request comes from a known proxy.
        client_host = request.client.host if request.client else "unknown"
        if client_host in self._trusted_proxies:
            forwarded = request.headers.get("X-Forwarded-For")
            if forwarded:
                return forwarded.split(",")[0].strip()
        return client_host

    def _is_rate_limited(self, client_ip: str) -> Tuple[bool, int]:
        global _request_counts, _request_timestamps
        now = time.time()

        # FIX: Use sliding window — remove timestamps outside the window
        timestamps = _request_timestamps[client_ip]
        window_start = now - self.config.window_seconds
        _request_timestamps[client_ip] = [t for t in timestamps if t > window_start]

        count = len(_request_timestamps[client_ip])

        if count >= self.config.requests_per_window:
            retry_after = int(self.config.window_seconds - (now - _request_timestamps[client_ip][0]))
            return True, max(retry_after, 1)

        _request_timestamps[client_ip].append(now)
        remaining = self.config.requests_per_window - count - 1
        return False, remaining

    async def dispatch(self, request: Request, call_next):
        if request.url.path.startswith("/health"):
            return await call_next(request)

        client_ip = self._get_client_ip(request)
        is_limited, value = self._is_rate_limited(client_ip)

        if is_limited:
            return JSONResponse(
                status_code=429,
                content={
                    "error": "Rate limit exceeded",
                    "retry_after": value,
                },
                headers={"Retry-After": str(value)},
            )

        response = await call_next(request)
        response.headers["X-RateLimit-Remaining"] = str(value)
        response.headers["X-RateLimit-Limit"] = str(self.config.requests_per_window)
        return response


def create_rate_limiter(
    requests_per_minute: int = 100,
    burst: int = 20,
) -> RateLimitMiddleware:
    config = RateLimitConfig(
        requests_per_window=requests_per_minute,
        window_seconds=60,
        burst_limit=burst,
    )
    return RateLimitMiddleware(app=None, config=config)
