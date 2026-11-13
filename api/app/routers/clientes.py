"""Routers para el recurso Clientes.

Endpoints:
- GET /clientes - Listado paginado
- GET /clientes/{id} - Detalle con subtipo
"""

from __future__ import annotations

from typing import Optional

import psycopg

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from api.app.db.queries.get_clients import get_clients_query, get_clients_count_query
from api.app.config import Settings, get_settings


router = APIRouter(tags=["Clientes"])


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


@router.get("/", tags=["Clientes"])
def listar_clientes(
    tipo_cliente: Optional[str] = None,
    page: int = 1,
    page_size: int = 20,
    conn: psycopg.Connection = Depends(get_db_conn),
):
    """Listar clientes con paginación y filtro opcional por tipo."""
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

    # 1. Obtener query SQL y parámetros
    sql, params = get_clients_query(
        tipo_cliente=tipo_cliente,
        page=page,
        page_size=page_size,
    )

    # 2. Ejecutar conteo total CON MISMOS filtros
    count_sql, count_params = get_clients_count_query(tipo_cliente=tipo_cliente)

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
        (id_cliente, apellido_razon_social, nombre, tipo_documento,
         nro_documento, direccion, codigo_postal, tipo_cliente_row,
         descuento_pct) = row
        items.append(
            {
                "id_cliente": id_cliente,
                "apellido_razon_social": apellido_razon_social,
                "nombre": nombre,
                "tipo_documento": tipo_documento,
                "nro_documento": nro_documento,
                "direccion": direccion,
                "codigo_postal": codigo_postal,
                "tipo_cliente": tipo_cliente_row,
                "descuento_pct": descuento_pct,
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


@router.get("/{id_cliente}", tags=["Clientes"])
def detalle_cliente(
    id_cliente: int,
    conn: psycopg.Connection = Depends(get_db_conn),
) -> dict:
    """Obtener detalle de un cliente por su ID, incluyendo subtipo."""
    # Consultar cliente principal
    sql_cliente = """
        SELECT
            c.id_cliente,
            c.apellido_razon_social,
            c.nombre,
            c.tipo_documento,
            c.nro_documento,
            c.direccion,
            c.codigo_postal,
            c.tipo_cliente,
            fn_descuento_cliente(c.id_cliente) AS descuento_pct
        FROM cliente c
        WHERE c.id_cliente = %s
    """
    # Consultar subtipo según tipo_cliente
    sql_subtipo = """
        SELECT
            id_cliente,
            -- Para distribuidor
            dzona_cobertura,
            znro_habilitacion,
            -- Para exportador
            pais_destino,
            -- Permisos de exportador
            (SELECT json_agg(json_build_object('codigo', codigo, 'fecha_emision', fecha_emision, 'fecha_vencimiento', fecha_vencimiento))
             FROM permiso_exportacion pe WHERE pe.id_cliente = c.id_cliente) AS permisos
        FROM (
            -- Distribuidor
            SELECT id_cliente, zona_cobertura, nro_habilitacion, NULL::VARCHAR AS pais_destino, NULL::JSON AS permisos
            FROM cliente_distribuidor WHERE id_cliente = %s
            UNION ALL
            -- Exportador
            SELECT id_cliente, NULL::VARCHAR AS zona_cobertura, NULL::VARCHAR AS nro_habilitacion, pais_destino, NULL::JSON AS permisos
            FROM cliente_exportador WHERE id_cliente = %s
        ) subtipo
        WHERE id_cliente = %s
    """

    with conn.cursor() as cur:
        # Obtener datos del cliente
        cur.execute(sql_cliente, (id_cliente,))
        row = cur.fetchone()
        if row is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Cliente con id = {id_cliente} no encontrado",
            )

        (id_cliente, apellido_razon_social, nombre, tipo_documento,
         nro_documento, direccion, codigo_postal, tipo_cliente_row,
         descuento_pct) = row

        # Obtener subtipo
        cur.execute(sql_subtipo, (id_cliente, id_cliente, id_cliente))
        subtipo_row = cur.fetchone()

    # Construir respuesta
    result = {
        "id_cliente": id_cliente,
        "apellido_razon_social": apellido_razon_social,
        "nombre": nombre,
        "tipo_documento": tipo_documento,
        "nro_documento": nro_documento,
        "direccion": direccion,
        "codigo_postal": codigo_postal,
        "tipo_cliente": tipo_cliente_row,
        "descuento_pct": descuento_pct,
    }

    # Agregar campos según subtipo
    if subtipo_row:
        (sub_id, zona_cobertura, nro_habilitacion, pais_destino, permisos_json) = subtipo_row
        if tipo_cliente_row == "distribuidor":
            result["distribuidor"] = {
                "zona_cobertura": zona_cobertura,
                "nro_habilitacion": nro_habilitacion,
            }
        elif tipo_cliente_row == "exportador":
            result["exportador"] = {
                "pais_destino": pais_destino,
                "permisos": permisos_json or [],
            }

    return result
