"""Pool de conexiones PostgreSQL con psycopg_pool."""

import logging
from collections.abc import Generator

import psycopg
import psycopg_pool
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from app.config import get_settings

logger = logging.getLogger("bodegas.db")

# Pool global. Se construye de forma perezosa en get_pool() y se abre
# explícitamente desde el lifespan de la aplicación.
_pool: ConnectionPool | None = None


def get_pool() -> ConnectionPool:
    """Devuelve el pool global, creándolo (sin abrir) si no existe."""
    global _pool
    if _pool is None:
        settings = get_settings()
        _pool = ConnectionPool(
            conninfo=settings.conninfo,
            min_size=settings.db_pool_min,
            max_size=settings.db_pool_max,
            timeout=settings.db_pool_timeout,
            max_idle=settings.db_pool_max_idle,
            open=False,  # Se abre desde el lifespan; fallo temprano al arrancar.
            kwargs={
                "row_factory": dict_row,
                "application_name": "bodegas-api",
            },
        )
    return _pool


def open_pool() -> None:
    """Abre el pool y espera a que las conexiones mínimas estén listas.

    Si la base no responde, se registra el host y la base (nunca la
    contraseña) y se relanza la excepción para que la API no arranque.
    """
    settings = get_settings()
    try:
        get_pool().open(wait=True, timeout=settings.db_pool_timeout)
    except psycopg_pool.PoolTimeout:
        logger.error(
            "No se pudo abrir el pool: host=%s base=%s",
            settings.db_host,
            settings.db_name,
        )
        raise


def close_pool() -> None:
    """Cierra el pool y libera todas las conexiones."""
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


def get_conn() -> Generator[psycopg.Connection, None, None]:
    """Dependencia de FastAPI: provee una conexión del pool.

    El manejo de transacciones (conn.transaction()) se hace en CADA función
    de consulta, NO en esta dependencia.
    """
    pool = get_pool()
    with pool.connection() as conn:
        yield conn