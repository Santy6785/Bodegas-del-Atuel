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
 * Obtiene el reporte de ventas agrupado por sala de venta.
 * GET /reportes/ventas-por-sala
 *
 * @param {object} [params={}] - Parámetros de consulta opcionales.
 * @param {string} [params.periodo] - Período relativo opcional (ej. "ultimo_trimestre").
 * @param {string} [params.fecha_desde] - Fecha inicial en formato ISO (YYYY-MM-DD).
 * @param {string} [params.fecha_hasta] - Fecha final en formato ISO (YYYY-MM-DD).
 * @returns {Promise<any[]>} Totales de ventas por sala [{ id_sala, calle, numero, monto_total }].
 */
export async function ventasPorSala(params = {}) {
  const { periodo, fecha_desde, fecha_hasta } = params || {};
  return request("/reportes/ventas-por-sala", {
    method: "GET",
    params: { periodo, fecha_desde, fecha_hasta }
  });
}

/**
 * Obtiene la lista de vinos que se encuentran sin stock disponible en una sala (o a nivel global si se omite).
 * GET /reportes/vinos-sin-stock
 *
 * @param {object|number|string} [params={}] - Parámetros de consulta opcionales o id_sala numérico directo.
 * @param {number|string} [params.id_sala] - Identificador opcional de la sala de venta.
 * @returns {Promise<any[]>} Vinos con stock en cero [{ cod_vino, nombre, stock_deposito }].
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
