"""Traducción de errores de PostgreSQL (SQLSTATE) a respuestas HTTP.

Implementa el mapeo obligatorio del contrato §1.2 y del TPI, Etapa 6,
sección "Traducción de errores". El módulo separa la lógica pura
(``traducir_error``) del registro de handlers de FastAPI, lo que permite
probar la traducción sin necesidad de una base de datos real.

Nombres, comentarios y strings de usuario en español, consistentes con el
resto del proyecto.
"""

from __future__ import annotations

import logging
from typing import Any

import psycopg
import psycopg.errors as pge
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

logger = logging.getLogger("bodegas.errors")

# Cuerpo genérico para errores no mapeados (nunca se expone el texto original).
_MENSAJE_GENERICO = "Error interno de la base de datos."

# Mapeo SQLSTATE -> (status_code, mensaje_clave, necesita_retry_after).
# El mensaje_clave es un texto genérico salvo para P0001, que usa el texto
# del RAISE EXCEPTION (diag.message_primary).
_MAPEO_SQLSTATE: dict[str, tuple[int, str, bool]] = {
    "23505": (409, "Ya existe un registro con esos datos.", False),
    "23514": (422, "Un valor no cumple una restricción de dominio.", False),
    "23502": (422, "Falta un dato obligatorio.", False),
    "22P02": (400, "Formato inválido para un dato.", False),
    "40001": (503, "La operación no pudo completarse por concurrencia. Intente nuevamente.", True),
    "40P01": (503, "La operación no pudo completarse por concurrencia. Intente nuevamente.", True),
}

# Clases psycopg que se resuelven por tipo (antes que el SQLSTATE bruto).
# 23503 es especial: el HTTP depende del método (409 DELETE / 422 resto).
_CLASSE_23503_DELETE = 409
_CLASSE_23503_OTRO = 422

_MENSAJE_23503_DELETE = "No se puede eliminar: el registro tiene datos asociados."
_MENSAJE_23503_OTRO = "El dato referenciado no existe."

_MENSAJE_08 = "No hay conexión con la base de datos."


def _restriccion(exc: psycopg.Error) -> str | None:
    """Devuelve el nombre de la restricción violada, si el driver lo expone."""
    return getattr(exc.diag, "constraint_name", None)


def _nombre_tabla(exc: psycopg.Error) -> str | None:
    """Devuelve el nombre de la tabla afectada, si el driver lo expone."""
    return getattr(exc.diag, "table_name", None)


def traducir_error(exc: psycopg.Error, metodo: str) -> tuple[int, dict[str, Any], dict[str, str]]:
    """Traduce una excepción de psycopg a (status_code, cuerpo, headers).

    Es una función pura: no toca la red ni la base de datos. Solo loguea
    cuando el error no está en la tabla de mapeo o es de clase inesperada.

    Args:
        exc: excepción de psycopg (cualquier subclase de ``psycopg.Error``).
        metodo: método HTTP de la petición que originó el error
            (ej. ``"DELETE"``, ``"POST"``).

    Returns:
        Tupla ``(status_code, cuerpo, headers)`` donde ``cuerpo`` tiene el
        formato anidado del contrato §1.1::

            {"error": {"sqlstate": "...", "mensaje": "...", "restriccion": ...}}
    """
    sqlstate = exc.sqlstate or ""
    headers: dict[str, str] = {}

    # --- Clase 08: errores de conexión -------------------------------------
    if sqlstate.startswith("08"):
        cuerpo = {
            "error": {
                "sqlstate": sqlstate,
                "mensaje": _MENSAJE_08,
                "restriccion": None,
            }
        }
        return 503, cuerpo, headers

    # --- P0001: regla de negocio (RAISE EXCEPTION) --------------------------
    if sqlstate == "P0001":
        mensaje = exc.diag.message_primary if exc.diag.message_primary is not None else str(exc)
        cuerpo = {
            "error": {
                "sqlstate": sqlstate,
                "mensaje": mensaje,
                "restriccion": None,
            }
        }
        return 409, cuerpo, headers

    # --- 23503: clave foránea (depende del método HTTP) ---------------------
    if sqlstate == "23503":
        if metodo.upper() == "DELETE":
            status = _CLASSE_23503_DELETE
            mensaje = _MENSAJE_23503_DELETE
        else:
            status = _CLASSE_23503_OTRO
            mensaje = _MENSAJE_23503_OTRO
        cuerpo = {
            "error": {
                "sqlstate": sqlstate,
                "mensaje": mensaje,
                "restriccion": _restriccion(exc),
            }
        }
        return status, cuerpo, headers

    # --- Mapeo directo por SQLSTATE -----------------------------------------
    if sqlstate in _MAPEO_SQLSTATE:
        status, mensaje, retry = _MAPEO_SQLSTATE[sqlstate]
        if retry:
            headers["Retry-After"] = "1"
        cuerpo = {
            "error": {
                "sqlstate": sqlstate,
                "mensaje": mensaje,
                "restriccion": _restriccion(exc),
            }
        }
        return status, cuerpo, headers

    # --- Cualquier otro error: 500 genérico y logueo del SQLSTATE -----------
    # Nunca se loguea el texto completo de la excepción: puede contener
    # valores de datos de la base (datos personales, CUITs, etc.).
    logger.error(
        "Error de base de datos no mapeado: sqlstate=%s constraint=%s tabla=%s",
        sqlstate,
        _restriccion(exc),
        _nombre_tabla(exc),
    )
    cuerpo = {
        "error": {
            "sqlstate": sqlstate or None,
            "mensaje": _MENSAJE_GENERICO,
            "restriccion": None,
        }
    }
    return 500, cuerpo, headers


async def _handler_psycopg_error(request: Request, exc: psycopg.Error) -> JSONResponse:
    """Handler de FastAPI para ``psycopg.Error``.

    Extrae el método de la petición y delega en la función pura
    ``traducir_error``. Nunca expone credenciales ni cadenas de conexión.
    """
    status_code, cuerpo, headers = traducir_error(exc, request.method)
    return JSONResponse(status_code=status_code, content=cuerpo, headers=headers)


def register_exception_handlers(app: FastAPI) -> None:
    """Registra el handler genérico de ``psycopg.Error`` en la app.

    Se registra para la clase base ``psycopg.Error``. Los handlers más
    específicos (``psycopg.OperationalError`` y ``psycopg_pool.PoolTimeout``)
    ya registrados en ``main.py`` tienen prioridad por jerarquía de clases,
    por lo que ``/salud`` sigue devolviendo su cuerpo distinto.
    """
    app.add_exception_handler(psycopg.Error, _handler_psycopg_error)
