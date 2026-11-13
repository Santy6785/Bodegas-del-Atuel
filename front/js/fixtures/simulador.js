/**
 * Bodegas del Atuel - Simulador de backend para desarrollo.
 *
 * ⚠️ SOLO PARA DESARROLLO. Imita el comportamiento de la API REST definido en
 * docs/api-contrato.md usando los fixtures locales de front/js/fixtures/catalogo.js.
 * No se usa cuando USAR_FIXTURES es false.
 *
 * Devuelve los mismos formatos que la API:
 * - listarVinosSimulado(filtros)  -> { items, page, page_size, total }
 * - obtenerVinoSimulado(cod)      -> objeto detalle del contrato (sección 4.1)
 * - listarCepasSimulado()         -> [{ id_cepa, nombre, tipo }]
 * - listarBodegasSimulado()       -> [{ cuit, razon_social, domicilio }]
 */

import {
  listaVinosFixture,
  detallesVinoFixture,
  cepasFixture,
  bodegasFixture,
  clientesFixture,
} from "./catalogo.js";

/**
 * Filtra y paginea la lista de vinos simulada aplicando los parámetros del
 * contrato: tipo, id_cepa, cuit_bodega, anada, nombre, page y page_size.
 * Los filtros se combinan con AND (como la API).
 *
 * @param {object} [filtros={}]
 * @param {string} [filtros.tipo]
 * @param {number} [filtros.id_cepa]
 * @param {string} [filtros.cuit_bodega]
 * @param {number} [filtros.anada]
 * @param {string} [filtros.nombre]
 * @param {number} [filtros.page]
 * @param {number} [filtros.page_size]
 * @returns {{ items: object[], page: number, page_size: number, total: number }}
 */
export function listarVinosSimulado({
  tipo,
  id_cepa,
  cuit_bodega,
  anada,
  nombre,
  page = 1,
  page_size = 20,
} = {}) {
  let resultado = listaVinosFixture.items;

  if (tipo) {
    resultado = resultado.filter((v) => v.tipo === tipo);
  }
  if (id_cepa !== undefined && id_cepa !== null && id_cepa !== "") {
    const id = Number(id_cepa);
    resultado = resultado.filter((v) => {
      const detalle = detallesVinoFixture[v.cod_vino];
      return detalle
        ? detalle.composicion.some((c) => c.id_cepa === id)
        : false;
    });
  }
  if (cuit_bodega) {
    resultado = resultado.filter((v) => v.cuit_bodega === cuit_bodega);
  }
  if (anada !== undefined && anada !== null && anada !== "") {
    const anio = Number(anada);
    resultado = resultado.filter((v) => v.anada === anio);
  }
  if (nombre) {
    const term = String(nombre).toLowerCase();
    resultado = resultado.filter((v) => v.nombre.toLowerCase().includes(term));
  }

  const total = resultado.length;
  const pagina = Math.max(1, Number(page) || 1);
  const tamanio = Math.max(1, Number(page_size) || 20);
  const inicio = (pagina - 1) * tamanio;
  const items = resultado.slice(inicio, inicio + tamanio);

  return { items, page: pagina, page_size: tamanio, total };
}

/**
 * Obtiene la ficha de detalle simulada de un vino por su código.
 *
 * @param {string|number} cod
 * @returns {object} Ficha del contrato (sección 4.1) o undefined si no existe.
 */
export function obtenerVinoSimulado(cod) {
  const key = String(cod);
  const vino = detallesVinoFixture[key];
  if (!vino) {
    throw new Error(`Vino no encontrado: ${cod}`);
  }
  return vino;
}

/**
 * Devuelve el catálogo de cepas simulado.
 * @returns {object[]} [{ id_cepa, nombre, tipo }]
 */
export function listarCepasSimulado() {
  return [...cepasFixture];
}

/**
 * Devuelve el catálogo de bodegas simulado.
 * @returns {object[]} [{ cuit, razon_social, domicilio }]
 */
export function listarBodegasSimulado() {
  return [...bodegasFixture];
}

/**
 * Busca y paginea clientes simulados aplicando el filtro de texto libre `q`
 * del contrato (sección 4.2 GET /clientes): busca por apellido, razón social,
 * nombre o prefijo de documento. Los filtros se combinan con AND.
 *
 * @param {object} [filtros={}]
 * @param {string} [filtros.q] - Texto libre de búsqueda.
 * @param {string} [filtros.tipo_cliente] - "socio" | "distribuidor" | "exportador".
 * @param {number} [filtros.page]
 * @param {number} [filtros.page_size]
 * @returns {{ items: object[], page: number, page_size: number, total: number }}
 */
export function buscarClientesSimulado({
  q,
  tipo_cliente,
  page = 1,
  page_size = 20,
} = {}) {
  let resultado = clientesFixture;

  if (tipo_cliente) {
    resultado = resultado.filter((c) => c.tipo_cliente === tipo_cliente);
  }
  if (q) {
    const term = String(q).toLowerCase();
    resultado = resultado.filter(
      (c) =>
        c.apellido_razon_social.toLowerCase().includes(term) ||
        (c.nombre && c.nombre.toLowerCase().includes(term)) ||
        c.nro_documento.toLowerCase().startsWith(term)
    );
  }

  const total = resultado.length;
  const pagina = Math.max(1, Number(page) || 1);
  const tamanio = Math.max(1, Number(page_size) || 20);
  const inicio = (pagina - 1) * tamanio;
  const items = resultado.slice(inicio, inicio + tamanio);

  return { items, page: pagina, page_size: tamanio, total };
}
