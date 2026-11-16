"""Pruebas para el router del recurso Ingresos (contrato §4.5) sin base de datos real."""

import pytest
from fastapi.testclient import TestClient

import app.routers.ingresos as router_ingresos


PAYLOAD_INGRESO = {
    "fecha": "2026-11-03",
    "cod_transportista": 3,
    "cuit_bodega": "30123456789",
}

PAYLOAD_RENGLON = {
    "cod_vino": 10,
    "cantidad": 120,
}


# ---------------------------------------------------------------------------
# GET /ingresos
# ---------------------------------------------------------------------------


def test_listar_ingresos_por_defecto_200(client: TestClient, monkeypatch):
    """GET /ingresos sin parámetros devuelve 200 con paginación por defecto."""
    llamadas = []

    def mock_listar(conn, *, page=1, page_size=20, estado=None):
        llamadas.append((page, page_size, estado))
        return [{"cod_ingreso": 1, "estado": "en_confeccion"}], 1

    monkeypatch.setattr(router_ingresos, "listar_ingresos", mock_listar)

    resp = client.get("/ingresos")

    assert resp.status_code == 200
    assert llamadas == [(1, 20, None)]
    body = resp.json()
    assert body["page"] == 1
    assert body["page_size"] == 20
    assert body["total"] == 1
    assert len(body["items"]) == 1


def test_listar_ingresos_con_filtros_200(client: TestClient, monkeypatch):
    """GET /ingresos con filtros transmite los parámetros a la DAL."""
    llamadas = []

    def mock_listar(conn, *, page=1, page_size=20, estado=None):
        llamadas.append((page, page_size, estado))
        return [], 0

    monkeypatch.setattr(router_ingresos, "listar_ingresos", mock_listar)

    resp = client.get("/ingresos?page=2&page_size=10&estado=terminado")

    assert resp.status_code == 200
    assert llamadas == [(2, 10, "terminado")]
    body = resp.json()
    assert body["page"] == 2
    assert body["page_size"] == 10
    assert body["total"] == 0


@pytest.mark.parametrize(
    "param",
    ["page=0", "page=-1", "page_size=0", "page_size=101", "estado=invalido"],
)
def test_listar_ingresos_parametros_invalidos_422(client: TestClient, param):
    """GET /ingresos con parámetros fuera de rango o tipo inválido devuelve 422."""
    resp = client.get(f"/ingresos?{param}")
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /ingresos
# ---------------------------------------------------------------------------


def test_crear_ingreso_201(client: TestClient, monkeypatch):
    """POST /ingresos crea un nuevo ingreso en estado 'en_confeccion' (201)."""
    llamadas = []

    def mock_crear(conn, fecha, cod_transportista, cuit_bodega):
        llamadas.append((fecha, cod_transportista, cuit_bodega))
        return {
            "cod_ingreso": 80,
            "fecha": str(fecha),
            "estado": "en_confeccion",
            "cod_transportista": cod_transportista,
            "cuit_bodega": cuit_bodega,
        }

    monkeypatch.setattr(router_ingresos, "crear_ingreso", mock_crear)

    resp = client.post("/ingresos", json=PAYLOAD_INGRESO)

    assert resp.status_code == 201
    assert resp.headers.get("location") == "/ingresos/80"
    assert len(llamadas) == 1
    assert llamadas[0][1] == 3
    assert llamadas[0][2] == "30123456789"
    body = resp.json()
    assert body["cod_ingreso"] == 80
    assert body["estado"] == "en_confeccion"


def test_crear_ingreso_value_error_traduce_a_422(client: TestClient, monkeypatch):
    """POST /ingresos traduce ValueError a 422."""
    def mock_crear(conn, fecha, cod_transportista, cuit_bodega):
        raise ValueError("Fecha invalida")

    monkeypatch.setattr(router_ingresos, "crear_ingreso", mock_crear)

    resp = client.post("/ingresos", json=PAYLOAD_INGRESO)
    assert resp.status_code == 422


def test_crear_ingreso_payload_invalido_422(client: TestClient):
    """POST /ingresos con campos faltantes devuelve 422."""
    resp = client.post("/ingresos", json={"fecha": "2026-11-03"})
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# GET /ingresos/{cod}
# ---------------------------------------------------------------------------


