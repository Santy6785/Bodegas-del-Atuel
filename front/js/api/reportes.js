/**
 * Bodegas del Atuel - Endpoints de Reportes y Estadísticas
 *
 * NOTA: Ninguna métrica, agregado, suma o cálculo de stock se efectúa en el front.
 * Todos los reportes son resueltos mediante consultas y vistas SQL del backend.
 */

import { request } from "./client.js";

/**
 * Obtiene el ranking de vinos más vendidos.
 * GET /reportes/top-vinos
 *
 * @param {object} [params={}] - Parámetros de consulta.
 * @param {number} [params.limit=10] - Cantidad máxima de vinos en el ranking (por defecto 10, máx. 100).
 * @returns {Promise<any>} Listado de vinos más vendidos.
 */
export async function topVinos(params = {}) {
  const limit = typeof params === "object" && params !== null ? params.limit : params;
  return request("/reportes/top-vinos", {
    method: "GET",
    params: { limit }
  });
}

/**
 * Obtiene el reporte de ventas agrupado por sala de venta en el último trimestre.
 * GET /reportes/ventas-por-sala
 *
 * @returns {Promise<any>} Totales de ventas por sala.
 */
export async function ventasPorSala() {
  return request("/reportes/ventas-por-sala", {
    method: "GET"
  });
}

/**
 * Obtiene la lista de vinos que se encuentran sin stock disponible en una sala.
 * GET /reportes/vinos-sin-stock
 *
 * @param {object} params - Parámetros de consulta obligatorios.
 * @param {number|string} params.id_sala - Identificador de la sala de venta (obligatorio, no sala_id).
 * @returns {Promise<any>} Vinos con stock en cero en la sala indicada.
 */
export async function vinosSinStock(params = {}) {
  const id_sala = typeof params === "object" && params !== null ? params.id_sala : params;
  return request("/reportes/vinos-sin-stock", {
    method: "GET",
    params: { id_sala }
  });
}

/**
 * Obtiene el reporte del transportista con mayor actividad registrada en el último mes.
 * GET /reportes/transportista-activo
 *
 * @returns {Promise<any>} Datos del transportista más activo.
 */
export async function transportistaActivo() {
  return request("/reportes/transportista-activo", {
    method: "GET"
  });
}

/**
 * Obtiene la trazabilidad completa de un vino (parcelas, fincas, lotes y cosechas de origen).
 * GET /reportes/trazabilidad/{cod}
 *
 * @param {string|number} cod - Código único del vino.
 * @returns {Promise<any>} Información de trazabilidad del vino.
 */
export async function trazabilidad(cod) {
  return request(`/reportes/trazabilidad/${encodeURIComponent(cod)}`, {
    method: "GET"
  });
}
