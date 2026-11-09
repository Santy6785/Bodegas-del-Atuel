"""Pruebas de integración que provocan violaciones reales de reglas de negocio.

Todas las pruebas están marcadas con ``@pytest.mark.integration`` y requieren
PostgreSQL local activo y migrado. Verifican código HTTP, sqlstate y mensaje
de la regla (RN-09, RN-01/RN-15, RN-11).

No se modifica la lógica de negocio ni las migraciones. Si una prueba revela
un defecto, se deja fallando con un comentario claro.
"""

from decimal import Decimal

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
# Helpers de preparación de datos (usados por cada prueba de forma autónoma)
# ---------------------------------------------------------------------------

def _preparar_entorno_venta(conn: psycopg.Connection, sufijo: str) -> dict:
    """Crea localidad, bodega, sala, cepa, vino, cliente y stock de sala.

    Devuelve ids y claves para armar el request de venta.
    """
    cp = f"TEST{sufijo}"
    # CUIT de 11 dígitos: 9 nueves + sufijo de 2 dígitos
    cuit = f"999999999{sufijo.zfill(2)}"

    calle = f"TEST Calle {sufijo}"
    nombre_cepas = f"TEST Cepa {sufijo}"
    nombre_vino = f"TEST Vino Stock {sufijo}"
    nombre_cliente = f"TEST Cliente {sufijo}"

    conn.execute(
        "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) "
        "VALUES (%s, %s, 'Mendoza', 'Encargado') ON CONFLICT DO NOTHING",
        (cp, f"Localidad Test {sufijo}"),
    )
    conn.execute(
        "INSERT INTO bodega (cuit, razon_social, domicilio) "
        "VALUES (%s, %s, 'Ruta Test') ON CONFLICT DO NOTHING",
        (cuit, f"TEST Bodega {sufijo}"),
    )
    conn.execute(
        "INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal) "
        "VALUES (%s, '1', 'lunes', %s) ON CONFLICT DO NOTHING",
        (calle, cp),
    )
    conn.execute(
        "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') ON CONFLICT DO NOTHING",
        (nombre_cepas,),
    )

    cur = conn.cursor()
    cur.execute("SELECT id_sala FROM sala_venta WHERE calle = %s", (calle,))
    id_sala = cur.fetchone()["id_sala"]
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = %s", (nombre_cepas,))
    id_cepa = cur.fetchone()["id_cepa"]

    # Vino con composición 100 % (dispara trigger diferido al COMMIT)
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

    # Cliente
    id_cliente = cur.execute(
        """
        INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento,
                             nro_documento, direccion, codigo_postal,
                             fecha_alta, tipo_cliente)
        VALUES (%s, 'TEST Cliente', 'CUIT', %s, 'Dir Test', %s, CURRENT_DATE, 'socio')
        RETURNING id_cliente;
        """,
        (nombre_cliente, cuit, cp),
    ).fetchone()["id_cliente"]

    # Stock de sala: 2 botellas (insuficiente para vender 5)
    cur.execute(
        """
        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (%s, %s, 2)
        ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 2;
        """,
        (id_sala, cod_vino),
    )

    return {"id_cliente": id_cliente, "id_sala": id_sala, "cod_vino": cod_vino}


def _preparar_entorno_transferencia(conn: psycopg.Connection, sufijo: str) -> dict:
    """Crea localidad, bodega, sala, vino, stock_deposito para transferencia.

    Devuelve id_sala y cod_vino.
    """
    cp = f"TEST{sufijo}"
    # CUIT de 11 dígitos: 9 nueves + sufijo de 2 dígitos
    cuit = f"999999999{sufijo.zfill(2)}"

    calle = f"TEST Calle {sufijo}"
    nombre_cepas = f"TEST Cepa {sufijo}"
    nombre_vino = f"TEST Vino Transf {sufijo}"

    conn.execute(
        "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) "
        "VALUES (%s, %s, 'Mendoza', 'Encargado') ON CONFLICT DO NOTHING",
        (cp, f"Localidad Test {sufijo}"),
    )
    conn.execute(
        "INSERT INTO bodega (cuit, razon_social, domicilio) "
        "VALUES (%s, %s, 'Ruta Test') ON CONFLICT DO NOTHING",
        (cuit, f"TEST Bodega {sufijo}"),
    )
    conn.execute(
        "INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal) "
        "VALUES (%s, '1', 'lunes', %s) ON CONFLICT DO NOTHING",
        (calle, cp),
    )
    conn.execute(
        "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') ON CONFLICT DO NOTHING",
        (nombre_cepas,),
    )

    cur = conn.cursor()
    cur.execute("SELECT id_sala FROM sala_venta WHERE calle = %s", (calle,))
    id_sala = cur.fetchone()["id_sala"]
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = %s", (nombre_cepas,))
    id_cepa = cur.fetchone()["id_cepa"]

    # Vino con composición 100 % (dispara trigger diferido al COMMIT)
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

    # Stock de depósito suficiente
    cur.execute(
        """
        INSERT INTO stock_deposito (cod_vino, cantidad)
        VALUES (%s, 100)
        ON CONFLICT (cod_vino) DO UPDATE SET cantidad = 100;
        """,
        (cod_vino,),
    )

    return {"id_sala": id_sala, "cod_vino": cod_vino}


