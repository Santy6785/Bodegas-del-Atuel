"""Prueba de integración: auditoría de precio desde la API.

Verifica que actualizar_vino (DAL con app_rw) registre correctamente en
auditoria_precio con usuario == 'app_rw'.

Nota: si la base usa DEFAULT current_user con SECURITY DEFINER, el usuario
registrado puede ser owner_bodegas en lugar de app_rw. Ese defecto está en
la base y no se corrige en esta tarea; el test se deja fallando si ocurre.
"""

from fastapi.testclient import TestClient

import pytest

from app.main import app
from app.db.queries.vinos import actualizar_vino, crear_vino


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


@pytest.mark.integration
def test_auditoria_precio_registro_usuario_app_rw(
    cliente_real,
    db_conn_commit,
    db_owner,
):
    """Auditoría de precio: actualizar_vino con app_rw registra usuario == 'app_rw'.

    Crea un vino con precio inicial (DAL, app_rw), cambia el precio con
    actualizar_vino (DAL, app_rw), y verifica con db_owner que auditoria_precio
    tiene precio_anterior, precio_nuevo y usuario correctos.
    """
    sufijo = "05"
    cp = f"TEST{sufijo}"
    cuit = f"999999999{sufijo.zfill(2)}"
    nombre_cepas = f"TEST Cepa Aud {sufijo}"
    nombre_vino = f"TEST Vino Aud {sufijo}"

    # Catálogo mínimo (app_rw puede insertar en localidad, bodega, sala, cepa)
    db_conn_commit.execute(
        "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) "
        "VALUES (%s, %s, 'Mendoza', 'Encargado') ON CONFLICT DO NOTHING",
        (cp, f"Localidad Test {sufijo}"),
    )
    db_conn_commit.execute(
        "INSERT INTO bodega (cuit, razon_social, domicilio) "
        "VALUES (%s, %s, 'Ruta Test') ON CONFLICT DO NOTHING",
        (cuit, f"TEST Bodega Aud {sufijo}"),
    )
    db_conn_commit.execute(
        "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') ON CONFLICT DO NOTHING",
        (nombre_cepas,),
    )

    cur = db_conn_commit.cursor()
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = %s", (nombre_cepas,))
    id_cepa = cur.fetchone()["id_cepa"]

    # Crear vino con precio inicial (DAL con app_rw, dentro de transacción)
    with db_conn_commit.transaction():
        cod_vino = crear_vino(
            db_conn_commit,
            {
                "nombre": nombre_vino,
                "tipo": "tinto",
                "anada": 2021,
                "volumen_ml": 750,
                "graduacion": "14.00",
                "precio": "10000.00",
                "cuit_bodega": cuit,
                "composicion": [{"id_cepa": id_cepa, "porcentaje": "100.00"}],
            },
        )

    # Cambiar el precio con actualizar_vino (DAL con app_rw)
    with db_conn_commit.transaction():
        actualizar_vino(
            db_conn_commit,
            cod_vino,
            {
                "nombre": nombre_vino,
                "tipo": "tinto",
                "anada": 2021,
                "volumen_ml": 750,
                "graduacion": "14.00",
                "precio": "15000.00",
                "cuit_bodega": cuit,
                "composicion": [{"id_cepa": id_cepa, "porcentaje": "100.00"}],
                "maridajes": [],
            },
        )

    # Consultar auditoria_precio con db_owner
    cur = db_owner.cursor()
    cur.execute(
        """
        SELECT precio_anterior, precio_nuevo, usuario
        FROM auditoria_precio
        WHERE cod_vino = %s
        ORDER BY fecha_hora DESC
        LIMIT 1
        """,
        (cod_vino,),
    )
    row = cur.fetchone()
    assert row is not None, f"No hay fila de auditoría para el vino {cod_vino}"
    assert row["precio_anterior"] == 10000.00, row["precio_anterior"]
    assert row["precio_nuevo"] == 15000.00, row["precio_nuevo"]
    assert row["usuario"] == "app_rw", row["usuario"]
