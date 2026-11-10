"""Bodegas del Atuel - FastAPI Application Entrypoint."""

import os
from contextlib import asynccontextmanager

import psycopg
import psycopg_pool
from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.db.pool import close_pool, get_conn, open_pool
from app.db.queries.salud import verificar_conexion
from app.errors import register_exception_handlers, traducir_error
from app.routers.comprobantes import router as comprobantes_router
from app.routers.transferencias import router as transferencias_router
from app.routers.vinos import router as vinos_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Abre el pool al arrancar y lo cierra al apagar."""
    open_pool()
    yield
    close_pool()


app = FastAPI(
    title="Bodegas del Atuel API",
    version="0.1.0",
    description="API REST del Sistema de Gestión Vitivinícola Bodegas del Atuel (UTN FRSR)",
    lifespan=lifespan,
)

register_exception_handlers(app)

app.include_router(vinos_router)
app.include_router(comprobantes_router)
app.include_router(transferencias_router)

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

@app.exception_handler(psycopg.OperationalError)
@app.exception_handler(psycopg_pool.PoolTimeout)
async def _error_conexion(request: Request, exc: psycopg.Error):
    """Traduce fallas de conexión.

    GET /salud conserva su cuerpo propio exigido por test_salud.py. Cualquier
    otro endpoint responde con el formato anidado del contrato §1.1,
    delegando en traducir_error (clase 08 -> 503 "No hay conexión...").
    """
    if request.url.path == "/salud":
        return JSONResponse(
            status_code=503,
            content={"estado": "error", "base_de_datos": "inaccesible"},
        )
    status_code, cuerpo, headers = traducir_error(exc, request.method)
    return JSONResponse(status_code=status_code, content=cuerpo, headers=headers)


@app.get("/salud", tags=["Salud"])
def get_salud(conn=Depends(get_conn)):
    """Verifica la operatividad de la API REST (Etapa 6 - Sección 6 del TPI)."""
    verificar_conexion(conn)
    return {"estado": "ok", "base_de_datos": "ok"}
