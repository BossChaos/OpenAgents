"""openapi.py - OpenAPI 3.0 schema generation"""
from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi
from typing import get_type_hints

def generate_openapi_with_auth(app: FastAPI) -> dict:
    """Generate OpenAPI schema with security schemes"""
    if app.openapi_schema:
        return app.openapi_schema

    schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
    )

    # Add security scheme
    schema["components"]["securitySchemes"] = {
        "BearerAuth": {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
            "description": "JWT token obtained from /auth/login"
        },
        "ApiKeyAuth": {
            "type": "apiKey",
            "in": "header",
            "name": "X-API-Key",
            "description": "API key for service-to-service calls"
        }
    }

    # Apply security to all operations
    for path, methods in schema["paths"].items():
        for method, operation in methods.items():
            if method in ("get", "post", "put", "delete", "patch"):
                operation["security"] = [{"BearerAuth": []}]

    # Add rate limit headers
    for path, methods in schema["paths"].items():
        for method, operation in methods.items():
            operation["responses"]["429"] = {
                "description": "Rate limit exceeded",
                "headers": {
                    "X-RateLimit-Limit": {"schema": {"type": "integer"}, "description": "Requests per window"},
                    "X-RateLimit-Remaining": {"schema": {"type": "integer"}, "description": "Remaining requests"},
                    "X-RateLimit-Reset": {"schema": {"type": "integer"}, "description": "Unix timestamp of reset"}
                }
            }

    app.openapi_schema = schema
    return schema

def setup_openapi(app: FastAPI):
    """Attach custom OpenAPI to app"""
    app.openapi = lambda: generate_openapi_with_auth(app)
