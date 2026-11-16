"""Prueba de integración: inyección SQL fallida en GET /vinos?nombre=.

Verifica que enviar ``' OR '1'='1`` como valor del filtro ``nombre`` no
produce inyección SQL: el parámetro se envía parametrizado a PostgreSQL
(psycopg ``%s``), se trata como texto literal y la respuesta es HTTP 200
sin coincidencias. Pydantic no debe rechazarlo con 422 antes de llegar a la
base.

No se modifican routers, queries ni esquemas. Requiere PostgreSQL real
activado y migrado (fixtures de ``api/tests/conftest.py``).
"""

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.main import app


# ---------------------------------------------------------------------------
# Fixture: cliente HTTP contra la base real
# ---------------------------------------------------------------------------

@pytest.fixture()
def cliente_real():
    """TestClient contra la app real con pool y get_conn reales.

    Si la base no está alcanzable, se salta la prueba.
    """
    from tests.conftest import is_database_reachable

    if not is_database_reachable():
        pytest.skip("Base de datos PostgreSQL no disponible para pruebas de integración")
    with TestClient(app) as client:
        yield client


# ---------------------------------------------------------------------------
# Helper: inserta vinos reales en la tabla vino (cumple RN-05: suma 100 %)
# ---------------------------------------------------------------------------

def _insertar_vinos_reales(
    conn: psycopg.Connection, sufijo: str
) -> dict:
    """Inserta localidad, bodega, sala, cepa y vino con composición 100 %.

    Devuelve el cod_vino y nombre del vino insertado para usarlos en el
    filtro de consulta legítima.
    """
    cp = f"TEST{sufijo}"
    # CUIT de 11 dígitos: 9 nueves + sufijo de 2 dígitos
    cuit = f"999999999{sufijo.zfill(2)}"
    calle = f"TEST Calle {sufijo}"
    nombre_cepa = f"TEST Cepa Inj {sufijo}"
    nombre_vino = f"TEST Vino Inj {sufijo}"

    conn.execute(
        "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) "
        "VALUES (%s, %s, 'Mendoza', 'Encargado') ON CONFLICT DO NOTHING",
        (cp, f"Localidad Test Inj {sufijo}"),
    )
    conn.execute(
        "INSERT INTO bodega (cuit, razon_social, domicilio) "
        "VALUES (%s, %s, 'Ruta Test') ON CONFLICT DO NOTHING",
        (cuit, f"TEST Bodega Inj {sufijo}"),
    )
    conn.execute(
        "INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal) "
        "VALUES (%s, '1', 'lunes', %s) ON CONFLICT DO NOTHING",
        (calle, cp),
    )
    conn.execute(
        "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') ON CONFLICT DO NOTHING",
        (nombre_cepa,),
    )

    cur = conn.cursor()
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = %s", (nombre_cepa,))
    id_cepa = cur.fetchone()["id_cepa"]

    # Vino con composición 100 % (dispara trigger diferido ctg_vino_composicion al COMMIT)
    with conn.transaction():
        cod_vino = cur.execute(
            """
            INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
            VALUES (%s, 'tinto', 2021, 750, 14.0, 10000.00, %s)
            RETURNING cod_vino;
            """,
            (nombre_vino, cuit),
        ).fetchone()["cod_vino"]
        cur.execute(
            "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)",
            (cod_vino, id_cepa),
        )

    return {"cod_vino": cod_vino, "nombre": nombre_vino}


# ---------------------------------------------------------------------------
# Caso: inyección SQL en GET /vinos?nombre=
# ---------------------------------------------------------------------------

@pytest.mark.integration
def test_inyeccion_sql_nombre_vino_fallida(
    cliente_real: TestClient,
    db_conn_commit: psycopg.Connection,
):
    """GET /vinos?nombre=' OR '1'='1 → 200, sin inyección, 0 coincidencias.

    El string malicioso se envía como parámetro de consulta. Pydantic lo
    acepta (es un str válido) y llega a PostgreSQL, donde psycopg lo pasa
    como valor %s parametrizado. PostgreSQL lo trata como texto literal, no
    como fragmento de SQL, por lo que no hay error de sintaxis (500) ni
    devolución de todos los vinos. La respuesta es 200 con items vacío.
    """
    sufijo = "11"
    datos = _insertar_vinos_reales(db_conn_commit, sufijo)
    nombre_insertado = datos["nombre"]

    # Petición con payload de inyección SQL
    payload_inyeccion = "' OR '1'='1"
    resp = cliente_real.get(
        "/vinos",
        params={"nombre": payload_inyeccion},
    )

    # 1) Pydantic no lo rechaza antes de llegar a la base → 200, no 422/500.
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert set(body.keys()) == {"items", "page", "page_size", "total"}

    # 2) El payload se trató como texto literal: ningún vino se llama así,
    #    por lo que no hay coincidencias.
    assert body["total"] == 0, body
    assert body["items"] == [], body

    # 3) Consulta legítima con el nombre real sí encuentra el vino insertado,
    #    demostrando que el endpoint filtra de verdad y la base está poblada.
    resp_real = cliente_real.get(
        "/vinos",
        params={"nombre": nombre_insertado},
    )
    assert resp_real.status_code == 200, resp_real.text
    body_real = resp_real.json()
    assert body_real["total"] >= 1, body_real
    assert any(
        item["nombre"] == nombre_insertado for item in body_real["items"]
    ), body_real
