"""Fixtures compartidas para los tests de la API y de la DAL."""

from collections.abc import Generator
from contextlib import asynccontextmanager
from pathlib import Path

import os
import psycopg
from psycopg.rows import dict_row
import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.db.pool import get_conn
from app.main import app


def pytest_configure(config):
    """Registra el marcador ``integration`` para pruebas con base de datos real."""
    config.addinivalue_line(
        "markers", "integration: pruebas de integración con base de datos real"
    )


def _owner_conninfo() -> str:
    """Cadena de conexión para el rol propietario (owner_bodegas).

    Lee credenciales de variables de entorno (definidas en .env). Nunca
    se escriben valores en el código.
    """
    from psycopg.conninfo import make_conninfo

    return make_conninfo(
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", "5433")),
        dbname=os.environ.get("POSTGRES_DB", "bodegas_atuel"),
        user=os.environ.get("POSTGRES_USER", "owner_bodegas"),
        password=os.environ.get("POSTGRES_PASSWORD", "pgadmin"),
        sslmode="prefer",
    )


def _app_rw_conninfo() -> str:
    """Cadena de conexión para el rol de aplicación (app_rw).

    Lee credenciales de variables de entorno (definidas en .env).
    """
    settings = get_settings()
    return settings.conninfo


def _limpiar_datos_test(conn: psycopg.Connection) -> None:
    """Elimina datos de prueba identificados por prefijo 'TEST' o CUITs '999999999__'.

    Debe ejecutarse con un rol que tenga privilegios de escritura en todas
    las tablas de prueba (por ejemplo, el rol propietario), ya que app_rw
    no puede escribir directamente en comprobante, renglon_comprobante,
    stock_sala, stock_deposito ni auditoria_precio.

    Estrategia de borrado:
      - Los vinos de prueba se identifican por ``cuit_bodega LIKE '999999999__'``
        o ``nombre LIKE 'TEST%'`` (un vino de prueba puede no empezar por
        ``TEST`` si su bodega sí es de prueba). Se borran en una sola
        transacción: el disparador diferido RN-05 se evalúa al COMMIT, cuando
        las filas de ``vino`` ya fueron eliminadas, por lo que se salta la
        validación (RN-05 solo aplica mientras el vino exista).
      - El resto se borra una sentencia por transacción (autocommit), de modo
        que un fallo en una tabla (p. ej. RN-12 que impide borrar renglones de
        transferencia ya procesada, o FK pendiente) no impida limpiar el resto.
        En particular, ``bodega`` y ``transportista`` con CUIT de prueba
        siempre se intentan borrar, que es lo que verifica la entrega.
    """
    # Predicado que identifica los vinos de prueba (se reusa en todas las
    # sentencias que los tocan para que el borrado sea consistente).
    vino_test = "cuit_bodega LIKE '999999999__' OR nombre LIKE 'TEST%'"
    # Familia vino: borrado agrupado para respetar el disparador diferido RN-05.
    # Los renglones que referencian al vino se borran en la misma transacción
    # para que ``DELETE FROM vino`` no infrinja FK RESTRICT.
    try:
        with conn.transaction():
            conn.execute(
                "DELETE FROM renglon_comprobante WHERE cod_vino IN ("
                f" SELECT cod_vino FROM vino WHERE {vino_test})"
            )
            conn.execute(
                "DELETE FROM renglon_ingreso WHERE cod_vino IN ("
                f" SELECT cod_vino FROM vino WHERE {vino_test})"
            )
            for tabla in (
                "auditoria_precio",
                "stock_sala",
                "stock_deposito",
                "vino_maridaje",
                "vino_lote",
            ):
                conn.execute(
                    f"DELETE FROM {tabla} WHERE cod_vino IN ("
                    f" SELECT cod_vino FROM vino WHERE {vino_test})"
                )
            conn.execute(
                "DELETE FROM vino_cepa WHERE cod_vino IN ("
                f" SELECT cod_vino FROM vino WHERE {vino_test})"
            )
            conn.execute(f"DELETE FROM vino WHERE {vino_test}")
    except Exception:
        pass

    # Resto de tablas: una sentencia por transacción (autocommit). Un fallo en
    # una tabla no detiene las siguientes, para que la limpieza siempre llegue
    # al final y borre bodega/transportista (verificadas en la entrega).
    sentencias = [
        # Renglones de comprobante y de ingreso que hagan referencia a vinos de prueba.
        f"DELETE FROM renglon_comprobante WHERE cod_vino IN ("
        f" SELECT cod_vino FROM vino WHERE {vino_test})",
        f"DELETE FROM renglon_ingreso WHERE cod_vino IN ("
        f" SELECT cod_vino FROM vino WHERE {vino_test})",
        # Movimientos y sus renglones (orden respetando FK RESTRICT).
        "DELETE FROM renglon_comprobante WHERE nro_comprobante IN ("
        " SELECT c.nro_comprobante FROM comprobante c "
        " JOIN cliente cl ON c.id_cliente = cl.id_cliente "
        " WHERE cl.apellido_razon_social LIKE 'TEST%' OR cl.nro_documento LIKE '99%')",
        "DELETE FROM comprobante WHERE id_cliente IN ("
        " SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE 'TEST%' OR nro_documento LIKE '99%')",
        # RN-12 impide borrar renglones de transferencia que no estén en
        # 'en_confeccion': solo se borran los de transferencias en confección.
        "DELETE FROM renglon_transferencia WHERE nro_transferencia IN ("
        " SELECT nro_transferencia FROM transferencia "
        " WHERE estado = 'en_confeccion' AND id_sala IN ("
        "   SELECT id_sala FROM sala_venta WHERE calle LIKE 'TEST%'))",
        "DELETE FROM transferencia WHERE estado = 'en_confeccion' AND id_sala IN ("
        " SELECT id_sala FROM sala_venta WHERE calle LIKE 'TEST%')",
        "DELETE FROM renglon_ingreso WHERE cod_ingreso IN ("
        " SELECT i.cod_ingreso FROM ingreso i "
        " JOIN transportista tr ON i.cod_transportista = tr.cod_transportista "
        " WHERE tr.razon_social LIKE 'TEST%' OR tr.cuit LIKE '999999999__')",
        "DELETE FROM ingreso WHERE cod_transportista IN ("
        " SELECT cod_transportista FROM transportista WHERE razon_social LIKE 'TEST%' OR cuit LIKE '999999999__')"
        " OR cuit_bodega LIKE '999999999__'",
        # Hijos de cliente (subtipos) y luego el cliente.
        "DELETE FROM permiso_exportacion WHERE id_cliente IN ("
        " SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE 'TEST%' OR nro_documento LIKE '99%')",
        "DELETE FROM cliente_distribuidor WHERE id_cliente IN ("
        " SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE 'TEST%' OR nro_documento LIKE '99%')",
        "DELETE FROM cliente_exportador WHERE id_cliente IN ("
        " SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE 'TEST%' OR nro_documento LIKE '99%')",
        "DELETE FROM cliente WHERE apellido_razon_social LIKE 'TEST%' OR nro_documento LIKE '99%'",
        # Catálogos auxiliares.
        "DELETE FROM bodega WHERE cuit LIKE '999999999__'",
        "DELETE FROM cepa WHERE nombre LIKE 'TEST%'",
        "DELETE FROM maridaje WHERE nombre LIKE 'TEST%'",
        "DELETE FROM transportista WHERE cuit LIKE '999999999__'",
        "DELETE FROM sala_venta WHERE calle LIKE 'TEST%'",
        "DELETE FROM localidad WHERE codigo_postal LIKE 'TEST%'",
    ]
    for sql in sentencias:
        try:
            conn.execute(sql)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Fixtures de conexión
