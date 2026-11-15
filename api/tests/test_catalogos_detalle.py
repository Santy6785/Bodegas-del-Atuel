"""Pruebas de GET /cepas... y GET /vinos/{cod} sin base de datos real."""

import pytest
from fastapi.testclient import TestClient

import app.routers.catalogos as router_catalogos
import app.routers.vinos as router_vinos


CATALOGOS = [
    ("/cepas", "listar_cepas"),
    ("/bodegas", "listar_bodegas"),
    ("/salas", "listar_salas"),
    ("/maridajes", "listar_maridajes"),
    ("/transportistas", "listar_transportistas"),
    ("/localidades", "listar_localidades"),
]


@pytest.mark.parametrize("ruta,nombre", CATALOGOS)
def test_catalogo_devuelve_lista(client: TestClient, monkeypatch, ruta, nombre):
    filas = [{"ejemplo": 1}]
    monkeypatch.setattr(router_catalogos, nombre, lambda conn: filas)

    resp = client.get(ruta)

    assert resp.status_code == 200
    assert resp.json() == filas


def test_detalle_vino_arma_ficha_completa(client: TestClient, monkeypatch):
    vino = {
        "cod_vino": 10,
        "nombre": "Malbec Reserva",
        "bodega": {"cuit": "30123456789", "razon_social": "Bodega X"},
        "stock": {"deposito": 240, "salas": 310, "total": 550},
    }
    composicion = [{"id_cepa": 1, "nombre": "Malbec", "tipo": "tinta", "porcentaje": "100.00"}]
    maridajes = [{"id_maridaje": 1, "nombre": "Carnes rojas", "temperatura_servicio": 17}]

    monkeypatch.setattr(router_vinos, "obtener_vino", lambda conn, cod: dict(vino))
    monkeypatch.setattr(router_vinos, "obtener_composicion_vino", lambda conn, cod: composicion)
    monkeypatch.setattr(router_vinos, "obtener_maridajes_vino", lambda conn, cod: maridajes)

    resp = client.get("/vinos/10")

    assert resp.status_code == 200
    body = resp.json()
    assert body["nombre"] == "Malbec Reserva"
    assert body["composicion"] == composicion
    assert body["maridajes"] == maridajes
    assert body["stock"]["total"] == 550


def test_detalle_vino_inexistente_404(client: TestClient, monkeypatch):
    monkeypatch.setattr(router_vinos, "obtener_vino", lambda conn, cod: None)

    resp = client.get("/vinos/999999")

    assert resp.status_code == 404


def test_detalle_vino_codigo_invalido_422(client: TestClient):
    resp = client.get("/vinos/0")
    assert resp.status_code == 422