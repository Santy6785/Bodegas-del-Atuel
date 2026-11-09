"""Pruebas de integración para api/app/db/queries/transferencias.py."""

import psycopg
import pytest

from app.db.queries.transferencias import (
    agregar_renglon_transferencia,
    crear_transferencia,
    listar_transferencias,
    obtener_transferencia,
    procesar_transferencia,
    terminar_transferencia,
)


@pytest.mark.integration
def test_transferencia_flujo_completo_con_stock(
    db_conn_commit: psycopg.Connection, db_owner: psycopg.Connection
):
    """Caso 11: Crear, agregar renglón, terminar y procesar transferencia con stock en depósito."""
    # Preparamos sala, vino con composición válida (RN-05) y stock en depósito
    with db_conn_commit.transaction():
        cur = db_conn_commit.cursor()
        cur.execute(
            """
            INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
            VALUES ('TEST5610', 'Localidad Trf', 'Mendoza', 'Encargado')
            ON CONFLICT DO NOTHING;
            INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
            VALUES ('TEST Calle Sala Trf 1', '100', 'domingo', 'TEST5610')
            ON CONFLICT DO NOTHING;
            INSERT INTO bodega (cuit, razon_social, domicilio)
            VALUES ('99999999981', 'TEST Bodega Trf', 'Ruta 144')
            ON CONFLICT DO NOTHING;
            INSERT INTO cepa (nombre, tipo)
            VALUES ('TEST Cepa Trf 1', 'tinta')
            ON CONFLICT DO NOTHING;
            """
        )
        cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa Trf 1'")
        id_cepa = cur.fetchone()["id_cepa"]
        cur.execute(
            """
            INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
            VALUES ('TEST Vino Transferencia 1', 'tinto', 2021, 750, 14.0, 10000, '99999999981')
            RETURNING cod_vino;
            """
        )
        cod_vino = cur.fetchone()["cod_vino"]
        cur.execute(
            "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)",
            (cod_vino, id_cepa),
        )

    cur = db_conn_commit.cursor()
    cur.execute(
        "SELECT id_sala FROM sala_venta WHERE calle = 'TEST Calle Sala Trf 1'"
    )
    id_sala = cur.fetchone()["id_sala"]

    # Dotamos al depósito de stock suficiente (100 botellas).
    # stock_deposito es de solo lectura para app_rw: se inserta con el propietario.
    db_owner.execute(
        """
        INSERT INTO stock_deposito (cod_vino, cantidad)
        VALUES (%s, 100)
        ON CONFLICT (cod_vino) DO UPDATE SET cantidad = 100;
        """,
        (cod_vino,),
    )
    # Sala inicia con 0 botellas.
    # stock_sala es de solo lectura para app_rw: se inserta con el propietario.
    db_owner.execute(
        """
        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (%s, %s, 0)
        ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 0;
        """,
        (id_sala, cod_vino),
    )

    # 1. Crear transferencia (estado en_confeccion)
    trf = crear_transferencia(db_conn_commit, id_sala)
    nro_trf = trf["nro_transferencia"]
    assert trf["estado"] == "en_confeccion"
    assert trf["id_sala"] == id_sala

    # 2. Agregar renglón: transferir 25 botellas
    renglon = agregar_renglon_transferencia(
        db_conn_commit, nro_trf, cod_vino, cantidad=25
    )
    assert renglon["cantidad"] == 25

    # 3. Terminar transferencia (estado pasa a terminado)
    term = terminar_transferencia(db_conn_commit, nro_trf)
    assert term is not None
    assert term["estado"] == "terminado"

    # 4. Procesar transferencia con stock disponible
    procesar_transferencia(db_conn_commit, nro_trf)

    # Verificaciones:
    # Transferencia queda en 'procesado'
    trf_final = obtener_transferencia(db_conn_commit, nro_trf)
    assert trf_final["estado"] == "procesado"
    assert len(trf_final["renglones"]) == 1

    # Stock depósito disminuyó: 100 - 25 = 75
    cur = db_conn_commit.cursor()
    cur.execute(
        "SELECT cantidad FROM stock_deposito WHERE cod_vino = %s", (cod_vino,)
    )
    assert cur.fetchone()["cantidad"] == 75

    # Stock sala aumentó: 0 + 25 = 25
    cur.execute(
        "SELECT fn_stock_sala(%s, %s) AS stock", (id_sala, cod_vino)
    )
    assert cur.fetchone()["stock"] == 25

    # Stock sala aumentó: 0 + 25 = 25
    cur.execute(
        "SELECT fn_stock_sala(%s, %s) AS stock", (id_sala, cod_vino)
    )
    assert cur.fetchone()["stock"] == 25


