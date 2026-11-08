/**
 * Bodegas del Atuel - Endpoints de Transferencias entre Depósito y Salas de Venta
 */

import { request } from "./client.js";

/**
 * Obtiene la lista de transferencias filtrada y paginada.
 * GET /transferencias
 *
 * @param {object} [filtros={}] - Filtros de búsqueda y paginación.
 * @param {number} [filtros.page] - Número de página.
 * @param {number} [filtros.page_size] - Cantidad de registros por página.
 * @param {string} [filtros.estado] - Estado de la transferencia (en_confeccion, terminado, procesado).
 * @param {number} [filtros.id_sala] - Identificador de la sala de venta solicitante.
 * @returns {Promise<any>} Listado paginado de transferencias devuelto por la API.
 */
export async function listarTransferencias({ page, page_size, estado, id_sala } = {}) {
  return request("/transferencias", {
    method: "GET",
    params: { page, page_size, estado, id_sala }
  });
}

/**
 * Obtiene el detalle de una transferencia con sus renglones y estado.
 * GET /transferencias/{nro}
 *
 * @param {string|number} nro - Número de transferencia.
 * @returns {Promise<any>} Cabecera y renglones de la transferencia.
 */
export async function obtenerTransferencia(nro) {
  return request(`/transferencias/${encodeURIComponent(nro)}`, {
    method: "GET"
  });
}

/**
 * Crea una nueva solicitud de transferencia en estado de confección.
 * POST /transferencias
 *
 * @param {object} data - Datos de la transferencia (ej. id_sala).
 * @returns {Promise<any>} Transferencia creada.
 */
export async function crearTransferencia(data) {
  return request("/transferencias", {
    method: "POST",
    body: data
  });
}

/**
 * Agrega un ítem/renglón a una transferencia en confección.
 * POST /transferencias/{nro}/renglones
 *
 * @param {string|number} nro - Número de transferencia.
 * @param {object} data - Datos del renglón (cod_vino, cantidad).
 * @returns {Promise<any>} Renglón creado.
 */
export async function agregarRenglonTransferencia(nro, data) {
  return request(`/transferencias/${encodeURIComponent(nro)}/renglones`, {
    method: "POST",
    body: data
  });
}

/**
 * Cambia el estado de una transferencia a terminado para permitir su procesamiento.
 * POST /transferencias/{nro}/terminar
 *
 * @param {string|number} nro - Número de transferencia.
 * @returns {Promise<any>} Transferencia en estado terminado.
 */
export async function terminarTransferencia(nro) {
  return request(`/transferencias/${encodeURIComponent(nro)}/terminar`, {
    method: "POST"
  });
}

/**
 * Procesa la transferencia descontando stock del depósito y acreditándolo en la sala.
 * POST /transferencias/{nro}/procesar
 *
 * @param {string|number} nro - Número de transferencia.
 * @returns {Promise<any>} Resultado del procesamiento y nuevo estado.
 */
export async function procesarTransferencia(nro) {
  return request(`/transferencias/${encodeURIComponent(nro)}/procesar`, {
    method: "POST"
  });
}
