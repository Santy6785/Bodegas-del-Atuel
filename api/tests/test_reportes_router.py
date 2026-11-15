"""Tests del router de reportes (S1, S6, S7 y S8) sin base de datos real.

Usan el fixture ``client`` de conftest.py (conexion falsa y sin pool) y
reemplazan las funciones de queries/reportes.py que el router importa. Asi se
verifica el enrutamiento, la validacion de parametros y la traduccion de
errores, sin tocar PostgreSQL.
"""

from datetime import date
from decimal import Decimal

import pytest

import app.routers.reportes as router_reportes


def _parchear(monkeypatch, nombre, resultado=None, error=None):
    """Reemplaza una funcion de consulta en el router y registra sus llamadas."""
    llamadas = []

    def falsa(*args, **kwargs):
        llamadas.append((args, kwargs))
        if error is not None:
            raise error
        return resultado if resultado is not None else []

    monkeypatch.setattr(router_reportes, nombre, falsa)
    return llamadas


# ---------------------------------------------------------------------------
# S1: top de vinos
# ---------------------------------------------------------------------------


def test_top_vinos_ok_usa_limite_por_defecto(client, monkeypatch):
    filas = [{"cod_vino": 1, "nombre": "TEST", "botellas_vendidas": 10}]
    llamadas = _parchear(monkeypatch, "top_vinos", resultado=filas)

    resp = client.get("/reportes/top-vinos")

    assert resp.status_code == 200
    assert resp.json() == {"items": filas, "limite": 10}
    assert llamadas[0][0][1] == 10  # (conn, limite)


def test_top_vinos_limite_personalizado(client, monkeypatch):
    llamadas = _parchear(monkeypatch, "top_vinos")

    resp = client.get("/reportes/top-vinos?limite=25")

    assert resp.status_code == 200
    assert resp.json()["limite"] == 25
    assert llamadas[0][0][1] == 25


@pytest.mark.parametrize("limite", ["0", "101", "-1", "abc"])
def test_top_vinos_limite_invalido_da_422(client, limite):
    resp = client.get(f"/reportes/top-vinos?limite={limite}")
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# S6: vinos sin stock
# ---------------------------------------------------------------------------


def test_vinos_sin_stock_con_sala(client, monkeypatch):
    filas = [{"cod_vino": 5, "nombre": "TEST"}]
    llamadas = _parchear(monkeypatch, "vinos_sin_stock", resultado=filas)

    resp = client.get("/reportes/vinos-sin-stock?id_sala=3")

    assert resp.status_code == 200
    assert resp.json() == {"items": filas}
    assert llamadas[0][1] == {"id_sala": 3}


def test_vinos_sin_stock_sin_sala_es_global(client, monkeypatch):
    llamadas = _parchear(monkeypatch, "vinos_sin_stock")

    resp = client.get("/reportes/vinos-sin-stock")

    assert resp.status_code == 200
    assert llamadas[0][1] == {"id_sala": None}


@pytest.mark.parametrize("id_sala", ["0", "-5", "abc"])
def test_vinos_sin_stock_sala_invalida_da_422(client, id_sala):
    resp = client.get(f"/reportes/vinos-sin-stock?id_sala={id_sala}")
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# S7: transportista activo
# ---------------------------------------------------------------------------


def test_transportista_activo_ok(client, monkeypatch):
    filas = [{"cod_transportista": 2, "razon_social": "TEST SA", "puesto": 1}]
    _parchear(monkeypatch, "transportista_activo", resultado=filas)

    resp = client.get("/reportes/transportista-activo")

    assert resp.status_code == 200
    assert resp.json() == {"items": filas}


def test_transportista_activo_sin_datos_devuelve_lista_vacia(client, monkeypatch):
    _parchear(monkeypatch, "transportista_activo", resultado=[])

    resp = client.get("/reportes/transportista-activo")

    assert resp.status_code == 200
    assert resp.json() == {"items": []}


# ---------------------------------------------------------------------------
# S8: ventas por sala
# ---------------------------------------------------------------------------


def test_ventas_por_sala_sin_filtros(client, monkeypatch):
    llamadas = _parchear(monkeypatch, "ventas_por_sala")

    resp = client.get("/reportes/ventas-por-sala")

    assert resp.status_code == 200
    assert llamadas[0][1] == {
        "periodo": None,
        "fecha_desde": None,
        "fecha_hasta": None,
    }


def test_ventas_por_sala_periodo_ultimo_trimestre(client, monkeypatch):
    llamadas = _parchear(monkeypatch, "ventas_por_sala")

    resp = client.get("/reportes/ventas-por-sala?periodo=ultimo_trimestre")

    assert resp.status_code == 200
    assert llamadas[0][1]["periodo"] == "ultimo_trimestre"


def test_ventas_por_sala_rango_de_fechas(client, monkeypatch):
    llamadas = _parchear(monkeypatch, "ventas_por_sala")

    resp = client.get(
        "/reportes/ventas-por-sala?fecha_desde=2026-01-01&fecha_hasta=2026-03-31"
    )

    assert resp.status_code == 200
    assert llamadas[0][1]["fecha_desde"] == date(2026, 1, 1)
    assert llamadas[0][1]["fecha_hasta"] == date(2026, 3, 31)


def test_ventas_por_sala_serializa_decimales(client, monkeypatch):
    filas = [{"id_sala": 1, "monto_total": Decimal("123.45")}]
    _parchear(monkeypatch, "ventas_por_sala", resultado=filas)

    resp = client.get("/reportes/ventas-por-sala")

    assert resp.status_code == 200
    assert float(resp.json()["items"][0]["monto_total"]) == 123.45


@pytest.mark.parametrize(
    "query",
    ["periodo=otro", "fecha_desde=hola", "fecha_hasta=2026-99-99"],
)
def test_ventas_por_sala_parametros_invalidos_dan_422(client, query):
    resp = client.get(f"/reportes/ventas-por-sala?{query}")
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Traduccion de ValueError (validaciones de la capa de consultas) a 422
# ---------------------------------------------------------------------------


def test_value_error_de_la_consulta_se_traduce_a_422(client, monkeypatch):
    _parchear(
        monkeypatch,
        "ventas_por_sala",
        error=ValueError("fecha_desde no puede ser posterior a fecha_hasta"),
    )

    resp = client.get(
        "/reportes/ventas-por-sala?fecha_desde=2026-03-01&fecha_hasta=2026-01-01"
    )

    assert resp.status_code == 422
    assert resp.json()["detail"] == "fecha_desde no puede ser posterior a fecha_hasta"
