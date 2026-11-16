"""Pruebas CRUD para el recurso Clientes (contrato §4.2) sin base de datos real."""

from datetime import date
from decimal import Decimal
import pytest
from fastapi.testclient import TestClient

import app.routers.clientes as router_clientes


CLIENTE_SOCIO_PAYLOAD = {
    "apellido_razon_social": "Perez",
    "nombre": "Ana",
    "tipo_documento": "DNI",
    "nro_documento": "30111222",
    "direccion": "Calle 123",
    "codigo_postal": "M5600",
    "tipo_cliente": "socio",
}

CLIENTE_DISTRIBUIDOR_PAYLOAD = {
    "apellido_razon_social": "Distribuidora Cuyo S.A.",
    "nombre": None,
    "tipo_documento": "CUIT",
    "nro_documento": "30123456789",
    "direccion": "Av. Mitre 500",
    "codigo_postal": "M5600",
    "tipo_cliente": "distribuidor",
    "distribuidor": {
        "zona_cobertura": "Cuyo",
        "nro_habilitacion": "HAB-2026-01",
    },
}

CLIENTE_EXPORTADOR_PAYLOAD = {
    "apellido_razon_social": "Exportadora Sur S.A.",
    "nombre": None,
    "tipo_documento": "CUIT",
    "nro_documento": "30987654321",
    "direccion": "Av. Ejemplo 500",
    "codigo_postal": "M5600",
    "tipo_cliente": "exportador",
    "exportador": {
        "pais_destino": "Brasil",
        "permisos": [
            {
                "codigo": "PE-001",
                "fecha_emision": "2026-01-01",
                "fecha_vencimiento": "2027-01-01",
            }
        ],
    },
}


# ---------------------------------------------------------------------------
# GET /clientes/{id}
# ---------------------------------------------------------------------------


def test_obtener_cliente_socio_200(client: TestClient, monkeypatch):
    cliente_db = {
        "id_cliente": 1,
        "apellido_razon_social": "Perez",
        "nombre": "Ana",
        "tipo_documento": "DNI",
        "nro_documento": "30111222",
        "direccion": "Calle 123",
        "codigo_postal": "M5600",
        "fecha_alta": date(2026, 1, 15),
        "tipo_cliente": "socio",
        "descuento_pct": Decimal("10.00"),
    }
    monkeypatch.setattr(router_clientes, "obtener_cliente", lambda conn, id_c: cliente_db)

    resp = client.get("/clientes/1")

    assert resp.status_code == 200
    body = resp.json()
    assert body["id_cliente"] == 1
    assert body["tipo_cliente"] == "socio"
    assert "distribuidor" not in body
    assert "exportador" not in body


def test_obtener_cliente_exportador_con_permisos_200(client: TestClient, monkeypatch):
    cliente_db = {
        "id_cliente": 2,
        "apellido_razon_social": "Exportadora Sur S.A.",
        "nombre": None,
        "tipo_documento": "CUIT",
        "nro_documento": "30987654321",
        "direccion": "Av. Ejemplo 500",
        "codigo_postal": "M5600",
        "fecha_alta": date(2026, 1, 15),
        "tipo_cliente": "exportador",
        "descuento_pct": Decimal("30.00"),
        "exportador": {
            "pais_destino": "Brasil",
            "permisos": [
                {
                    "codigo": "PE-001",
                    "fecha_emision": "2026-01-01",
                    "fecha_vencimiento": "2027-01-01",
                }
            ],
        },
    }
    monkeypatch.setattr(router_clientes, "obtener_cliente", lambda conn, id_c: cliente_db)

    resp = client.get("/clientes/2")

    assert resp.status_code == 200
    body = resp.json()
    assert body["id_cliente"] == 2
    assert body["tipo_cliente"] == "exportador"
    assert body["exportador"]["pais_destino"] == "Brasil"
    assert len(body["exportador"]["permisos"]) == 1


def test_obtener_cliente_inexistente_404(client: TestClient, monkeypatch):
    monkeypatch.setattr(router_clientes, "obtener_cliente", lambda conn, id_c: None)

    resp = client.get("/clientes/99999")
    assert resp.status_code == 404


@pytest.mark.parametrize("id_cliente", ["0", "-1", "abc"])
def test_obtener_cliente_id_invalido_422(client: TestClient, id_cliente):
    resp = client.get(f"/clientes/{id_cliente}")
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /clientes
# ---------------------------------------------------------------------------


def test_crear_cliente_socio_201(client: TestClient, monkeypatch):
    llamadas_crear = []

    def mock_crear(conn, datos):
        llamadas_crear.append(datos)
        return 5

    cliente_creado = {
        "id_cliente": 5,
        **CLIENTE_SOCIO_PAYLOAD,
        "fecha_alta": "2026-11-16",
        "descuento_pct": "10.00",
    }
    monkeypatch.setattr(router_clientes, "crear_cliente", mock_crear)
    monkeypatch.setattr(router_clientes, "obtener_cliente", lambda conn, id_c: cliente_creado)

    resp = client.post("/clientes", json=CLIENTE_SOCIO_PAYLOAD)

    assert resp.status_code == 201
    assert resp.headers.get("location") == "/clientes/5"
    assert len(llamadas_crear) == 1
    assert llamadas_crear[0]["tipo_cliente"] == "socio"
    body = resp.json()
    assert body["id_cliente"] == 5
    assert body["tipo_cliente"] == "socio"


