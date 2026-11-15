"""Tests del endpoint GET /clientes sin base de datos real.

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
    """Cursor falso cuyo fetchall devuelve filas con clave total (como listar_clientes)."""

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
    """Conexión falsa que simula un listado exitoso de clientes."""

    def __init__(self, total: int = 1):
        self.rows = [
            {
                "id_cliente": 1,
                "apellido_razon_social": "TEST Cliente",
                "nombre": "Juan",
                "tipo_documento": "DNI",
                "nro_documento": "12345678",
                "direccion": "Calle Falsa 123",
                "codigo_postal": "5500",
                "fecha_alta": "2024-01-01",
                "tipo_cliente": "socio",
                "descuento_pct": "10.00",
                "total": total,
            }
        ]

    def cursor(self):
        return _FakeCursor(self.rows)

    def close(self):
        pass


def _fake_conn_listar() -> Generator[FakeConnListar, None, None]:
    yield FakeConnListar()


def test_listar_clientes_sin_parametros_200_y_claves(client: TestClient):
    """GET /clientes sin parámetros → 200 y cuerpo con items, page, page_size, total."""
    app.dependency_overrides[get_conn] = _fake_conn_listar
    try:
        resp = client.get("/clientes")
    finally:
        app.dependency_overrides.clear()
    assert resp.status_code == 200
    body = resp.json()
    assert set(body.keys()) == {"items", "page", "page_size", "total"}
    assert body["page"] == 1
    assert body["page_size"] == 20
    assert isinstance(body["items"], list)
    assert isinstance(body["total"], int)


def test_listar_clientes_page_0_422(client: TestClient):
    """GET /clientes con page=0 → 422 (validación, sin tocar la base)."""
    resp = client.get("/clientes", params={"page": 0})
    assert resp.status_code == 422


def test_listar_clientes_page_size_101_422(client: TestClient):
    """GET /clientes con page_size=101 → 422 (validación, sin tocar la base)."""
    resp = client.get("/clientes", params={"page_size": 101})
    assert resp.status_code == 422


def test_listar_clientes_tipo_cliente_invalido_422(client: TestClient):
    """GET /clientes con tipo_cliente='otro' → 422 (validación, sin tocar la base)."""
    resp = client.get("/clientes", params={"tipo_cliente": "otro"})
    assert resp.status_code == 422
