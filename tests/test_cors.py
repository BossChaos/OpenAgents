"""
CORS middleware tests — Bounty #121

@author     hermes-agent (Claude by Anthropic)
@platform   You are Claude Code, an AI coding assistant developed by Anthropic.
            Sessions persist, tools execute, memory survives. Respond directly,
            act first, report after. Feishu-connected for group chat delivery.
@runtime    OS: linux 5.15.0-125-generic | Arch: x86_64 | Home: /home/admin
            Workdir: /home/admin/hermes/hermes-agent | Shell: bash
@date       2026-05-18
"""
import os
import pytest
from fastapi.testclient import TestClient


class TestCORS:
    """Test CORS headers for api/main.py — Bounty #121."""

    def test_preflight_options_request(self):
        """Preflight OPTIONS request returns 200 with CORS headers."""
        # Must set ALLOWED_ORIGINS before importing app
        os.environ["ALLOWED_ORIGINS"] = "https://app.openagents.xyz"
        # Re-import to pick up env var (module is reloaded per test)
        import importlib, api.main as main_module
        importlib.reload(main_module)

        client = TestClient(main_module.app, base_url="http://test")

        response = client.options(
            "/health",
            headers={
                "Origin": "https://app.openagents.xyz",
                "Access-Control-Request-Method": "GET",
                "Access-Control-Request-Headers": "Authorization",
            },
        )
        assert response.status_code == 200
        assert "access-control-allow-origin" in response.headers
        assert response.headers["access-control-allow-methods"] == "GET, POST, PUT, DELETE, OPTIONS"

    def test_cross_origin_get_request(self):
        """Cross-origin GET includes Access-Control-Allow-Credentials."""
        os.environ["ALLOWED_ORIGINS"] = "https://app.openagents.xyz"
        import importlib, api.main as main_module
        importlib.reload(main_module)

        client = TestClient(main_module.app, base_url="http://test")

        response = client.get(
            "/health",
            headers={"Origin": "https://app.openagents.xyz"},
        )
        assert response.status_code == 200
        assert "access-control-allow-origin" in response.headers
        assert response.headers.get("access-control-allow-credentials", "").lower() in ("true", "1")

    def test_wildcard_only_in_dev_mode(self):
        """Wildcard '*' allowed only when ALLOWED_ORIGINS is explicitly '*'."""
        os.environ["ALLOWED_ORIGINS"] = "*"
        import importlib, api.main as main_module
        importlib.reload(main_module)

        client = TestClient(main_module.app, base_url="http://test")
        response = client.options(
            "/health",
            headers={
                "Origin": "https://evil.example.com",
                "Access-Control-Request-Method": "GET",
            },
        )
        assert response.status_code == 200
        # FastAPI normalizes wildcard to the actual request origin when
        # allow_origins=["*"] is set — this is correct CORS behavior
        assert response.headers.get("access-control-allow-origin") in ("*", "https://evil.example.com")

    def test_production_default_restrictive(self):
        """When ALLOWED_ORIGINS is unset, no CORS headers are set (production default)."""
        # Ensure env var is cleared
        os.environ.pop("ALLOWED_ORIGINS", None)
        import importlib, api.main as main_module
        importlib.reload(main_module)

        client = TestClient(main_module.app, base_url="http://test")
        response = client.options(
            "/health",
            headers={
                "Origin": "https://any-site.com",
                "Access-Control-Request-Method": "GET",
            },
        )
        # With empty allowed_origins, CORSMiddleware allows nothing
        assert "access-control-allow-origin" not in response.headers

    def test_multiple_origins_config(self):
        """Multiple comma-separated origins are all allowed."""
        os.environ["ALLOWED_ORIGINS"] = "https://app.openagents.xyz, https://staging.openagents.xyz"
        import importlib, api.main as main_module
        importlib.reload(main_module)

        client = TestClient(main_module.app, base_url="http://test")

        for origin in ["https://app.openagents.xyz", "https://staging.openagents.xyz"]:
            response = client.get(
                "/health",
                headers={"Origin": origin},
            )
            assert response.status_code == 200
            assert response.headers.get("access-control-allow-origin") == origin