@pytest.mark.integration
def test_transferencia_sin_stock_deposito_lanza_p0001(
    db_conn_commit: psycopg.Connection, db_owner: psycopg.Connection
):
    """Caso 12: Transferencia sin stock en depósito lanza P0001 y estado queda 'terminado'."""
    with db_conn_commit.transaction():
        cur = db_conn_commit.cursor()
        cur.execute(
            """
            INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
            VALUES ('TEST5611', 'Localidad Trf Sin Stock', 'Mendoza', 'Encargado')
            ON CONFLICT DO NOTHING;
            INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
            VALUES ('TEST Calle Sala Trf 2', '200', 'lunes', 'TEST5611')
            ON CONFLICT DO NOTHING;
            INSERT INTO bodega (cuit, razon_social, domicilio)
            VALUES ('99999999982', 'TEST Bodega Trf 2', 'Ruta 144')
            ON CONFLICT DO NOTHING;
            INSERT INTO cepa (nombre, tipo)
            VALUES ('TEST Cepa Trf 2', 'tinta')
            ON CONFLICT DO NOTHING;
            """
        )
        cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa Trf 2'")
        id_cepa = cur.fetchone()["id_cepa"]
        cur.execute(
            """
            INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
            VALUES ('TEST Vino Transferencia Sin Stock', 'tinto', 2021, 750, 14.0, 10000, '99999999982')
            RETURNING cod_vino;
            """
        )
        cod_vino = cur.fetchone()["cod_vino"]
        cur.execute(
            "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)",
            (cod_vino, id_cepa),
        )

    cur = db_conn_commit.cursor()
    cur.execute(
        "SELECT id_sala FROM sala_venta WHERE calle = 'TEST Calle Sala Trf 2'"
    )
    id_sala = cur.fetchone()["id_sala"]

    # Depósito tiene solo 5 botellas.
    # stock_deposito es de solo lectura para app_rw: se inserta con el propietario.
    db_owner.execute(
        """
        INSERT INTO stock_deposito (cod_vino, cantidad)
        VALUES (%s, 5)
        ON CONFLICT (cod_vino) DO UPDATE SET cantidad = 5;
        """,
        (cod_vino,),
    )

    # Creamos transferencia y pedimos 50 botellas (mayor que el stock disponible)
    trf = crear_transferencia(db_conn_commit, id_sala)
    nro_trf = trf["nro_transferencia"]
    agregar_renglon_transferencia(db_conn_commit, nro_trf, cod_vino, cantidad=50)
    terminar_transferencia(db_conn_commit, nro_trf)

    # Al procesar debe fallar con P0001 por stock insuficiente en el depósito central
    with pytest.raises(psycopg.errors.RaiseException) as exc_info:
        procesar_transferencia(db_conn_commit, nro_trf)
    assert exc_info.value.sqlstate == "P0001"
    assert "RN-09" in str(exc_info.value)

    # El estado debe permanecer en 'terminado' y el stock de depósito inalterado (5 botellas)
    trf_actual = obtener_transferencia(db_conn_commit, nro_trf)
    assert trf_actual["estado"] == "terminado"

    cur = db_conn_commit.cursor()
    cur.execute(
        "SELECT cantidad FROM stock_deposito WHERE cod_vino = %s", (cod_vino,)
    )
    assert cur.fetchone()["cantidad"] == 5


@pytest.mark.integration
def test_listar_transferencias_paginacion(db_conn: psycopg.Connection):
    """Prueba listar_transferencias con paginación y filtros por estado y sala."""
    db_conn.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST5612', 'Localidad Trf List', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
        VALUES ('TEST Sala List Trf', '300', 'martes', 'TEST5612')
        ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn.cursor()
    cur.execute(
        "SELECT id_sala FROM sala_venta WHERE calle = 'TEST Sala List Trf'"
    )
    id_sala = cur.fetchone()["id_sala"]

    # Creamos dos transferencias
    t1 = crear_transferencia(db_conn, id_sala)
    t2 = crear_transferencia(db_conn, id_sala)

    items, total = listar_transferencias(
        db_conn, page=1, page_size=10, id_sala=id_sala, estado="en_confeccion"
    )
    assert total >= 2
    nros = [item["nro_transferencia"] for item in items]
    assert t1["nro_transferencia"] in nros
    assert t2["nro_transferencia"] in nros
