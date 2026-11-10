/**
 * Bodegas del Atuel - Pantalla 1: Catálogo de Vinos.
 *
 * Exporta iniciarCatalogo(contenedor). La pantalla solo importa de
 * front/js/fuentes/vinos-fuente.js y construye el DOM con createElement /
 * textContent. No usa innerHTML ni insertAdjacentHTML con datos de la fuente.
 *
 * Cada llamada a iniciarCatalogo cancela la anterior (AbortController), para
 * que no se acumulen listeners al volver a montar la pantalla.
 */

import {
  obtenerListadoVinos,
  obtenerDetalleVino,
  obtenerCepas,
  obtenerBodegas,
  usandoFixtures,
} from "../fuentes/vinos-fuente.js";

const TIPOS = ["tinto", "blanco", "rosado", "espumante"];

/** Controlador de la montura activa; se aborta al montar de nuevo. */
let montajeActual = null;

/**
 * Crea un elemento, opcionalmente con clase y texto (vía textContent).
 */
function el(tag, { clase, texto, tipo, nombre, valor, placeholder, atributos } = {}) {
  const elemento = document.createElement(tag);
  if (clase) elemento.className = clase;
  if (texto !== undefined) elemento.textContent = texto;
  if (tipo) elemento.type = tipo;
  if (nombre) elemento.name = nombre;
  if (valor !== undefined) elemento.value = valor;
  if (placeholder !== undefined) elemento.placeholder = placeholder;
  if (atributos) {
    for (const [key, value] of Object.entries(atributos)) {
      elemento.setAttribute(key, value);
    }
  }
  return elemento;
}

/**
 * Elimina todos los nodos hijos de un elemento sin usar innerHTML.
 */
function vaciar(elemento) {
  while (elemento.firstChild) {
    elemento.removeChild(elemento.firstChild);
  }
}

/**
 * Muestra un mensaje de error tal cual (sin modificar) en el elemento de alerta.
 */
function mostrarError(alerta, mensaje) {
  alerta.hidden = false;
  alerta.textContent = mensaje;
}

function ocultarError(alerta) {
  alerta.hidden = true;
  alerta.textContent = "";
}

/**
 * Renderiza el detalle de un vino en el panel modal.
 * Muestra los valores tal como los devuelve la fuente, sin sumar ni calcular.
 */
function renderizarDetalle(modal, detalle) {
  const panel = modal.querySelector(".detalle-panel");
  vaciar(panel);

  panel.appendChild(el("h2", { texto: `Detalle - ${detalle.nombre}` }));

  const fila = (etiqueta, valor) => {
    const div = el("div", { clase: "detalle-fila" });
    div.appendChild(el("span", { clase: "detalle-label", texto: `${etiqueta}: ` }));
    div.appendChild(el("span", { texto: String(valor) }));
    return div;
  };

  panel.appendChild(fila("Código", detalle.cod_vino));
  panel.appendChild(fila("Nombre", detalle.nombre));
  panel.appendChild(fila("Tipo", detalle.tipo));
  panel.appendChild(fila("Añada", detalle.anada));
  panel.appendChild(fila("Volumen (ml)", detalle.volumen_ml));
  panel.appendChild(fila("Graduación", detalle.graduacion));
  panel.appendChild(fila("Precio", `$${detalle.precio}`));

  const bodega = detalle.bodega || {};
  panel.appendChild(fila("Bodega CUIT", bodega.cuit));
  panel.appendChild(fila("Bodega", bodega.razon_social));

  panel.appendChild(el("h3", { texto: "Composición de cepas" }));
  const compLista = el("ul", { clase: "detalle-lista" });
  (detalle.composicion || []).forEach((c) => {
    compLista.appendChild(el("li", { texto: `${c.nombre} (${c.tipo}): ${c.porcentaje}%` }));
  });
  panel.appendChild(compLista);

  panel.appendChild(el("h3", { texto: "Maridajes sugeridos" }));
  const marLista = el("ul", { clase: "detalle-lista" });
  (detalle.maridajes || []).forEach((m) => {
    marLista.appendChild(
      el("li", { texto: `${m.nombre} - temperatura de servicio: ${m.temperatura_servicio}°C` })
    );
  });
  panel.appendChild(marLista);

  const stock = detalle.stock || {};
  panel.appendChild(fila("Stock depósito", stock.deposito));
  panel.appendChild(fila("Stock salas", stock.salas));
  panel.appendChild(fila("Stock total", stock.total));

  const btnCerrar = el("button", { clase: "btn btn-primary", texto: "Cerrar" });
  btnCerrar.addEventListener("click", () => {
    modal.hidden = true;
  });
  panel.appendChild(btnCerrar);

  modal.hidden = false;
}

