// SPDX-License-Identifier: MIT
"""main.py - FastAPI with CORS configuration"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# FIX #121: Explicit CORS configuration
ALLOWED_ORIGINS = [
    "https://app.openagents.com",
    "https://dashboard.openagents.com",
    "http://localhost:3000",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,  # Explicit list, not wildcard
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    expose_headers=["X-Request-ID"],
    max_age=600,  # 10 minutes cache for preflight
)

@app.get("/health")
async def health():
    return {"status": "ok"}
