"""Tests del endpoint GET /salud."""

from collections.abc import Generator

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.db.pool import get_conn
from app.main import app


class FailConn:
    """Conexión falsa que falla en cualquier consulta."""

    def execute(self, query, params=None):
        raise psycopg.OperationalError("conexión simulada fallida")


def _fake_conn_fail() -> Generator[FailConn, None, None]:
    yield FailConn()

# Caso OK

def test_salud_ok(client):
    """Devuelve 200 y base_de_datos 'ok' cuando la base responde."""
    resp = client.get("/salud")
    assert resp.status_code == 200
    assert resp.json() == {"estado": "ok", "base_de_datos": "ok"}


def test_salud_no_expone_entorno(client):
    """No expone host, puerto, base ni usuario."""
    body = client.get("/salud").json()
    for clave in ("host", "puerto", "base_datos", "usuario", "db"):
        assert clave not in body

# Caso error

def test_salud_error_503(client):
    """Devuelve 503 cuando la consulta a la base falla."""
    app.dependency_overrides[get_conn] = _fake_conn_fail
    resp = client.get("/salud")
    assert resp.status_code == 503
    assert resp.json() == {"estado": "error", "base_de_datos": "inaccesible"}