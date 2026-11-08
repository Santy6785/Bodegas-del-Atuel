"""Consultas de acceso a datos para el recurso Ingresos.

Gestiona el circuito logístico de recepción de vinos desde las bodegas productoras
hacia el depósito central: en_confeccion -> terminado -> procesado (RN-10, RN-12).
El impacto en stock_deposito se delega a sp_procesar_ingreso (RN-10).
"""

from datetime import date
import psycopg

from ._reglas import validar_fecha, validar_rango_paginacion


def listar_ingresos(
    conn: psycopg.Connection,
    *,
    page: int = 1,
    page_size: int = 20,
    estado: str | None = None,
) -> tuple[list[dict], int]:
    """Obtiene el listado paginado de ingresos filtrable por estado.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla ingreso.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        page: Número de página (1-based, mínimo 1).
        page_size: Tamaño de página (mínimo 1, máximo 100).
        estado: Filtro por estado ('en_confeccion', 'terminado', 'procesado').

    Devuelve:
        Tupla (items, total) con las cabeceras de ingreso.

    Errores posibles:
        ValueError: Si page o page_size están fuera de rango.
        psycopg.Error: Falla en la comunicación con la base de datos.
    """
    validar_rango_paginacion(page, page_size)

    condiciones: list[str] = []
    params: list[object] = []

    if estado is not None:
        condiciones.append("i.estado = %s")
        params.append(estado)

    where_sql = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""
    offset = (page - 1) * page_size

    query = f"""
        SELECT i.cod_ingreso, i.fecha, i.estado, i.cod_transportista, i.cuit_bodega,
               count(*) OVER() AS total
          FROM ingreso i
         {where_sql}
         ORDER BY i.cod_ingreso ASC
         LIMIT %s OFFSET %s
    """

    with conn.cursor() as cur:
        cur.execute(query, params + [page_size, offset])
        rows = cur.fetchall()

        if rows:
            total = int(rows[0]["total"])
            items = [{k: v for k, v in r.items() if k != "total"} for r in rows]
            return items, total

        count_query = f"SELECT COUNT(*) AS total FROM ingreso i {where_sql}"
        cur.execute(count_query, params)
        count_row = cur.fetchone()
        total_real = int(count_row["total"]) if count_row else 0
        return [], total_real


def obtener_ingreso(conn: psycopg.Connection, cod_ingreso: int) -> dict | None:
    """Obtiene la cabecera y lista de renglones de un remito de ingreso.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tablas ingreso y renglon_ingreso.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        cod_ingreso: Identificador del ingreso.

    Devuelve:
        Diccionario con la cabecera y lista 'renglones', o None si no existe.
    """
    query_cabecera = """
        SELECT cod_ingreso, fecha, estado, cod_transportista, cuit_bodega
          FROM ingreso
         WHERE cod_ingreso = %s
    """
    query_renglones = """
        SELECT cod_vino, cantidad
          FROM renglon_ingreso
         WHERE cod_ingreso = %s
         ORDER BY cod_vino ASC
    """
    with conn.cursor() as cur:
        cur.execute(query_cabecera, (cod_ingreso,))
        cabecera = cur.fetchone()
        if not cabecera:
            return None

        cur.execute(query_renglones, (cod_ingreso,))
        renglones = cur.fetchall()

        resultado = dict(cabecera)
        resultado["renglones"] = renglones
        return resultado


def crear_ingreso(
    conn: psycopg.Connection,
    fecha: date | str,
    cod_transportista: int,
    cuit_bodega: str,
) -> dict:
    """Registra un nuevo ingreso de mercadería en estado 'en_confeccion'.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tabla ingreso.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        fecha: Fecha de emisión del documento / arribo.
        cod_transportista: Identificador del transportista.
        cuit_bodega: CUIT de la bodega de origen.

    Devuelve:
        dict: Cabecera del ingreso creado (cod_ingreso, fecha, estado,
              cod_transportista, cuit_bodega).

    Errores posibles:
        psycopg.errors.ForeignKeyViolation (23503): Transportista o bodega inexistente.
    """
    with conn.transaction():
        with conn.cursor() as cur:
            fecha_normalizada = validar_fecha(fecha, "fecha")
            insert_sql = """
                INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
                VALUES (%s, %s, %s)
                RETURNING cod_ingreso, fecha, estado, cod_transportista, cuit_bodega
            """
            cur.execute(insert_sql, (fecha_normalizada, cod_transportista, cuit_bodega))
            row = cur.fetchone()
            return dict(row)


def agregar_renglon_ingreso(
    conn: psycopg.Connection, cod_ingreso: int, cod_vino: int, cantidad: int
) -> dict:
    """Agrega un vino y cantidad de botellas a un ingreso en confección.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tabla renglon_ingreso. Trigger trg_renglon_ingreso_confeccion (RN-12).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        cod_ingreso: Identificador del ingreso.
        cod_vino: Identificador del vino ingresado.
        cantidad: Cantidad de botellas (> 0).

    Devuelve:
        dict: Renglón creado (cod_ingreso, cod_vino, cantidad).

    Errores posibles:
        psycopg.errors.RaiseException (P0001): Ingreso no está en confección (RN-12).
        psycopg.errors.UniqueViolation (23505): Vino repetido en el mismo ingreso.
        psycopg.errors.ForeignKeyViolation (23503): Ingreso o vino inexistente.
        psycopg.errors.CheckViolation (23514): Cantidad <= 0.
    """
    with conn.transaction():
        with conn.cursor() as cur:
            insert_sql = """
                INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
                VALUES (%s, %s, %s)
                RETURNING cod_ingreso, cod_vino, cantidad
            """
            cur.execute(insert_sql, (cod_ingreso, cod_vino, cantidad))
            row = cur.fetchone()
            return dict(row)


def terminar_ingreso(conn: psycopg.Connection, cod_ingreso: int) -> dict | None:
    """Pasa el estado de un ingreso de 'en_confeccion' a 'terminado'.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tabla ingreso. Trigger trg_ingreso_estados (RN-10).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        cod_ingreso: Identificador del ingreso a terminar.

    Devuelve:
        dict | None: Diccionario con cod_ingreso y estado ('terminado'), o None si no existe.

    Errores posibles:
        psycopg.errors.RaiseException (P0001): Transición de estado inválida (RN-10).
        Nota: las validaciones de estado y stock (RN-09, RN-10, RN-11, RN-12) las
        hace la base de datos; la DAL no las replica.
    """
    with conn.transaction():
        with conn.cursor() as cur:
            update_sql = """
                UPDATE ingreso
                   SET estado = 'terminado'
                 WHERE cod_ingreso = %s
                RETURNING cod_ingreso, estado
            """
            cur.execute(update_sql, (cod_ingreso,))
            row = cur.fetchone()
            return dict(row) if row else None


def procesar_ingreso(conn: psycopg.Connection, cod_ingreso: int) -> None:
    """Procesa un ingreso terminado sumando las cantidades al depósito central.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Procedimiento sp_procesar_ingreso (RN-10).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        cod_ingreso: Identificador del ingreso a procesar.

    Devuelve:
        None.

    Errores posibles:
        psycopg.errors.RaiseException (P0001): Ingreso inexistente, no terminado o sin renglones.
        psycopg.errors.SerializationFailure (40001) / DeadlockDetected (40P01): Concurrencia.
        Nota: las validaciones de estado y stock (RN-09, RN-10, RN-11, RN-12) las
        hace la base de datos; la DAL no las replica.
    """
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("CALL sp_procesar_ingreso(%s::integer)", (cod_ingreso,))
