/**
 * Bodegas del Atuel - Endpoints de Ingresos de Vinos a Depósito Central
 */

import { request } from "./client.js";

/**
 * Registra un nuevo ingreso de mercadería en estado de confección.
 * POST /ingresos
 *
 * @param {object} data - Datos del ingreso (ej. cuit_bodega, cod_transportista).
 * @returns {Promise<any>} Ingreso creado.
 */
export async function crearIngreso(data) {
  return request("/ingresos", {
    method: "POST",
    body: data
  });
}

/**
 * Agrega un renglón de vino y cantidad a un ingreso en confección.
 * POST /ingresos/{cod}/renglones
 *
 * @param {string|number} cod - Código de ingreso.
 * @param {object} data - Datos del renglón (cod_vino, cantidad).
 * @returns {Promise<any>} Renglón agregado.
 */
export async function agregarRenglonIngreso(cod, data) {
  return request(`/ingresos/${encodeURIComponent(cod)}/renglones`, {
    method: "POST",
    body: data
  });
}

/**
 * Procesa el ingreso incrementando el stock del depósito central.
 * POST /ingresos/{cod}/procesar
 *
 * @param {string|number} cod - Código de ingreso.
 * @returns {Promise<any>} Resultado del procesamiento del ingreso.
 */
export async function procesarIngreso(cod) {
  return request(`/ingresos/${encodeURIComponent(cod)}/procesar`, {
    method: "POST"
  });
}
