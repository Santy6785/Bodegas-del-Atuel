"""Consultas de acceso a datos para el recurso Comprobantes (Ventas).

La creación de comprobantes se delega exclusivamente al procedimiento
almacenado sp_crear_comprobante dentro de una transacción explícita.
Los precios, descuentos, subtotales, totales y descuento de stock
son calculados automáticamente por la base de datos (RN-06, RN-08, RN-09).
"""

import psycopg


def crear_comprobante(
    conn: psycopg.Connection,
    id_cliente: int,
    id_sala: int,
    cod_vinos: list[int],
    cantidades: list[int],
) -> int:
    """Registra una venta completa invocando el procedimiento sp_crear_comprobante.

    Precios, descuentos, subtotales, total y descuento de stock los calcula
    sp_crear_comprobante con sus triggers; la DAL no los envía ni los calcula.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Procedimiento sp_crear_comprobante (RN-06, RN-08, RN-09).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        id_cliente: Identificador del cliente comprador.
        id_sala: Identificador de la sala de venta emisora.
        cod_vinos: Lista de identificadores de vinos adquiridos.
        cantidades: Lista de cantidades de botellas por vino.

    Devuelve:
        int: Número de comprobante generado (p_nro_comprobante obtenido del INOUT).

    Errores posibles:
        ValueError: Si las listas están vacías o difieren en tamaño.
        psycopg.errors.RaiseException (P0001): Stock insuficiente en la sala (RN-09).
        psycopg.errors.UniqueViolation (23505): Vino repetido en los renglones.
        psycopg.errors.ForeignKeyViolation (23503): Cliente, sala o vino inexistente.
        psycopg.errors.CheckViolation (23514): Cantidad de botellas <= 0.
        psycopg.errors.UndefinedFunction (42883): Si sp_crear_comprobante no existe en la base.
    """
    if not cod_vinos or not cantidades:
        raise ValueError("Las listas de vinos y cantidades no pueden estar vacías")
    if len(cod_vinos) != len(cantidades):
        raise ValueError("Las listas de vinos y cantidades deben tener la misma longitud")

    with conn.transaction():
        with conn.cursor() as cur:
            call_sql = """
                CALL sp_crear_comprobante(%s, %s, %s::integer[], %s::integer[], %s::integer)
            """
            cur.execute(call_sql, (id_cliente, id_sala, cod_vinos, cantidades, None))
            row = cur.fetchone()
            if not row:
                raise RuntimeError("El procedimiento sp_crear_comprobante no devolvió fila de salida")

            # El parámetro INOUT se devuelve con su nombre (o como único valor en la fila)
            if "p_nro_comprobante" in row:
                return int(row["p_nro_comprobante"])
            return int(next(iter(row.values())))


def obtener_comprobante(conn: psycopg.Connection, nro_comprobante: int) -> dict | None:
    """Obtiene la cabecera y el detalle de renglones de un comprobante emitido.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tablas comprobante y renglon_comprobante.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        nro_comprobante: Número único del comprobante.

    Devuelve:
        Diccionario con la cabecera y la lista 'renglones', o None si no existe.
    """
    query_cabecera = """
        SELECT nro_comprobante, fecha, id_cliente, id_sala,
               subtotal, descuento, total
          FROM comprobante
         WHERE nro_comprobante = %s
    """
    query_renglones = """
        SELECT cod_vino, cantidad, precio_unitario, descuento_pct, subtotal
          FROM renglon_comprobante
         WHERE nro_comprobante = %s
         ORDER BY cod_vino ASC
    """
    with conn.cursor() as cur:
        cur.execute(query_cabecera, (nro_comprobante,))
        cabecera = cur.fetchone()
        if not cabecera:
            return None

        cur.execute(query_renglones, (nro_comprobante,))
        renglones = cur.fetchall()

        resultado = dict(cabecera)
        resultado["renglones"] = renglones
        return resultado