def test_crear_cliente_distribuidor_201(client: TestClient, monkeypatch):
    monkeypatch.setattr(router_clientes, "crear_cliente", lambda conn, d: 8)
    monkeypatch.setattr(
        router_clientes,
        "obtener_cliente",
        lambda conn, id_c: {"id_cliente": 8, **CLIENTE_DISTRIBUIDOR_PAYLOAD},
    )

    resp = client.post("/clientes", json=CLIENTE_DISTRIBUIDOR_PAYLOAD)

    assert resp.status_code == 201
    assert resp.headers.get("location") == "/clientes/8"
    assert resp.json()["id_cliente"] == 8


def test_crear_cliente_exportador_201(client: TestClient, monkeypatch):
    monkeypatch.setattr(router_clientes, "crear_cliente", lambda conn, d: 9)
    monkeypatch.setattr(
        router_clientes,
        "obtener_cliente",
        lambda conn, id_c: {"id_cliente": 9, **CLIENTE_EXPORTADOR_PAYLOAD},
    )

    resp = client.post("/clientes", json=CLIENTE_EXPORTADOR_PAYLOAD)

    assert resp.status_code == 201
    assert resp.headers.get("location") == "/clientes/9"
    assert resp.json()["id_cliente"] == 9


def test_crear_cliente_value_error_traduce_a_422(client: TestClient, monkeypatch):
    def mock_crear(conn, datos):
        raise ValueError("tipo_cliente socio no debe incluir bloque distribuidor")

    monkeypatch.setattr(router_clientes, "crear_cliente", mock_crear)

    resp = client.post("/clientes", json=CLIENTE_SOCIO_PAYLOAD)
    assert resp.status_code == 422


def test_crear_cliente_payload_invalido_422(client: TestClient):
    resp = client.post("/clientes", json={"apellido_razon_social": "Incompleto"})
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# PUT /clientes/{id}
# ---------------------------------------------------------------------------


def test_actualizar_cliente_200(client: TestClient, monkeypatch):
    llamadas_actualizar = []

    def mock_actualizar(conn, id_c, datos):
        llamadas_actualizar.append((id_c, datos))
        return 1

    cliente_act = {
        "id_cliente": 1,
        **CLIENTE_SOCIO_PAYLOAD,
        "direccion": "Nueva Calle 456",
    }
    monkeypatch.setattr(router_clientes, "actualizar_cliente", mock_actualizar)
    monkeypatch.setattr(router_clientes, "obtener_cliente", lambda conn, id_c: cliente_act)

    payload = {**CLIENTE_SOCIO_PAYLOAD, "direccion": "Nueva Calle 456"}
    resp = client.put("/clientes/1", json=payload)

    assert resp.status_code == 200
    assert len(llamadas_actualizar) == 1
    assert llamadas_actualizar[0][0] == 1
    assert llamadas_actualizar[0][1]["direccion"] == "Nueva Calle 456"
    assert resp.json()["direccion"] == "Nueva Calle 456"


def test_actualizar_cliente_inexistente_404(client: TestClient, monkeypatch):
    monkeypatch.setattr(router_clientes, "actualizar_cliente", lambda conn, id_c, d: 0)

    resp = client.put("/clientes/99999", json=CLIENTE_SOCIO_PAYLOAD)
    assert resp.status_code == 404


def test_actualizar_cliente_value_error_traduce_a_422(client: TestClient, monkeypatch):
    def mock_actualizar(conn, id_c, datos):
        raise ValueError("el tipo de cliente no puede modificarse")

    monkeypatch.setattr(router_clientes, "actualizar_cliente", mock_actualizar)

    resp = client.put("/clientes/1", json=CLIENTE_SOCIO_PAYLOAD)
    assert resp.status_code == 422


@pytest.mark.parametrize("id_cliente", ["0", "-1", "abc"])
def test_actualizar_cliente_id_invalido_422(client: TestClient, id_cliente):
    resp = client.put(f"/clientes/{id_cliente}", json=CLIENTE_SOCIO_PAYLOAD)
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# DELETE /clientes/{id}
# ---------------------------------------------------------------------------


def test_eliminar_cliente_ok_204(client: TestClient, monkeypatch):
    llamadas_eliminar = []

    def mock_eliminar(conn, id_c):
        llamadas_eliminar.append(id_c)
        return 1

    monkeypatch.setattr(router_clientes, "eliminar_cliente", mock_eliminar)

    resp = client.delete("/clientes/1")

    assert resp.status_code == 204
    assert llamadas_eliminar == [1]


def test_eliminar_cliente_inexistente_404(client: TestClient, monkeypatch):
    monkeypatch.setattr(router_clientes, "eliminar_cliente", lambda conn, id_c: 0)

    resp = client.delete("/clientes/99999")
    assert resp.status_code == 404


@pytest.mark.parametrize("id_cliente", ["0", "-1", "abc"])
def test_eliminar_cliente_id_invalido_422(client: TestClient, id_cliente):
    resp = client.delete(f"/clientes/{id_cliente}")
    assert resp.status_code == 422
