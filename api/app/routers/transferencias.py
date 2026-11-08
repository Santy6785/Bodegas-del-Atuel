"""Router del recurso Transferencias (contrato §4.4).

Endpoints mínimos para esta tarea:
- POST /transferencias                         : alta (en_confeccion)
- POST /transferencias/{nro}/renglones         : agregar renglón (dispara RN-12)
- POST /transferencias/{nro}/terminar          : en_confeccion -> terminado (dispara RN-11)
- POST /transferencias/{nro}/procesar          : verifica stock depósito y pasa a procesado (dispara RN-09, RN-11)

Delegan en app/db/queries/transferencias.py. No hay SQL en este router.
"""

from fastapi import APIRouter, Depends, HTTPException, Path, status
import psycopg

from app.db.pool import get_conn
from app.db.queries.transferencias import (
    agregar_renglon_transferencia,
    crear_transferencia,
    obtener_transferencia,
    procesar_transferencia,
    terminar_transferencia,
)
from app.schemas.modelos import (
    RenglonTransferenciaCreate,
    TransferenciaCreate,
)

router = APIRouter(prefix="/transferencias", tags=["Transferencias"])


@router.post("", status_code=status.HTTP_201_CREATED)
def crear_transferencia_endpoint(
    datos: TransferenciaCreate,
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Crea una transferencia en estado 'en_confeccion'."""
    return crear_transferencia(conn, id_sala=datos.id_sala)


@router.post("/{nro}/renglones", status_code=status.HTTP_201_CREATED)
def agregar_renglon_transferencia_endpoint(
    nro: int = Path(..., gt=0),
    datos: RenglonTransferenciaCreate = ...,
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Agrega un vino y cantidad a una transferencia en confección.

    Si la transferencia no está en confección, la base lanza P0001 (RN-12).
    """
    return agregar_renglon_transferencia(
        conn, nro=nro, cod_vino=datos.cod_vino, cantidad=datos.cantidad
    )


@router.post("/{nro}/terminar", status_code=status.HTTP_200_OK)
def terminar_transferencia_endpoint(
    nro: int = Path(..., gt=0),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Pasa la transferencia de 'en_confeccion' a 'terminado'.

    Si la transición es inválida, la base lanza P0001 (RN-11).
    """
    resultado = terminar_transferencia(conn, nro=nro)
    if resultado is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transferencia {nro} no encontrada",
        )
    return resultado


@router.post("/{nro}/procesar", status_code=status.HTTP_200_OK)
def procesar_transferencia_endpoint(
    nro: int = Path(..., gt=0),
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Procesa una transferencia terminada.

    Verifica stock del depósito (RN-09) y valida estado (RN-11).
    Los errores de la base se propagan al handler global.
    """
    procesar_transferencia(conn, nro=nro)
    resultado = obtener_transferencia(conn, nro)
    return resultado or {"nro_transferencia": nro}
