"""Consultas para catálogos auxiliares (salas, cepas, bodegas, etc.)."""

from __future__ import annotations


def get_salas_query() -> Tuple[str, tuple]:
    """Retorna (sql, params) para GET /salas."""
    sql = "SELECT id_sala, calle, numero, dia_cierre, codigo_postal FROM sala_venta ORDER BY id_sala"
    return sql, tuple()


def get_cepas_query() -> Tuple[str, tuple]:
    """Retorna (sql, params) para GET /cepas."""
    sql = "SELECT id_cepa, nombre, tipo FROM cepa ORDER BY nombre"
    return sql, tuple()


def get_bodegas_query() -> Tuple[str, tuple]:
    """Retorna (sql, params) para GET /bodegas."""
    sql = "SELECT cuit, razon_social, domicilio FROM bodega ORDER BY razon_social"
    return sql, tuple()


def get_maridajes_query() -> Tuple[str, tuple]:
    """Retorna (sql, params) para GET /maridajes."""
    sql = "SELECT id_maridaje, nombre, temperatura_servicio FROM maridaje ORDER BY nombre"
    return sql, tuple()


def get_transportistas_query() -> Tuple[str, tuple]:
    """Retorna (sql, params) para GET /transportistas."""
    sql = "SELECT cod_transportista, razon_social, cuit FROM transportista ORDER BY razon_social"
    return sql, tuple()


def get_localidades_query() -> Tuple[str, tuple]:
    """Retorna (sql, params) para GET /localidades."""
    sql = "SELECT codigo_postal, nombre, provincia FROM localidad ORDER BY nombre"
    return sql, tuple()