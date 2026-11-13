"""Routers para el recurso Comprobantes.

Endpoints:
- GET /comprobantes/{nro} - Comprobante con renglones
"""

from __future__ import annotations

from typing import Optional

import psycopg

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from api.app.db.queries.get_comprobante import (
    get_comprobante_cabecera_query,
    get_comprobante_renglones_query,
)
from api.app.config import Settings, get_settings


router = APIRouter(tags=["Comprobantes"])


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


@router.get("/{nro_comprobante}", tags=["Comprobantes"])
def detalle_comprobante(
    nro_comprobante: int,
    conn: psycopg.Connection = Depends(get_db_conn),
) -> dict:
    """Obtener un comprobante con sus renglones."""
    # 1. Obtener cabecera
    cabecera_sql, cabecera_params = get_comprobante_cabecera_query(nro_comprobante=nro_comprobante)

    # 2. Obtener renglones
    renglones_sql, renglones_params = get_comprobante_renglones_query(nro_comprobante=nro_comprobante)

    with conn.cursor() as cur:
        # Ejecutar cabecera
        cur.execute(cabecera_sql, cabecera_params)
        cabecera_row = cur.fetchone()
        if cabecera_row is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Comprobante con nro={nro_comprobante} no encontrado",
            )

        (nro, fecha, id_cliente, id_sala, subtotal, descuento, total,
         cliente_apellido, cliente_nombre, tipo_doc, nro_doc,
         calle, sala_numero) = cabecera_row

        # Ejecutar renglones
        cur.execute(renglones_sql, renglones_params)
        renglones_rows = cur.fetchall()

    # Formatear renglones
    renglones = []
    for rrow in renglones_rows:
        (cod_vino, cantidad, precio_unitario, descuento_pct, renglo_subtotal,
         vino_nombre, vino_tipo) = rrow
        renglones.append(
            {
                "cod_vino": cod_vino,
                "cantidad": cantidad,
                "precio_unitario": precio_unitario,
                "descuento_pct": descuento_pct,
                "subtotal": renglo_subtotal,
                "vino_nombre": vino_nombre,
                "vino_tipo": vino_tipo,
            }
        )

    return {
        "nro_comprobante": nro,
        "fecha": fecha,
        "id_cliente": id_cliente,
        "id_sala": id_sala,
        "subtotal": subtotal,
        "descuento": descuento,
        "total": total,
        "cliente": {"apellido_razon_social": cliente_apellido, "nombre": cliente_nombre},
        "tipo_documento": tipo_doc,
        "nro_documento": nro_doc,
        "sala": {"calle": calle, "numero": sala_numero},
        "renglones": renglones,
    }
