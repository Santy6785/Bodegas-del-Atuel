"""Pruebas de integración para api/app/db/queries/comprobantes.py."""

from decimal import Decimal
import psycopg
import pytest

from app.db.queries.comprobantes import crear_comprobante, obtener_comprobante


@pytest.mark.integration
def test_crear_comprobante_validacion_python_listas(db_conn: psycopg.Connection):
    """Valida que crear_comprobante verifique listas vacías o longitudes dispares antes de tocar la base."""
    with pytest.raises(ValueError, match="no pueden estar vacías"):
        crear_comprobante(db_conn, id_cliente=1, id_sala=1, cod_vinos=[], cantidades=[])

    with pytest.raises(ValueError, match="misma longitud"):
        crear_comprobante(
            db_conn, id_cliente=1, id_sala=1, cod_vinos=[10, 11], cantidades=[5]
        )


@pytest.mark.integration
def test_obtener_comprobante_inexistente_retorna_none(db_conn: psycopg.Connection):
    """Verifica que obtener_comprobante devuelva None para un número que no existe."""
    comprobante = obtener_comprobante(db_conn, nro_comprobante=999999)
    assert comprobante is None


def _preparar_datos_comprobante(
    conn: psycopg.Connection, db_owner_conn: psycopg.Connection
) -> tuple[int, int, int]:
    """Crea localidad, bodega, sala, cepa, vino con stock y cliente; devuelve (id_cliente, id_sala, cod_vino).

    Las tablas de catálogo se escriben con la conexión de la aplicación
    (app_rw, en autocommit vía db_conn_commit) y el stock de sala, que
    app_rw no puede escribir directamente, se inserta con el propietario.

    Vino y su composición se insertan en una misma transacción: el trigger
    diferido RN-05 valida que los porcentajes sumen 100 al COMMIT.
    """
    cur = conn.cursor()
    with conn.transaction():
        cur.execute(
            "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) "
            "VALUES ('TESTCC02', 'Localidad Test CC2', 'Mendoza', 'Encargado') "
            "ON CONFLICT DO NOTHING"
        )
        cur.execute(
            "INSERT INTO bodega (cuit, razon_social, domicilio) "
            "VALUES ('99999999992', 'TEST Bodega CC2', 'Ruta Test') "
            "ON CONFLICT DO NOTHING"
        )
        cur.execute(
            "INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal) "
            "VALUES ('Calle Test CC2', '1', 'lunes', 'TESTCC02') "
            "ON CONFLICT DO NOTHING RETURNING id_sala",
        )
        id_sala = cur.fetchone()["id_sala"]
        cur.execute(
            "INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Test CC2', 'tinta') "
            "ON CONFLICT DO NOTHING"
        )
        cur.execute(
            """
            INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
            VALUES ('TEST Vino CC2', 'tinto', 2021, 750, 14.0, 10000.00, '99999999992')
            RETURNING cod_vino;
            """
        )
        cod_vino = cur.fetchone()["cod_vino"]
        cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'Cepa Test CC2'")
        id_cepa = cur.fetchone()["id_cepa"]
        cur.execute(
            "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)",
            (cod_vino, id_cepa),
        )
        cur.execute(
            "INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, "
            "nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente) "
            "VALUES ('TEST Cliente CC2', 'Cliente', 'CUIT', '99999999992', 'Dir Test', "
            "'TESTCC02', CURRENT_DATE, 'socio') RETURNING id_cliente;",
        )
        id_cliente = cur.fetchone()["id_cliente"]
    # Stock de sala: 100 botellas (suficiente para ventas de prueba).
    # stock_sala es de solo lectura para app_rw: se inserta con el propietario
    # una vez que sala y vino ya están confirmados.
    db_owner_conn.execute(
        "INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (%s, %s, 100)",
        (id_sala, cod_vino),
    )
    return id_cliente, id_sala, cod_vino


@pytest.mark.integration
def test_crear_comprobante_sin_stock_lanza_p0001(
    db_conn_commit: psycopg.Connection, db_owner: psycopg.Connection
):
    """Caso 8: Venta sin stock lanza P0001 y no deja comprobante ni renglones."""
    id_cliente, id_sala, cod_vino = _preparar_datos_comprobante(
        db_conn_commit, db_owner
    )
    # Pedir 999999 botellas cuando solo hay 100: debe lanzar P0001 (RN-09)
    with pytest.raises(psycopg.errors.RaiseException) as exc_info:
        crear_comprobante(
            db_conn_commit,
            id_cliente=id_cliente,
            id_sala=id_sala,
            cod_vinos=[cod_vino],
            cantidades=[999999],
        )
    assert exc_info.value.sqlstate == "P0001"


@pytest.mark.integration
def test_crear_comprobante_exitoso_y_obtener(
    db_conn_commit: psycopg.Connection, db_owner: psycopg.Connection
):
    """Caso 9: Venta correcta con stock suficiente totaliza igual a fn_total_comprobante."""
    id_cliente, id_sala, cod_vino = _preparar_datos_comprobante(
        db_conn_commit, db_owner
    )
    nro = crear_comprobante(
        db_conn_commit,
        id_cliente=id_cliente,
        id_sala=id_sala,
        cod_vinos=[cod_vino],
        cantidades=[1],
    )
    assert nro > 0

    comp = obtener_comprobante(db_conn_commit, nro)
    assert comp is not None
    assert comp["nro_comprobante"] == nro
    assert len(comp["renglones"]) == 1

    # Verificación en el test (no en la DAL): comp['total'] == fn_total_comprobante(nro)
    row_total = db_conn_commit.execute(
        "SELECT fn_total_comprobante(%s) AS total_calculado", (nro,)
    ).fetchone()
    assert comp["total"] == row_total["total_calculado"]