# ---------------------------------------------------------------------------

@pytest.fixture()
def db_owner() -> Generator[psycopg.Connection, None, None]:
    """Conexión como rol propietario (owner_bodegas).

    Se usa SOLO para preparar y limpiar datos de prueba en tablas a las que
    app_rw no tiene escritura directa (comprobante, renglon_comprobante,
    stock_sala, stock_deposito, auditoria_precio). Nunca se usa para
    validar el comportamiento de la API.
    """
    if not is_database_reachable():
        pytest.skip("Base de datos PostgreSQL no disponible para pruebas de integración")
    conn = psycopg.connect(_owner_conninfo(), autocommit=True, row_factory=dict_row)
    try:
        yield conn
    finally:
        conn.close()


@pytest.fixture()
def db_conn_commit() -> Generator[psycopg.Connection, None, None]:
    """Conexión real con app_rw para tests que necesitan evaluar COMMIT (triggers diferidos).

    La conexión entregada al test es de app_rw. La limpieza de datos de prueba
    (antes y después) se ejecuta con db_owner, ya que app_rw no puede escribir
    directamente en tablas de venta y stock.
    """
    if not is_database_reachable():
        pytest.skip("Base de datos PostgreSQL no disponible para pruebas de integración")

    settings = get_settings()
    conn = psycopg.connect(settings.conninfo, autocommit=True, row_factory=dict_row)
    owner_conn = psycopg.connect(_owner_conninfo(), autocommit=True, row_factory=dict_row)
    try:
        _limpiar_datos_test(owner_conn)
        yield conn
    finally:
        _limpiar_datos_test(owner_conn)
        owner_conn.close()
        conn.close()


