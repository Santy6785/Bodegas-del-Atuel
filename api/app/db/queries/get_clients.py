"""Consulta: GET /clientes - Listado paginado con filtro por tipo de cliente."""

from __future__ import annotations


def get_clients_query(
    tipo_cliente: Optional[str] = None,
    page: int = 1,
    page_size: int = 20,
) -> Tuple[str, tuple]:
    """
    Retorna (sql, params) para listar clientes con paginación y filtro opcional.
    
    El campo descuento_pct se calcula con fn_descuento_cliente(c.id_cliente)
    en la aplicación o se puede agregar como función de SQL.
    """
    if page < 1:
        page = 1
    if page_size < 1 or page_size > 100:
        page_size = 20

    offset = (page - 1) * page_size

    conditions: List[str] = []
    params: List = []

    if tipo_cliente is not None:
        conditions.append("c.tipo_cliente = %s")
        params.append(tipo_cliente)

    where_clause = " AND ".join(conditions) if conditions else "1=1"

    sql = f"""
        SELECT
            c.id_cliente,
            c.apellido_razon_social,
            c.nombre,
            c.tipo_documento,
            c.nro_documento,
            c.direccion,
            l.codigo_postal,
            c.tipo_cliente,
            fn_descuento_cliente(c.id_cliente) AS descuento_pct
        FROM cliente c
        LEFT JOIN localidad l ON c.codigo_postal = l.codigo_postal
        WHERE {where_clause}
        ORDER BY c.nombre, c.id_cliente
        LIMIT %s OFFSET %s
    """
    params.extend([page_size, offset])

    return sql, tuple(params)


def get_clients_count_query(
    tipo_cliente: Optional[str] = None,
) -> Tuple[str, tuple]:
    """Retorna (sql, params) para COUNT(*) de clientes."""
    conditions: List[str] = []
    params: List = []

    if tipo_cliente is not None:
        conditions.append("c.tipo_cliente = %s")
        params.append(tipo_cliente)

    where_clause = " AND ".join(conditions) if conditions else "1=1"

    sql = f"""
        SELECT COUNT(*)
        FROM cliente c
        WHERE {where_clause}
    """
    return sql, tuple(params)