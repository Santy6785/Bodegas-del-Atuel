"""Consulta: GET /comprobantes/{nro} - Comprobante con renglones."""

from __future__ import annotations


def get_comprobante_cabecera_query(nro_comprobante: int) -> Tuple[str, tuple]:
    """Retorna (sql, params) para la cabecera del comprobante."""
    params = (nro_comprobante,)
    sql = f"""
        SELECT
            c.nro_comprobante,
            c.fecha,
            c.id_cliente,
            c.id_sala,
            c.subtotal,
            c.descuento,
            c.total,
            cli.apellido_razon_social AS cliente_apellido,
            cli.nombre AS cliente_nombre,
            cli.tipo_documento,
            cli.nro_documento,
            s.calle,
            s.numero AS sala_numero
        FROM comprobante c
        JOIN cliente cli ON c.id_cliente = cli.id_cliente
        JOIN sala_venta s ON c.id_sala = s.id_sala
        WHERE c.nro_comprobante = %s
    """
    return sql, params


def get_comprobante_renglones_query(nro_comprobante: int) -> Tuple[str, tuple]:
    """Retorna (sql, params) para los renglones del comprobante."""
    params = (nro_comprobante,)
    sql = f"""
        SELECT
            rc.cod_vino,
            rc.cantidad,
            rc.precio_unitario,
            rc.descuento_pct,
            rc.subtotal AS renglo_subtotal,
            v.nombre AS vino_nombre,
            v.tipo AS vino_tipo
        FROM renglon_comprobante rc
        JOIN vino v ON rc.cod_vino = v.cod_vino
        WHERE rc.nro_comprobante = %s
        ORDER BY rc.cod_vino
    """
    return sql, params