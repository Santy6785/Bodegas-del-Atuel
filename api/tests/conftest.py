"""Fixtures compartidas para los tests de la API y de la DAL."""

from collections.abc import Generator
from contextlib import asynccontextmanager
from pathlib import Path

import psycopg
from psycopg.rows import dict_row
import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.db.pool import get_conn
from app.main import app


def pytest_configure(config):
    """Registra markers personalizados de pytest."""
    config.addinivalue_line(
        "markers", "integration: pruebas de integración con base de datos real"
    )


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


def _limpiar_datos_test(conn: psycopg.Connection) -> None:
    """Elimina datos de prueba identificados por prefijo 'TEST' o CUITs '999999999%'."""
    # 1. Limpiar clientes de prueba y sus subtipos en una sola transacción
    try:
        with conn.transaction():
            conn.execute(
                """
                DELETE FROM permiso_exportacion WHERE id_cliente IN (
                    SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE 'TEST%' OR nro_documento LIKE '99%'
                );
                DELETE FROM cliente_distribuidor WHERE id_cliente IN (
                    SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE 'TEST%' OR nro_documento LIKE '99%'
                );
                DELETE FROM cliente_exportador WHERE id_cliente IN (
                    SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE 'TEST%' OR nro_documento LIKE '99%'
                );
                DELETE FROM cliente WHERE apellido_razon_social LIKE 'TEST%' OR nro_documento LIKE '99%';
                """
            )
    except Exception:
        pass

    # 2. Limpiar vinos de prueba y tablas relacionadas
    try:
        with conn.transaction():
            conn.execute(
                """
                DELETE FROM auditoria_precio WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre LIKE 'TEST%');
                DELETE FROM stock_sala WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre LIKE 'TEST%');
                DELETE FROM stock_deposito WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre LIKE 'TEST%');
                DELETE FROM vino_cepa WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre LIKE 'TEST%');
                DELETE FROM vino_maridaje WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre LIKE 'TEST%');
                DELETE FROM vino_lote WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre LIKE 'TEST%');
                DELETE FROM vino WHERE nombre LIKE 'TEST%';
                """
            )
    except Exception:
        pass

    # 3. Limpiar catálogos auxiliares de prueba
    try:
        with conn.transaction():
            conn.execute(
                """
                DELETE FROM bodega WHERE cuit LIKE '999999999%';
                DELETE FROM cepa WHERE nombre LIKE 'TEST%';
                DELETE FROM maridaje WHERE nombre LIKE 'TEST%';
                DELETE FROM transportista WHERE cuit LIKE '999999999%';
                DELETE FROM sala_venta WHERE calle LIKE 'TEST%';
                DELETE FROM localidad WHERE codigo_postal LIKE 'TEST%';
                """
            )
    except Exception:
        pass


@pytest.fixture()
def db_conn_commit() -> Generator[psycopg.Connection, None, None]:
    """Conexión real con app_rw para tests que necesitan evaluar COMMIT (triggers diferidos).

    Limpia los datos creados con prefijo TEST o CUIT 9999999999% al finalizar.
    Utiliza autocommit=True en la conexión para que los bloques `with conn.transaction():`
    de la DAL emitan un BEGIN/COMMIT real de primer nivel donde se evalúan los triggers diferidos.
    """
    if not is_database_reachable():
        pytest.skip("Base de datos PostgreSQL no disponible para pruebas de integración")

    settings = get_settings()
    conn = psycopg.connect(settings.conninfo, autocommit=True, row_factory=dict_row)
    _limpiar_datos_test(conn)
    try:
        yield conn
    finally:
        _limpiar_datos_test(conn)
        conn.close()
