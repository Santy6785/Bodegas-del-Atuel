"""Router del recurso Comprobantes (venta) (contrato §4.3).

Endpoints mínimos para esta tarea:
- POST /comprobantes : venta completa en una transacción.

Delega en app/db/queries/comprobantes.py. No hay SQL en este router.
"""

from fastapi import APIRouter, Depends, status
import psycopg

from app.db.pool import get_conn
from app.db.queries.comprobantes import (
    crear_comprobante,
    obtener_comprobante,
)
from app.schemas.modelos import ComprobanteCreate

router = APIRouter(prefix="/comprobantes", tags=["Comprobantes"])


@router.post("", status_code=status.HTTP_201_CREATED)
def crear_comprobante_endpoint(
    datos: ComprobanteCreate,
    conn: psycopg.Connection = Depends(get_conn),
) -> dict:
    """Registra una venta completa.

    Delegar en crear_comprobante: invoca CALL sp_crear_comprobante y los
    triggers de la base aplican RN-09 (stock insuficiente -> P0001 -> 409),
    RN-06 (descuento) y RN-08 (subtotal/total).

    No se hace try/except: los errores de psycopg se propagan al
    handler global de errores.
    """
    nro = crear_comprobante(
        conn,
        id_cliente=datos.id_cliente,
        id_sala=datos.id_sala,
        cod_vinos=datos.cod_vinos,
        cantidades=datos.cantidades,
    )
    comprobante = obtener_comprobante(conn, nro)
    return comprobante or {"nro_comprobante": nro}
