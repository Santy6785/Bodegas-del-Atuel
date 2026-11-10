"""Consultas de acceso a datos para el recurso Transferencias.

Maneja el circuito de distribución desde el depósito central a las salas
de venta: en_confeccion -> terminado -> procesado (RN-11, RN-12).
El impacto de stock y validación de disponibilidad en el depósito se
realiza en el procedimiento sp_procesar_transferencia (RN-09, RN-11).
"""

import psycopg

from ._reglas import validar_rango_paginacion


def listar_transferencias(
    conn: psycopg.Connection,
    *,
    page: int = 1,
    page_size: int = 20,
    estado: str | None = None,
    id_sala: int | None = None,
) -> tuple[list[dict], int]:
    """Obtiene el listado paginado de transferencias filtrable por estado y sala.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla transferencia.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        page: Número de página (1-based, mínimo 1).
        page_size: Tamaño de página (mínimo 1, máximo 100).
        estado: Filtro por estado ('en_confeccion', 'terminado', 'procesado').
        id_sala: Filtro por sala de venta solicitante.

    Devuelve:
        Tupla (items, total) con las cabeceras de transferencia.

    Errores posibles:
        ValueError: Si page o page_size están fuera de rango.
        psycopg.Error: Falla en la comunicación con la base de datos.
    """
    validar_rango_paginacion(page, page_size)

    condiciones: list[str] = []
    params: list[object] = []

    if estado is not None:
        condiciones.append("t.estado = %s")
        params.append(estado)

    if id_sala is not None:
        condiciones.append("t.id_sala = %s")
        params.append(id_sala)

    where_sql = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""
    offset = (page - 1) * page_size

    query = f"""
        SELECT t.nro_transferencia, t.id_sala, t.fecha_confeccion, t.estado,
               count(*) OVER() AS total
          FROM transferencia t
         {where_sql}
         ORDER BY t.nro_transferencia ASC
         LIMIT %s OFFSET %s
    """

    with conn.cursor() as cur:
        cur.execute(query, params + [page_size, offset])
        rows = cur.fetchall()

        if rows:
            total = int(rows[0]["total"])
            items = [{k: v for k, v in r.items() if k != "total"} for r in rows]
            return items, total

        count_query = f"SELECT COUNT(*) AS total FROM transferencia t {where_sql}"
        cur.execute(count_query, params)
        count_row = cur.fetchone()
        total_real = int(count_row["total"]) if count_row else 0
        return [], total_real


def obtener_transferencia(conn: psycopg.Connection, nro: int) -> dict | None:
    """Obtiene la cabecera y lista de renglones de una transferencia.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tablas transferencia y renglon_transferencia.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        nro: Número identificador de la transferencia.

    Devuelve:
        Diccionario con cabecera y 'renglones', o None si no existe.
    """
    query_cabecera = """
        SELECT nro_transferencia, id_sala, fecha_confeccion, estado
          FROM transferencia
         WHERE nro_transferencia = %s
    """
    query_renglones = """
        SELECT cod_vino, cantidad
          FROM renglon_transferencia
         WHERE nro_transferencia = %s
         ORDER BY cod_vino ASC
    """
    with conn.cursor() as cur:
        cur.execute(query_cabecera, (nro,))
        cabecera = cur.fetchone()
        if not cabecera:
            return None

        cur.execute(query_renglones, (nro,))
        renglones = cur.fetchall()

        resultado = dict(cabecera)
        resultado["renglones"] = renglones
        return resultado


def crear_transferencia(conn: psycopg.Connection, id_sala: int) -> dict:
    """Inicia una nueva transferencia en estado 'en_confeccion' para la sala solicitante.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tabla transferencia.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        id_sala: Identificador de la sala de destino.

    Devuelve:
        dict: Cabecera de la transferencia creada (nro_transferencia, id_sala,
              fecha_confeccion, estado).

    Errores posibles:
        psycopg.errors.ForeignKeyViolation (23503): Sala inexistente.
    """
    with conn.transaction():
        with conn.cursor() as cur:
            insert_sql = """
                INSERT INTO transferencia (id_sala)
                VALUES (%s)
                RETURNING nro_transferencia, id_sala, fecha_confeccion, estado
            """
            cur.execute(insert_sql, (id_sala,))
            row = cur.fetchone()
            return dict(row)


def agregar_renglon_transferencia(
    conn: psycopg.Connection, nro: int, cod_vino: int, cantidad: int
) -> dict:
    """Agrega un vino y cantidad a una transferencia en confección.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tabla renglon_transferencia. Trigger trg_renglon_transferencia_confeccion (RN-12).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        nro: Número de la transferencia.
        cod_vino: Identificador del vino a transferir.
        cantidad: Cantidad de botellas a transferir (> 0).

    Devuelve:
        dict: Renglón creado (nro_transferencia, cod_vino, cantidad).

    Errores posibles:
        psycopg.errors.RaiseException (P0001): Si la transferencia no está en confección (RN-12).
        psycopg.errors.UniqueViolation (23505): Vino repetido en la transferencia.
        psycopg.errors.ForeignKeyViolation (23503): Vino o transferencia inexistente.
        psycopg.errors.CheckViolation (23514): Cantidad <= 0.
    """
    with conn.transaction():
        with conn.cursor() as cur:
            insert_sql = """
                INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
                VALUES (%s, %s, %s)
                RETURNING nro_transferencia, cod_vino, cantidad
            """
            cur.execute(insert_sql, (nro, cod_vino, cantidad))
            row = cur.fetchone()
            return dict(row)


def terminar_transferencia(conn: psycopg.Connection, nro: int) -> dict | None:
    """Pasa el estado de una transferencia de 'en_confeccion' a 'terminado'.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tabla transferencia. Trigger trg_transferencia_estados (RN-11).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        nro: Número de transferencia a terminar.

    Devuelve:
        dict | None: Diccionario con nro_transferencia y estado ('terminado'), o None si no existe.

    Errores posibles:
        psycopg.errors.RaiseException (P0001): Transición de estado inválida (RN-11).
        Nota: las validaciones de estado y stock (RN-09, RN-10, RN-11, RN-12) las
        hace la base de datos; la DAL no las replica.
    """
    with conn.transaction():
        with conn.cursor() as cur:
            update_sql = """
                UPDATE transferencia
                   SET estado = 'terminado'
                 WHERE nro_transferencia = %s
                RETURNING nro_transferencia, estado
            """
            cur.execute(update_sql, (nro,))
            row = cur.fetchone()
            return dict(row) if row else None


def procesar_transferencia(conn: psycopg.Connection, nro: int) -> None:
    """Procesa una transferencia terminada impactando el stock del depósito y sala.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Procedimiento sp_procesar_transferencia (RN-09, RN-11).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        nro: Número de la transferencia a procesar.

    Devuelve:
        None.

    Errores posibles:
        psycopg.errors.RaiseException (P0001): Transferencia inexistente, no terminada,
            sin renglones o con stock insuficiente en el depósito central (RN-09, RN-11).
        psycopg.errors.SerializationFailure (40001) / DeadlockDetected (40P01): Concurrencia.
        Nota: las validaciones de estado y stock (RN-09, RN-10, RN-11, RN-12) las
        hace la base de datos; la DAL no las replica.
    """
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("CALL sp_procesar_transferencia(%s::integer)", (nro,))
