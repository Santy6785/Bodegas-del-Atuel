"""Consulta: GET /reportes/ventas-por-sala - Ventas agrupadas por sala y período."""

from __future__ import annotations


def get_ventas_por_sala_query(
    periodo: Optional[str] = None,
    fecha_desde: Optional[str] = None,
    fecha_hasta: Optional[str] = None,
    id_sala: Optional[int] = None,
) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para el reporte ventas-por-sala.
    
    Períodos relativos:
    - 'ultimo_trimestre': últimos 3 meses con CURRENT_DATE
    - 'ultimo_mes': último mes con CURRENT_DATE
    - 'ultimos_15_días': últimos 15 días con CURRENT_DATE
    
    Fechas absolutas con ISO YYYY-MM-DD.
    """
    conditions: List[str] = []
    params: List = []

    # Filtro de fechas - siempre usar CURRENT_DATE para períodos relativos
    # y nunca envolver la columna en una función (sargable)
    if fecha_desde is None and fecha_hasta is None and periodo is not None:
        # Períodos relativos usando CURRENT_DATE (sargable)
        if periodo == "ultimo_trimestre":
            conditions.append("c.fecha >= CURRENT_DATE - INTERVAL '3 months'")
            # No envolver c.fecha en función alguna
        elif periodo == "ultimo_mes":
            conditions.append("c.fecha >= CURRENT_DATE - INTERVAL '1 months'")
        elif periodo == "ultimos_15_dias":
            conditions.append("c.fecha >= CURRENT_DATE - INTERVAL '15 days'")
        else:
            # Período desconocido, sin filtro de fecha
            pass
    elif fecha_desde is not None and fecha_hasta is not None:
        # Fechas absolutas - sargable: columna >= valor y columna <= valor
        conditions.append("c.fecha >= %s")
        params.append(fecha_desde)
        conditions.append("c.fecha <= %s")
        params.append(fecha_hasta)
    # Si no hay ninguno, sin filtro de fecha (o se podría defaults a trimestre)

    # Filtro por id_sala opcional
    if id_sala is not None:
        conditions.append("c.id_sala = %s")
        params.append(id_sala)

    where_clause = " AND ".join(conditions) if conditions else "1=1"

    sql = f"""
        SELECT
            s.id_sala,
            s.calle,
            s.numero,
            COALESCE(SUM(rc.cantidad * v.precio), 0) AS monto_total
        FROM comprobante c
        JOIN renglon_comprobante rc ON c.nro_comprobante = rc.nro_comprobante
        JOIN vino v ON rc.cod_vino = v.cod_vino
        JOIN sala_venta s ON c.id_sala = s.id_sala
        WHERE {where_clause}
        GROUP BY s.id_sala, s.calle, s.numero
        ORDER BY monto_total DESC
    """
    return sql, tuple(params)