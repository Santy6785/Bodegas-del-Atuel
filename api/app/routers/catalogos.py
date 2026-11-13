"""Routers para catálogos auxiliares de solo lectura."""

from __future__ import annotations

import psycopg

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from api.app.db.queries.get_catalog import (
    get_salas_query,
    get_cepas_query,
    get_bodegas_query,
    get_maridajes_query,
    get_transportistas_query,
    get_localidades_query,
)
from api.app.config import Settings, get_settings


router = APIRouter(tags=["Catálogos"])


def get_db_conn(settings: Settings = Depends(get_settings)) -> psycopg.Connection:
    """Dependency: crea una conexión psycopg con la configuración actual."""
    from psycopg.conninfo import make_conninfo
    conninfo = make_conninfo(
        host=settings.db_host,
        port=settings.db_port,
        dbname=settings.db_name,
        user=settings.db_user,
        password=settings.db_password,
        sslmode=settings.db_sslmode,
    )
    return psycopg.connect(conninfo)


@router.get("/salas", tags=["Catálogos"])
def listar_salas(conn: psycopg.Connection = Depends(get_db_conn)) -> list:
    """Listar salas de venta."""
    sql, params = get_salas_query()
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    return [{"id_sala": r[0], "calle": r[1], "numero": r[2], "dia_cierre": r[3], "codigo_postal": r[4]} for r in rows]


@router.get("/cepas", tags=["Catálogos"])
def listar_cepas(conn: psycopg.Connection = Depends(get_db_conn)) -> list:
    """Listar cepas."""
    sql, params = get_cepas_query()
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    return [{"id_cepa": r[0], "nombre": r[1], "tipo": r[2]} for r in rows]


@router.get("/bodegas", tags=["Catálogos"])
def listar_bodegas(conn: psycopg.Connection = Depends(get_db_conn)) -> list:
    """Listar bodegas."""
    sql, params = get_bodegas_query()
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    return [{"cuit": r[0], "razon_social": r[1], "domicilio": r[2]} for r in rows]


@router.get("/maridajes", tags=["Catálogos"])
def listar_maridajes(conn: psycopg.Connection = Depends(get_db_conn)) -> list:
    """Listar maridajes."""
    sql, params = get_maridajes_query()
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    return [{"id_maridaje": r[0], "nombre": r[1], "temperatura_servicio": r[2]} for r in rows]


@router.get("/transportistas", tags=["Catálogos"])
def listar_transportistas(conn: psycopg.Connection = Depends(get_db_conn)) -> list:
    """Listar transportistas."""
    sql, params = get_transportistas_query()
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    return [{"cod_transportista": r[0], "razon_social": r[1], "cuit": r[2]} for r in rows]


@router.get("/localidades", tags=["Catálogos"])
def listar_localidades(conn: psycopg.Connection = Depends(get_db_conn)) -> list:
    """Listar localidades."""
    sql, params = get_localidades_query()
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    return [{"codigo_postal": r[0], "nombre": r[1], "provincia": r[2]} for r in rows]
