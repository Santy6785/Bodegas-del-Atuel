"""Consultas de acceso a datos para el recurso Vinos.

Maneja el catálogo, detalle con stock consolidado (vw_stock_total_vino),
composición varietal (vino_cepa), maridajes (vino_maridaje) y operaciones
transaccionales de alta, modificación y baja.
"""

from decimal import Decimal
import psycopg

from ._reglas import rechazar_campos_calculados, validar_rango_paginacion


def listar_vinos(
    conn: psycopg.Connection,
    *,
    page: int = 1,
    page_size: int = 20,
    tipo: str | None = None,
    id_cepa: int | None = None,
    cuit_bodega: str | None = None,
    anada: int | None = None,
    nombre: str | None = None,
) -> tuple[list[dict], int]:
    """Obtiene el listado paginado de vinos aplicando filtros opcionales.

    Los errores de formato de los parámetros (código SQL 22P02, invalid text
    representation) los propaga la base de datos.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla vino con JOIN a bodega y EXISTS sobre vino_cepa.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        page: Número de página (1-based, mínimo 1).
        page_size: Tamaño de página (mínimo 1, máximo 100).
        tipo: Filtro por tipo de vino (tinto, blanco, rosado, espumante).
        id_cepa: Filtro por vino que contenga la cepa indicada.
        cuit_bodega: Filtro por CUIT de la bodega productora.
        anada: Filtro por año de cosecha (añada).
        nombre: Búsqueda parcial por nombre comercial (coincidencia insensible a mayúsculas).

    Devuelve:
        Tupla (items, total) donde items es una lista de diccionarios con los vinos
        y total es la cantidad total de registros que coinciden con los filtros.

    Errores posibles:
        ValueError: Si page o page_size están fuera de rango.
        psycopg.Error: Falla en la comunicación con la base de datos o formato inválido (22P02).
    """
    validar_rango_paginacion(page, page_size)

    condiciones: list[str] = []
    params: list[object] = []

    if tipo is not None:
        condiciones.append("v.tipo = %s")
        params.append(tipo)

    if id_cepa is not None:
        condiciones.append(
            "EXISTS (SELECT 1 FROM vino_cepa vc WHERE vc.cod_vino = v.cod_vino AND vc.id_cepa = %s)"
        )
        params.append(id_cepa)

    if cuit_bodega is not None:
        condiciones.append("v.cuit_bodega = %s")
        params.append(cuit_bodega)

    if anada is not None:
        condiciones.append("v.anada = %s")
        params.append(anada)

    if nombre is not None:
        nombre_escapado = nombre.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        condiciones.append("v.nombre ILIKE ('%%' || %s || '%%') ESCAPE '\\'")
        params.append(nombre_escapado)

    where_sql = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""

    offset = (page - 1) * page_size
    query = f"""
        SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
               v.graduacion, v.precio, v.cuit_bodega,
               b.razon_social AS bodega_razon_social,
               count(*) OVER() AS total
          FROM vino v
          JOIN bodega b ON b.cuit = v.cuit_bodega
         {where_sql}
         ORDER BY v.cod_vino ASC
         LIMIT %s OFFSET %s
    """

    with conn.cursor() as cur:
        cur.execute(query, params + [page_size, offset])
        rows = cur.fetchall()

        if rows:
            total = int(rows[0]["total"])
            items = [{k: v for k, v in r.items() if k != "total"} for r in rows]
            return items, total

        # Si la página pedida no devolvió filas, calculamos el total real con COUNT
        count_query = f"""
            SELECT COUNT(*) AS total
              FROM vino v
              JOIN bodega b ON b.cuit = v.cuit_bodega
             {where_sql}
        """
        cur.execute(count_query, params)
        count_row = cur.fetchone()
        total_real = int(count_row["total"]) if count_row else 0
        return [], total_real


def obtener_vino(conn: psycopg.Connection, cod_vino: int) -> dict | None:
    """Obtiene la ficha técnica de un vino, su bodega y stock consolidado.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla vino JOIN bodega LEFT JOIN vw_stock_total_vino.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        cod_vino: Identificador único del vino.

    Devuelve:
        Diccionario con datos del vino, bodega y stock, o None si no existe.

    Errores posibles:
        psycopg.Error: Falla en la comunicación con la base de datos o formato inválido (22P02).
    """
    query = """
        SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
               v.graduacion, v.precio, v.cuit_bodega,
               b.razon_social AS bodega_razon_social,
               COALESCE(st.stock_deposito, 0)::BIGINT AS stock_deposito,
               COALESCE(st.stock_salas, 0)::BIGINT AS stock_salas,
               COALESCE(st.stock_total, 0)::BIGINT AS stock_total
          FROM vino v
          JOIN bodega b ON b.cuit = v.cuit_bodega
          LEFT JOIN vw_stock_total_vino st ON st.cod_vino = v.cod_vino
         WHERE v.cod_vino = %s
    """
    with conn.cursor() as cur:
        cur.execute(query, (cod_vino,))
        row = cur.fetchone()
        if not row:
            return None

        resultado = dict(row)
        resultado["bodega"] = {
            "cuit": resultado["cuit_bodega"],
            "razon_social": resultado["bodega_razon_social"],
        }
        resultado["stock"] = {
            "deposito": resultado["stock_deposito"],
            "salas": resultado["stock_salas"],
            "total": resultado["stock_total"],
        }
        return resultado


