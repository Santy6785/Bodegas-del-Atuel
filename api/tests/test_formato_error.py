"""Verifica que todos los errores HTTP usen el formato del contrato §1.1."""

import pytest
from fastapi.testclient import TestClient

import app.routers.vinos as router_vinos


def _assert_formato(body: dict) -> None:
    """El cuerpo debe tener exactamente la raíz 'error' y sus tres campos."""
    assert set(body.keys()) == {"error"}
    assert set(body["error"].keys()) == {"sqlstate", "mensaje", "restriccion"}


def test_404_de_ruta_inexistente_usa_formato_contrato(client: TestClient):
    resp = client.get("/ruta-que-no-existe")

    assert resp.status_code == 404
    body = resp.json()
    _assert_formato(body)
    assert body["error"]["sqlstate"] is None
    assert body["error"]["restriccion"] is None
    assert body["error"]["mensaje"] == "Not Found"


def test_404_de_recurso_inexistente_usa_formato_contrato(client: TestClient, monkeypatch):
    monkeypatch.setattr(router_vinos, "obtener_vino", lambda conn, cod: None)

    resp = client.get("/vinos/999999")

    assert resp.status_code == 404
    body = resp.json()
    _assert_formato(body)
    assert body["error"]["mensaje"] == "Vino 999999 no encontrado"


def test_405_usa_formato_contrato_y_conserva_allow(client: TestClient):
    resp = client.patch("/vinos/1")

    assert resp.status_code == 405
    _assert_formato(resp.json())
    assert resp.json()["error"]["sqlstate"] is None
    assert "allow" in {k.lower() for k in resp.headers.keys()}


def test_422_de_validacion_usa_formato_contrato(client: TestClient):
    resp = client.get("/vinos/0")

    assert resp.status_code == 422
    body = resp.json()
    _assert_formato(body)
    assert body["error"]["sqlstate"] is None
    assert "cod_vino" in body["error"]["mensaje"]