# ---------------------------------------------------------------------------
# Caso 1: RN-09 Stock insuficiente (POST /comprobantes)
# ---------------------------------------------------------------------------

@pytest.mark.integration
def test_rn09_stock_insuficiente_venta(cliente_real: TestClient, db_conn_commit: psycopg.Connection):
    """RN-09: Vender más que el stock de sala → 409, P0001, mensaje RN-09.

    No queda nada a medias: stock de sala sigue en 2 y no hay comprobante.
    """
    sufijo = "01"
    datos = _preparar_entorno_venta(db_conn_commit, sufijo)

    resp = cliente_real.post(
        "/comprobantes",
        json={
            "id_cliente": datos["id_cliente"],
            "id_sala": datos["id_sala"],
            "cod_vinos": [datos["cod_vino"]],
            "cantidades": [5],  # Pide 5, solo hay 2
        },
    )

    assert resp.status_code == 409, resp.text
    body = resp.json()
    assert body["error"]["sqlstate"] == "P0001"
    assert "RN-09" in body["error"]["mensaje"], body["error"]["mensaje"]

    # Verificar que el stock de sala sigue en 2 (no se descontó nada)
    cur = db_conn_commit.cursor()
    cur.execute(
        "SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s",
        (datos["id_sala"], datos["cod_vino"]),
    )
    row = cur.fetchone()
    assert row is not None
    assert row["cantidad"] == 2

    # Verificar que no quedó comprobante
    cur.execute(
        "SELECT nro_comprobante FROM comprobante WHERE id_cliente = %s",
        (datos["id_cliente"],),
    )
    assert cur.fetchall() == []


