"""Router del recurso Clientes (contrato §4.x).

Endpoints:
- GET /clientes : listado paginado con filtro opcional por tipo_cliente.

Delega en app/db/queries/clientes.py: no hay SQL en este router.
"""

from typing import Literal

from fastapi import APIRouter, Depends, Query
import psycopg

from app.db.pool import get_conn
from app.db.queries.clientes import listar_clientes

router = APIRouter(prefix="/clientes", tags=["Clientes"])


@router.get("")
def listar_clientes_endpoint(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    tipo_cliente: Literal["socio", "distribuidor", "exportador"] | None = Query(
        default=None
    ),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Listado paginado de clientes con filtro opcional por tipo de cliente.

    Delega la consulta en app/db/queries/clientes.py: no hay SQL en este router.
    """
    items, total = listar_clientes(
        conn,
        page=page,
        page_size=page_size,
        tipo_cliente=tipo_cliente,
    )
    return {"items": items, "page": page, "page_size": page_size, "total": total}
