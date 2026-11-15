"""Router del recurso Vinos (contrato §4.1).

Endpoints mínimos para esta tarea:
- POST /vinos   : alta de vino (dispara check ck_vino_precio -> RN-01/RN-15)
- DELETE /vinos/{cod} : baja de vino (dispara FK RESTRICT -> RN-14)

Delegan en app/db/queries/vinos.py. No hay SQL en este router.
"""

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
import psycopg

from app.db.pool import get_conn
from app.db.queries.vinos import crear_vino, eliminar_vino, listar_vinos
from app.schemas.modelos import VinoCreate

router = APIRouter(prefix="/vinos", tags=["Vinos"])


@router.post("", status_code=status.HTTP_201_CREATED)
def crear_vino_endpoint(
    datos: VinoCreate,
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Da de alta un vino con composición y maridajes.

    Los errores de base (23514 precio <= 0, 23505 duplicado, 23503 FK)
    se propagan al handler global de psycopg.Error.
    """
    payload = datos.model_dump()
    cod_vino = crear_vino(conn, payload)
    return {"cod_vino": cod_vino}


@router.get("")
def listar_vinos_endpoint(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    tipo: str | None = Query(default=None),
    id_cepa: int | None = Query(default=None),
    cuit_bodega: str | None = Query(default=None),
    anada: int | None = Query(default=None),
    nombre: str | None = Query(default=None),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Listado paginado de vinos con filtros opcionales.

    Delega la consulta en app/db/queries/vinos.py: no hay SQL en este router.
    """
    items, total = listar_vinos(
        conn,
        page=page,
        page_size=page_size,
        tipo=tipo,
        id_cepa=id_cepa,
        cuit_bodega=cuit_bodega,
        anada=anada,
        nombre=nombre,
    )
    return {"items": items, "page": page, "page_size": page_size, "total": total}


@router.delete("/{cod_vino}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_vino_endpoint(
    cod_vino: int = Path(..., gt=0),
    conn: psycopg.Connection = Depends(get_conn),
) -> None:
    """Elimina un vino.

    Si el vino tiene movimientos o stock (RN-14), la base lanza
    ForeignKeyViolation (23503) que el handler traduce a 409.
    """
    filas = eliminar_vino(conn, cod_vino)
    if filas == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Vino {cod_vino} no encontrado",
        )
