"""Router del recurso Ingresos (contrato §4.5).

Endpoints:
- GET /ingresos                  : listado paginado con filtro por estado
- POST /ingresos                 : alta de ingreso (en_confeccion)
- GET /ingresos/{cod}            : detalle con cabecera y renglones
- POST /ingresos/{cod}/renglones : agregar renglón (dispara RN-12)
- POST /ingresos/{cod}/terminar  : en_confeccion -> terminado (dispara RN-10)
- POST /ingresos/{cod}/procesar  : procesa ingreso y suma al depósito (RN-10)

Delegan en app/db/queries/ingresos.py. No hay SQL en este router.
"""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Response, status
import psycopg

from app.db.pool import get_conn
from app.db.queries.ingresos import (
    agregar_renglon_ingreso,
    crear_ingreso,
    listar_ingresos,
    obtener_ingreso,
    procesar_ingreso,
    terminar_ingreso,
)
from app.schemas.modelos import (
    IngresoCreate,
    RenglonIngresoCreate,
)

router = APIRouter(prefix="/ingresos", tags=["Ingresos"])


@router.get("")
def listar_ingresos_endpoint(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    estado: Literal["en_confeccion", "terminado", "procesado"] | None = Query(default=None),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Listado paginado de ingresos filtrable por estado."""
    try:
        items, total = listar_ingresos(
            conn,
            page=page,
            page_size=page_size,
            estado=estado,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=422,
            detail=str(exc),
        ) from exc
    return {"items": items, "page": page, "page_size": page_size, "total": total}


@router.post("", status_code=status.HTTP_201_CREATED)
def crear_ingreso_endpoint(
    datos: IngresoCreate,
    response: Response,
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Registra un nuevo ingreso de mercadería en estado 'en_confeccion'."""
    try:
        resultado = crear_ingreso(
            conn,
            fecha=datos.fecha,
            cod_transportista=datos.cod_transportista,
            cuit_bodega=datos.cuit_bodega,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=422,
            detail=str(exc),
        ) from exc
    cod = resultado.get("cod_ingreso")
    if cod:
        response.headers["Location"] = f"/ingresos/{cod}"
    return resultado


@router.get("/{cod}")
def obtener_ingreso_endpoint(
    cod: int = Path(..., gt=0),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Detalle de un remito de ingreso con sus renglones."""
    ingreso = obtener_ingreso(conn, cod)
    if ingreso is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Ingreso {cod} no encontrado",
        )
    return ingreso


@router.post("/{cod}/renglones", status_code=status.HTTP_201_CREATED)
def agregar_renglon_ingreso_endpoint(
    cod: int = Path(..., gt=0),
    datos: RenglonIngresoCreate = ...,
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Agrega un vino y cantidad a un ingreso en confección.

    Si el ingreso no está en confección, la base lanza P0001 (RN-12).
    """
    return agregar_renglon_ingreso(
        conn,
        cod_ingreso=cod,
        cod_vino=datos.cod_vino,
        cantidad=datos.cantidad,
    )


@router.post("/{cod}/terminar", status_code=status.HTTP_200_OK)
def terminar_ingreso_endpoint(
    cod: int = Path(..., gt=0),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Pasa el estado de un ingreso de 'en_confeccion' a 'terminado'.

    Si la transición es inválida, la base lanza P0001 (RN-10).
    """
    resultado = terminar_ingreso(conn, cod_ingreso=cod)
    if resultado is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Ingreso {cod} no encontrado",
        )
    return resultado


@router.post("/{cod}/procesar", status_code=status.HTTP_200_OK)
def procesar_ingreso_endpoint(
    cod: int = Path(..., gt=0),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Procesa un ingreso terminado sumando las cantidades al depósito central.

    Valida estado (RN-10). Los errores de la base se propagan al handler global.
    """
    procesar_ingreso(conn, cod_ingreso=cod)
    resultado = obtener_ingreso(conn, cod)
    return resultado or {"cod_ingreso": cod, "estado": "procesado"}
