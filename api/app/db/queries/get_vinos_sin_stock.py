"""Consulta: GET /reportes/vinos-sin-stock - Vinos con stock 0."""

from __future__ import annotations


def get_vinos_sin_stock_query(id_sala: int) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para el reporte vinos-sin-stock.
    
    Vinos que tienen stock 0 en la sala especificada (stock_salas = 0 o sin fila).
    También incluye el stock en el depósito central.
    Obligatoriamente requiere id_sala.
    """
    params = (id_sala,)

    sql = f"""
        SELECT
            v.cod_vino,
            v.nombre,
            v.tipo,
            COALESCE(SUM(sd.cantidad), 0) AS stock_deposito,
            COALESCE(SUM(sl.cantidad), 0) AS stock_salas
        FROM vino v
        LEFT JOIN stock_sala sl ON sl.cod_vino = v.cod_vino AND sl.id_sala = %s
        LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
        GROUP BY v.cod_vino, v.nombre, v.tipo
        HAVING COALESCE(SUM(sl.cantidad), 0) = 0
        ORDER BY v.nombre, v.cod_vino
    """
    return sql, params