"""Pruebas del endpoint PUT /vinos/{cod} sin base de datos real."""

from decimal import Decimal
import pytest
from fastapi.testclient import TestClient

import app.routers.vinos as router_vinos


PAYLOAD_VALIDO = {
    "nombre": "Malbec Gran Reserva",
    "tipo": "tinto",
    "anada": 2020,
    "volumen_ml": 750,
    "graduacion": "14.50",
    "precio": "15000.00",
    "cuit_bodega": "30123456789",
    "composicion": [
        {"id_cepa": 1, "porcentaje": "85.00"},
        {"id_cepa": 2, "porcentaje": "15.00"},
    ],
    "maridajes": [1, 2],
}


def test_actualizar_vino_ok(client: TestClient, monkeypatch):
    """PUT /vinos/{cod} con datos válidos actualiza y devuelve el vino (200)."""
    llamadas_actualizar = []

    def mock_actualizar(conn, cod_vino, datos):
        llamadas_actualizar.append((cod_vino, datos))
        return 1

    vino_db = {
        "cod_vino": 10,
        "nombre": "Malbec Gran Reserva",
        "tipo": "tinto",
        "anada": 2020,
        "volumen_ml": 750,
        "graduacion": Decimal("14.50"),
        "precio": Decimal("15000.00"),
        "cuit_bodega": "30123456789",
        "bodega": {"cuit": "30123456789", "razon_social": "Bodega Ejemplo"},
        "stock": {"deposito": 100, "salas": 50, "total": 150},
    }
    comp_db = [
        {"id_cepa": 1, "nombre": "Malbec", "tipo": "tinta", "porcentaje": Decimal("85.00")},
        {"id_cepa": 2, "nombre": "Cabernet", "tipo": "tinta", "porcentaje": Decimal("15.00")},
    ]
    maridajes_db = [{"id_maridaje": 1, "nombre": "Carnes rojas", "temperatura_servicio": 17}]

    monkeypatch.setattr(router_vinos, "actualizar_vino", mock_actualizar)
    monkeypatch.setattr(router_vinos, "obtener_vino", lambda conn, cod: dict(vino_db))
    monkeypatch.setattr(router_vinos, "obtener_composicion_vino", lambda conn, cod: comp_db)
    monkeypatch.setattr(router_vinos, "obtener_maridajes_vino", lambda conn, cod: maridajes_db)

    resp = client.put("/vinos/10", json=PAYLOAD_VALIDO)

    assert resp.status_code == 200
    assert len(llamadas_actualizar) == 1
    assert llamadas_actualizar[0][0] == 10
    assert llamadas_actualizar[0][1]["nombre"] == "Malbec Gran Reserva"

    body = resp.json()
    assert body["cod_vino"] == 10
    assert body["nombre"] == "Malbec Gran Reserva"
    assert len(body["composicion"]) == 2
    assert len(body["maridajes"]) == 1


def test_actualizar_vino_inexistente_404(client: TestClient, monkeypatch):
    """PUT /vinos/{cod} con vino inexistente devuelve 404."""
    monkeypatch.setattr(router_vinos, "actualizar_vino", lambda conn, cod, datos: 0)

    resp = client.put("/vinos/99999", json=PAYLOAD_VALIDO)
    assert resp.status_code == 404


def test_actualizar_vino_value_error_traduce_a_422(client: TestClient, monkeypatch):
    """PUT /vinos/{cod} traduce ValueError de la capa de queries a 422."""
    def mock_actualizar(conn, cod_vino, datos):
        raise ValueError("Error en la composicion varietal")

    monkeypatch.setattr(router_vinos, "actualizar_vino", mock_actualizar)

    resp = client.put("/vinos/10", json=PAYLOAD_VALIDO)
    assert resp.status_code == 422


@pytest.mark.parametrize("cod", ["0", "-1", "abc"])
def test_actualizar_vino_codigo_invalido_422(client: TestClient, cod):
    """PUT /vinos/{cod} con código inválido devuelve 422."""
    resp = client.put(f"/vinos/{cod}", json=PAYLOAD_VALIDO)
    assert resp.status_code == 422


def test_actualizar_vino_payload_invalido_422(client: TestClient):
    """PUT /vinos/{cod} con payload incompleto devuelve 422."""
    resp = client.put("/vinos/10", json={"nombre": "Malbec Incompleto"})
    assert resp.status_code == 422


def test_eliminar_vino_sigue_funcionando(client: TestClient, monkeypatch):
    """DELETE /vinos/{cod} sigue funcionando (204 cuando existe, 404 cuando no)."""
    monkeypatch.setattr(router_vinos, "eliminar_vino", lambda conn, cod: 1)
    resp = client.delete("/vinos/10")
    assert resp.status_code == 204

    monkeypatch.setattr(router_vinos, "eliminar_vino", lambda conn, cod: 0)
    resp = client.delete("/vinos/999")
    assert resp.status_code == 404
