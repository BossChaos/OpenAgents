"""
API Request ID Tests — Bounty #178
Request ID middleware for log correlation.
"""
import pytest
from fastapi.testclient import TestClient
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))
from main import app

client = TestClient(app)


class TestRequestID:
    """Tests for X-Request-ID middleware (Bounty #178)."""

    def test_generates_unique_request_id_per_request(self):
        """Each request gets a unique UUID request ID."""
        res1 = client.get("/health")
        res2 = client.get("/health")

        id1 = res1.headers.get("x-request-id")
        id2 = res2.headers.get("x-request-id")

        assert id1 is not None, "x-request-id header missing"
        assert len(id1) == 36, f"Expected UUID length 36, got {len(id1)}"
        assert id2 is not None
        assert id1 != id2, "Request IDs should be unique"

    def test_uses_client_provided_request_id(self):
        """If client sends X-Request-ID, use it (idempotency key pattern)."""
        custom_id = "my-custom-request-id-12345"
        res = client.get("/health", headers={"X-Request-ID": custom_id})

        assert res.headers.get("x-request-id") == custom_id

    def test_request_id_on_all_endpoints(self):
        """All API endpoints return X-Request-ID header."""
        endpoints = ["/health", "/agents", "/tasks", "/leaderboard"]
        for endpoint in endpoints:
            res = client.get(endpoint)
            assert "x-request-id" in res.headers, f"Missing x-request-id on {endpoint}"
            assert len(res.headers["x-request-id"]) == 36

    def test_request_id_in_response_body_health(self):
        """Health endpoint includes request ID in response body."""
        res = client.get("/health")
        assert res.status_code == 200
        assert "request_id" in res.json()
        assert len(res.json()["request_id"]) == 36
