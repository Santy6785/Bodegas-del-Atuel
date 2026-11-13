"""Consultas de acceso a datos para el recurso Clientes.

Gestiona la jerarquía de clientes (supertipo cliente y subtipos cliente_distribuidor,
cliente_exportador con permiso_exportacion). Los porcentajes de descuento no se
envían ni se recalculan en Python: se leen de fn_descuento_cliente(id_cliente).
"""

import psycopg

from ._reglas import (
    rechazar_campos_calculados,
    validar_fecha,
    validar_nombre_cliente,
    validar_rango_paginacion,
)


def listar_clientes(
    conn: psycopg.Connection,
    *,
    page: int = 1,
    page_size: int = 20,
    tipo_cliente: str | None = None,
    q: str | None = None,
) -> tuple[list[dict], int]:
    """Listado paginado de clientes, con búsqueda opcional por texto o documento.

    Parámetro q:
        - Si es solo dígitos (posible documento), filtra por prefijo de nro_documento.
        - Si no, busca por apellido_razon_social o nombre (ILIKE, contiene).
        Los caracteres % _ \\ del usuario se escapan para que sean literales.

    Tipo de operación: Lectura. Transacción: No requerida.
    Objeto de base: Tabla cliente y función fn_descuento_cliente.
    """
    validar_rango_paginacion(page, page_size)

    condiciones: list[str] = []
    params: list[object] = []

    if tipo_cliente is not None:
        condiciones.append("c.tipo_cliente = %s")
        params.append(tipo_cliente)

    if q is not None and q.strip():
        termino = q.strip()
        if termino.isdigit():
            # Prefijo de documento: "3012" encuentra 30123456, 30123457...
            condiciones.append("c.nro_documento LIKE %s ESCAPE '\\'")
            params.append(_escapar_like(termino) + "%")
        else:
            condiciones.append(
                "(c.apellido_razon_social ILIKE %s ESCAPE '\\' "
                " OR c.nombre ILIKE %s ESCAPE '\\')"
            )
            patron = "%" + _escapar_like(termino) + "%"
            params.extend([patron, patron])

    where_sql = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""
    offset = (page - 1) * page_size

    query = f"""
        SELECT c.id_cliente, c.apellido_razon_social, c.nombre,
               c.tipo_documento, c.nro_documento, c.direccion,
               c.codigo_postal, c.fecha_alta, c.tipo_cliente,
               fn_descuento_cliente(c.id_cliente) AS descuento_pct,
               count(*) OVER() AS total
          FROM cliente c
         {where_sql}
         ORDER BY c.apellido_razon_social ASC, c.id_cliente ASC
         LIMIT %s OFFSET %s
    """
    # ... resto igual (rows, total, count de página vacía)

    with conn.cursor() as cur:
        cur.execute(query, params + [page_size, offset])
        rows = cur.fetchall()

        if rows:
            total = int(rows[0]["total"])
            items = [{k: v for k, v in r.items() if k != "total"} for r in rows]
            return items, total

        count_query = f"SELECT COUNT(*) AS total FROM cliente c {where_sql}"
        cur.execute(count_query, params)
        count_row = cur.fetchone()
        total_real = int(count_row["total"]) if count_row else 0
        return [], total_real

def _escapar_like(texto: str) -> str:
    """Escapa los metacaracteres de LIKE para tratarlos como texto literal."""
    return texto.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

