"""Pruebas unitarias (sin base de datos) para _reglas y validaciones transversales.

Estas pruebas no tocan la base de datos ni abren una conexión real y se
ejecutan con:
    pytest -m "not integration" -v
"""

from datetime import date
from decimal import Decimal
from pathlib import Path

import psycopg
import pytest

from app.db.queries._reglas import (
    CAMPOS_CALCULADOS_PROHIBIDOS,
    rechazar_campos_calculados,
    validar_fecha,
    validar_nombre_cliente,
    validar_rango_paginacion,
)
from app.db.queries.comprobantes import crear_comprobante
from app.db.queries.clientes import crear_cliente
from app.db.queries.reportes import (
    exportadores_con_descuento_extendido,
    ventas_por_sala,
)
from app.db.queries.vinos import crear_vino


class _ConexionProhibida:
    """Conexión falsa que falla si se intenta usarla.

    Su único fin es garantizar que la función bajo prueba falle antes de
    tocar la conexión. Registra en ``intentos`` cuántas veces se intentó
    usar la conexión para que las pruebas puedan verificar que no se usó.
    """

    def __init__(self) -> None:
        self.intentos = 0

    def execute(self, query, params=None):
        self.intentos += 1
        raise AssertionError("La conexión no debería usarse en esta prueba unitaria")

    def transaction(self):
        return self

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def cursor(self):
        self.intentos += 1
        raise AssertionError("La conexión no debería usarse en esta prueba unitaria")


# ---------------------------------------------------------------------------
# U1. rechazar_campos_calculados lanza ValueError para cada clave prohibida.
# ---------------------------------------------------------------------------
@pytest.mark.parametrize("campo", sorted(CAMPOS_CALCULADOS_PROHIBIDOS))
def test_rechazar_campos_calculados_todas_las_claves(campo):
    with pytest.raises(ValueError, match=campo):
        rechazar_campos_calculados({campo: 1}, "contexto_prueba")


def test_rechazar_campos_calculados_sin_campos_prohibidos_no_lanza():
    rechazar_campos_calculados({"nombre": "Ana", "tipo_cliente": "socio"}, "crear_cliente")


# ---------------------------------------------------------------------------
# U2. validar_fecha acepta date y "2026-11-05"; rechaza "2026-1-5" y "05/11/2026".
# ---------------------------------------------------------------------------
def test_validar_fecha_acepta_date():
    assert validar_fecha(date(2026, 11, 5), "fecha") == date(2026, 11, 5)


def test_validar_fecha_acepta_str_iso():
    assert validar_fecha("2026-11-05", "fecha") == date(2026, 11, 5)


def test_validar_fecha_rechaza_str_no_iso():
    with pytest.raises(ValueError, match="fecha"):
        validar_fecha("2026-1-5", "fecha")


def test_validar_fecha_rechaza_str_con_guiones_espanol():
    with pytest.raises(ValueError, match="fecha"):
        validar_fecha("05/11/2026", "fecha")


def test_validar_fecha_rechaza_tipo_invalido():
    with pytest.raises(ValueError, match="fecha"):
        validar_fecha(123, "fecha")


# ---------------------------------------------------------------------------
# U3. validar_rango_paginacion rechaza page 0, page_size 0 y page_size 101.
# ---------------------------------------------------------------------------
def test_validar_rango_paginacion_page_cero():
    with pytest.raises(ValueError, match="page"):
        validar_rango_paginacion(0, 10)


def test_validar_rango_paginacion_page_size_cero():
    with pytest.raises(ValueError, match="page_size"):
        validar_rango_paginacion(1, 0)


def test_validar_rango_paginacion_page_size_101():
    with pytest.raises(ValueError, match="page_size"):
        validar_rango_paginacion(1, 101)


def test_validar_rango_paginacion_valores_ok():
    validar_rango_paginacion(1, 1)
    validar_rango_paginacion(1, 100)
    validar_rango_paginacion(5, 20)


