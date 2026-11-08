/**
 * Bodegas del Atuel - Endpoints de Ingresos de Vinos a Depósito Central
 */

import { request } from "./client.js";

/**
 * Registra un nuevo ingreso de mercadería en estado de confección.
 * POST /ingresos
 *
 * @param {object} data - Datos del ingreso a crear en el cuerpo de la petición.
 * @param {string} data.fecha - Fecha del ingreso en formato ISO (YYYY-MM-DD).
 * @param {number} data.cod_transportista - Código del transportista asignado.
 * @param {string} data.cuit_bodega - CUIT de 11 dígitos de la bodega remitente.
 * @returns {Promise<any>} Ingreso creado en estado en_confeccion.
 */
export async function crearIngreso(data) {
  return request("/ingresos", {
    method: "POST",
    body: data
  });
}

/**
 * Obtiene el detalle completo de un ingreso con sus renglones y estado.
 * GET /ingresos/{cod}
 *
 * @param {string|number} cod - Código único del ingreso.
 * @returns {Promise<any>} Cabecera y renglones del ingreso.
 */
export async function obtenerIngreso(cod) {
  return request(`/ingresos/${encodeURIComponent(cod)}`, {
    method: "GET"
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
 * Cambia el estado de un ingreso a terminado para habilitar su procesamiento.
 * POST /ingresos/{cod}/terminar
 *
 * @param {string|number} cod - Código único del ingreso.
 * @returns {Promise<any>} Ingreso actualizado en estado terminado.
 */
export async function terminarIngreso(cod) {
  return request(`/ingresos/${encodeURIComponent(cod)}/terminar`, {
    method: "POST"
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
