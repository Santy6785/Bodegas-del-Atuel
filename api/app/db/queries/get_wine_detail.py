"""Consulta: GET /vinos/{cod} - Ficha del vino con composición y maridajes."""

from __future__ import annotations
from typing import Tuple


def get_wine_detail_query(cod_vino: int) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para obtener la ficha completa de un vino.

    Las 5 secciones son queries independientes para evitar problemas de GROUP BY
    con JOINs múltiples y asegurar resultados correctos.
    """
    params = (cod_vino,)

    # 1. Datos básicos del vino + bodega
    sql1 = """
        SELECT
            v.cod_vino,
            v.nombre,
            v.tipo,
            v.anada,
            v.volumen_ml,
            v.graduacion,
            v.precio,
            b.cuit,
            b.razon_social
        FROM vino v
        JOIN bodega b ON v.cuit_bodega = b.cuit
        WHERE v.cod_vino = %s
    """
    # 2. Composición: cepas que componen el vino
    sql2 = """
        SELECT
            vc.id_cepa,
            c.nombre,
            c.tipo,
            vc.porcentaje
        FROM vino_cepa vc
        JOIN cepa c ON vc.id_cepa = c.id_cepa
        WHERE vc.cod_vino = %s
    """
    # 3. Maridajes
    sql3 = """
        SELECT
            mar.nombre,
            mar.temperatura_servicio
        FROM vino_maridaje m
        JOIN maridaje mar ON m.id_maridaje = mar.id_maridaje
        WHERE m.cod_vino = %s
    """
    # 4. Stock en depósito
    sql4 = """
        SELECT COALESCE(SUM(sd.cantidad), 0)
        FROM stock_deposito sd
        WHERE sd.cod_vino = %s
    """
    # 5. Stock en salas (total en todas salas)
    sql5 = """
        SELECT COALESCE(SUM(sl.cantidad), 0)
        FROM stock_sala sl
        WHERE sl.cod_vino = %s
    """

    # Retornar los 5 SQLs como una tupla de (sql, params) multiples
    # El controlador decidirá cuál ejecutar o los ejecutará todos
    return (sql1, sql2, sql3, sql4, sql5), params


def get_wine_comp_query(cod_vino: int) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para obtener las cepas que componen un vino
    con su porcentaje de composición.
    """
    sql = """
        SELECT
            vc.id_cepa,
            c.nombre,
            c.tipo,
            vc.porcentaje
        FROM vino_cepa vc
        JOIN cepa c ON vc.id_cepa = c.id_cepa
        WHERE vc.cod_vino = %s
    """
    return sql, (cod_vino,)


def get_wine_maridaje_query(cod_vino: int) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para obtener los maridajes de un vino
    con nombre y temperatura de servicio.
    """
    sql = """
        SELECT
            m.id_maridaje,
            mar.nombre,
            mar.temperatura_servicio
        FROM vino_maridaje m
        JOIN maridaje mar ON m.id_maridaje = mar.id_maridaje
        WHERE m.cod_vino = %s
    """
    return sql, (cod_vino,)


def get_wine_stock_deposito_query(cod_vino: int) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para obtener el stock del vino en el depósito central.
    """
    sql = """
        SELECT COALESCE(SUM(sd.cantidad), 0)
        FROM stock_deposito sd
        WHERE sd.cod_vino = %s
    """
    return sql, (cod_vino,)


def get_wine_stock_sala_query(cod_vino: int) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para obtener el stock del vino por sala.
    """
    sql = """
        SELECT COALESCE(SUM(sl.cantidad), 0)
        FROM stock_sala sl
        WHERE sl.cod_vino = %s
    """
    return sql, (cod_vino,)
