import pytest
from fastapi.testclient import TestClient

from sample_api.main import app


@pytest.fixture()
def client() -> TestClient:
    return TestClient(app)


def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_readyz(client):
    assert client.get("/readyz").json() == {"status": "ready"}


def test_version_reports_build(client):
    body = client.get("/version").json()
    assert set(body) == {"service", "version", "git_sha", "environment", "started_at"}


def test_root_points_to_health(client):
    assert client.get("/").json()["health"] == "/healthz"


def test_security_headers(client):
    r = client.get("/healthz")
    assert r.headers["X-Content-Type-Options"] == "nosniff"
    assert r.headers["Cache-Control"] == "no-store"


def test_quote_standard(client):
    r = client.post("/api/v1/quotes", json={"weight_kg": 2, "distance_km": 100})
    assert r.status_code == 200
    # 4.90 + 2*0.85 + 100*0.012 = 7.80
    assert r.json() == {"price_eur": 7.8, "currency": "EUR"}


def test_quote_express_costs_more(client):
    std = client.post("/api/v1/quotes", json={"weight_kg": 2, "distance_km": 100}).json()
    exp = client.post(
        "/api/v1/quotes", json={"weight_kg": 2, "distance_km": 100, "express": True}
    ).json()
    assert exp["price_eur"] == pytest.approx(std["price_eur"] * 1.5, abs=0.01)


@pytest.mark.parametrize(
    "payload",
    [
        {"weight_kg": 0, "distance_km": 10},
        {"weight_kg": -1, "distance_km": 10},
        {"weight_kg": 1, "distance_km": 0},
        {"weight_kg": 5000, "distance_km": 10},
        {"distance_km": 10},
    ],
)
def test_quote_rejects_invalid_input(client, payload):
    assert client.post("/api/v1/quotes", json=payload).status_code == 422
