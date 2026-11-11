/**
 * Bodegas del Atuel - Endpoints de Clientes
 */

import { request } from "./client.js";

/**
 * Obtiene la lista de clientes filtrada y paginada.
 * GET /clientes
 *
 * @param {object} [filtros={}] - Filtros de búsqueda (tipo_cliente, etc.) y paginación.
 * @param {number} [filtros.page] - Número de página. Obligatorio.
 * @param {number} [filtros.page_size] - Tamaño de página. Obligatorio. Máximo 100.
 * @returns {Promise<any>} Listado de clientes.
 *
 * @note La paginación es obligatoria (page, page_size) porque la base tiene
 * ~20.000 clientes; no se permite listar sin paginar.
 * @note La búsqueda por texto (parámetro q) está pendiente: ver docs/api-contrato.md.
 * No se implementa aquí todavía.
 */
export async function listarClientes(filtros = {}) {
  return request("/clientes", {
    method: "GET",
    params: filtros
  });
}

/**
 * Obtiene los datos de un cliente por su ID.
 * GET /clientes/{id}
 *
 * @param {string|number} id - Identificador único del cliente.
 * @returns {Promise<any>} Datos del cliente.
 */
export async function obtenerCliente(id) {
  return request(`/clientes/${encodeURIComponent(id)}`, {
    method: "GET"
  });
}

/**
 * Registra un nuevo cliente (socio, distribuidor o exportador).
 * POST /clientes
 *
 * @param {object} data - Datos del cliente y datos específicos de su subtipo.
 * @returns {Promise<any>} Cliente creado.
 */
export async function crearCliente(data) {
  return request("/clientes", {
    method: "POST",
    body: data
  });
}

/**
 * Actualiza los datos de un cliente existente.
 * PUT /clientes/{id}
 *
 * @param {string|number} id - Identificador único del cliente a actualizar.
 * @param {object} data - Datos actualizados del cliente.
 * @returns {Promise<any>} Cliente actualizado.
 */
export async function actualizarCliente(id, data) {
  return request(`/clientes/${encodeURIComponent(id)}`, {
    method: "PUT",
    body: data
  });
}

/**
 * Elimina un cliente existente (sujeto a restricciones de compras históricas).
 * DELETE /clientes/{id}
 *
 * @param {string|number} id - Identificador único del cliente a eliminar.
 * @returns {Promise<any>} Confirmación de eliminación.
 */
export async function eliminarCliente(id) {
  return request(`/clientes/${encodeURIComponent(id)}`, {
    method: "DELETE"
  });
}
