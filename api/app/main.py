"""Bodegas del Atuel - FastAPI Application Entrypoint."""

import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="Bodegas del Atuel API",
    version="0.1.0",
    description="API REST del Sistema de Gestión Vitivinícola Bodegas del Atuel (UTN FRSR)",
)

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


@app.get("/salud", tags=["Salud"])
def get_salud():
    """Verifica la operatividad de la API REST (Etapa 6 - Sección 6 del TPI)."""
    return {
        "estado": "ok",
        "servicio": "Bodegas del Atuel API",
        "db": {
            "host": os.environ.get("DB_HOST", "db"),
            "puerto": int(os.environ.get("DB_PORT", 5432)),
            "base_datos": os.environ.get(
                "DB_NAME", os.environ.get("POSTGRES_DB", "bodegas_atuel")
            ),
            "usuario": os.environ.get("DB_USER", "app_rw"),
        },
    }
