"""Consultas analíticas y de reportes para el sistema Bodegas del Atuel.

Todas las consultas en este módulo son estrictamente de solo lectura.
No realizan modificaciones de datos ni refrescan vistas materializadas (R8).
Los importes y totales monetarios provienen directamente de los valores
almacenados y calculados por la base de datos (R4).
"""

from datetime import date
from decimal import Decimal
import psycopg

from ._reglas import validar_fecha, validar_rango_paginacion


def top_vinos(conn: psycopg.Connection, limite: int = 10) -> list[dict]:
    """Obtiene los vinos más vendidos según cantidad de botellas despachadas (Consigna S1).

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tabla renglon_comprobante JOIN vino.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        limite: Cantidad máxima de registros a retornar (1 a 100, default 10).

    Devuelve:
        Lista de diccionarios con: posicion, cod_vino, nombre, botellas_vendidas.
        La posición ordinal (1..n) se numera en Python mediante enumerate.

    Errores posibles:
        ValueError: Si limite está fuera de rango (1 a 100).
        psycopg.Error: Falla en la comunicación con la base de datos.
    """
    validar_rango_paginacion(1, limite)

    query = """
        SELECT rc.cod_vino, v.nombre,
               COALESCE(SUM(rc.cantidad), 0)::BIGINT AS botellas_vendidas
          FROM renglon_comprobante rc
          JOIN vino v ON v.cod_vino = rc.cod_vino
         GROUP BY rc.cod_vino, v.nombre
         ORDER BY botellas_vendidas DESC, rc.cod_vino ASC
         LIMIT %s
    """
    with conn.cursor() as cur:
        cur.execute(query, (limite,))
        rows = cur.fetchall()

        resultado: list[dict] = []
        for idx, row in enumerate(rows, start=1):
            item = dict(row)
            item["posicion"] = idx
            resultado.append(item)
        return resultado


def ventas_por_sala(
    conn: psycopg.Connection,
    *,
    periodo: str | None = None,
    fecha_desde: date | str | None = None,
    fecha_hasta: date | str | None = None,
) -> list[dict]:
    """Reporte de monto total facturado por sala de venta (Consigna S8).

    Utiliza LEFT JOIN entre sala_venta y comprobante con filtros temporales
    en la cláusula ON para garantizar que las salas sin ventas figuren con 0.
    El monto total es la suma del campo total de comprobante ya calculado por la base.

    Reglas de filtrado temporal:
        - Si se especifica periodo='ultimo_trimestre', se filtra por c.fecha >= CURRENT_DATE - INTERVAL '3 months'
          directamente en PostgreSQL.
        - Si vienen simultáneamente 'periodo' y rango de fechas ('fecha_desde'/'fecha_hasta'),
          el filtro 'periodo' tiene prioridad sobre el rango explícito.
        - Si se utiliza rango de fechas, se valida que fecha_desde <= fecha_hasta.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tablas sala_venta y comprobante.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        periodo: Cadena identificadora del período relativo ('ultimo_trimestre').
        fecha_desde: Fecha límite inferior inclusiva.
        fecha_hasta: Fecha límite superior inclusiva.

    Devuelve:
        Lista de diccionarios con: id_sala, calle, numero, monto_total (Decimal).
        Ordenado descendentemente por monto_total.

    Errores posibles:
        ValueError: Si fecha_desde es posterior a fecha_hasta.
        psycopg.Error: Falla en la comunicación con la base de datos.
    """
    on_condiciones: list[str] = []
    params: list[object] = []

    if periodo is not None and periodo != "ultimo_trimestre":
        raise ValueError(
            f"periodo '{periodo}' no es válido. Valores admitidos: None, 'ultimo_trimestre'"
        )

    f_desde: date | None = None
    f_hasta: date | None = None

    if fecha_desde is not None:
        f_desde = validar_fecha(fecha_desde, "fecha_desde")
    if fecha_hasta is not None:
        f_hasta = validar_fecha(fecha_hasta, "fecha_hasta")

    if f_desde is not None and f_hasta is not None and f_desde > f_hasta:
        raise ValueError("La 'fecha_desde' no puede ser posterior a 'fecha_hasta'")

    if periodo == "ultimo_trimestre":
        # Período relativo calculado en la base mediante CURRENT_DATE (exigencia TPI)
        on_condiciones.append("c.fecha >= CURRENT_DATE - INTERVAL '3 months'")
    else:
        if f_desde is not None:
            on_condiciones.append("c.fecha >= %s")
            params.append(f_desde)

        if f_hasta is not None:
            on_condiciones.append("c.fecha <= %s")
            params.append(f_hasta)

    and_on = (" AND " + " AND ".join(on_condiciones)) if on_condiciones else ""

    query = f"""
        SELECT s.id_sala, s.calle, s.numero,
               COALESCE(SUM(c.total), 0)::NUMERIC(12,2) AS monto_total
          FROM sala_venta s
          LEFT JOIN comprobante c ON c.id_sala = s.id_sala{and_on}
         GROUP BY s.id_sala, s.calle, s.numero
         ORDER BY monto_total DESC, s.id_sala ASC
    """
    with conn.cursor() as cur:
        cur.execute(query, params)
        return cur.fetchall()