def obtener_cliente(conn: psycopg.Connection, id_cliente: int) -> dict | None:
    """Obtiene el detalle completo de un cliente incluyendo datos de su subtipo y permisos.

    El descuento_pct es 10.00, 20.00, 30.00 o 35.00 según el tipo y la cantidad de permisos, determinado por fn_descuento_cliente.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla cliente LEFT JOIN cliente_distribuidor, cliente_exportador,
                    permiso_exportacion y fn_descuento_cliente.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        id_cliente: Identificador único del cliente.

    Devuelve:
        Diccionario con datos del cliente y su bloque de subtipo, o None si no existe.
    """
    query = """
        SELECT c.id_cliente, c.apellido_razon_social, c.nombre,
               c.tipo_documento, c.nro_documento, c.direccion,
               c.codigo_postal, c.fecha_alta, c.tipo_cliente,
               fn_descuento_cliente(c.id_cliente) AS descuento_pct,
               cd.zona_cobertura, cd.nro_habilitacion,
               ce.pais_destino
          FROM cliente c
          LEFT JOIN cliente_distribuidor cd ON cd.id_cliente = c.id_cliente
          LEFT JOIN cliente_exportador ce ON ce.id_cliente = c.id_cliente
         WHERE c.id_cliente = %s
    """
    with conn.cursor() as cur:
        cur.execute(query, (id_cliente,))
        row = cur.fetchone()
        if not row:
            return None

        resultado = dict(row)
        tipo = resultado["tipo_cliente"]

        if tipo == "distribuidor" and resultado["zona_cobertura"] is not None:
            resultado["distribuidor"] = {
                "zona_cobertura": resultado["zona_cobertura"],
                "nro_habilitacion": resultado["nro_habilitacion"],
            }
        elif tipo == "exportador" and resultado["pais_destino"] is not None:
            permisos = obtener_permisos_exportacion(conn, id_cliente)
            resultado["exportador"] = {
                "pais_destino": resultado["pais_destino"],
                "permisos": permisos,
            }

        return resultado


def obtener_permisos_exportacion(conn: psycopg.Connection, id_cliente: int) -> list[dict]:
    """Obtiene los permisos de exportación vigentes de un cliente exportador.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla permiso_exportacion.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        id_cliente: Identificador del exportador.

    Devuelve:
        Lista de diccionarios con: codigo, fecha_emision, fecha_vencimiento.
    """
    query = """
        SELECT codigo, fecha_emision, fecha_vencimiento
          FROM permiso_exportacion
         WHERE id_cliente = %s
         ORDER BY codigo ASC
    """
    with conn.cursor() as cur:
        cur.execute(query, (id_cliente,))
        return cur.fetchall()


