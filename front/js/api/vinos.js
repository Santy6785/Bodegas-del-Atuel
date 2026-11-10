/**
 * Bodegas del Atuel - Endpoints de Vinos
 */

import { request } from "./client.js";

/**
 * Obtiene la lista de vinos filtrada y paginada.
 * GET /vinos
 *
 * @param {object} [filtros={}] - Filtros de búsqueda y paginación.
 * @param {string} [filtros.tipo] - Tipo de vino (ej. tinto, blanco, rosado, espumante).
 * @param {number} [filtros.id_cepa] - ID numérico de la cepa.
 * @param {string} [filtros.cuit_bodega] - CUIT de 11 dígitos de la bodega productora.
 * @param {number} [filtros.anada] - Año de cosecha / añada.
 * @param {string} [filtros.nombre] - Búsqueda parcial por nombre comercial.
 * @param {number} [filtros.page] - Número de página.
 * @param {number} [filtros.page_size] - Cantidad de registros por página.
 * @returns {Promise<any>} Listado de vinos devuelto por la API.
 */
export async function listarVinos({ tipo, id_cepa, cuit_bodega, anada, nombre, page, page_size, pageSize } = {}) {
  return request("/vinos", {
    method: "GET",
    params: { tipo, id_cepa, cuit_bodega, anada, nombre, page, page_size: page_size ?? pageSize }
  });
}

/**
 * Obtiene los detalles de un vino por su código.
 * GET /vinos/{cod}
 *
 * @param {string|number} cod - Código único del vino.
 * @returns {Promise<any>} Datos del vino.
 */
export async function obtenerVino(cod) {
  return request(`/vinos/${encodeURIComponent(cod)}`, {
    method: "GET"
  });
}

/**
 * Registra un nuevo vino en el catálogo.
 * POST /vinos
 *
 * @param {object} data - Datos del vino a crear.
 * @returns {Promise<any>} Vino creado con su identificador generado.
 */
export async function crearVino(data) {
  return request("/vinos", {
    method: "POST",
    body: data
  });
}

/**
 * Actualiza los datos de un vino existente.
 * PUT /vinos/{cod}
 *
 * @param {string|number} cod - Código único del vino a actualizar.
 * @param {object} data - Datos actualizados del vino.
 * @returns {Promise<any>} Vino actualizado.
 */
export async function actualizarVino(cod, data) {
  return request(`/vinos/${encodeURIComponent(cod)}`, {
    method: "PUT",
    body: data
  });
}

/**
 * Elimina un vino del catálogo (sujeto a restricciones de integridad de la BD).
 * DELETE /vinos/{cod}
 *
 * @param {string|number} cod - Código único del vino a eliminar.
 * @returns {Promise<any>} Respuesta de confirmación.
 */
export async function eliminarVino(cod) {
  return request(`/vinos/${encodeURIComponent(cod)}`, {
    method: "DELETE"
  });
}
