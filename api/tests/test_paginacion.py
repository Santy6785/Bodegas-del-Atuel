"""Pruebas automáticas para la API Bodegas del Atuel - Issue #56.

Pruebas de lectura masiva y paginación.
"""

from __future__ import annotations

import pytest
from fastapi import status
from fastapi.testclient import TestClient
from unittest.mock import MagicMock

from api.app.main import app
from api.app.routers import vinos, clientes, reportes


# ---------------------------------------------------------------------------
# Helper para parsear respuestas paginadas
# ---------------------------------------------------------------------------

def _parse_items(resp):
    """Extraer items y metadata de la respuesta paginada."""
    body = resp.json()
    return body.get("items", []), body.get("page"), body.get("page_size"), body.get("total"), body.get("totalPages")


# ---------------------------------------------------------------------------
# Pruebas de paginación - /vinos
# ---------------------------------------------------------------------------

@pytest.mark.pagination
class TestVinosPagination:
    """Pruebas de paginación del catálogo de vinos."""

    def test_page_cero_422(self, client, monkeypatch):
        """GET /vinos/?page=0 debe devolver 422."""
        # Configurar mock psycopg para validación de página
        mock_psycopg = MagicMock()
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda self: mock_cursor
        mock_cursor.__exit__ = lambda self, *args: None
        mock_cursor.execute.return_value = None
        # page=0 < 1 lanza 422 antes de ejecutar query
        mock_conn.cursor.return_value = mock_cursor
        mock_psycopg.connect.return_value = mock_conn
        monkeypatch.setattr(vinos, "psycopg", mock_psycopg)

        resp = client.get("/vinos/?page=0")
        assert resp.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY

    def test_page_size_mayor_al_maximo(self, client, monkeypatch):
        """GET /vinos/?page_size=101 debe devolver 422."""
        # Configurar mock psycopg para validación de page_size
        mock_psycopg = MagicMock()
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda self: mock_cursor
        mock_cursor.__exit__ = lambda self, *args: None
        mock_cursor.execute.return_value = None
        # page_size=101 > 100 lanza 422 antes de ejecutar query
        mock_conn.cursor.return_value = mock_cursor
        mock_psycopg.connect.return_value = mock_conn
        monkeypatch.setattr(vinos, "psycopg", mock_psycopg)

        resp = client.get("/vinos/?page_size=101")
        assert resp.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY

    def test_page_no_numerico(self, client, monkeypatch):
        """GET /vinos/?page=abc debe devolver 422 (validación Pydantic)."""
        # Con mock psycopg, la validación Pydantic lanza 422 antes de la query
        mock_psycopg = MagicMock()
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda self: mock_cursor
        mock_cursor.__exit__ = lambda self, *args: None
        mock_cursor.execute.return_value = None
        mock_conn.cursor.return_value = mock_cursor
        mock_psycopg.connect.return_value = mock_conn
        monkeypatch.setattr(vinos, "psycopg", mock_psycopg)

        resp = client.get("/vinos/?page=abc")
        assert resp.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY

    def test_pagina_inexistente_vacía(self, client, monkeypatch):
        """GET /vinos/?page=9999&page_size=10 debe devolver 200 con items vacío."""
        # Configurar mock: fetchone retorna (0,) => total = 0
        # y fetchall retorna [] => items vacío
        # El router usa "with conn.cursor() as cur:", por lo que hay que
        # configurar __enter__ para que cur sea el propio mock_cursor
        mock_psycopg = MagicMock()
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda self: mock_cursor
        mock_cursor.__exit__ = lambda self, *args: None
        mock_cursor.execute.return_value = None
        mock_cursor.fetchone.return_value = (0,)  # total = 0
        mock_cursor.fetchall.return_value = []  # items = []
        mock_conn.cursor.return_value = mock_cursor
        mock_psycopg.connect.return_value = mock_conn

        monkeypatch.setattr(vinos, "psycopg", mock_psycopg)

        resp = client.get("/vinos/?page=9999&page_size=10")
        assert resp.status_code == 200
        items, page, page_size, total, total_pages = _parse_items(resp)
        assert items == []
        assert total >= 0


# ---------------------------------------------------------------------------
# Pruebas de clientes - paginación
# ---------------------------------------------------------------------------

@pytest.mark.pagination
class TestClientesPagination:
    """Pruebas de paginación del listado de clientes."""

    def test_page_negativo_422(self, client, monkeypatch):
        """GET /clientes/?page=-1 debe devolver 422."""
        # Configurar mock psycopg para validación de página negativa
        mock_psycopg = MagicMock()
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda self: mock_cursor
        mock_cursor.__exit__ = lambda self, *args: None
        mock_cursor.execute.return_value = None
        # page=-1 < 1 lanza 422 antes de ejecutar query
        mock_conn.cursor.return_value = mock_cursor
        mock_psycopg.connect.return_value = mock_conn
        monkeypatch.setattr(clientes, "psycopg", mock_psycopg)

        resp = client.get("/clientes/?page=-1")
        assert resp.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY


# ---------------------------------------------------------------------------
# Pruebas de reportes
# ---------------------------------------------------------------------------

@pytest.mark.reports
class TestReportes:
    """Pruebas de reportes con volumen de datos."""

    def test_vinos_sin_stock_sin_id_sala_422(self, client, monkeypatch):
        """GET /reportes/vinos-sin-stock sin id_sala debe devolver 422."""
        # Configurar mock psycopg para el reporte vinos-sin-stock
        mock_psycopg = MagicMock()
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda self: mock_cursor
        mock_cursor.__exit__ = lambda self, *args: None
        mock_psycopg.connect.return_value = mock_conn
        monkeypatch.setattr(reportes, "psycopg", mock_psycopg)

        resp = client.get("/reportes/vinos-sin-stock")
        assert resp.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY

    def test_vinos_99999_no_encontrado_404(self, client, monkeypatch):
        """GET /vinos/99999 debe devolver 404 y JSON con 'detail' como string."""
        # Configurar mock: fetchone retorna None => trigger 404 en detalle_vino
        # También hay que configurar __enter__ para que funcione con "with conn.cursor() as cur:"
        mock_psycopg = MagicMock()
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda self: mock_cursor
        mock_cursor.__exit__ = lambda self, *args: None
        mock_cursor.execute.return_value = None
        mock_cursor.fetchone.return_value = None  # None trigger 404
        mock_cursor.fetchall.return_value = []
        mock_conn.cursor.return_value = mock_cursor
        mock_psycopg.connect.return_value = mock_conn

        monkeypatch.setattr(vinos, "psycopg", mock_psycopg)

        resp = client.get("/vinos/99999")
        assert resp.status_code == 404
        body = resp.json()
        assert isinstance(body["detail"], str)

    def test_top_vinos_con_items_lista(self, client, monkeypatch):
        """GET /reportes/top-vinos debe devolver 200 y que 'items' sea una lista."""
        # Configurar mock psycopg para el reporte top-vinos
        mock_psycopg = MagicMock()
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda self: mock_cursor
        mock_cursor.__exit__ = lambda self, *args: None
        mock_psycopg.connect.return_value = mock_conn
        monkeypatch.setattr(reportes, "psycopg", mock_psycopg)

        resp = client.get("/reportes/top-vinos")
        assert resp.status_code == 200
        body = resp.json()
        assert isinstance(body["items"], list)