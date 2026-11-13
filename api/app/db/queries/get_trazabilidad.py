"""Consulta: GET /reportes/trazabilidad/{cod} - Lotes de uva de un vino."""

from __future__ import annotations


def get_trazabilidad_query(cod_vino: int) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para el reporte trazabilidad de un vino.

    Lotes de uva que componen el vino (tabla vino_lote con finca, parcela, cepa).
    """
    params = (cod_vino,)

    sql = f"""
        SELECT
            lt.id_lote,
            lt.nro_lote,
            lt.campania,
            lt.fecha_cosecha,
            lt.kilos,
            f.nombre AS finca_nombre,
            lt.id_finca,
            lt.nro_parcela,
            c.nombre AS cepa_nombre,
            ft.superficie_ha
        FROM vino v
        JOIN vino_lote vl ON v.cod_vino = vl.cod_vino
        JOIN lote_uva lt ON vl.id_lote = lt.id_lote
        LEFT JOIN finca f ON lt.id_finca = f.id_finca
        LEFT JOIN parcela p ON lt.id_finca = p.id_finca AND lt.nro_parcela = p.nro_parcela
        LEFT JOIN cepa c ON p.id_cepa = c.id_cepa
        LEFT JOIN finca ft ON lt.id_finca = ft.id_finca
        WHERE v.cod_vino = %s
        GROUP BY lt.id_lote, lt.nro_lote, lt.campania, lt.fecha_cosecha, lt.kilos,
                 f.nombre, lt.id_finca, lt.nro_parcela, c.nombre, ft.superficie_ha
        ORDER BY lt.nro_lote
    """
    return sql, params