def obtener_composicion_vino(conn: psycopg.Connection, cod_vino: int) -> list[dict]:
    """Obtiene la composición varietal de un vino (cepas y porcentajes).

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla vino_cepa JOIN cepa.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        cod_vino: Identificador del vino.

    Devuelve:
        Lista de diccionarios con: id_cepa, nombre, tipo, porcentaje.
    """
    query = """
        SELECT vc.id_cepa, c.nombre, c.tipo, vc.porcentaje
          FROM vino_cepa vc
          JOIN cepa c ON c.id_cepa = vc.id_cepa
         WHERE vc.cod_vino = %s
         ORDER BY vc.id_cepa ASC
    """
    with conn.cursor() as cur:
        cur.execute(query, (cod_vino,))
        return cur.fetchall()


def obtener_maridajes_vino(conn: psycopg.Connection, cod_vino: int) -> list[dict]:
    """Obtiene los maridajes asociados a un vino.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla vino_maridaje JOIN maridaje.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        cod_vino: Identificador del vino.

    Devuelve:
        Lista de diccionarios con: id_maridaje, nombre, temperatura_servicio.
    """
    query = """
        SELECT m.id_maridaje, m.nombre, m.temperatura_servicio
          FROM vino_maridaje vm
          JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
         WHERE vm.cod_vino = %s
         ORDER BY m.id_maridaje ASC
    """
    with conn.cursor() as cur:
        cur.execute(query, (cod_vino,))
        return cur.fetchall()


def crear_vino(conn: psycopg.Connection, datos: dict) -> int:
    """Registra un nuevo vino con su composición varietal y maridajes en una transacción.

    Los precios y descuentos no se envían desde la API; se leen de la base.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tablas vino, vino_cepa, vino_maridaje. Trigger diferido ctg_vino_composicion.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        datos: Diccionario con campos del vino (nombre, tipo, anada, volumen_ml,
               graduacion, precio, cuit_bodega), lista 'composicion' de cepas
               ({'id_cepa', 'porcentaje'}) y lista opcional 'maridajes' (ids enteros).

    Devuelve:
        cod_vino (int): Clave primaria generada para el nuevo vino.

    Errores posibles:
        ValueError: Si el payload contiene campos calculados, maridajes que no son int,
            o composición con id_cepa/porcentaje faltantes.
        psycopg.errors.UniqueViolation (23505): Vino duplicado (nombre, anada, volumen_ml).
        psycopg.errors.CheckViolation (23514): Precio <= 0, graduación fuera de rango (RN-01, RN-15).
        psycopg.errors.ForeignKeyViolation (23503): Bodega o cepa inexistente.
        psycopg.errors.RaiseException (P0001): Composición no suma 100 % (RN-05 diferido al COMMIT).
    """
    rechazar_campos_calculados(datos, "crear_vino")

    composicion = datos.get("composicion", [])
    if composicion:
        for c in composicion:
            if not isinstance(c, dict):
                raise ValueError("Cada elemento de 'composicion' debe ser un diccionario")
            if "id_cepa" not in c or c["id_cepa"] is None:
                raise ValueError("Cada elemento de 'composicion' requiere id_cepa")
            if not isinstance(c["id_cepa"], int):
                raise ValueError("id_cepa debe ser un entero")
            if "porcentaje" not in c or c["porcentaje"] is None:
                raise ValueError("Cada elemento de 'composicion' requiere porcentaje")
            if not isinstance(c["porcentaje"], (Decimal, int, str)):
                raise ValueError("porcentaje debe ser un Decimal o string decimal")

    maridajes = datos.get("maridajes", [])
    if maridajes:
        if not isinstance(maridajes, list):
            raise ValueError("maridajes debe ser una lista de enteros")
        for m in maridajes:
            if not isinstance(m, int):
                raise ValueError("Cada elemento de 'maridajes' debe ser un entero")

    with conn.transaction():
        with conn.cursor() as cur:
            insert_vino_sql = """
                INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING cod_vino
            """
            cur.execute(
                insert_vino_sql,
                (
                    datos["nombre"],
                    datos["tipo"],
                    datos["anada"],
                    datos["volumen_ml"],
                    datos["graduacion"],
                    datos["precio"],
                    datos["cuit_bodega"],
                ),
            )
            row = cur.fetchone()
            cod_vino = int(row["cod_vino"])

            if composicion:
                insert_cepa_sql = """
                    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
                    VALUES (%s, %s, %s)
                """
                cepa_params = [
                    (cod_vino, c["id_cepa"], c["porcentaje"]) for c in composicion
                ]
                cur.executemany(insert_cepa_sql, cepa_params)

            if maridajes:
                insert_maridaje_sql = """
                    INSERT INTO vino_maridaje (cod_vino, id_maridaje)
                    VALUES (%s, %s)
                """
                maridaje_params = [(cod_vino, m) for m in maridajes]
                cur.executemany(insert_maridaje_sql, maridaje_params)

            return cod_vino


