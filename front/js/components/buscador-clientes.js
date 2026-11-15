/**
 * Bodegas del Atuel - Buscador de clientes (componente reutilizable).
 *
 * Busca por texto o documento contra GET /clientes?q=...
 * No calcula descuentos ni importes: muestra lo que devuelve la API.
 */

import { buscarClientes } from "../fuentes/clientes-fuente.js";

const ESPERA_MS = 300;
const MIN_CARACTERES = 2;

function el(tag, { clase, texto } = {}) {
  const n = document.createElement(tag);
  if (clase) n.className = clase;
  if (texto !== undefined) n.textContent = texto;
  return n;
}

/**
 * Monta el buscador dentro del contenedor.
 * @param {HTMLElement} contenedor
 * @param {(cliente: object) => void} onSeleccion - recibe el cliente elegido.
 * @returns {{ destruir: () => void }}
 */
export function montarBuscadorClientes(contenedor, onSeleccion) {
  const input = el("input", { clase: "buscador-input" });
  input.type = "search";
  input.placeholder = "Apellido, razón social o documento";
  input.setAttribute("aria-label", "Buscar cliente");

  const estado = el("div", { clase: "buscador-estado" });
  const lista = el("ul", { clase: "buscador-resultados" });
  lista.setAttribute("role", "listbox");

  contenedor.appendChild(input);
  contenedor.appendChild(estado);
  contenedor.appendChild(lista);

  let temporizador = null;
  let ultimaConsulta = 0;

  function limpiarLista() {
    while (lista.firstChild) lista.removeChild(lista.firstChild);
  }

  function renderResultados(items) {
    limpiarLista();
    if (items.length === 0) {
      estado.textContent = "Sin coincidencias";
      return;
    }
    estado.textContent = "";
    items.forEach((c) => {
      const li = el("li", { clase: "buscador-item" });
      li.setAttribute("role", "option");
      li.tabIndex = 0;
      const nombre = c.nombre
        ? `${c.apellido_razon_social}, ${c.nombre}`
        : c.apellido_razon_social;
      li.appendChild(el("span", { clase: "buscador-nombre", texto: nombre }));
      li.appendChild(
        el("span", {
          clase: "buscador-doc",
          texto: `${c.tipo_documento} ${c.nro_documento} · ${c.tipo_cliente}`,
        })
      );
      const elegir = () => {
        onSeleccion(c);
        input.value = nombre;
        limpiarLista();
        estado.textContent = "";
      };
      li.addEventListener("click", elegir);
      li.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter") elegir();
      });
      lista.appendChild(li);
    });
  }

  async function buscar(texto) {
    const consulta = ++ultimaConsulta;
    estado.textContent = "Buscando...";
    try {
      const datos = await buscarClientes({ q: texto, page_size: 10 });
      if (consulta !== ultimaConsulta) return; // respuesta vieja, se descarta
      renderResultados(datos.items);
    } catch (error) {
      if (consulta !== ultimaConsulta) return;
      limpiarLista();
      estado.textContent = error.message; // mensaje de la API, sin reemplazar
    }
  }

  function alEscribir() {
    clearTimeout(temporizador);
    const texto = input.value.trim();
    if (texto.length < MIN_CARACTERES) {
      ultimaConsulta++;
      limpiarLista();
      estado.textContent = `Escriba al menos ${MIN_CARACTERES} caracteres`;
      return;
    }
    temporizador = setTimeout(() => buscar(texto), ESPERA_MS);
  }

  input.addEventListener("input", alEscribir);

  return {
    destruir() {
      clearTimeout(temporizador);
      ultimaConsulta++;
    },
  };
}