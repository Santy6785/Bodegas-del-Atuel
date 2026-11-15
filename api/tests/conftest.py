"""Fixtures compartidas para los tests de la API y de la DAL."""

from collections.abc import Generator
from contextlib import asynccontextmanager
from pathlib import Path

import os
import pathlib
import subprocess
import psycopg
from psycopg.rows import dict_row
import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.db.pool import get_conn
from app.main import app

TEST_DB = "bodegas_atuel_test"
RAIZ = pathlib.Path(__file__).resolve().parents[2]

# La suite de integración usa siempre la base de pruebas, nunca la de desarrollo.
os.environ["DB_NAME"] = TEST_DB
os.environ["POSTGRES_DB"] = TEST_DB
get_settings.cache_clear()

def pytest_configure(config):
    """Registra el marcador ``integration`` para pruebas con base de datos real."""
    config.addinivalue_line(
        "markers", "integration: pruebas de integración con base de datos real"
    )

def _sql_en_contenedor(sql: str, base: str) -> None:
    subprocess.run(
        [
            "docker", "compose", "exec", "-T", "db",
            "psql", "-U", "owner_bodegas", "-d", base,
            "-v", "ON_ERROR_STOP=1", "-c", sql,
        ],
        cwd=RAIZ,
        check=True,
    )


@pytest.fixture(scope="session")
def base_de_pruebas() -> None:
    """Recrea bodegas_atuel_test desde cero una vez por sesión de pytest."""
    _sql_en_contenedor(f"DROP DATABASE IF EXISTS {TEST_DB} WITH (FORCE);", "postgres")
    _sql_en_contenedor(f"CREATE DATABASE {TEST_DB};", "postgres")
    subprocess.run(["bash", "scripts/migrate.sh", "--db", TEST_DB], cwd=RAIZ, check=True)

def _owner_conninfo() -> str:
    """Cadena de conexión para el rol propietario (owner_bodegas).

    Lee credenciales de variables de entorno (definidas en .env). Nunca
    se escriben valores en el código. Usa el mismo DB_PORT que el rol de
    aplicación (get_settings) para no apuntar a un puerto distinto al de
    la base de datos local.
    """
    from psycopg.conninfo import make_conninfo

    return make_conninfo(
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", "5432")),
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


# ---------------------------------------------------------------------------
# Fixtures de conexión
# ---------------------------------------------------------------------------

@pytest.fixture()
def db_owner(base_de_pruebas) -> Generator[psycopg.Connection, None, None]:
    if not is_database_reachable():
        pytest.skip("Base de datos PostgreSQL no disponible para pruebas de integración")
    conn = psycopg.connect(_owner_conninfo(), autocommit=True, row_factory=dict_row)
    try:
        yield conn
    finally:
        conn.close()


@pytest.fixture()
def db_conn_commit(base_de_pruebas) -> Generator[psycopg.Connection, None, None]:
    if not is_database_reachable():
        pytest.skip("Base de datos PostgreSQL no disponible para pruebas de integración")
    conn = psycopg.connect(get_settings().conninfo, autocommit=True, row_factory=dict_row)
    try:
        yield conn
    finally:
        conn.close()


@pytest.fixture()
def db_conn(base_de_pruebas) -> Generator[psycopg.Connection, None, None]:
    if not is_database_reachable():
        pytest.skip("Base de datos PostgreSQL no disponible para pruebas de integración")
    conn = psycopg.connect(get_settings().conninfo, row_factory=dict_row)
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
