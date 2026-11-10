/**
 * Bodegas del Atuel - Fuente de datos de vinos.
 *
 * Capa de intercambio que la pantalla del catálogo consume exclusivamente.
 * - Si window.APP_CONFIG.USAR_FIXTURES es true, delega en el simulador local
 *   (front/js/fixtures/simulador.js) para desarrollo.
 * - Si es false, delega en la capa de API real (front/js/api/).
 *
 * La pantalla SOLO importa de este módulo.
 */

import {
  listarVinosSimulado,
  obtenerVinoSimulado,
  listarCepasSimulado,
  listarBodegasSimulado,
} from "../fixtures/simulador.js";

import {
  listarVinos,
  obtenerVino,
  listarCepas,
  listarBodegas,
} from "../api/index.js";

/**
 * Indica si se está usando la fuente simulada.
 * @returns {boolean}
 */
export function usandoFixtures() {
  return window.APP_CONFIG?.USAR_FIXTURES === true;
}

/**
 * Obtiene el listado paginado y filtrado de vinos.
 * @param {object} [filtros={}]
 * @returns {Promise<{ items: object[], page: number, page_size: number, total: number }>}
 */
export async function obtenerListadoVinos(filtros = {}) {
  if (usandoFixtures()) {
    return listarVinosSimulado(filtros);
  }
  return listarVinos(filtros);
}

/**
 * Obtiene el detalle de un vino por su código.
 * @param {string|number} cod
 * @returns {Promise<object>}
 */
export async function obtenerDetalleVino(cod) {
  if (usandoFixtures()) {
    return obtenerVinoSimulado(cod);
  }
  return obtenerVino(cod);
}

/**
 * Obtiene el catálogo de cepas.
 * @returns {Promise<object[]>}
 */
export async function obtenerCepas() {
  if (usandoFixtures()) {
    return listarCepasSimulado();
  }
  return listarCepas();
}

/**
 * Obtiene el catálogo de bodegas.
 * @returns {Promise<object[]>}
 */
export async function obtenerBodegas() {
  if (usandoFixtures()) {
    return listarBodegasSimulado();
  }
  return listarBodegas();
}
