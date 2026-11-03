/**
 * Bodegas del Atuel - Endpoints de Comprobantes de Venta
 *
 * NOTA: Los importes, descuentos y subtotales son calculados y devueltos
 * exclusivamente por el backend mediante las funciones y triggers de la base de datos.
 */

import { request } from "./client.js";

/**
 * Registra un nuevo comprobante de venta junto con sus renglones.
 * POST /comprobantes
 *
 * @param {object} data - Cabecera (id_cliente, id_sala) y renglones (cod_vino, cantidad).
 * @returns {Promise<any>} Comprobante creado con subtotales, descuentos y total calculados por el servidor.
 */
export async function crearComprobante(data) {
  return request("/comprobantes", {
    method: "POST",
    body: data
  });
}

/**
 * Obtiene el detalle completo de un comprobante de venta por su número.
 * GET /comprobantes/{nro}
 *
 * @param {string|number} nro - Número de comprobante.
 * @returns {Promise<any>} Cabecera y renglones del comprobante.
 */
export async function obtenerComprobante(nro) {
  return request(`/comprobantes/${encodeURIComponent(nro)}`, {
    method: "GET"
  });
}
