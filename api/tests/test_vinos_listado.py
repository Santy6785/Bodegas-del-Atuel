"""Tests del endpoint GET /vinos sin base de datos real.

Sobreescribe la dependencia ``get_conn`` con un fake para los casos que
requieren listado (200) y usa el fixture ``client`` de conftest.py para los
casos de validación (422), que responden antes de tocar la base.
"""

from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

from app.db.pool import get_conn
from app.main import app


class _FakeCursor:
    """Cursor falso cuyo fetchall devuelve filas con clave total (como listar_vinos)."""

    def __init__(self, rows: list[dict]):
        self.rows = rows

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, query, params=None):
        return self

    def fetchall(self):
        return self.rows

    def fetchone(self):
        return self.rows[0] if self.rows else None


class FakeConnListar:
    """Conexión falsa que simula un listado exitoso de vinos."""

    def __init__(self, total: int = 1):
        self.rows = [
            {
                "cod_vino": 1,
                "nombre": "TEST Vino Listado",
                "tipo": "tinto",
                "anada": 2021,
                "volumen_ml": 750,
                "graduacion": "14.00",
                "precio": "1000.00",
                "cuit_bodega": "99999999901",
                "bodega_razon_social": "Bodega Test",
                "total": total,
            }
        ]

    def cursor(self):
        return _FakeCursor(self.rows)

    def close(self):
        pass


def _fake_conn_listar() -> Generator[FakeConnListar, None, None]:
    yield FakeConnListar()


def test_listar_vinos_sin_parametros_200_y_claves(client: TestClient):
    """GET /vinos sin parámetros → 200 y cuerpo con items, page, page_size, total."""
    app.dependency_overrides[get_conn] = _fake_conn_listar
    try:
        resp = client.get("/vinos")
    finally:
        app.dependency_overrides.clear()
    assert resp.status_code == 200
    body = resp.json()
    assert set(body.keys()) == {"items", "page", "page_size", "total"}
    assert body["page"] == 1
    assert body["page_size"] == 20
    assert isinstance(body["items"], list)
    assert isinstance(body["total"], int)


def test_listar_vinos_page_size_100_200(client: TestClient):
    """GET /vinos con page_size=100 (límite válido) → 200."""
    app.dependency_overrides[get_conn] = _fake_conn_listar
    try:
        resp = client.get("/vinos", params={"page_size": 100})
    finally:
        app.dependency_overrides.clear()
    assert resp.status_code == 200
    body = resp.json()
    assert body["page_size"] == 100


def test_listar_vinos_page_0_422(client: TestClient):
    """GET /vinos con page=0 → 422 (validación, sin tocar la base)."""
    resp = client.get("/vinos", params={"page": 0})
    assert resp.status_code == 422


def test_listar_vinos_page_size_101_422(client: TestClient):
    """GET /vinos con page_size=101 → 422 (validación, sin tocar la base)."""
    resp = client.get("/vinos", params={"page_size": 101})
    assert resp.status_code == 422