@pytest.mark.integration
def test_rn09_stock_insuficiente_dos_renglones_atomicidad(
    cliente_real: TestClient, db_conn_commit: psycopg.Connection
):
    """RN-09: Dos renglones, el segundo sin stock → 409, P0001, RN-09, atomicidad.

    El renglón primero tiene stock suficiente pero el segundo no; la venta
    completa se rechaza y no queda ni comprobante ni renglones ni se descontó
    stock del primero (todo o nada).
    """
    sufijo = "07"
    cp = f"TEST{sufijo}"
    cuit = f"999999999{sufijo.zfill(2)}"
    nombre_localidad = f"Localidad Test {sufijo}"
    nombre_bodega = f"TEST Bodega {sufijo}"
    nombre_cepas = f"TEST Cepa {sufijo}"
    calle = f"TEST Calle {sufijo}"

    db_conn_commit.execute(
        "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) "
        "VALUES (%s, %s, 'Mendoza', 'Encargado') ON CONFLICT DO NOTHING",
        (cp, nombre_localidad),
    )
    db_conn_commit.execute(
        "INSERT INTO bodega (cuit, razon_social, domicilio) "
        "VALUES (%s, %s, 'Ruta Test') ON CONFLICT DO NOTHING",
        (cuit, nombre_bodega),
    )
    db_conn_commit.execute(
        "INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal) "
        "VALUES (%s, '1', 'lunes', %s) ON CONFLICT DO NOTHING",
        (calle, cp),
    )
    db_conn_commit.execute(
        "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') ON CONFLICT DO NOTHING",
        (nombre_cepas,),
    )

    cur = db_conn_commit.cursor()
    cur.execute("SELECT id_sala FROM sala_venta WHERE calle = %s", (calle,))
    id_sala = cur.fetchone()["id_sala"]
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = %s", (nombre_cepas,))
    id_cepa = cur.fetchone()["id_cepa"]

    # Dos vinos con composición 100 % cada uno
    with db_conn_commit.transaction():
        cod_vino_1 = cur.execute(
            """
            INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
            VALUES (%s, 'tinto', 2021, 750, 14.0, 10000.00, %s)
            RETURNING cod_vino;
            """,
            (f"TEST Vino Atomic 1 {sufijo}", cuit),
        ).fetchone()["cod_vino"]
        cur.execute(
            "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)",
            (cod_vino_1, id_cepa),
        )

        cod_vino_2 = cur.execute(
            """
            INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
            VALUES (%s, 'tinto', 2021, 750, 14.0, 10000.00, %s)
            RETURNING cod_vino;
            """,
            (f"TEST Vino Atomic 2 {sufijo}", cuit),
        ).fetchone()["cod_vino"]
        cur.execute(
            "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)",
            (cod_vino_2, id_cepa),
        )

    # Cliente
    id_cliente = cur.execute(
        """
        INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento,
                             nro_documento, direccion, codigo_postal,
                             fecha_alta, tipo_cliente)
        VALUES (%s, 'TEST Cliente', 'CUIT', %s, 'Dir Test', %s, CURRENT_DATE, 'socio')
        RETURNING id_cliente;
        """,
        (f"TEST Cliente {sufijo}", cuit, cp),
    ).fetchone()["id_cliente"]

    # Stock de sala: 10 del vino 1 (suficiente para 3), 2 del vino 2 (insuficiente para 5)
    cur.execute(
        "INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (%s, %s, 10)",
        (id_sala, cod_vino_1),
    )
    cur.execute(
        "INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (%s, %s, 2)",
        (id_sala, cod_vino_2),
    )

    resp = cliente_real.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente,
            "id_sala": id_sala,
            "cod_vinos": [cod_vino_1, cod_vino_2],
            "cantidades": [3, 5],  # el segundo no tiene stock (solo hay 2)
        },
    )

    assert resp.status_code == 409, resp.text
    body = resp.json()
    assert body["error"]["sqlstate"] == "P0001"
    assert "RN-09" in body["error"]["mensaje"], body["error"]["mensaje"]

    # Atomicidad: stock de ambos vinos sin cambios
    cur.execute(
        "SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s",
        (id_sala, cod_vino_1),
    )
    assert cur.fetchone()["cantidad"] == 10
    cur.execute(
        "SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s",
        (id_sala, cod_vino_2),
    )
    assert cur.fetchone()["cantidad"] == 2

    # No quedó comprobante ni renglones
    cur.execute(
        "SELECT nro_comprobante FROM comprobante WHERE id_cliente = %s",
        (id_cliente,),
    )
    assert cur.fetchall() == []


# ---------------------------------------------------------------------------
# Caso 2: RN-01 / RN-15 Precio no positivo (POST /vinos)
# ---------------------------------------------------------------------------

@pytest.mark.integration
def test_rn01_precio_cero(cliente_real: TestClient, db_conn_commit: psycopg.Connection):
    """RN-01/RN-15: precio = 0 → 422, sqlstate 23514, no se crea vino."""
    sufijo = "02"
    cp = f"TEST{sufijo}"
    cuit = f"999999999{sufijo.zfill(2)}"
    nombre_localidad = f"Localidad Test {sufijo}"
    nombre_bodega = f"TEST Bodega {sufijo}"
    nombre_cepas = f"TEST Cepa {sufijo}"
    nombre_vino = f"TEST Vino Precio Cero {sufijo}"

    db_conn_commit.execute(
        "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) "
        "VALUES (%s, %s, 'Mendoza', 'Encargado') ON CONFLICT DO NOTHING",
        (cp, nombre_localidad),
    )
    db_conn_commit.execute(
        "INSERT INTO bodega (cuit, razon_social, domicilio) "
        "VALUES (%s, %s, 'Ruta Test') ON CONFLICT DO NOTHING",
        (cuit, nombre_bodega),
    )
    db_conn_commit.execute(
        "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') ON CONFLICT DO NOTHING",
        (nombre_cepas,),
    )
    cur = db_conn_commit.cursor()
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = %s", (nombre_cepas,))
    id_cepa = cur.fetchone()["id_cepa"]

    resp = cliente_real.post(
        "/vinos",
        json={
            "nombre": nombre_vino,
            "tipo": "tinto",
            "anada": 2021,
            "volumen_ml": 750,
            "graduacion": "14.00",
            "precio": "0.00",
            "cuit_bodega": cuit,
            "composicion": [{"id_cepa": id_cepa, "porcentaje": "100.00"}],
        },
    )

    assert resp.status_code == 422, resp.text
    body = resp.json()
    assert body["error"]["sqlstate"] == "23514"

    # Verificar que no se creó vino
    cur.execute(
        "SELECT cod_vino FROM vino WHERE nombre = %s",
        (nombre_vino,),
    )
    assert cur.fetchone() is None


