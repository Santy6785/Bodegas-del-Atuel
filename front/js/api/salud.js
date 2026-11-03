/**
 * Bodegas del Atuel - Endpoint de Verificación de Salud (Health Check)
 */

import { request } from "./client.js";

/**
 * Consulta el estado de operatividad de la API REST.
 * GET /salud
 *
 * @returns {Promise<any>} Objeto con el estado del servidor (ej. { estado: "ok" }).
 */
export async function verificarSalud() {
  return request("/salud", {
    method: "GET"
  });
}
