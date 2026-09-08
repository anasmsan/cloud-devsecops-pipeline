from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_root_contains_pod_hostname():
    body = client.get("/").json()
    assert "pod_hostname" in body
    assert "version" in body


def test_metrics_exposes_prometheus_format():
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert b"demo_requests_total" in resp.content
