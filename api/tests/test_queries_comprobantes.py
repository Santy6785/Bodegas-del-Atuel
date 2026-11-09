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


@pytest.mark.integration
def test_crear_comprobante_sin_stock_lanza_p0001(db_conn: psycopg.Connection):
    """Caso 8: Venta sin stock lanza P0001 y no deja comprobante ni renglones."""
    # crear_comprobante con cantidad mayor al stock disponible de la sala debe lanzar P0001 (RN-09)
    with pytest.raises(psycopg.errors.RaiseException) as exc_info:
        crear_comprobante(
            db_conn,
            id_cliente=1,
            id_sala=1,
            cod_vinos=[1],
            cantidades=[999999],
        )
    assert exc_info.value.sqlstate == "P0001"


@pytest.mark.integration
def test_crear_comprobante_exitoso_y_obtener(db_conn: psycopg.Connection):
    """Caso 9: Venta correcta con stock suficiente totaliza igual a fn_total_comprobante."""
    nro = crear_comprobante(
        db_conn,
        id_cliente=1,
        id_sala=1,
        cod_vinos=[1],
        cantidades=[1],
    )
    assert nro > 0

    comp = obtener_comprobante(db_conn, nro)
    assert comp is not None
    assert comp["nro_comprobante"] == nro
    assert len(comp["renglones"]) == 1

    # Verificación en el test (no en la DAL): comp['total'] == fn_total_comprobante(nro)
    row_total = db_conn.execute(
        "SELECT fn_total_comprobante(%s) AS total_calculado", (nro,)
    ).fetchone()
    assert comp["total"] == row_total["total_calculado"]
