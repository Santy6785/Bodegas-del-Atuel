"""Routers para los reportes.

Endpoints:
- GET /reportes/top-vinos
- GET /reportes/ventas-por-sala
- GET /reportes/vinos-sin-stock
- GET /reportes/transportista-activo
- GET /reportes/trazabilidad/{cod}
"""

from __future__ import annotations

from typing import Optional

import psycopg

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from api.app.db.queries.get_top_vinos import get_top_vinos_query
from api.app.db.queries.get_ventas_por_sala import get_ventas_por_sala_query
from api.app.db.queries.get_vinos_sin_stock import get_vinos_sin_stock_query
from api.app.db.queries.get_transportista_activo import get_transportista_activo_query
from api.app.db.queries.get_trazabilidad import get_trazabilidad_query
from api.app.config import Settings, get_settings


router = APIRouter(tags=["Reportes"])


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


@router.get("/top-vinos", tags=["Reportes"])
def top_vinos(
    limit: int = 10,
    conn: psycopg.Connection = Depends(get_db_conn),
) -> dict:
    """Reporte de vinos más vendidos."""
    if limit < 1 or limit > 100:
        limit = 10

    sql, params = get_top_vinos_query(limit=limit)

    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    items = []
    for i, row in enumerate(rows, start=1):
        (posicion, cod_vino, nombre, botellas_vendidas) = row
        items.append(
            {
                "posicion": posicion,
                "cod_vino": cod_vino,
                "nombre": nombre,
                "botellas_vendidas": botellas_vendidas,
            }
        )

    return {"items": items, "limit": limit}


@router.get("/ventas-por-sala", tags=["Reportes"])
def ventas_por_sala(
    periodo: Optional[str] = None,
    fecha_desde: Optional[str] = None,
    fecha_hasta: Optional[str] = None,
    id_sala: Optional[int] = None,
    conn: psycopg.Connection = Depends(get_db_conn),
) -> dict:
    """Reporte de ventas agrupadas por sala y período."""
    sql, params = get_ventas_por_sala_query(
        periodo=periodo,
        fecha_desde=fecha_desde,
        fecha_hasta=fecha_hasta,
        id_sala=id_sala,
    )

    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    items = []
    for row in rows:
        (id_sala_row, calle, numero, monto_total) = row
        items.append(
            {
                "id_sala": id_sala_row,
                "calle": calle,
                "numero": numero,
                "monto_total": monto_total,
            }
        )

    return {"items": items}


@router.get("/vinos-sin-stock", tags=["Reportes"])
def vinos_sin_stock(
    id_sala: int,
    conn: psycopg.Connection = Depends(get_db_conn),
) -> dict:
    """Reporte de vinos con stock 0."""
    sql, params = get_vinos_sin_stock_query(id_sala=id_sala)

    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    items = []
    for row in rows:
        (cod_vino, nombre, tipo, stock_deposito, stock_salas) = row
        items.append(
            {
                "cod_vino": cod_vino,
                "nombre": nombre,
                "tipo": tipo,
                "stock_deposito": stock_deposito,
                "stock_salas": stock_salas,
            }
        )

    return {"items": items}


@router.get("/transportista-activo", tags=["Reportes"])
def transportista_activo(
    conn: psycopg.Connection = Depends(get_db_conn),
) -> dict:
    """Reporte del transportista más activo."""
    sql, params = get_transportista_activo_query()

    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    items = []
    for row in rows:
        (cod_transportista, razon_social, cantidad_ingresos) = row
        items.append(
            {
                "cod_transportista": cod_transportista,
                "razon_social": razon_social,
                "cantidad_ingresos": cantidad_ingresos,
            }
        )

    return {"items": items}


@router.get("/trazabilidad/{cod_vino}", tags=["Reportes"])
def trazabilidad(
    cod_vino: int,
    conn: psycopg.Connection = Depends(get_db_conn),
) -> dict:
    """Lotes de uva que componen un vino."""
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM vino WHERE cod_vino = %s", (cod_vino,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Vino con cod_vino={cod_vino} no encontrado",
        )

    sql, params = get_trazabilidad_query(cod_vino=cod_vino)

    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    if not rows:
        return {"items": []}

    # El primer row tiene los datos del vino, los siguientes son los lotes
    # Agrupar por lote
    lotes = []
    for row in rows:
        (id_lote, nro_lote, campania, fecha_cosecha, kilos,
         finca_nombre, id_parcela, cepa_nombre, superficie_ha) = row
        lotes.append(
            {
                "id_lote": id_lote,
                "nro_lote": nro_lote,
                "campania": campania,
                "fecha_cosecha": fecha_cosecha,
                "kilos": kilos,
                "finca_nombre": finca_nombre,
                "id_parcela": id_parcela,
                "cepa_nombre": cepa_nombre,
                "superficie_ha": superficie_ha,
            }
        )

    return {"cod_vino": cod_vino, "lotes": lotes}
