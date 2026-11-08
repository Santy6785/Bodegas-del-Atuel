"""Fixtures compartidas para los tests de la API."""

from collections.abc import Generator
from contextlib import asynccontextmanager

import pytest
from fastapi.testclient import TestClient

from app.db.pool import get_conn
from app.main import app


class FakeConn:
    """Conexión falsa: simula una consulta exitosa sin base real."""

    def execute(self, query, params=None):
        return self

    def fetchone(self):
        return {"ok": 1}


def _fake_conn_ok() -> Generator[FakeConn, None, None]:
    yield FakeConn()


@asynccontextmanager
async def _lifespan_vacio(_app):
    """Reemplaza el lifespan para no abrir el pool real en tests."""
    yield


@pytest.fixture()
def client() -> Generator[TestClient, None, None]:
    """TestClient con conexión falsa y sin pool real."""
    original_lifespan = app.router.lifespan_context
    app.router.lifespan_context = _lifespan_vacio
    app.dependency_overrides[get_conn] = _fake_conn_ok
    try:
        with TestClient(app) as c:
            yield c
    finally:
        app.dependency_overrides.clear()
        app.router.lifespan_context = original_lifespan