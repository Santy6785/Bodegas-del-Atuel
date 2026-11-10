"""Pruebas de integración para api/app/db/queries/ingresos.py."""

from datetime import date
import psycopg
import pytest

from app.db.queries.ingresos import (
    agregar_renglon_ingreso,
    crear_ingreso,
    listar_ingresos,
    obtener_ingreso,
    procesar_ingreso,
    terminar_ingreso,
)


@pytest.mark.integration
def test_ingreso_flujo_completo_impacta_deposito(
    db_conn_commit: psycopg.Connection, db_owner: psycopg.Connection
):
    """Prueba flujo completo de ingreso: crear, agregar renglón, terminar y procesar."""
    # Preparamos transportista, bodega, cepa y vino con composición válida (RN-05)
    with db_conn_commit.transaction():
        cur = db_conn_commit.cursor()
        cur.execute(
            """
            INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
            VALUES ('TEST Trans Flujo', '99999999971', 'test@trans.com', '123', 'Dir')
            ON CONFLICT DO NOTHING;
            INSERT INTO bodega (cuit, razon_social, domicilio)
            VALUES ('99999999972', 'TEST Bodega Ingreso', 'Ruta 143')
            ON CONFLICT DO NOTHING;
            INSERT INTO cepa (nombre, tipo)
            VALUES ('TEST Cepa Ingreso', 'tinta')
            ON CONFLICT DO NOTHING;
            """
        )
        cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa Ingreso'")
        id_cepa = cur.fetchone()["id_cepa"]
        cur.execute(
            """
            INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
            VALUES ('TEST Vino Ingreso 1', 'tinto', 2021, 750, 14.0, 10000, '99999999972')
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
        "SELECT cod_transportista FROM transportista WHERE cuit = '99999999971'"
    )
    cod_trans = cur.fetchone()["cod_transportista"]

    # Inicializamos stock en depósito en 10.
    # stock_deposito es de solo lectura para app_rw: se inserta con el propietario.
    db_owner.execute(
        """
        INSERT INTO stock_deposito (cod_vino, cantidad)
        VALUES (%s, 10)
        ON CONFLICT (cod_vino) DO UPDATE SET cantidad = 10;
        """,
        (cod_vino,),
    )

    # 1. Crear ingreso en confección
    ingreso = crear_ingreso(
        db_conn_commit,
        fecha=date(2026, 11, 1),
        cod_transportista=cod_trans,
        cuit_bodega="99999999972",
    )
    cod_ing = ingreso["cod_ingreso"]
    assert ingreso["estado"] == "en_confeccion"

    # 2. Agregar renglón: 60 botellas
    renglon = agregar_renglon_ingreso(db_conn_commit, cod_ing, cod_vino, cantidad=60)
    assert renglon["cantidad"] == 60

    # 3. Terminar ingreso
    term = terminar_ingreso(db_conn_commit, cod_ing)
    assert term is not None
    assert term["estado"] == "terminado"

    # 4. Procesar ingreso (sp_procesar_ingreso)
    procesar_ingreso(db_conn_commit, cod_ing)

    # Verificaciones:
    # Estado en procesado
    ing_final = obtener_ingreso(db_conn_commit, cod_ing)
    assert ing_final["estado"] == "procesado"
    assert len(ing_final["renglones"]) == 1

    # Depósito incrementó en 60: 10 + 60 = 70 botellas
    cur = db_conn_commit.cursor()
    cur.execute(
        "SELECT cantidad FROM stock_deposito WHERE cod_vino = %s", (cod_vino,)
    )
    assert cur.fetchone()["cantidad"] == 70


@pytest.mark.integration
def test_ingreso_no_terminado_no_puede_procesarse(db_conn: psycopg.Connection):
    """Prueba que un ingreso en confección no pueda ser procesado (RN-10)."""
    db_conn.execute(
        """
        INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
        VALUES ('TEST Trans RN10', '99999999973', 'rn10@trans.com', '123', 'Dir')
        ON CONFLICT DO NOTHING;
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999974', 'TEST Bodega RN10', 'Ruta 143')
        ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn.cursor()
    cur.execute(
        "SELECT cod_transportista FROM transportista WHERE cuit = '99999999973'"
    )
    cod_trans = cur.fetchone()["cod_transportista"]

    ingreso = crear_ingreso(
        db_conn,
        fecha=date(2026, 11, 2),
        cod_transportista=cod_trans,
        cuit_bodega="99999999974",
    )
    cod_ing = ingreso["cod_ingreso"]

    with pytest.raises(psycopg.errors.RaiseException) as exc_info:
        procesar_ingreso(db_conn, cod_ing)
    assert exc_info.value.sqlstate == "P0001"
    assert "RN-10" in str(exc_info.value)


@pytest.mark.integration
def test_listar_ingresos_paginado(db_conn: psycopg.Connection):
    """Prueba listar_ingresos con paginación y filtro por estado."""
    db_conn.execute(
        """
        INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
        VALUES ('TEST Trans List', '99999999975', 'list@trans.com', '123', 'Dir')
        ON CONFLICT DO NOTHING;
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999976', 'TEST Bodega List', 'Ruta 143')
        ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn.cursor()
    cur.execute(
        "SELECT cod_transportista FROM transportista WHERE cuit = '99999999975'"
    )
    cod_trans = cur.fetchone()["cod_transportista"]

    ing = crear_ingreso(
        db_conn,
        fecha=date(2026, 11, 3),
        cod_transportista=cod_trans,
        cuit_bodega="99999999976",
    )

    items, total = listar_ingresos(db_conn, page=1, page_size=10, estado="en_confeccion")
    assert total >= 1
    assert any(i["cod_ingreso"] == ing["cod_ingreso"] for i in items)
