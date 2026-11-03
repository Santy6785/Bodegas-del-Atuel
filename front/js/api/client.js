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
   */
  constructor(status, message, data = null) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.data = data;
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

    // Probar en el body los campos mensaje, message, detail, error
    if (parsedData && typeof parsedData === "object") {
      const candidate =
        parsedData.mensaje ??
        parsedData.message ??
        parsedData.detail ??
        parsedData.error;

      if (typeof candidate === "string" && candidate.trim()) {
        errorMessage = candidate.trim();
      } else if (Array.isArray(candidate)) {
        errorMessage = candidate
          .map((item) =>
            typeof item === "string"
              ? item
              : item?.msg || item?.message || JSON.stringify(item)
          )
          .join(", ");
      } else if (candidate && typeof candidate === "object") {
        errorMessage =
          candidate.msg || candidate.message || JSON.stringify(candidate);
      }
    } else if (typeof parsedData === "string" && parsedData.trim()) {
      errorMessage = parsedData.trim();
    }

    // Si no se encontró ningún mensaje en el body
    if (!errorMessage) {
      errorMessage = `Error ${response.status}`;
    }

    throw new ApiError(response.status, errorMessage, parsedData);
  }

  return parsedData;
}
