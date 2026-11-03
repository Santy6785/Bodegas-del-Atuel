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
 * @param {object} [params={}] - Parámetros de filtrado (ej. limite, fecha_desde, fecha_hasta).
 * @returns {Promise<any>} Listado de vinos más vendidos.
 */
export async function topVinos(params = {}) {
  return request("/reportes/top-vinos", {
    method: "GET",
    params
  });
}

/**
 * Obtiene el reporte de ventas agrupado por sala de venta.
 * GET /reportes/ventas-por-sala
 *
 * @param {object} [params={}] - Parámetros de filtrado (ej. fecha_desde, fecha_hasta).
 * @returns {Promise<any>} Totales de ventas por sala.
 */
export async function ventasPorSala(params = {}) {
  return request("/reportes/ventas-por-sala", {
    method: "GET",
    params
  });
}

/**
 * Obtiene la lista de vinos que se encuentran sin stock disponible.
 * GET /reportes/vinos-sin-stock
 *
 * @param {object} [params={}] - Parámetros de consulta (ej. id_sala o depósito).
 * @returns {Promise<any>} Vinos con stock en cero.
 */
export async function vinosSinStock(params = {}) {
  return request("/reportes/vinos-sin-stock", {
    method: "GET",
    params
  });
}

/**
 * Obtiene el reporte del transportista con mayor actividad registrada.
 * GET /reportes/transportista-activo
 *
 * @param {object} [params={}] - Parámetros de consulta o rango de fechas.
 * @returns {Promise<any>} Datos del transportista más activo.
 */
export async function transportistaActivo(params = {}) {
  return request("/reportes/transportista-activo", {
    method: "GET",
    params
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