def vinos_sin_stock(
    conn: psycopg.Connection, id_sala: int | None = None
) -> list[dict]:
    """Reporte de vinos sin stock disponible (Consigna S6).

    Criterios de filtrado:
        - Si se provee id_sala: Vinos cuyo stock en dicha sala sea 0 (según fn_stock_sala)
          pero que dispongan de stock mayor a 0 en el depósito central (Consigna S6 del TPI).
        - Si NO se provee id_sala: Vinos cuyo stock_total sea 0 en toda la empresa
          (según vista vw_stock_total_vino). Decisión de alcance general a validar con el grupo.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tablas vino, stock_deposito, función fn_stock_sala y vista vw_stock_total_vino.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        id_sala: Identificador opcional de la sala de venta a consultar.

    Devuelve:
        Lista de diccionarios con: cod_vino, nombre, stock_deposito.

    Nota:
        El router verifica la existencia de la sala (404) antes de llamar a esta
        función cuando se provee id_sala.
    """
    if id_sala is not None:
        query = """
            SELECT v.cod_vino, v.nombre,
                   COALESCE(sd.cantidad, 0)::BIGINT AS stock_deposito
              FROM vino v
              LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
             WHERE fn_stock_sala(%s, v.cod_vino) = 0
               AND COALESCE(sd.cantidad, 0) > 0
             ORDER BY v.cod_vino ASC
        """
        params = (id_sala,)
    else:
        query = """
            SELECT v.cod_vino, v.nombre,
                   COALESCE(sd.cantidad, 0)::BIGINT AS stock_deposito
              FROM vino v
              JOIN vw_stock_total_vino st ON st.cod_vino = v.cod_vino
              LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
             WHERE st.stock_total = 0
             ORDER BY v.cod_vino ASC
        """
        params = ()

    with conn.cursor() as cur:
        cur.execute(query, params)
        return cur.fetchall()


