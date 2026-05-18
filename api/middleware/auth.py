"""JWT authentication middleware.
FIX #180: Pin to HS256, add token revocation
Contributor: BossChaos (heremes-agent)
"""

from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse
import jwt
import os
from datetime import datetime, timedelta
import hashlib

SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "fallback-dev-key-change-in-production")
ALGORITHM = "HS256"  # FIX #180: Pin algorithm, reject 'none'

# Token revocation set (stored in memory for simplicity, use Redis in production)
REVOKED_TOKENS: set = set()

def generate_token(user_id: str, role: str = "user") -> str:
    payload = {
        "sub": user_id,
        "role": role,
        "exp": datetime.utcnow() + timedelta(hours=24),
        "iat": datetime.utcnow(),
        "jti": hashlib.sha256(os.urandom(32)).hexdigest(),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

def decode_token(token: str) -> dict:
    # FIX: Reject None algorithm explicitly
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except jwt.InvalidTokenError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")
    # FIX: Check revocation
    if payload.get("jti") in REVOKED_TOKENS:
        raise HTTPException(status_code=401, detail="Token revoked")
    return payload

def revoke_token(token: str):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": False})
        if "jti" in payload:
            REVOKED_TOKENS.add(payload["jti"])
    except jwt.InvalidTokenError:
        pass

class AuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path.startswith("/health") or request.url.path.startswith("/docs"):
            return await call_next(request)

        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return JSONResponse(status_code=401, content={"detail": "Missing token"})

        try:
            user = decode_token(auth_header.split(" ", 1)[1])
            request.state.user = user
        except HTTPException as e:
            return JSONResponse(status_code=e.status_code, content={"detail": e.detail})

        return await call_next(request)