@pytest.mark.integration
def test_rn15_precio_negativo(cliente_real: TestClient, db_conn_commit: psycopg.Connection):
    """RN-15: precio < 0 → 422, sqlstate 23514, no se crea vino."""
    sufijo = "03"
    cp = f"TEST{sufijo}"
    cuit = f"999999999{sufijo.zfill(2)}"
    nombre_localidad = f"Localidad Test {sufijo}"
    nombre_bodega = f"TEST Bodega {sufijo}"
    nombre_cepas = f"TEST Cepa {sufijo}"
    nombre_vino = f"TEST Vino Precio Negativo {sufijo}"

    db_conn_commit.execute(
        "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) "
        "VALUES (%s, %s, 'Mendoza', 'Encargado') ON CONFLICT DO NOTHING",
        (cp, nombre_localidad),
    )
    db_conn_commit.execute(
        "INSERT INTO bodega (cuit, razon_social, domicilio) "
        "VALUES (%s, %s, 'Ruta Test') ON CONFLICT DO NOTHING",
        (cuit, nombre_bodega),
    )
    db_conn_commit.execute(
        "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') ON CONFLICT DO NOTHING",
        (nombre_cepas,),
    )
    cur = db_conn_commit.cursor()
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = %s", (nombre_cepas,))
    id_cepa = cur.fetchone()["id_cepa"]

    resp = cliente_real.post(
        "/vinos",
        json={
            "nombre": nombre_vino,
            "tipo": "tinto",
            "anada": 2021,
            "volumen_ml": 750,
            "graduacion": "14.00",
            "precio": "-100.00",
            "cuit_bodega": cuit,
            "composicion": [{"id_cepa": id_cepa, "porcentaje": "100.00"}],
        },
    )

    assert resp.status_code == 422, resp.text
    body = resp.json()
    assert body["error"]["sqlstate"] == "23514"

    cur.execute(
        "SELECT cod_vino FROM vino WHERE nombre = %s",
        (nombre_vino,),
    )
    assert cur.fetchone() is None


# ---------------------------------------------------------------------------
# Caso 3: RN-11 Cambio de estado inválido (POST /transferencias/{nro}/procesar
# sobre transferencia en 'en_confeccion')
# ---------------------------------------------------------------------------

@pytest.mark.integration
def test_rn11_procesar_transferencia_no_terminada(
    cliente_real: TestClient, db_conn_commit: psycopg.Connection
):
    """RN-11: Procesar transferencia en 'en_confeccion' → 409, P0001, mensaje RN-11.

    El estado sigue en 'en_confeccion'.
    """
    sufijo = "04"
    datos = _preparar_entorno_transferencia(db_conn_commit, sufijo)

    # Crear transferencia (estado en_confeccion por defecto)
    resp = cliente_real.post(
        "/transferencias",
        json={"id_sala": datos["id_sala"]},
    )
    assert resp.status_code == 201, resp.text
    nro = resp.json()["nro_transferencia"]

    # Agregar renglón
    resp = cliente_real.post(
        f"/transferencias/{nro}/renglones",
        json={"cod_vino": datos["cod_vino"], "cantidad": 10},
    )
    assert resp.status_code == 201, resp.text

    # Intentar procesar sin terminar → RN-11
    resp = cliente_real.post(f"/transferencias/{nro}/procesar")
    assert resp.status_code == 409, resp.text
    body = resp.json()
    assert body["error"]["sqlstate"] == "P0001"
    assert "RN-11" in body["error"]["mensaje"], body["error"]["mensaje"]

    # Verificar que el estado sigue en en_confeccion
    cur = db_conn_commit.cursor()
    cur.execute("SELECT estado FROM transferencia WHERE nro_transferencia = %s", (nro,))
    row = cur.fetchone()
    assert row is not None
    assert row["estado"] == "en_confeccion"
