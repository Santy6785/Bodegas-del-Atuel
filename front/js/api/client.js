/**
 * Bodegas del Atuel - Cliente HTTP Centralizado
 *
 * Este es el ÚNICO archivo del proyecto donde se utiliza `fetch`.
 * Toda la comunicación con la API REST pasa obligatoriamente por aquí.
 */

/**
 * Error personalizado para respuestas no exitosas o fallos de red con la API.
 */
export class ApiError extends Error {
  /**
   * @param {number} status - Código de estado HTTP (o 0 si ocurrió un error de red).
   * @param {string} message - Mensaje de error devuelto por la API tal cual o mensaje de fallo de conexión.
   * @param {any} [data=null] - Payload completo de la respuesta de error o null.
   * @param {string|null} [sqlstate=null] - Código SQLSTATE de PostgreSQL o null si no aplica.
   * @param {string|null} [restriccion=null] - Nombre de la restricción violada o null si no aplica.
   */
  constructor(status, message, data = null, sqlstate = null, restriccion = null) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.data = data;
    this.sqlstate =
      sqlstate ??
      (data && typeof data === "object" ? data.error?.sqlstate ?? null : null);
    this.restriccion =
      restriccion ??
      (data && typeof data === "object" ? data.error?.restriccion ?? null : null);
  }
}

/**
 * Obtiene la URL base configurada para la API.
 * Lee `window.APP_CONFIG?.API_BASE_URL`, advierte si no existe y elimina cualquier barra final.
 * @returns {string} URL base saneada.
 */
function getApiBaseUrl() {
  const rawBaseUrl = window.APP_CONFIG?.API_BASE_URL;
  if (!rawBaseUrl) {
    console.warn(
      "window.APP_CONFIG.API_BASE_URL no está definido. Usando valor por defecto: http://localhost:8000"
    );
    return "http://localhost:8000";
  }
  return rawBaseUrl.replace(/\/+$/, "");
}

/**
 * Realiza una petición HTTP contra la API REST.
 *
 * @param {string} path - Ruta relativa del endpoint (ej. "/vinos" o "/comprobantes/12").
 * @param {object} [opciones={}] - Opciones de la petición.
 * @param {string} [opciones.method="GET"] - Método HTTP (GET, POST, PUT, DELETE, etc.).
 * @param {object} [opciones.params] - Parámetros de consulta (query string). Se ignoran null, undefined y "".
 * @param {any} [opciones.body] - Datos para enviar en el cuerpo. Si está presente, se serializa como JSON y se agrega el header Content-Type.
 * @returns {Promise<any>} Datos parseados de la respuesta, o null si la respuesta no tiene contenido (ej. 204).
 * @throws {ApiError} Si ocurre un error de red (status 0) o si la respuesta HTTP no es ok (status >= 400).
 */
export async function request(path, { method = "GET", params, body } = {}) {
  const baseUrl = getApiBaseUrl();
  const cleanPath = path.startsWith("/") ? path : `/${path}`;

  // Construir query string ignorando null, undefined y cadenas vacías
  const searchParams = new URLSearchParams();
  if (params && typeof params === "object") {
    for (const [key, value] of Object.entries(params)) {
      if (value !== undefined && value !== null && value !== "") {
        searchParams.append(key, String(value));
      }
    }
  }

  const queryString = searchParams.toString();
  const url = `${baseUrl}${cleanPath}${queryString ? `?${queryString}` : ""}`;

  const fetchOptions = {
    method,
    headers: {}
  };

  // Enviar cabecera Content-Type únicamente si hay cuerpo en la petición
  if (body !== undefined && body !== null) {
    fetchOptions.headers["Content-Type"] = "application/json";
    fetchOptions.body = typeof body === "string" ? body : JSON.stringify(body);
  }

  let response;
  try {
    response = await fetch(url, fetchOptions);
  } catch (networkError) {
    // Si fetch rechaza (falla de red o CORS), lanzar ApiError con status 0
    throw new ApiError(0, "No se pudo conectar con el servidor de la API.", null);
  }

  // Soporte para respuestas 204 No Content
  if (response.status === 204) {
    return null;
  }

  // Leer cuerpo de la respuesta en texto para soportar JSON o texto crudo
  const rawText = await response.text();
  if (!rawText || !rawText.trim()) {
    if (!response.ok) {
      throw new ApiError(response.status, `Error ${response.status}`, null);
    }
    return null;
  }

  let parsedData;
  try {
    parsedData = JSON.parse(rawText);
  } catch {
    parsedData = rawText;
  }

  if (!response.ok) {
    let errorMessage = "";
    let sqlstate = null;
    let restriccion = null;

    if (parsedData && typeof parsedData === "object") {
      // 1) Formato oficial del contrato: {"error": {"sqlstate", "mensaje", "restriccion"}}
      if (parsedData.error && typeof parsedData.error === "object") {
        if (
          typeof parsedData.error.mensaje === "string" &&
          parsedData.error.mensaje.trim()
        ) {
          errorMessage = parsedData.error.mensaje.trim();
        }
        if (parsedData.error.sqlstate !== undefined && parsedData.error.sqlstate !== null) {
          sqlstate = parsedData.error.sqlstate;
        }
        if (parsedData.error.restriccion !== undefined && parsedData.error.restriccion !== null) {
          restriccion = parsedData.error.restriccion;
        }
      }

      // 2) Formatos alternativos en primer nivel (mensaje, message, detail, error como string)
      if (!errorMessage) {
        if (typeof parsedData.mensaje === "string" && parsedData.mensaje.trim()) {
          errorMessage = parsedData.mensaje.trim();
        } else if (typeof parsedData.message === "string" && parsedData.message.trim()) {
          errorMessage = parsedData.message.trim();
        } else if (typeof parsedData.detail === "string" && parsedData.detail.trim()) {
          errorMessage = parsedData.detail.trim();
        } else if (Array.isArray(parsedData.detail)) {
          errorMessage = parsedData.detail
            .map((item) =>
              typeof item === "string"
                ? item
                : item?.msg || item?.message || JSON.stringify(item)
            )
            .join(", ");
        } else if (parsedData.detail && typeof parsedData.detail === "object") {
          errorMessage =
            parsedData.detail.msg ||
            parsedData.detail.message ||
            JSON.stringify(parsedData.detail);
        } else if (typeof parsedData.error === "string" && parsedData.error.trim()) {
          errorMessage = parsedData.error.trim();
        }
      }

      // 3) JSON.stringify solo como último recurso
      if (!errorMessage) {
        try {
          errorMessage = JSON.stringify(parsedData);
        } catch {
          errorMessage = "";
        }
      }
    } else if (typeof parsedData === "string" && parsedData.trim()) {
      errorMessage = parsedData.trim();
    }

    // 4) Si no se encontró ningún mensaje en el body
    if (!errorMessage) {
      errorMessage = `Error ${response.status}`;
    }

    throw new ApiError(response.status, errorMessage, parsedData, sqlstate, restriccion);
  }

  return parsedData;
}
