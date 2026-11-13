"""Routers para el recurso Vinos.

Endpoints:
- GET /vinos - Catálogo con filtros y paginación
- GET /vinos/{cod} - Ficha del vino con composición y maridajes
"""

from __future__ import annotations

from typing import Optional, Tuple, List

import psycopg

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from api.app.db.queries.get_wines import get_wines_query, get_wines_count_query
from api.app.db.queries.get_wine_detail import (
    get_wine_detail_query,
    get_wine_comp_query,
    get_wine_maridaje_query,
    get_wine_stock_deposito_query,
    get_wine_stock_sala_query,
)
from api.app.config import Settings, get_settings


router = APIRouter(tags=["Vinos"])


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


@router.get("/", tags=["Vinos"])
def listar_vinos(
    tipo: Optional[str] = None,
    id_cepa: Optional[int] = None,
    cuit_bodega: Optional[str] = None,
    anada: Optional[int] = None,
    nombre: Optional[str] = None,
    page: int = 1,
    page_size: int = 20,
    conn: psycopg.Connection = Depends(get_db_conn),
):
    """Listar vinos con filtros opcionales y paginación."""
    # Validación de parámetros de paginación
    if page < 1:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Page debe ser >= 1",
        )
    if page_size < 1 or page_size > 100:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="page_size debe estar entre 1 y 100",
        )

    # 1. Obtener query SQL y parámetros de listado
    sql, params = get_wines_query(
        tipo=tipo,
        id_cepa=id_cepa,
        cuit_bodega=cuit_bodega,
        anada=anada,
        nombre=nombre,
        page=page,
        page_size=page_size,
    )

    # 2. Ejecutar conteo total CON MISMOS filtros
    count_sql, count_params = get_wines_count_query(
        tipo=tipo,
        id_cepa=id_cepa,
        cuit_bodega=cuit_bodega,
        anada=anada,
        nombre=nombre,
    )

    with conn.cursor() as cur:
        # Ejecutar COUNT
        cur.execute(count_sql, count_params)
        total = cur.fetchone()[0]

        # Ejecutar listado
        cur.execute(sql, params)
        rows = cur.fetchall()

    # Formato de respuesta conforme al contrato
    items = []
    for row in rows:
        (cod_vino, nombre, tipo_vino, anada, volumen_ml, graduacion, precio, cuit_bodega_razon_social) = row
        items.append(
            {
                "cod_vino": cod_vino,
                "nombre": nombre,
                "tipo": tipo_vino,
                "anada": anada,
                "volumen_ml": volumen_ml,
                "graduacion": graduacion,
                "precio": precio,
                "cuit_bodega_razon_social": cuit_bodega_razon_social,
            }
        )

    total_pages = (total + page_size - 1) // page_size if total > 0 else 0

    return {
        "items": items,
        "page": page,
        "page_size": page_size,
        "total": total,
        "totalPages": total_pages,
    }


@router.get("/{cod_vino}", tags=["Vinos"])
def detalle_vino(
    cod_vino: int,
    conn: psycopg.Connection = Depends(get_db_conn),
) -> dict:
    """Obtener ficha completa de un vino por su código."""
    with conn.cursor() as cur:
        # Datos básicos (query 1) - get_wine_detail_query retorna ((sql1..sql5), params)
        detail_tuple = get_wine_detail_query(cod_vino=cod_vino)
        sql1 = detail_tuple[0][0]  # Primer SQL de la tupla anidada
        params1 = detail_tuple[1]  # params
        cur.execute(sql1, params1)
        row1 = cur.fetchone()
        if row1 is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Vino con cod_vino={cod_vino} no encontrado",
            ) 

        (c_cod_vino, nombre, tipo_vino, anada, volumen_ml, graduacion, precio, cuit_bodega, razon_social) = row1

        # Composición (query 2)
        sql2, p2 = get_wine_comp_query(cod_vino=cod_vino)
        cur.execute(sql2, p2)
        comp_rows = cur.fetchall()
        composicion = [
            {"id_cepa": r[0], "nombre": r[1], "tipo": r[2], "porcentaje": r[3]}
            for r in comp_rows
        ]

        # Maridajes (query 3)
        sql3, p3 = get_wine_maridaje_query(cod_vino=cod_vino)
        cur.execute(sql3, p3)
        maridaje_rows = cur.fetchall()
        maridajes = [
            {"id_maridaje": r[0], "nombre": r[1], "temperatura_servicio": r[2]}
            for r in maridaje_rows
        ]

        # Stock depósito (query 4)
        sql4, p4 = get_wine_stock_deposito_query(cod_vino=cod_vino)
        cur.execute(sql4, p4)
        stock_deposito = cur.fetchone()[0]

        # Stock salas (query 5)
        sql5, p5 = get_wine_stock_sala_query(cod_vino=cod_vino)
        cur.execute(sql5, p5)
        stock_salas = cur.fetchone()[0]

    return {
        "cod_vino": c_cod_vino,
        "nombre": nombre,
        "tipo": tipo_vino,
        "anada": anada,
        "volumen_ml": volumen_ml,
        "graduacion": graduacion,
        "precio": precio,
        "bodega": {"cuit": cuit_bodega, "razon_social": razon_social},
        "composicion": composicion,
        "maridajes": maridajes,
        "stock": {"deposito": stock_deposito, "salas": stock_salas, "total": stock_deposito + stock_salas},
    }
