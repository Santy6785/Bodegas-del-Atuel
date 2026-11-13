"""Consulta: GET /reportes/top-vinos - Ranking de vinos más vendidos."""

from __future__ import annotations


def get_top_vinos_query(
    limit: int = 10,
) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para el reporte top-vinos.
    
    Listado de vinos más vendores (por botellas) con su posición.
    Límite máximo de 100.
    """
    if limit < 1 or limit > 100:
        limit = 10

    params = (limit,)

    sql = f"""
        SELECT
            ROW_NUMBER() OVER (ORDER BY SUM(rc.cantidad) DESC) AS posicion,
            v.cod_vino,
            v.nombre,
            SUM(rc.cantidad) AS botellas_vendidas
        FROM renglon_comprobante rc
        JOIN comprobante c ON rc.nro_comprobante = c.nro_comprobante
        JOIN vino v ON rc.cod_vino = v.cod_vino
        GROUP BY v.cod_vino, v.nombre
        ORDER BY botellas_vendidas DESC
        LIMIT %s
    """
    return sql, params