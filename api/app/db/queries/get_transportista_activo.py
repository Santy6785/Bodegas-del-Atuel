"""Consulta: GET /reportes/transportista-activo - Transportista con más ingresos."""

from __future__ import annotations


def get_transportista_activo_query() -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para el reporte transportista-activo.
    
    Transportista con más ingresos registrados. Puede haber empate.
    """
    params: List = []

    sql = f"""
        SELECT
            t.cod_transportista,
            t.razon_social,
            COUNT(i.cod_ingreso) AS cantidad_ingresos
        FROM transportista t
        LEFT JOIN ingreso i ON t.cod_transportista = i.cod_transportista
        GROUP BY t.cod_transportista, t.razon_social
        ORDER BY cantidad_ingresos DESC
    """
    return sql, tuple(params)