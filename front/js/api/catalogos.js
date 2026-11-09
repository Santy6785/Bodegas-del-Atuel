/**
 * Bodegas del Atuel - Endpoints de Catálogos Auxiliares
 *
 * Consultas de solo lectura y sin paginar para alimentar selectores y listas desplegables.
 */

import { request } from "./client.js";

/**
 * Obtiene el listado completo de salas de venta.
 * GET /salas
 *
 * @returns {Promise<any[]>} Arreglo de salas [{ id_sala, calle, numero, dia_cierre, codigo_postal }].
 */
export async function listarSalas() {
  return request("/salas", {
    method: "GET"
  });
}

/**
 * Obtiene el catálogo completo de cepas de uva.
 * GET /cepas
 *
 * @returns {Promise<any[]>} Arreglo de cepas [{ id_cepa, nombre, tipo }].
 */
export async function listarCepas() {
  return request("/cepas", {
    method: "GET"
  });
}

/**
 * Obtiene el catálogo de bodegas productoras.
 * GET /bodegas
 *
 * @returns {Promise<any[]>} Arreglo de bodegas [{ cuit, razon_social, domicilio }].
 */
export async function listarBodegas() {
  return request("/bodegas", {
    method: "GET"
  });
}

/**
 * Obtiene el catálogo de maridajes recomendados.
 * GET /maridajes
 *
 * @returns {Promise<any[]>} Arreglo de maridajes [{ id_maridaje, nombre, temperatura_servicio }].
 */
export async function listarMaridajes() {
  return request("/maridajes", {
    method: "GET"
  });
}

/**
 * Obtiene el catálogo de empresas transportistas.
 * GET /transportistas
 *
 * @returns {Promise<any[]>} Arreglo de transportistas [{ cod_transportista, razon_social, cuit }].
 */
export async function listarTransportistas() {
  return request("/transportistas", {
    method: "GET"
  });
}

/**
 * Obtiene el catálogo de localidades geográficas.
 * GET /localidades
 *
 * @returns {Promise<any[]>} Arreglo de localidades [{ codigo_postal, nombre, provincia }].
 */
export async function listarLocalidades() {
  return request("/localidades", {
    method: "GET"
  });
}
