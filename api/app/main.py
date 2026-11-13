"""Bodegas del Atuel - FastAPI Application Entrypoint."""

import os
from fastapi.middleware.cors import CORSMiddleware
import logging
import traceback

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import HTTPException as FastAPIHTTPException
from psycopg import errors as pg_errors

from api.app.config import get_settings, Settings
from api.app.errors import translate_sqlstate_to_http, build_error_response

app = FastAPI(
    title="Bodegas del Atuel API",
    version="0.1.0",
    description="API REST del Sistema de Gestión Vitivinícola Bodegas del Atuel (UTN FRSR)",
)


@app.get("/salud", tags=["Salud"])
async def salud() -> JSONResponse:
    from fastapi.responses import JSONResponse
    import os

    response = {
        "estado": "ok",
        "servicio": "Bodegas del Atuel API",
        "db": {
            "host": os.environ.get("DB_HOST", "db"),
            "puerto": int(os.environ.get("DB_PORT", 5432)),
            "base_datos": os.environ.get("DB_NAME", os.environ.get("POSTGRES_DB", "bodegas_atuel")),
            "usuario": os.environ.get("DB_USER", "app_rw"),
        },
    }
    return JSONResponse(content=response)


# ---------------------------------------------------------------------------
# Manejador de excepciones psycopg / SQLSTATE
# ---------------------------------------------------------------------------

@app.exception_handler(pg_errors.Error)
async def psycopg_error_handler(request: Request, exc: pg_errors.Error) -> JSONResponse:
    """
    Maneja errores lanzados por psycopg (ej. RAISE EXCEPTION con P0001,
    violaciones de constraint, deadlock, etc.) y los traduce a respuestas HTTP
    unificadas según el SQLSTATE de PostgreSQL.
    """
    # Extraer SQLSTATE y mensaje de PostgreSQL
    sqlstate = getattr(exc, "sqlstate", None) or getattr(exc, "pgcode", None)
    # Psycopg a veces pone el mensaje en exc.message o exc.args[0]
    exc_message = str(exc)
    if hasattr(exc, "pgcode") and exc.pgcode:
        sqlstate = exc.pgcode
    elif hasattr(exc, "sqlstate") and exc.sqlstate:
        sqlstate = exc.sqlstate

    # Traducir a HTTP
    http_code, detail, sqlstate_code = translate_sqlstate_to_http(sqlstate or "")

    # Si no hay detail y es P0001, intentemos extraer el mensaje primario
    # Psycopg a veces tiene exc.diag.message_primary pero no siempre está disponible
    if not detail and sqlstate == "P0001":
        # Intentar extraer mensaje de diag si está disponible
        diag_getattr = None
        try:
            # Algunos errores psycopg expone diag a través de attributes dinámicos
            diag_getattr = getattr(exc, "diag", None)
        except Exception:
            diag_getattr = None
        if diag_getattr and getattr(diag_getattr, "message_primary", None):
            detail = diag_getattr.message_primary
        elif not detail:
            # Fallback: usar el mensaje genérico si no hay diag
            detail = "Regla de negocio rechazada"

    # Construir respuesta unificada
    response = build_error_response(http_code, sqlstate or "", detail=detail)

    # Registrar detalle completo en log (nunca en respuesta si pudiera tener datos sensibles)
    logging.getLogger("api.errors").warning(
        "SQLSTATE %s | HTTP %s | Detail: %s | Query: %s",
        sqlstate,
        http_code,
        detail,
        request.url.path,
        exc_info=True,
    )

    return JSONResponse(
        status_code=http_code,
        content=response,
    )


# ---------------------------------------------------------------------------
# Manejador de excepciones HTTP de FastAPI (422, 404, etc.)
# ---------------------------------------------------------------------------

@app.exception_handler(FastAPIHTTPException)
async def fastapi_http_exception_handler(request: Request, exc: FastAPIHTTPException) -> JSONResponse:
    """
    Maneja las excepciones HTTP nativas de FastAPI (validación Pydantic, campos
    faltantes, etc.) manteniendo el formato unificado.
    """
    # FastAPI ya pone el título y detail en el formato que espera el front
    # Tratamos de mapear a nuestro formato, pero preservando el detail original
    response = build_error_response(
        exc.status_code,
        getattr(exc, "sqlstate", None) or "",
        detail=exc.detail,
        title=exc.detail,
    )
    return JSONResponse(status_code=exc.status_code, content=response)


# ---------------------------------------------------------------------------
# Manejador genérico de excepciones 500 (cualquier error no capturado)
# ---------------------------------------------------------------------------

@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """
    Manejo genérico de cualquier excepción no capturada arriba.
    Devuelve 500 con un mensaje genérico SIN datos sensibles (sin contraseñas,
    hosts, paths internos, etc.) y registra el detalle real en el log.
    """
    # Limpiar el mensaje para evitar fugas de información
    exc_str = str(exc)
    # Quitar posibles rutas del sistema, contraseñas, etc. (patrones simples)
    # Esto es una protección básica; en producción se usa Sentry o similar
    safe_detail = exc_str
    # Evitar que se filtre información de conexión
    import re
    safe_detail = re.sub(r"postgresql://[^\s]+@", "postgresql://***@...", safe_detail)
    safe_detail = re.sub(r"password=[^&\\s]+", "password=***", safe_detail)

    logging.getLogger("api.errors").error(
        "Unhandled exception %s | %s | Path: %s",
        type(exc).__name__,
        safe_detail,
        request.url.path,
        exc_info=True,
    )

    response = build_error_response(500, "Unknown", detail="Error interno del servidor")
    return JSONResponse(status_code=500, content=response)


# ---------------------------------------------------------------------------
# CORS y resto de configuración
# ---------------------------------------------------------------------------

# CORS: permitir conexiones desde el Frontend (puerto 5173 o 3000)
cors_origins_raw = os.environ.get(
    "CORS_ORIGINS",
    "http://localhost:3000,http://localhost:5173,http://127.0.0.1:5173",
)
origins = [o.strip() for o in cors_origins_raw.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins if origins else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from api.app.routers import vinos, clientes, comprobantes, reportes, catalogos  # noqa: F401

app.include_router(vinos.router, prefix="/vinos", tags=["Vinos"])
app.include_router(clientes.router, prefix="/clientes", tags=["Clientes"])
app.include_router(comprobantes.router, prefix="/comprobantes", tags=["Comprobantes"])
app.include_router(reportes.router, prefix="/reportes", tags=["Reportes"])
app.include_router(catalogos.router, prefix="/catalogos", tags=["Catálogos"])

# Alias para compatibilidad con importaciones directas
api_app = app