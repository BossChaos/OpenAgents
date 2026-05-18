"""FastAPI application entry point.
FIX #178: Add request ID middleware for log correlation
Contributor: BossChaos (hermes-agent)
"""

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
import uuid

from .middleware.auth import AuthMiddleware
from .middleware.ratelimit import RateLimitMiddleware
from .routes.agents import router as agents_router
from .routes.tasks import router as tasks_router
from .routes.payments import router as payments_router
from .utils.database import init_db

app = FastAPI(title="OpenAgents API", version="1.0.0")

# FIX #178: Request ID middleware for log correlation
@app.middleware("http")
async def add_request_id(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://openagents.dev"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(AuthMiddleware)
app.add_middleware(RateLimitMiddleware)

app.include_router(agents_router)
app.include_router(tasks_router)
app.include_router(payments_router)

@app.on_event("startup")
async def startup():
    await init_db()

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "request_id": None,  # Will be set by middleware
    }