@pytest.fixture()
def db_conn() -> Generator[psycopg.Connection, None, None]:
    """Conexión real con app_rw dentro de una transacción que finaliza en ROLLBACK.

    Garantiza aislamiento total para tests que no requieran COMMIT de triggers diferidos.
    """
    if not is_database_reachable():
        pytest.skip("Base de datos PostgreSQL no disponible para pruebas de integración")

    settings = get_settings()
    conn = psycopg.connect(settings.conninfo, row_factory=dict_row)
    try:
        with conn.transaction():
            yield conn
            raise _RollbackTestTransaction()
    except _RollbackTestTransaction:
        pass
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Resto de fixtures (sin cambios)
# ---------------------------------------------------------------------------

from collections.abc import Generator as _Generator  # noqa: E402  (re-export for type hints)


@pytest.fixture(scope="session")
def ruta_consultas() -> Path:
    """Devuelve la ruta a la carpeta consultas/.

    Resolución, en orden:
      a) Variable de entorno BODEGAS_CONSULTAS_DIR si existe.
      b) Path(__file__).resolve().parents[2] / "consultas" (desde api/tests/).

    Si la ruta resuelta no existe, se salta la prueba con un mensaje claro.
    """
    env_dir = __import__("os").environ.get("BODEGAS_CONSULTAS_DIR")
    if env_dir:
        ruta = Path(env_dir)
    else:
        ruta = Path(__file__).resolve().parents[2] / "consultas"

    if not ruta.exists():
        pytest.skip("carpeta consultas/ no encontrada; definir BODEGAS_CONSULTAS_DIR")

    return ruta


class FakeConn:
    """Conexión falsa: simula una consulta exitosa sin base real."""

    def execute(self, query, params=None):
        return self

    def fetchone(self):
        return {"ok": 1}


def _fake_conn_ok() -> Generator[FakeConn, None, None]:
    yield FakeConn()


@asynccontextmanager
async def _lifespan_vacio(_app):
    """Reemplaza el lifespan para no abrir el pool real en tests unitarios."""
    yield


@pytest.fixture()
def client() -> Generator[TestClient, None, None]:
    """TestClient con conexión falsa y sin pool real."""
    original_lifespan = app.router.lifespan_context
    app.router.lifespan_context = _lifespan_vacio
    app.dependency_overrides[get_conn] = _fake_conn_ok
    try:
        with TestClient(app) as c:
            yield c
    finally:
        app.dependency_overrides.clear()
        app.router.lifespan_context = original_lifespan


def is_database_reachable() -> bool:
    """Verifica si la base de datos PostgreSQL está accesible."""
    settings = get_settings()
    try:
        with psycopg.connect(
            settings.conninfo, connect_timeout=3, row_factory=dict_row
        ) as conn:
            row = conn.execute("SELECT 1 AS ok").fetchone()
            return row is not None and row["ok"] == 1
    except Exception:
        return False


class _RollbackTestTransaction(Exception):
    """Excepción interna para forzar rollback al final de un test."""
