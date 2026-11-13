# Mapeo SQLSTATE -> HTTP para la API Bodegas del Atuel
# Todos los códigos son los definidos por PostgreSQL (5 caracteres SQLSTATE)

# Mapeo directo de SQLSTATE a código HTTP
_SQLSTATE_HTTP = {
    # Clase 23: Integridad de datos (constraints, FK, CHECK)
    "23505": 409,  # UNIQUE violation
    "23503": 409,  # FOREIGN KEY violation
    "23514": 422,  # CHECK constraint violation
    "23502": 422,  # NOT NULL violation

    # Clase P0001: Regla rechazada por trigger o procedimiento (RAISE EXCEPTION)
    "P0001": 409,  # Regla de negocio rechazada por trigger/procedimiento

    # Clase 22: Formato de datos
    "22P02": 400,  # Formato de datos inválido

    # Clase 40P01 / 40001: Deadlock o fallo de serialización
    "40001": 503,  # Deadlock o fallo de serialización
    "40P01": 503,  # Deadlock o fallo de serialización

    # NUEVO: Clase 57 - Query canceled
    "57014": 503,  # Query canceled (statement_timeout exceeded)
}

# Prefijos de SQLSTATE que requieren tratamiento especial
_SQLSTATE_PREFIX_HANDLERS = {
    # "08" = Errores de conexión
    "08": 503,  # Base de datos inaccesible
}


def translate_sqlstate_to_http(sqlstate: str) -> tuple:
    """
    Traducir un SQLSTATE de PostgreSQL a una respuesta HTTP.

    Retorna tupla: (http_status_code, detail_message, sqlstate)
    La función toma el mensaje de diag.message_primary cuando esté disponible
    para incluirlo en el detail, pero el caller debe pasarlo como parámetro.

    La clave "08xxx" se resuelve por prefijo (empieza con "08").
    SQLSTATEs no mapeados devuelven (500, "Error interno", sqlstate).
    """
    if not sqlstate:
        return 500, "SQLSTATE vacío", None

    # 1️⃣ Verificar prefijo "08" (errores de conexión)
    if sqlstate.startswith("08"):
        return _SQLSTATE_PREFIX_HANDLERS["08"], "Base de datos inaccesible", sqlstate

    # 2️⃣ Verificar mapeo exacto
    if sqlstate in _SQLSTATE_HTTP:
        return _SQLSTATE_HTTP[sqlstate], None, sqlstate

    # 3️⃣ SQLSTATE no mapeado: devolver 500 genérico SIN datos sensibles
    return 500, "Error interno del servidor", sqlstate


def build_error_response(
    http_status: int,
    sqlstate: str,
    detail: str | None = None,
    title: str | None = None,
) -> dict:
    """
    Construir un diccionario de respuesta de error unificado.

    Formato: {"status": <http>, "title": "...", "detail": "<mensaje>", "sqlstate": "<código>"}
    """
    # Título por defecto según clase de error
    if title is None:
        if http_status == 409:
            title = "Conflict"
        elif http_status == 422:
            title = "Unprocessable Entity"
        elif http_status == 400:
            title = "Bad Request"
        elif http_status == 503:
            title = "Service Unavailable"
        else:
            title = "Error"

    # Si detail viene vacío y es P0001, el caller debería haber pasado el mensaje real
    if not detail and http_status == 409:
        # Este es el caso: el error viene sin detail (el front debería leerlo de error?)
        # Pero por compatibilidad, dejamos detail como string vacío o mensaje por defecto
        detail = detail or "Error de regla de negocio"

    return {
        "status": http_status,
        "title": title,
        "detail": detail or "",
        "sqlstate": sqlstate,
    }