def crear_cliente(conn: psycopg.Connection, datos: dict) -> int:
    """Registra un nuevo cliente con su subtipo correspondiente en una sola transacción.

    El descuento_pct (10.00, 20.00, 30.00 o 35.00) lo determina fn_descuento_cliente
    según el tipo y la cantidad de permisos de exportación.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tablas cliente, cliente_distribuidor, cliente_exportador,
                    permiso_exportacion. Triggers ctg_cliente_* (coherencia de subtipos).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        datos: Diccionario con datos de cliente y bloques opcionales 'distribuidor' o 'exportador'.
               Nota: 'fecha_alta' nunca se envía, se completa por DEFAULT CURRENT_DATE.

    Devuelve:
        id_cliente (int): Identificador generado del nuevo cliente.

    Errores posibles:
        ValueError: Si faltan campos obligatorios, tipo_cliente inválido o bloques incoherentes.
        psycopg.errors.UniqueViolation (23505): Documento (tipo + nro) o nro_habilitacion repetido.
        psycopg.errors.ForeignKeyViolation (23503): Código postal inexistente.
        psycopg.errors.CheckViolation (23514): Vencimiento <= emisión en permisos (RN-07).
        psycopg.errors.RaiseException (P0001): Incoherencia entre tipo_cliente y subtipo (validado al COMMIT).
    """
    # --- Validaciones previas a la transacción ---
    rechazar_campos_calculados(datos, "crear_cliente")

    if isinstance(datos.get("distribuidor"), dict):
        rechazar_campos_calculados(datos["distribuidor"], "crear_cliente.bloque distribuidor")
    if isinstance(datos.get("exportador"), dict):
        rechazar_campos_calculados(datos["exportador"], "crear_cliente.bloque exportador")

    campos_obligatorios = (
        "apellido_razon_social",
        "tipo_documento",
        "nro_documento",
        "direccion",
        "codigo_postal",
        "tipo_cliente",
    )
    for campo in campos_obligatorios:
        if campo not in datos or datos[campo] in (None, ""):
            raise ValueError(f"Falta el campo obligatorio: {campo}")

    tipo_cliente = datos["tipo_cliente"]
    tipos_validos = {"socio", "distribuidor", "exportador"}
    if tipo_cliente not in tipos_validos:
        raise ValueError(
            f"tipo_cliente '{tipo_cliente}' no es válido. Valores admitidos: "
            f"{sorted(tipos_validos)}"
        )

    dist = datos.get("distribuidor")
    exp = datos.get("exportador")

    if tipo_cliente == "socio":
        if dist is not None or exp is not None:
            raise ValueError("Un cliente socio no debe venir con bloques 'distribuidor' ni 'exportador'")

    elif tipo_cliente == "distribuidor":
        if exp is not None:
            raise ValueError("Un cliente distribuidor no debe venir con bloque 'exportador'")
        if not isinstance(dist, dict):
            raise ValueError("Falta el bloque obligatorio 'distribuidor' para tipo_cliente distribuidor")
        zona = dist.get("zona_cobertura")
        nro_hab = dist.get("nro_habilitacion")
        if not zona or not nro_hab:
            raise ValueError("El bloque 'distribuidor' requiere zona_cobertura y nro_habilitacion no vacíos")

    elif tipo_cliente == "exportador":
        if dist is not None:
            raise ValueError("Un cliente exportador no debe venir con bloque 'distribuidor'")
        if not isinstance(exp, dict):
            raise ValueError("Falta el bloque obligatorio 'exportador' para tipo_cliente exportador")
        pais = exp.get("pais_destino")
        if not pais:
            raise ValueError("El bloque 'exportador' requiere pais_destino no vacío")
        permisos = exp.get("permisos", [])
        if permisos is None:
            permisos = []
        if not isinstance(permisos, list):
            raise ValueError("El campo 'permisos' del bloque exportador debe ser una lista")
        for p in permisos:
            if not isinstance(p, dict):
                raise ValueError("Cada permiso debe ser un diccionario")
            for campo_permiso in ("codigo", "fecha_emision", "fecha_vencimiento"):
                if campo_permiso not in p:
                    raise ValueError(f"Cada permiso requiere el campo {campo_permiso}")
            validar_fecha(p["fecha_emision"], f"permisos[{p.get('codigo','?')}]#fecha_emision")
            validar_fecha(p["fecha_vencimiento"], f"permisos[{p.get('codigo','?')}]#fecha_vencimiento")

    # Validación de nombre según tipo de documento (regla de formato de la DAL).
    validar_nombre_cliente(datos["tipo_documento"], datos.get("nombre"))

    with conn.transaction():
        with conn.cursor() as cur:
            insert_cliente_sql = """
                INSERT INTO cliente (
                    apellido_razon_social, nombre, tipo_documento,
                    nro_documento, direccion, codigo_postal, tipo_cliente
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id_cliente
            """
            cur.execute(
                insert_cliente_sql,
                (
                    datos["apellido_razon_social"],
                    datos.get("nombre"),
                    datos["tipo_documento"],
                    datos["nro_documento"],
                    datos["direccion"],
                    datos["codigo_postal"],
                    tipo_cliente,
                ),
            )
            row = cur.fetchone()
            id_cliente = int(row["id_cliente"])

            if tipo_cliente == "distribuidor":
                dist = datos.get("distribuidor", {})
                insert_dist_sql = """
                    INSERT INTO cliente_distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
                    VALUES (%s, %s, %s)
                """
                cur.execute(
                    insert_dist_sql,
                    (id_cliente, dist.get("zona_cobertura"), dist.get("nro_habilitacion")),
                )

            elif tipo_cliente == "exportador":
                exp = datos.get("exportador", {})
                insert_exp_sql = """
                    INSERT INTO cliente_exportador (id_cliente, pais_destino)
                    VALUES (%s, %s)
                """
                cur.execute(insert_exp_sql, (id_cliente, exp.get("pais_destino")))

                permisos = exp.get("permisos", [])
                if permisos:
                    insert_permiso_sql = """
                        INSERT INTO permiso_exportacion (id_cliente, codigo, fecha_emision, fecha_vencimiento)
                        VALUES (%s, %s, %s, %s)
                    """
                    permiso_params = [
                        (id_cliente, p["codigo"], p["fecha_emision"], p["fecha_vencimiento"])
                        for p in permisos
                    ]
                    cur.executemany(insert_permiso_sql, permiso_params)

            return id_cliente


