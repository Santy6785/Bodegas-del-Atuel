"""Consultas para catálogos auxiliares del sistema Bodegas del Atuel.

Todos los catálogos son de solo lectura, no están paginados y ordenan
por nombre o clave de forma determinística.
"""

import psycopg


def listar_salas(conn: psycopg.Connection) -> list[dict]:
    """Obtiene el catálogo completo de salas de venta.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla sala_venta.

    Parámetros:
        conn: Conexión activa a PostgreSQL.

    Devuelve:
        Lista de diccionarios con: id_sala, calle, numero, dia_cierre, codigo_postal.

    Errores posibles:
        psycopg.Error: Falla en la comunicación con la base de datos.
    """
    query = """
        SELECT id_sala, calle, numero, dia_cierre, codigo_postal
          FROM sala_venta
         ORDER BY id_sala ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchall()


def listar_cepas(conn: psycopg.Connection) -> list[dict]:
    """Obtiene el catálogo completo de cepas de uva.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla cepa.

    Parámetros:
        conn: Conexión activa a PostgreSQL.

    Devuelve:
        Lista de diccionarios con: id_cepa, nombre, tipo.

    Errores posibles:
        psycopg.Error: Falla en la comunicación con la base de datos.
    """
    query = """
        SELECT id_cepa, nombre, tipo
          FROM cepa
         ORDER BY nombre ASC, id_cepa ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchall()


def listar_bodegas(conn: psycopg.Connection) -> list[dict]:
    """Obtiene el catálogo completo de bodegas registradas.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla bodega.

    Parámetros:
        conn: Conexión activa a PostgreSQL.

    Devuelve:
        Lista de diccionarios con: cuit, razon_social, domicilio.

    Errores posibles:
        psycopg.Error: Falla en la comunicación con la base de datos.
    """
    query = """
        SELECT cuit, razon_social, domicilio
          FROM bodega
         ORDER BY razon_social ASC, cuit ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchall()


def listar_maridajes(conn: psycopg.Connection) -> list[dict]:
    """Obtiene el catálogo completo de maridajes y sugerencias gastronómicas.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla maridaje.

    Parámetros:
        conn: Conexión activa a PostgreSQL.

    Devuelve:
        Lista de diccionarios con: id_maridaje, nombre, temperatura_servicio.

    Errores posibles:
        psycopg.Error: Falla en la comunicación con la base de datos.
    """
    query = """
        SELECT id_maridaje, nombre, temperatura_servicio
          FROM maridaje
         ORDER BY nombre ASC, id_maridaje ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchall()


def listar_transportistas(conn: psycopg.Connection) -> list[dict]:
    """Obtiene el catálogo completo de empresas transportistas.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla transportista.

    Parámetros:
        conn: Conexión activa a PostgreSQL.

    Devuelve:
        Lista de diccionarios con: cod_transportista, razon_social, cuit.

    Errores posibles:
        psycopg.Error: Falla en la comunicación con la base de datos.
    """
    query = """
        SELECT cod_transportista, razon_social, cuit
          FROM transportista
         ORDER BY razon_social ASC, cod_transportista ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchall()


def listar_localidades(conn: psycopg.Connection) -> list[dict]:
    """Obtiene el catálogo completo de localidades postales.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla localidad.

    Parámetros:
        conn: Conexión activa a PostgreSQL.

    Devuelve:
        Lista de diccionarios con: codigo_postal, nombre, provincia.

    Errores posibles:
        psycopg.Error: Falla en la comunicación con la base de datos.
    """
    query = """
        SELECT codigo_postal, nombre, provincia
          FROM localidad
         ORDER BY nombre ASC, codigo_postal ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchall()
