"""Pruebas de endpoints GET /transferencias y GET /transferencias/{nro} sin base de datos real."""

import pytest
from fastapi.testclient import TestClient

import app.routers.transferencias as router_transferencias


def test_listar_transferencias_por_defecto_200(client: TestClient, monkeypatch):
    """GET /transferencias sin parámetros devuelve 200 con paginación por defecto."""
    llamadas = []

    def mock_listar(conn, *, page=1, page_size=20, estado=None, id_sala=None):
        llamadas.append((page, page_size, estado, id_sala))
        return [{"nro_transferencia": 1, "id_sala": 1, "estado": "en_confeccion"}], 1

    monkeypatch.setattr(router_transferencias, "listar_transferencias", mock_listar)

    resp = client.get("/transferencias")

    assert resp.status_code == 200
    assert llamadas == [(1, 20, None, None)]
    body = resp.json()
    assert body["page"] == 1
    assert body["page_size"] == 20
    assert body["total"] == 1
    assert len(body["items"]) == 1


def test_listar_transferencias_con_filtros_200(client: TestClient, monkeypatch):
    """GET /transferencias con filtros de estado y sala los transmite a la DAL."""
    llamadas = []

    def mock_listar(conn, *, page=1, page_size=20, estado=None, id_sala=None):
        llamadas.append((page, page_size, estado, id_sala))
        return [], 0

    monkeypatch.setattr(router_transferencias, "listar_transferencias", mock_listar)

    resp = client.get("/transferencias?page=2&page_size=10&estado=terminado&id_sala=3")

    assert resp.status_code == 200
    assert llamadas == [(2, 10, "terminado", 3)]
    body = resp.json()
    assert body["page"] == 2
    assert body["page_size"] == 10
    assert body["total"] == 0
    assert body["items"] == []


@pytest.mark.parametrize(
    "param",
    ["page=0", "page=-1", "page_size=0", "page_size=101", "id_sala=0", "id_sala=-1", "estado=invalido"],
)
def test_listar_transferencias_parametros_invalidos_422(client: TestClient, param):
    """GET /transferencias valida parámetros de consulta y responde 422."""
    resp = client.get(f"/transferencias?{param}")
    assert resp.status_code == 422


def test_obtener_transferencia_ok_200(client: TestClient, monkeypatch):
    """GET /transferencias/{nro} devuelve cabecera y renglones con HTTP 200."""
    transferencia = {
        "nro_transferencia": 55,
        "id_sala": 1,
        "fecha_confeccion": "2026-11-03",
        "estado": "en_confeccion",
        "renglones": [
            {"cod_vino": 10, "cantidad": 24},
            {"cod_vino": 12, "cantidad": 12},
        ],
    }
    monkeypatch.setattr(
        router_transferencias,
        "obtener_transferencia",
        lambda conn, nro: dict(transferencia),
    )

    resp = client.get("/transferencias/55")

    assert resp.status_code == 200
    body = resp.json()
    assert body["nro_transferencia"] == 55
    assert body["estado"] == "en_confeccion"
    assert len(body["renglones"]) == 2


def test_obtener_transferencia_inexistente_404(client: TestClient, monkeypatch):
    """GET /transferencias/{nro} devuelve 404 si la transferencia no existe."""
    monkeypatch.setattr(router_transferencias, "obtener_transferencia", lambda conn, nro: None)

    resp = client.get("/transferencias/99999")
    assert resp.status_code == 404


@pytest.mark.parametrize("nro", ["0", "-1", "abc"])
def test_obtener_transferencia_nro_invalido_422(client: TestClient, nro):
    """GET /transferencias/{nro} con nro no positivo o no numérico devuelve 422."""
    resp = client.get(f"/transferencias/{nro}")
    assert resp.status_code == 422