/**
 * Crea y devuelve el panel modal de detalle (oculto por defecto).
 */
function crearModalDetalle() {
  const overlay = el("div", { clase: "detalle-modal-overlay" });
  overlay.hidden = true;

  const modal = el("div", { clase: "detalle-modal" });
  modal.appendChild(el("div", { clase: "detalle-panel" }));
  overlay.appendChild(modal);

  overlay.addEventListener("click", (ev) => {
    if (ev.target === overlay) {
      overlay.hidden = true;
    }
  });

  return overlay;
}

/**
 * Renderiza la tabla de vinos y el paginador.
 * Crea la tabla y su tbody en cada render: no se reutilizan nodos entre renders.
 *
 * @param {object} ctx - Referencias del montaje: contenedor, modal, paginador, alerta, onPagina, onDetalle.
 * @param {object} datos - { items, page, page_size, total }
 */
function renderizarListado(ctx, datos) {
  const { contenedor, modal, paginador } = ctx;

  // Borra la tabla previa antes de crear la nueva
  const tablaPrevia = contenedor.querySelector(".tabla-vinos");
  if (tablaPrevia) {
    contenedor.removeChild(tablaPrevia);
  }
  vaciar(paginador);

  if (!datos || !Array.isArray(datos.items)) {
    return;
  }

  const tabla = el("table", { clase: "tabla-vinos" });
  const thead = el("thead");
  const filaEnc = el("tr");
  ["Código", "Nombre", "Tipo", "Añada", "Precio", "Bodega", "Detalle"].forEach((texto) => {
    filaEnc.appendChild(el("th", { texto }));
  });
  thead.appendChild(filaEnc);
  tabla.appendChild(thead);

  const tbody = el("tbody");
  datos.items.forEach((vino) => {
    const tr = el("tr");
    const celdas = [
      vino.cod_vino,
      vino.nombre,
      vino.tipo,
      vino.anada,
      `$${vino.precio}`,
      vino.bodega_razon_social,
    ];
    celdas.forEach((texto) => {
      tr.appendChild(el("td", { texto: String(texto) }));
    });

    const tdAccion = el("td");
    const btnDetalle = el("button", { clase: "btn btn-sm", texto: "Detalle" });
    btnDetalle.addEventListener("click", () => ctx.onDetalle(vino.cod_vino));
    tdAccion.appendChild(btnDetalle);
    tr.appendChild(tdAccion);

    tbody.appendChild(tr);
  });
  tabla.appendChild(tbody);

  contenedor.insertBefore(tabla, modal);

  // Paginador
  const paginaActual = datos.page || 1;
  const pageSize = datos.page_size || 20;
  const total = datos.total || 0;
  const totalPaginas = Math.max(1, Math.ceil(total / pageSize));

  const btnAnterior = el("button", { clase: "btn btn-sm btn-paginador", texto: "Anterior" });
  btnAnterior.disabled = paginaActual <= 1;
  btnAnterior.addEventListener("click", () => ctx.onPagina(paginaActual - 1));

  const lblPagina = el("span", { clase: "pagina-actual", texto: `Página ${paginaActual} de ${totalPaginas}` });

  const btnSiguiente = el("button", { clase: "btn btn-sm btn-paginador", texto: "Siguiente" });
  btnSiguiente.disabled = paginaActual >= totalPaginas;
  btnSiguiente.addEventListener("click", () => ctx.onPagina(paginaActual + 1));

  paginador.appendChild(btnAnterior);
  paginador.appendChild(lblPagina);
  paginador.appendChild(btnSiguiente);
}

/**
 * Exportada: inicia la pantalla del catálogo dentro del contenedor dado.
 * Sin efectos al importar. Si ya había una pantalla montada, su listener se cancela.
 */