def transportista_activo(conn: psycopg.Connection) -> list[dict]:
    """Identifica la/s empresa/s transportista/s con mayor cantidad de ingresos en el último mes (Consigna S7).

    Evalúa los ingresos con fecha dentro del intervalo de 1 mes (CURRENT_DATE - INTERVAL '1 month').
    Utiliza DENSE_RANK() para resolver empates en el primer puesto.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tablas transportista e ingreso.

    Parámetros:
        conn: Conexión activa a PostgreSQL.

    Devuelve:
        Lista de diccionarios con: cod_transportista, razon_social, cantidad_ingresos.
        Lista vacía si no hubo ingresos registrados en el período.
    """
    query = """
        WITH ranking AS (
            SELECT t.cod_transportista, t.razon_social,
                   COUNT(i.cod_ingreso)::BIGINT AS cantidad_ingresos,
                   DENSE_RANK() OVER (ORDER BY COUNT(i.cod_ingreso) DESC) AS puesto
              FROM transportista t
              JOIN ingreso i ON i.cod_transportista = t.cod_transportista
             WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
             GROUP BY t.cod_transportista, t.razon_social
            HAVING COUNT(i.cod_ingreso) > 0
        )
        SELECT cod_transportista, razon_social, cantidad_ingresos
          FROM ranking
         WHERE puesto = 1
         ORDER BY cod_transportista ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchall()


def trazabilidad_vino(conn: psycopg.Connection, cod_vino: int) -> list[dict]:
    """Obtiene la cadena de trazabilidad de los lotes de uva de un vino.

    La verificación de existencia del vino debe ser realizada por el router
    mediante obtener_vino(conn, cod_vino). Si el vino existe pero carece de
    trazabilidad cargada, esta función devuelve una lista vacía.

    Tipo de operación: Lectura.
    Transacción: No requerida.
    Objeto de base: Tablas vino_lote, lote_uva, parcela, finca, cepa.

    Parámetros:
        conn: Conexión activa a PostgreSQL.
        cod_vino: Identificador del vino.

    Devuelve:
        Lista de diccionarios con: id_lote, nro_lote, campania, fecha_cosecha,
        kilos, id_finca, finca, nro_parcela, cepa.
    """
    query = """
        SELECT l.id_lote, l.nro_lote, l.campania, l.fecha_cosecha, l.kilos,
               f.id_finca, f.nombre AS finca, p.nro_parcela, c.nombre AS cepa
          FROM vino_lote vl
          JOIN lote_uva l ON l.id_lote = vl.id_lote
          JOIN parcela p ON p.id_finca = l.id_finca AND p.nro_parcela = l.nro_parcela
          JOIN finca f ON f.id_finca = p.id_finca
          JOIN cepa c ON c.id_cepa = p.id_cepa
         WHERE vl.cod_vino = %s
         ORDER BY l.fecha_cosecha ASC, l.id_lote ASC
    """
    with conn.cursor() as cur:
        cur.execute(query, (cod_vino,))
        return cur.fetchall()


def exportadores_con_descuento_extendido(conn: psycopg.Connection) -> list[dict]:
    """Exportadores con más de 3 permisos de exportación y su descuento (consulta U6-R).

    Tipo: Lectura. Transacción: No requerida.
    Objeto de base: cliente, cliente_exportador, permiso_exportacion, fn_descuento_cliente.
    Es la misma consulta que U6-R en consultas/select.sql.

    Cuenta TODOS los permisos cargados sin filtrar por vigencia. El descuento se
    obtiene de fn_descuento_cliente (umbral "más de 3" da 35 %, con 3 o menos da 30 %).

    Parámetros:
        conn: Conexión activa a PostgreSQL.

    Devuelve:
        Lista de diccionarios con: id_cliente, apellido_razon_social, nombre,
        cantidad_permisos (int), descuento_pct (Decimal). Orden por id_cliente.
    """
    query = """
        SELECT c.id_cliente,
               c.apellido_razon_social,
               c.nombre,
               COUNT(p.codigo) AS cantidad_permisos,
               fn_descuento_cliente(c.id_cliente) AS descuento_pct
          FROM cliente c
          JOIN cliente_exportador e ON e.id_cliente = c.id_cliente
          LEFT JOIN permiso_exportacion p ON p.id_cliente = c.id_cliente
         GROUP BY c.id_cliente, c.apellido_razon_social, c.nombre
        HAVING COUNT(p.codigo) > 3
         ORDER BY c.id_cliente;
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchall()