def actualizar_cliente(conn: psycopg.Connection, id_cliente: int, datos: dict) -> int:
    """Actualiza los datos de un cliente y su subtipo correspondiente.

    El tipo de cliente no es modificable. El descuento_pct (10.00, 20.00, 30.00 o 35.00)
    lo determina fn_descuento_cliente según el tipo y la cantidad de permisos.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tablas cliente, cliente_distribuidor, cliente_exportador, permiso_exportacion.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        id_cliente: Identificador del cliente.
        datos: Diccionario con campos a actualizar. El campo tipo_cliente no es modificable.

    Devuelve:
        int: Cantidad de clientes modificados (1 si actualizó, 0 si no existe).

    Errores posibles:
        ValueError: Si el tipo de cliente cambia, o los bloques no coinciden con el tipo actual.
        psycopg.errors.UniqueViolation (23505): Conflicto de unicidad de documento o habilitación.
        psycopg.errors.CheckViolation (23514): Validación de fechas en permisos (RN-07).
        psycopg.errors.RaiseException (P0001): Subtipo incompatible con el tipo actual.
    """
    rechazar_campos_calculados(datos, "actualizar_cliente")

    if isinstance(datos.get("distribuidor"), dict):
        rechazar_campos_calculados(
            datos["distribuidor"], "actualizar_cliente.bloque distribuidor"
        )
    if isinstance(datos.get("exportador"), dict):
        rechazar_campos_calculados(
            datos["exportador"], "actualizar_cliente.bloque exportador"
        )

    dist = datos.get("distribuidor")
    exp = datos.get("exportador")

    # Validación de nombre según tipo de documento (regla de formato de la DAL),
    # solo cuando se proporciona tipo_documento en la actualización parcial.
    if "tipo_documento" in datos:
        validar_nombre_cliente(datos["tipo_documento"], datos.get("nombre"))

    with conn.transaction():
        with conn.cursor() as cur:
            # Bloquear la fila para evitar cambios concurrentes de tipo
            cur.execute(
                "SELECT tipo_cliente FROM cliente WHERE id_cliente = %s FOR UPDATE",
                (id_cliente,),
            )
            row_tipo = cur.fetchone()
            if not row_tipo:
                return 0
            tipo_actual = row_tipo["tipo_cliente"]

            # El tipo_cliente no puede modificarse
            if "tipo_cliente" in datos and datos["tipo_cliente"] != tipo_actual:
                raise ValueError("el tipo de cliente no puede modificarse")

            # Validar que los bloques enviados correspondan al tipo actual
            if tipo_actual == "socio":
                if dist is not None or exp is not None:
                    raise ValueError(
                        "Un cliente socio no debe venir con bloques 'distribuidor' ni 'exportador'"
                    )

            elif tipo_actual == "distribuidor":
                if exp is not None:
                    raise ValueError(
                        "Un cliente distribuidor no debe venir con bloque 'exportador'"
                    )
                if dist is not None:
                    if not isinstance(dist, dict):
                        raise ValueError("El bloque 'distribuidor' debe ser un diccionario")
                    zona = dist.get("zona_cobertura")
                    nro_hab = dist.get("nro_habilitacion")
                    if not zona or not nro_hab:
                        raise ValueError(
                            "El bloque 'distribuidor' requiere zona_cobertura y nro_habilitacion no vacíos"
                        )

            elif tipo_actual == "exportador":
                if dist is not None:
                    raise ValueError(
                        "Un cliente exportador no debe venir con bloque 'distribuidor'"
                    )
                if not isinstance(exp, dict):
                    raise ValueError("El bloque 'exportador' debe ser un diccionario")
                pais = exp.get("pais_destino")
                if not pais:
                    raise ValueError(
                        "El bloque 'exportador' requiere pais_destino no vacío"
                    )
                if "permisos" in exp:
                    permisos = exp["permisos"]
                    if permisos is not None and not isinstance(permisos, list):
                        raise ValueError(
                            "El campo 'permisos' del bloque exportador debe ser una lista"
                        )
                    if permisos:
                        for p in permisos:
                            if not isinstance(p, dict):
                                raise ValueError("Cada permiso debe ser un diccionario")
                            for campo_permiso in ("codigo", "fecha_emision", "fecha_vencimiento"):
                                if campo_permiso not in p:
                                    raise ValueError(
                                        f"Cada permiso requiere el campo {campo_permiso}"
                                    )
                            validar_fecha(
                                p["fecha_emision"],
                                f"permisos[{p.get('codigo','?')}]#fecha_emision",
                            )
                            validar_fecha(
                                p["fecha_vencimiento"],
                                f"permisos[{p.get('codigo','?')}]#fecha_vencimiento",
                            )

            # UPDATE del supertipo
            update_sql = """
                UPDATE cliente
                   SET apellido_razon_social = %s,
                       nombre = %s,
                       tipo_documento = %s,
                       nro_documento = %s,
                       direccion = %s,
                       codigo_postal = %s
                 WHERE id_cliente = %s
            """
            cur.execute(
                update_sql,
                (
                    datos["apellido_razon_social"],
                    datos.get("nombre"),
                    datos["tipo_documento"],
                    datos["nro_documento"],
                    datos["direccion"],
                    datos["codigo_postal"],
                    id_cliente,
                ),
            )
            if cur.rowcount == 0:
                return 0

            # UPDATE del subtipo según el tipo actual
            if tipo_actual == "distribuidor" and dist is not None:
                cur.execute(
                    """
                    UPDATE cliente_distribuidor
                       SET zona_cobertura = %s,
                           nro_habilitacion = %s
                     WHERE id_cliente = %s
                    """,
                    (dist.get("zona_cobertura"), dist.get("nro_habilitacion"), id_cliente),
                )

            elif tipo_actual == "exportador" and exp is not None:
                cur.execute(
                    """
                    UPDATE cliente_exportador
                       SET pais_destino = %s
                     WHERE id_cliente = %s
                    """,
                    (exp.get("pais_destino"), id_cliente),
                )

                if "permisos" in exp:
                    cur.execute(
                        "DELETE FROM permiso_exportacion WHERE id_cliente = %s",
                        (id_cliente,),
                    )
                    permisos = exp["permisos"]
                    if permisos:
                        insert_permiso_sql = """
                            INSERT INTO permiso_exportacion (
                                id_cliente, codigo, fecha_emision, fecha_vencimiento
                            )
                            VALUES (%s, %s, %s, %s)
                        """
                        permiso_params = [
                            (id_cliente, p["codigo"], p["fecha_emision"], p["fecha_vencimiento"])
                            for p in permisos
                        ]
                        cur.executemany(insert_permiso_sql, permiso_params)

            return 1


def eliminar_cliente(conn: psycopg.Connection, id_cliente: int) -> int:
    """Elimina un cliente y sus subtipos/permisos asociados en cascada.

    Tipo de operación: Escritura.
    Transacción: Sí (explícita).
    Objeto de base: Tabla cliente (CASCADE en subtipos y permisos;
                    RESTRICT en comprobante para impedir borrado con ventas, RN-14).

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        id_cliente: Identificador del cliente a eliminar.

    Devuelve:
        int: Cantidad de clientes eliminados (1 si existía, 0 si no existía).

    Errores posibles:
        psycopg.errors.ForeignKeyViolation (23503): El cliente tiene comprobantes emitidos (RN-14).
    """
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("DELETE FROM cliente WHERE id_cliente = %s", (id_cliente,))
            return cur.rowcount
