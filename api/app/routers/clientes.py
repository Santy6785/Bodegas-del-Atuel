"""Router del recurso Clientes (contrato §4.2).

Endpoints:
- GET /clientes        : listado paginado con filtros opcionales.
- GET /clientes/{id}   : detalle de un cliente con su subtipo y permisos.
- POST /clientes       : alta de un nuevo cliente.
- PUT /clientes/{id}   : reemplazo completo de un cliente existente.
- DELETE /clientes/{id}: baja de un cliente.

Delega en app/db/queries/clientes.py: no hay SQL en este router.
"""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Response, status
import psycopg

from app.db.pool import get_conn
from app.db.queries.clientes import (
    actualizar_cliente,
    crear_cliente,
    eliminar_cliente,
    listar_clientes,
    obtener_cliente,
)
from app.schemas.modelos import ClienteCreate

router = APIRouter(prefix="/clientes", tags=["Clientes"])


@router.get("")
def listar_clientes_endpoint(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    tipo_cliente: Literal["socio", "distribuidor", "exportador"] | None = Query(default=None),
    q: str | None = Query(default=None, max_length=100),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Listado paginado de clientes con filtros opcionales por tipo y por texto/documento."""
    try:
        items, total = listar_clientes(
            conn,
            page=page,
            page_size=page_size,
            tipo_cliente=tipo_cliente,
            q=q,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=422,
            detail=str(exc),
        ) from exc
    return {"items": items, "page": page, "page_size": page_size, "total": total}


@router.post("", status_code=status.HTTP_201_CREATED)
def crear_cliente_endpoint(
    datos: ClienteCreate,
    response: Response,
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Alta de cliente con su subtipo y permisos en una sola transacción."""
    payload = datos.model_dump()
    try:
        id_cliente = crear_cliente(conn, payload)
    except ValueError as exc:
        raise HTTPException(
            status_code=422,
            detail=str(exc),
        ) from exc
    response.headers["Location"] = f"/clientes/{id_cliente}"
    cliente = obtener_cliente(conn, id_cliente)
    return cliente or {"id_cliente": id_cliente}


@router.get("/{id_cliente}")
def obtener_cliente_endpoint(
    id_cliente: int = Path(..., gt=0),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Detalle completo de un cliente con su subtipo y permisos."""
    cliente = obtener_cliente(conn, id_cliente)
    if cliente is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Cliente {id_cliente} no encontrado",
        )
    return cliente


@router.put("/{id_cliente}")
def actualizar_cliente_endpoint(
    id_cliente: int = Path(..., gt=0),
    datos: ClienteCreate = ...,
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Actualización completa de un cliente sin modificar su tipo."""
    payload = datos.model_dump()
    try:
        filas = actualizar_cliente(conn, id_cliente, payload)
    except ValueError as exc:
        raise HTTPException(
            status_code=422,
            detail=str(exc),
        ) from exc
    if filas == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Cliente {id_cliente} no encontrado",
        )
    cliente = obtener_cliente(conn, id_cliente)
    return cliente or {"id_cliente": id_cliente}


@router.delete("/{id_cliente}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_cliente_endpoint(
    id_cliente: int = Path(..., gt=0),
    conn: psycopg.Connection = Depends(get_conn),
) -> None:
    """Elimina un cliente y sus datos asociados en cascada."""
    filas = eliminar_cliente(conn, id_cliente)
    if filas == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Cliente {id_cliente} no encontrado",
        )