# ---------------------------------------------------------------------------
# U4. ventas_por_sala con periodo="ultimo_mes" lanza ValueError sin tocar la base.
# ---------------------------------------------------------------------------
def test_ventas_por_sala_periodo_invalido_sin_base():
    conn = _ConexionProhibida()
    with pytest.raises(ValueError, match="periodo"):
        ventas_por_sala(conn, periodo="ultimo_mes")
    assert conn.intentos == 0, "La conexión no debió usarse"


# ---------------------------------------------------------------------------
# U5. ventas_por_sala con fecha_desde > fecha_hasta lanza ValueError.
# ---------------------------------------------------------------------------
def test_ventas_por_sala_rango_invalido():
    conn = _ConexionProhibida()
    with pytest.raises(ValueError, match="no puede ser posterior"):
        ventas_por_sala(
            conn,
            fecha_desde=date(2026, 12, 1),
            fecha_hasta=date(2026, 1, 1),
        )
    assert conn.intentos == 0, "La conexión no debió usarse"


# ---------------------------------------------------------------------------
# U6. crear_cliente con "porcentaje_descuento" en el bloque exportador lanza ValueError.
# ---------------------------------------------------------------------------
def test_crear_cliente_exportador_con_porcentaje_descuento():
    datos = {
        "apellido_razon_social": "TEST X",
        "tipo_documento": "CUIT",
        "nro_documento": "99999999991",
        "direccion": "Calle 1",
        "codigo_postal": "TEST5600",
        "tipo_cliente": "exportador",
        "exportador": {
            "pais_destino": "Brasil",
            "porcentaje_descuento": Decimal("30.00"),
        },
    }
    conn = _ConexionProhibida()
    with pytest.raises(ValueError, match="porcentaje_descuento"):
        crear_cliente(conn, datos)
    assert conn.intentos == 0, "La conexión no debió usarse"


# ---------------------------------------------------------------------------
# U7. crear_cliente con tipo "socio" y bloque "exportador" lanza ValueError.
# ---------------------------------------------------------------------------
def test_crear_cliente_socio_con_bloque_exportador():
    datos = {
        "apellido_razon_social": "TEST X",
        "tipo_documento": "DNI",
        "nro_documento": "99999999992",
        "direccion": "Calle 1",
        "codigo_postal": "TEST5600",
        "tipo_cliente": "socio",
        "exportador": {"pais_destino": "Brasil"},
    }
    conn = _ConexionProhibida()
    with pytest.raises(ValueError):
        crear_cliente(conn, datos)
    assert conn.intentos == 0, "La conexión no debió usarse"


# ---------------------------------------------------------------------------
# U8. crear_cliente con tipo "exportador" sin bloque "exportador" lanza ValueError.
# ---------------------------------------------------------------------------
def test_crear_cliente_exportador_sin_bloque():
    datos = {
        "apellido_razon_social": "TEST X",
        "tipo_documento": "CUIT",
        "nro_documento": "99999999993",
        "direccion": "Calle 1",
        "codigo_postal": "TEST5600",
        "tipo_cliente": "exportador",
    }
    conn = _ConexionProhibida()
    with pytest.raises(ValueError):
        crear_cliente(conn, datos)
    assert conn.intentos == 0, "La conexión no debió usarse"


# ---------------------------------------------------------------------------
# U9. crear_vino con maridajes que no son int lanza ValueError.
# ---------------------------------------------------------------------------
def test_crear_vino_maridajes_no_entero():
    datos = {
        "nombre": "TEST Vino",
        "tipo": "tinto",
        "anada": 2021,
        "volumen_ml": 750,
        "graduacion": Decimal("14.0"),
        "precio": Decimal("10000.00"),
        "cuit_bodega": "99999999991",
        "composicion": [{"id_cepa": 1, "porcentaje": Decimal("100.00")}],
        "maridajes": ["no-es-un-int"],
    }
    conn = _ConexionProhibida()
    with pytest.raises(ValueError, match="maridajes|entero"):
        crear_vino(conn, datos)
    assert conn.intentos == 0, "La conexión no debió usarse"


