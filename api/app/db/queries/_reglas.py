"""Utilidades compartidas de validación para la capa de acceso a datos.

Estas funciones centralizan la lógica que los módulos de queries reutilizan para
aplicar las reglas de negocio del TPI (rechazo de campos calculados, validación
de fechas y paginación) en un solo lugar, evitando repetirla en cada módulo.
"""

from datetime import date

# Campos calculados por la base de datos (fn_*, triggers, DEFAULT) que nunca
# deben llegar de la capa de usuario ni escribirse desde Python en una escritura.
# Su valor lo determina la base (D1, D3, D4, D5).
CAMPOS_CALCULADOS_PROHIBIDOS: frozenset[str] = frozenset(
    {
        "descuento",
        "descuento_pct",
        "porcentaje_descuento",
        "subtotal",
        "total",
        "precio_unitario",
        "stock",
        "stock_deposito",
        "stock_salas",
        "stock_total",
        "fecha_alta",
        "fecha_confeccion",
        "estado",
    }
)


def rechazar_campos_calculados(datos: dict, contexto: str) -> None:
    """Lanza ValueError si alguna clave de datos es un campo calculado prohibido.

    Parámetros:
        datos: Diccionario de payload a validar.
        contexto: Descripción breve del punto de validación (para el mensaje).
    """
    for campo in datos.keys():
        if campo in CAMPOS_CALCULADOS_PROHIBIDOS:
            raise ValueError(
                f"El campo '{campo}' es calculado por la base de datos y no debe "
                f"provenir del cliente ({contexto})."
            )


def validar_fecha(valor: date | str, nombre: str) -> date:
    """Devuelve un objeto date a partir de un date o string ISO (YYYY-MM-DD).

    Parámetros:
        valor: date o string ISO a convertir.
        nombre: Nombre del parámetro (se incluye en el mensaje de error).

    Devuelve:
        Instancia de datetime.date.

    Errores:
        ValueError: Si valor no es date ni str, o el str no es ISO válido.
    """
    if isinstance(valor, date):
        return valor
    if isinstance(valor, str):
        try:
            return date.fromisoformat(valor)
        except ValueError as exc:
            raise ValueError(
                f"El parámetro '{nombre}' debe ser una fecha ISO (YYYY-MM-DD). "
                f"Valor recibido: {valor!r}"
            ) from exc
    raise ValueError(
        f"El parámetro '{nombre}' debe ser una fecha (date o str ISO), "
        f"se recibió {type(valor).__name__}."
    )


def validar_rango_paginacion(page: int, page_size: int) -> None:
    """Valida que page y page_size estén dentro del rango permitido.

    Parámetros:
        page: Número de página (1-based, mínimo 1).
        page_size: Tamaño de página (1 a 100).

    Errores:
        ValueError: Si page < 1 o page_size fuera de [1, 100].
    """
    if page < 1:
        raise ValueError("El parámetro 'page' debe ser mayor o igual a 1")
    if page_size < 1 or page_size > 100:
        raise ValueError("El parámetro 'page_size' debe estar comprendido entre 1 y 100")


DOCUMENTOS_PERSONA_HUMANA = {"DNI", "CUIL", "PASAPORTE"}
DOCUMENTO_RAZON_SOCIAL = "CUIT"


def validar_nombre_cliente(tipo_documento: str, nombre) -> None:
    """Valida el campo nombre según el tipo de documento.

    Reglas de formato de la DAL (no replicadas en la base):
    - Persona humana (DNI, CUIL, PASAPORTE): nombre es obligatorio y no vacío.
    - Razón social (CUIT): nombre debe ser None; si viene con valor, ValueError.

    Parámetros:
        tipo_documento: Tipo de documento del cliente.
        nombre: Valor del campo nombre (puede ser None o str).

    Errores:
        ValueError: Si se viola la regla de nombre para el tipo de documento.
    """
    if tipo_documento in DOCUMENTOS_PERSONA_HUMANA:
        if nombre is None or (isinstance(nombre, str) and nombre.strip() == ""):
            raise ValueError(
                f"El campo 'nombre' es obligatorio para tipo de documento '{tipo_documento}'."
            )
    elif tipo_documento == DOCUMENTO_RAZON_SOCIAL:
        if nombre is not None:
            raise ValueError(
                "Las razones sociales (tipo CUIT) no llevan nombre; el campo debe ser None."
            )
