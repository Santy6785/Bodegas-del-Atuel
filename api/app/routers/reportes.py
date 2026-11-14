"""Router del recurso Reportes (consignas S1, S6, S7 y S8).

Endpoints de solo lectura:
- GET /reportes/top-vinos            : S1, ranking de vinos mas vendidos
- GET /reportes/vinos-sin-stock      : S6, vinos sin stock (opcionalmente en una sala)
- GET /reportes/transportista-activo : S7, transportista con mayor actividad del ultimo mes
- GET /reportes/ventas-por-sala      : S8, monto facturado por sala

Delegan en app/db/queries/reportes.py. No hay SQL en este router.
"""

from datetime import date
from typing import Literal

import psycopg
from fastapi import APIRouter, Depends, HTTPException, Query

from app.db.pool import get_conn
from app.db.queries.reportes import (
    top_vinos,
    transportista_activo,
    ventas_por_sala,
    vinos_sin_stock,
)

router = APIRouter(prefix="/reportes", tags=["Reportes"])


def _o_422(funcion, *args, **kwargs):
    """Ejecuta una consulta y traduce ValueError (validaciones) a HTTP 422.

    Las funciones de queries/reportes.py validan fechas, rangos y periodos
    lanzando ValueError. El handler global solo cubre psycopg.Error, asi que
    sin esta traduccion el cliente recibiria un 500.
    """
    try:
        return funcion(*args, **kwargs)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get("/top-vinos")
def top_vinos_endpoint(
    limite: int = Query(default=10, ge=1, le=100),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """S1: vinos mas vendidos por cantidad de botellas (tope de 100)."""
    items = _o_422(top_vinos, conn, limite)
    return {"items": items, "limite": limite}


@router.get("/vinos-sin-stock")
def vinos_sin_stock_endpoint(
    id_sala: int | None = Query(default=None, gt=0),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """S6: vinos sin stock.

    Con id_sala: vinos sin stock en esa sala pero con stock en el deposito.
    Sin id_sala: vinos sin stock en toda la empresa.
    """
    items = _o_422(vinos_sin_stock, conn, id_sala=id_sala)
    return {"items": items}


@router.get("/transportista-activo")
def transportista_activo_endpoint(
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """S7: transportista(s) con mayor cantidad de ingresos en el ultimo mes."""
    items = _o_422(transportista_activo, conn)
    return {"items": items}


@router.get("/ventas-por-sala")
def ventas_por_sala_endpoint(
    periodo: Literal["ultimo_trimestre"] | None = Query(default=None),
    fecha_desde: date | None = Query(default=None),
    fecha_hasta: date | None = Query(default=None),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """S8: monto facturado por sala, con filtro opcional de periodo o fechas."""
    items = _o_422(
        ventas_por_sala,
        conn,
        periodo=periodo,
        fecha_desde=fecha_desde,
        fecha_hasta=fecha_hasta,
    )
    return {"items": items}
