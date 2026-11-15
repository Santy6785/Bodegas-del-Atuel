"""Router de catálogos de solo lectura (contrato §4.7).

- GET /cepas, /bodegas, /salas, /maridajes, /transportistas, /localidades

Sin paginación: devuelven un arreglo JSON completo.
Delegan en app/db/queries/catalogos.py. No hay SQL en este router.
"""

from fastapi import APIRouter, Depends
import psycopg

from app.db.pool import get_conn
from app.db.queries.catalogos import (
    listar_bodegas,
    listar_cepas,
    listar_localidades,
    listar_maridajes,
    listar_salas,
    listar_transportistas,
)

router = APIRouter(tags=["Catálogos"])


@router.get("/cepas")
def cepas_endpoint(conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    return listar_cepas(conn)


@router.get("/bodegas")
def bodegas_endpoint(conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    return listar_bodegas(conn)


@router.get("/salas")
def salas_endpoint(conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    return listar_salas(conn)


@router.get("/maridajes")
def maridajes_endpoint(conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    return listar_maridajes(conn)


@router.get("/transportistas")
def transportistas_endpoint(conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    return listar_transportistas(conn)


@router.get("/localidades")
def localidades_endpoint(conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    return listar_localidades(conn)