def actualizar_vino(conn: psycopg.Connection, cod_vino: int, datos: dict) -> int:
    """Actualiza los datos editables de un vino, reemplazando composición y maridajes.

    Los precios y descuentos no se envían desde la API; se leen de la base.
    La suma de la composición = 100 % no se valida en Python (RN-05 en la base).

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tablas vino, vino_cepa, vino_maridaje. Trigger trg_vino_auditoria (RN-13).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        cod_vino: Identificador del vino a modificar.
        datos: Diccionario con campos actualizados del vino, 'composicion' y 'maridajes'.

    Devuelve:
        int: Cantidad de filas afectadas en la tabla vino (1 si actualizó, 0 si no existe).

    Errores posibles:
        ValueError: Si el payload contiene campos calculados, maridajes que no son int,
            o composición con id_cepa/porcentaje faltantes.
        psycopg.errors.UniqueViolation (23505): Conflicto de unicidad con otro vino.
        psycopg.errors.CheckViolation (23514): Restricciones de precio o graduación violadas.
        psycopg.errors.RaiseException (P0001): Composición no suma 100 % (RN-05).
    """
    rechazar_campos_calculados(datos, "actualizar_vino")

    composicion = datos.get("composicion", [])
    if composicion:
        for c in composicion:
            if not isinstance(c, dict):
                raise ValueError("Cada elemento de 'composicion' debe ser un diccionario")
            if "id_cepa" not in c or c["id_cepa"] is None:
                raise ValueError("Cada elemento de 'composicion' requiere id_cepa")
            if not isinstance(c["id_cepa"], int):
                raise ValueError("id_cepa debe ser un entero")
            if "porcentaje" not in c or c["porcentaje"] is None:
                raise ValueError("Cada elemento de 'composicion' requiere porcentaje")
            if not isinstance(c["porcentaje"], (Decimal, int, str)):
                raise ValueError("porcentaje debe ser un Decimal o string decimal")

    maridajes = datos.get("maridajes", [])
    if maridajes:
        if not isinstance(maridajes, list):
            raise ValueError("maridajes debe ser una lista de enteros")
        for m in maridajes:
            if not isinstance(m, int):
                raise ValueError("Cada elemento de 'maridajes' debe ser un entero")

    with conn.transaction():
        with conn.cursor() as cur:
            update_sql = """
                UPDATE vino
                   SET nombre = %s,
                       tipo = %s,
                       anada = %s,
                       volumen_ml = %s,
                       graduacion = %s,
                       precio = %s,
                       cuit_bodega = %s
                 WHERE cod_vino = %s
            """
            cur.execute(
                update_sql,
                (
                    datos["nombre"],
                    datos["tipo"],
                    datos["anada"],
                    datos["volumen_ml"],
                    datos["graduacion"],
                    datos["precio"],
                    datos["cuit_bodega"],
                    cod_vino,
                ),
            )
            if cur.rowcount == 0:
                return 0

            # Reemplazar composición
            cur.execute("DELETE FROM vino_cepa WHERE cod_vino = %s", (cod_vino,))
            if composicion:
                insert_cepa_sql = """
                    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
                    VALUES (%s, %s, %s)
                """
                cepa_params = [
                    (cod_vino, c["id_cepa"], c["porcentaje"]) for c in composicion
                ]
                cur.executemany(insert_cepa_sql, cepa_params)

            # Reemplazar maridajes
            cur.execute("DELETE FROM vino_maridaje WHERE cod_vino = %s", (cod_vino,))
            if maridajes:
                insert_maridaje_sql = """
                    INSERT INTO vino_maridaje (cod_vino, id_maridaje)
                    VALUES (%s, %s)
                """
                maridaje_params = [(cod_vino, m) for m in maridajes]
                cur.executemany(insert_maridaje_sql, maridaje_params)

            return 1


def eliminar_vino(conn: psycopg.Connection, cod_vino: int) -> int:
    """Elimina un vino del catálogo.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tabla vino (ON DELETE CASCADE en vino_cepa, vino_maridaje, vino_lote;
                    ON DELETE RESTRICT en comprobante, ingreso, transferencia, stock, RN-14).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        cod_vino: Identificador del vino a eliminar.

    Devuelve:
        int: Cantidad de registros eliminados (1 si existía, 0 si no existía).

    Errores posibles:
        psycopg.errors.ForeignKeyViolation (23503): El vino posee movimientos históricos o stock (RN-14).
    """
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("DELETE FROM vino WHERE cod_vino = %s", (cod_vino,))
            return cur.rowcount
