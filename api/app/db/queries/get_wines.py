"""Consulta: GET /vinos - Catálogo con filtros y paginación."""

from __future__ import annotations

from typing import List, Tuple, Optional


def get_wines_query(
    tipo: Optional[str] = None,
    id_cepa: Optional[int] = None,
    cuit_bodega: Optional[str] = None,
    anada: Optional[int] = None,
    nombre: Optional[str] = None,
    page: int = 1,
    page_size: int = 20,
) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para listar vinos con filtros opcionales y paginación.
    
    Validaciones en el controlador:
    - page >= 1, page_size >= 1 y page_size <= 100
    - ORDER BY determinístico: cod_vino con desempate
    """
    if page < 1:
        page = 1
    if page_size < 1 or page_size > 100:
        page_size = 20

    # Build WHERE conditions dynamically
    conditions: List[str] = []
    params: List = []

    # 1️⃣ Filtro por tipo de vino (sargable, usa el ENUM de la base)
    if tipo is not None:
        conditions.append("v.tipo = %s")
        params.append(tipo)

    # 2️⃣ Filtro por cepa: usar EXISTS sobre la composición (vino_cepa)
    # IMPORTANTE: NO usar JOIN directo que duplicaría vinos con >1 cepa
    if id_cepa is not None:
        conditions.append(
            "EXISTS (SELECT 1 FROM vino_cepa vc WHERE vc.cod_vino = v.cod_vino AND vc.id_cepa = %s)"
        )
        params.append(id_cepa)

    # 3️⃣ Filtro por bodega (cuit)
    if cuit_bodega is not None:
        conditions.append("v.cuit_bodega = %s")
        params.append(cuit_bodega)

    # 4️⃣ Filtro por añada
    if anada is not None:
        conditions.append("v.anada = %s")
        params.append(anada)

    # 5️⃣ Búsqueda parcial por nombre (ILIKE - sargable si se usa al principio)
    if nombre is not None:
        conditions.append("v.nombre ILIKE %s")
        params.append(f"%{nombre}%")

    where_clause = " AND ".join(conditions) if conditions else "1=1"

    # OFFSET cálculo: (page - 1) * page_size
    offset = (page - 1) * page_size

    sql = f"""
        SELECT
            v.cod_vino,
            v.nombre,
            v.tipo,
            v.anada,
            v.volumen_ml,
            v.graduacion,
            v.precio,
            b.razon_social AS cuit_bodega_razon_social
        FROM vino v
        JOIN bodega b ON v.cuit_bodega = b.cuit
        WHERE {where_clause}
        ORDER BY v.cod_vino, v.nombre  -- ORDER BY determinístico con desempate
        LIMIT %s OFFSET %s
    """
    params.extend([page_size, offset])

    return sql, tuple(params)


def get_wines_count_query(
    tipo: Optional[str] = None,
    id_cepa: Optional[int] = None,
    cuit_bodega: Optional[str] = None,
    anada: Optional[int] = None,
    nombre: Optional[str] = None,
) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para COUNT(*) con los mismos filtros.
    """
    conditions: List[str] = []
    params: List = []

    if tipo is not None:
        conditions.append("v.tipo = %s")
        params.append(tipo)

    if id_cepa is not None:
        conditions.append(
            "EXISTS (SELECT 1 FROM vino_cepa vc WHERE vc.cod_vino = v.cod_vino AND vc.id_cepa = %s)"
        )
        params.append(id_cepa)

    if cuit_bodega is not None:
        conditions.append("v.cuit_bodega = %s")
        params.append(cuit_bodega)

    if anada is not None:
        conditions.append("v.anada = %s")
        params.append(anada)

    if nombre is not None:
        conditions.append("v.nombre ILIKE %s")
        params.append(f"%{nombre}%")

    where_clause = " AND ".join(conditions) if conditions else "1=1"

    sql = f"""
        SELECT COUNT(*)
        FROM vino v
        JOIN bodega b ON v.cuit_bodega = b.cuit
        WHERE {where_clause}
    """
    return sql, tuple(params)