export async function iniciarCatalogo(contenedor) {
  // Cancela el montaje anterior: sus listeners (AbortSignal) dejan de responder
  if (montajeActual) {
    montajeActual.abort();
  }
  const controlador = new AbortController();
  montajeActual = controlador;
  const signal = controlador.signal;

  vaciar(contenedor);

  const estado = {
    filtros: { tipo: "", id_cepa: "", cuit_bodega: "", anada: "", nombre: "" },
    page: 1,
    page_size: 20,
  };

  const alerta = el("div", { clase: "alerta error", atributos: { role: "alert" } });
  alerta.hidden = true;

  const carga = el("div", { clase: "carga", texto: "Cargando..." });
  carga.hidden = true;

  if (usandoFixtures()) {
    contenedor.appendChild(el("div", { clase: "banner simulado", texto: "Modo datos simulados" }));
  }

  contenedor.appendChild(alerta);
  contenedor.appendChild(carga);

  const modal = crearModalDetalle();
  contenedor.appendChild(modal);

  // Formulario de filtros
  const form = el("form", { clase: "filtros-form" });

  const selectTipo = el("select", { nombre: "tipo" });
  selectTipo.appendChild(el("option", { texto: "Todos los tipos", valor: "" }));
  TIPOS.forEach((t) => {
    selectTipo.appendChild(el("option", { texto: t.charAt(0).toUpperCase() + t.slice(1), valor: t }));
  });

  const selectCepa = el("select", { nombre: "id_cepa" });
  selectCepa.appendChild(el("option", { texto: "Todas las cepas", valor: "" }));

  const selectBodega = el("select", { nombre: "cuit_bodega" });
  selectBodega.appendChild(el("option", { texto: "Todas las bodegas", valor: "" }));

  const inputAnada = el("input", { nombre: "anada", tipo: "number", placeholder: "Añada" });
  const inputNombre = el("input", { nombre: "nombre", tipo: "text", placeholder: "Nombre" });
  const btnBuscar = el("button", { clase: "btn btn-primary", texto: "Buscar", tipo: "submit" });

  form.appendChild(el("label", { texto: "Tipo" }));
  form.appendChild(selectTipo);
  form.appendChild(el("label", { texto: "Cepa" }));
  form.appendChild(selectCepa);
  form.appendChild(el("label", { texto: "Bodega" }));
  form.appendChild(selectBodega);
  form.appendChild(el("label", { texto: "Añada" }));
  form.appendChild(inputAnada);
  form.appendChild(el("label", { texto: "Nombre" }));
  form.appendChild(inputNombre);
  form.appendChild(btnBuscar);

  contenedor.appendChild(form);

  const paginador = el("div", { clase: "paginador" });
  contenedor.appendChild(paginador);

  // Contexto compartido por los renders de este montaje
  const ctx = {
    contenedor,
    modal,
    paginador,
    alerta,
    onPagina: (nueva) => {
      if (!nueva || nueva < 1) return;
      estado.page = nueva;
      cargarListado();
    },
    onDetalle: async (cod) => {
      ocultarError(alerta);
      try {
        const detalle = await obtenerDetalleVino(cod);
        if (signal.aborted) return;
        renderizarDetalle(modal, detalle);
      } catch (error) {
        if (signal.aborted) return;
        mostrarError(alerta, error.message);
      }
    },
  };

  async function cargarSelectores() {
    carga.hidden = false;
    ocultarError(alerta);
    try {
      const [cepas, bodegas] = await Promise.all([obtenerCepas(), obtenerBodegas()]);
      if (signal.aborted) return;

      vaciar(selectCepa);
      selectCepa.appendChild(el("option", { texto: "Todas las cepas", valor: "" }));
      cepas.forEach((c) => {
        selectCepa.appendChild(el("option", { texto: c.nombre, valor: String(c.id_cepa) }));
      });

      vaciar(selectBodega);
      selectBodega.appendChild(el("option", { texto: "Todas las bodegas", valor: "" }));
      bodegas.forEach((b) => {
        selectBodega.appendChild(el("option", { texto: b.razon_social, valor: b.cuit }));
      });
    } catch (error) {
      if (signal.aborted) return;
      mostrarError(alerta, error.message);
    } finally {
      if (!signal.aborted) carga.hidden = true;
    }
  }

  async function cargarListado() {
    carga.hidden = false;
    ocultarError(alerta);
    try {
      const datos = await obtenerListadoVinos({
        ...estado.filtros,
        page: estado.page,
        page_size: estado.page_size,
      });
      if (signal.aborted) return;
      estado.page = datos.page || estado.page;
      estado.page_size = datos.page_size || estado.page_size;
      renderizarListado(ctx, datos);
    } catch (error) {
      if (signal.aborted) return;
      mostrarError(alerta, error.message);
      vaciar(paginador);
    } finally {
      if (!signal.aborted) carga.hidden = true;
    }
  }

  // Un único listener de envío por montaje; se quita al abortar
  form.addEventListener(
    "submit",
    (ev) => {
      ev.preventDefault();
      const formData = new FormData(form);
      estado.filtros = {
        tipo: formData.get("tipo") || "",
        id_cepa: formData.get("id_cepa") || "",
        cuit_bodega: formData.get("cuit_bodega") || "",
        anada: formData.get("anada") || "",
        nombre: formData.get("nombre") || "",
      };
      estado.page = 1;
      cargarListado();
    },
    { signal }
  );

  await cargarSelectores();
  if (signal.aborted) return;
  await cargarListado();
}