def test_obtener_ingreso_ok_200(client: TestClient, monkeypatch):
    """GET /ingresos/{cod} devuelve cabecera y renglones con HTTP 200."""
    ingreso = {
        "cod_ingreso": 80,
        "fecha": "2026-11-03",
        "estado": "en_confeccion",
        "cod_transportista": 3,
        "cuit_bodega": "30123456789",
        "renglones": [
            {"cod_vino": 10, "cantidad": 120},
        ],
    }
    monkeypatch.setattr(router_ingresos, "obtener_ingreso", lambda conn, cod: dict(ingreso))

    resp = client.get("/ingresos/80")

    assert resp.status_code == 200
    body = resp.json()
    assert body["cod_ingreso"] == 80
    assert body["estado"] == "en_confeccion"
    assert len(body["renglones"]) == 1


def test_obtener_ingreso_inexistente_404(client: TestClient, monkeypatch):
    """GET /ingresos/{cod} devuelve 404 si el ingreso no existe."""
    monkeypatch.setattr(router_ingresos, "obtener_ingreso", lambda conn, cod: None)

    resp = client.get("/ingresos/99999")
    assert resp.status_code == 404


@pytest.mark.parametrize("cod", ["0", "-1", "abc"])
def test_obtener_ingreso_cod_invalido_422(client: TestClient, cod):
    resp = client.get(f"/ingresos/{cod}")
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /ingresos/{cod}/renglones
# ---------------------------------------------------------------------------


def test_agregar_renglon_ingreso_201(client: TestClient, monkeypatch):
    """POST /ingresos/{cod}/renglones agrega un renglón (201)."""
    llamadas = []

    def mock_agregar(conn, cod_ingreso, cod_vino, cantidad):
        llamadas.append((cod_ingreso, cod_vino, cantidad))
        return {"cod_ingreso": cod_ingreso, "cod_vino": cod_vino, "cantidad": cantidad}

    monkeypatch.setattr(router_ingresos, "agregar_renglon_ingreso", mock_agregar)

    resp = client.post("/ingresos/80/renglones", json=PAYLOAD_RENGLON)

    assert resp.status_code == 201
    assert llamadas == [(80, 10, 120)]
    assert resp.json()["cantidad"] == 120


@pytest.mark.parametrize(
    "payload",
    [{"cod_vino": 0, "cantidad": 10}, {"cod_vino": 10, "cantidad": 0}, {"cod_vino": 10, "cantidad": -5}],
)
def test_agregar_renglon_ingreso_invalido_422(client: TestClient, payload):
    resp = client.post("/ingresos/80/renglones", json=payload)
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /ingresos/{cod}/terminar
# ---------------------------------------------------------------------------


def test_terminar_ingreso_ok_200(client: TestClient, monkeypatch):
    """POST /ingresos/{cod}/terminar pasa el estado a 'terminado' (200)."""
    monkeypatch.setattr(
        router_ingresos,
        "terminar_ingreso",
        lambda conn, cod_ingreso: {"cod_ingreso": cod_ingreso, "estado": "terminado"},
    )

    resp = client.post("/ingresos/80/terminar")

    assert resp.status_code == 200
    assert resp.json() == {"cod_ingreso": 80, "estado": "terminado"}


def test_terminar_ingreso_inexistente_404(client: TestClient, monkeypatch):
    monkeypatch.setattr(router_ingresos, "terminar_ingreso", lambda conn, cod_ingreso: None)

    resp = client.post("/ingresos/99999/terminar")
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# POST /ingresos/{cod}/procesar
# ---------------------------------------------------------------------------


def test_procesar_ingreso_ok_200(client: TestClient, monkeypatch):
    """POST /ingresos/{cod}/procesar procesa el ingreso y devuelve estado 'procesado' (200)."""
    llamadas_procesar = []

    def mock_procesar(conn, cod_ingreso):
        llamadas_procesar.append(cod_ingreso)

    ingreso_procesado = {
        "cod_ingreso": 80,
        "fecha": "2026-11-03",
        "estado": "procesado",
        "cod_transportista": 3,
        "cuit_bodega": "30123456789",
        "renglones": [{"cod_vino": 10, "cantidad": 120}],
    }

    monkeypatch.setattr(router_ingresos, "procesar_ingreso", mock_procesar)
    monkeypatch.setattr(router_ingresos, "obtener_ingreso", lambda conn, cod: ingreso_procesado)

    resp = client.post("/ingresos/80/procesar")

    assert resp.status_code == 200
    assert llamadas_procesar == [80]
    assert resp.json()["estado"] == "procesado"


@pytest.mark.parametrize("cod", ["0", "-1", "abc"])
def test_procesar_ingreso_cod_invalido_422(client: TestClient, cod):
    resp = client.post(f"/ingresos/{cod}/procesar")
    assert resp.status_code == 422