# ---------------------------------------------------------------------------
# U10. crear_comprobante con listas vacías o de distinta longitud lanza ValueError.
# ---------------------------------------------------------------------------
def test_crear_comprobante_listas_vacias():
    conn = _ConexionProhibida()
    with pytest.raises(ValueError, match="vacías"):
        crear_comprobante(conn, id_cliente=1, id_sala=1, cod_vinos=[], cantidades=[])
    assert conn.intentos == 0, "La conexión no debió usarse"


def test_crear_comprobante_listas_distinta_longitud():
    conn = _ConexionProhibida()
    with pytest.raises(ValueError, match="misma longitud"):
        crear_comprobante(
            conn, id_cliente=1, id_sala=1, cod_vinos=[1, 2], cantidades=[5]
        )
    assert conn.intentos == 0, "La conexión no debió usarse"


# ---------------------------------------------------------------------------
# U11. exportadores_con_descuento_extendido existe y es callable.
# ---------------------------------------------------------------------------
def test_exportadores_con_descuento_extendido_es_callable():
    assert callable(exportadores_con_descuento_extendido)


# ---------------------------------------------------------------------------
# U11 (integración). exportadores_con_descuento_extendido coincide con la
# consulta de consultas/select.sql.
# ---------------------------------------------------------------------------
@pytest.mark.integration
def test_exportadores_con_descuento_extendido_coincide_con_select_sql(
    db_conn: psycopg.Connection, ruta_consultas: Path
):
    """Compara el resultado de la DAL con la consulta U6-R de consultas/select.sql."""
    sql = (ruta_consultas / "select.sql").read_text(encoding="utf-8")
    filas_sql = db_conn.execute(sql).fetchall()

    filas_dal = exportadores_con_descuento_extendido(db_conn)

    assert len(filas_sql) == len(filas_dal)
    for fila_sql, fila_dal in zip(filas_sql, filas_dal):
        assert fila_sql["id_cliente"] == fila_dal["id_cliente"]
        assert fila_sql["cantidad_permisos"] == fila_dal["cantidad_permisos"]
        assert fila_sql["descuento_pct"] == fila_dal["descuento_pct"]


# ---------------------------------------------------------------------------
# U12. consultas/update.sql no contiene "porcentaje_descuento" (lectura de texto).
# ---------------------------------------------------------------------------
def test_update_sql_sin_porcentaje_descuento(ruta_consultas: Path):
    contenido = (ruta_consultas / "update.sql").read_text(encoding="utf-8")
    assert "porcentaje_descuento" not in contenido


# ---------------------------------------------------------------------------
# U13. consultas/select.sql contiene el encabezado "U6-R".
# ---------------------------------------------------------------------------
def test_select_sql_contiene_encabezado_u6r(ruta_consultas: Path):
    contenido = (ruta_consultas / "select.sql").read_text(encoding="utf-8")
    assert "U6-R" in contenido


# ---------------------------------------------------------------------------
# U14 (validación de nombre). DNI sin nombre -> ValueError.
# ---------------------------------------------------------------------------
def test_validar_nombre_dni_sin_nombre():
    with pytest.raises(ValueError, match="nombre"):
        validar_nombre_cliente("DNI", None)


# ---------------------------------------------------------------------------
# U15 (validación de nombre). DNI con nombre vacío -> ValueError.
# ---------------------------------------------------------------------------
def test_validar_nombre_dni_nombre_vacio():
    with pytest.raises(ValueError, match="nombre"):
        validar_nombre_cliente("DNI", "")


# ---------------------------------------------------------------------------
# U16 (validación de nombre). CUIT con nombre None -> no lanza.
# ---------------------------------------------------------------------------
def test_validar_nombre_cuit_nombre_none():
    validar_nombre_cliente("CUIT", None)


# ---------------------------------------------------------------------------
# U17 (validación de nombre). CUIT con nombre "Ana" -> ValueError.
# ---------------------------------------------------------------------------
def test_validar_nombre_cuit_con_nombre():
    with pytest.raises(ValueError, match="razones sociales"):
        validar_nombre_cliente("CUIT", "Ana")
