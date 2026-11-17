/**
 * Bodegas del Atuel - Pantalla: Transferencias de stock.
 *
 * Exporta iniciarTransferencias(contenedor). Construye el DOM con
 * document.createElement / textContent. No usa innerHTML con datos.
 * Cada llamada cancela la anterior con AbortController.
 */

import {
  listarTransferencias,
  obtenerTransferencia,
  crearTransferencia,
  agregarRenglonTransferencia,
  terminarTransferencia,
  procesarTransferencia,
} from "../api/transferencias.js";
import { listarSalas } from "../api/catalogos.js";
import { obtenerListadoVinos } from "../fuentes/vinos-fuente.js";

/**
 * Crea un elemento, opcionalmente con clase y texto (vía textContent).
 */
function el(tag, { clase, texto, tipo, nombre, valor, placeholder, id, atributos } = {}) {
  const elemento = document.createElement(tag);
  if (clase) elemento.className = clase;
  if (texto !== undefined) elemento.textContent = texto;
  if (tipo) elemento.type = tipo;
  if (nombre) elemento.name = nombre;
  if (valor !== undefined) elemento.value = valor;
  if (placeholder !== undefined) elemento.placeholder = placeholder;
  if (id) elemento.id = id;
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

/** Controlador de la montura activa; se aborta el anterior al montar. */
let montajeActual = null;

export function iniciarTransferencias(contenedor) {
  if (montajeActual) {
    montajeActual.abort();
  }
  const controlador = new AbortController();
  montajeActual = controlador;
  const signal = controlador.signal;

  vaciar(contenedor);

  let temporizadorVino = null;
  let detalleActual = null;
  let nroActual = null;
  let salas = [];
  let page = 1;
  const page_size = 10;
  let estadoFiltro = "";
  let idSalaFiltro = "";

  const h1 = el("h1", { texto: "Transferencias de stock" });
  contenedor.appendChild(h1);

  const alerta = el("div", { clase: "alerta", atributos: { role: "alert" } });
  alerta.hidden = true;
  contenedor.appendChild(alerta);

  function mostrarAlerta(mensaje, esExito = false) {
    alerta.hidden = false;
    alerta.textContent = mensaje;
    alerta.className = esExito ? "alerta alerta-exito" : "alerta error";
  }

  function limpiarAlerta() {
    alerta.hidden = true;
    alerta.textContent = "";
    alerta.className = "alerta";
  }

  // ---------- A) Bloque: Nueva transferencia ----------
  const seccionNueva = el("section", { clase: "card" });
  const h2Nueva = el("h2", { texto: "Nueva transferencia" });
  const labelSalaNueva = el("label", { clase: "label-buscar-vino", texto: "Sala de destino:", atributos: { for: "sala-nueva" } });
  const selectSalaNueva = el("select", { id: "sala-nueva", nombre: "id_sala" });
  selectSalaNueva.appendChild(el("option", { texto: "Seleccionar sala", valor: "" }));
  const btnCrear = el("button", { clase: "btn btn-primary", texto: "Crear transferencia", atributos: { type: "button" } });

  seccionNueva.appendChild(h2Nueva);
  seccionNueva.appendChild(labelSalaNueva);
  seccionNueva.appendChild(selectSalaNueva);
  seccionNueva.appendChild(btnCrear);
  contenedor.appendChild(seccionNueva);

  btnCrear.addEventListener("click", async () => {
    if (signal.aborted) return;
    limpiarAlerta();
    const valor = selectSalaNueva.value;
    if (valor === "") {
      mostrarAlerta("Seleccione una sala.");
      return;
    }
    btnCrear.disabled = true;
    try {
      const resp = await crearTransferencia({ id_sala: Number(valor) });
      if (signal.aborted) return;
      mostrarAlerta(`Transferencia ${resp.nro_transferencia} creada en confección.`, true);
      abrirDetalle(resp.nro_transferencia);
      cargarListado();
    } catch (error) {
      if (signal.aborted) return;
      mostrarAlerta(error.message);
    }
    btnCrear.disabled = false;
  }, { signal });

  // ---------- B) Bloque: Listado ----------
  const seccionListado = el("section", { clase: "card" });
  const h2Listado = el("h2", { texto: "Listado de transferencias" });

  const formFiltros = el("form", { clase: "filtros-form", atributos: { novalidate: "" } });
  const labelEstado = el("label", { texto: "Estado:" });
  const selectEstado = el("select", { nombre: "estado" });
  selectEstado.appendChild(el("option", { texto: "Todos", valor: "" }));
  selectEstado.appendChild(el("option", { texto: "En confección", valor: "en_confeccion" }));
  selectEstado.appendChild(el("option", { texto: "Terminado", valor: "terminado" }));
  selectEstado.appendChild(el("option", { texto: "Procesado", valor: "procesado" }));
  const labelSalaFiltro = el("label", { texto: "Sala:" });
  const selectSalaFiltro = el("select", { nombre: "id_sala" });
  selectSalaFiltro.appendChild(el("option", { texto: "Todas", valor: "" }));
  const btnFiltrar = el("button", { clase: "btn btn-primary", texto: "Filtrar", atributos: { type: "submit" } });

  formFiltros.appendChild(labelEstado);
  formFiltros.appendChild(selectEstado);
  formFiltros.appendChild(labelSalaFiltro);
  formFiltros.appendChild(selectSalaFiltro);
  formFiltros.appendChild(btnFiltrar);

  const barraAbrir = el("div", { clase: "barra-abrir" });
  const inputNro = el("input", { tipo: "number", placeholder: "N.º transferencia", atributos: { min: "1", step: "1" } });
  const btnAbrir = el("button", { clase: "btn btn-sm", texto: "Abrir", atributos: { type: "button" } });

  barraAbrir.appendChild(inputNro);
  barraAbrir.appendChild(btnAbrir);

  const tablaListado = el("table", { clase: "tabla-vinos" }); const theadListado = el("thead"); const trHeadListado = el("tr"); ["N.\u00ba", "Sala", "Fecha de confecci\u00f3n", "Estado", "Acci\u00f3n"].forEach((t) => trHeadListado.appendChild(el("th", { texto: t }))); theadListado.appendChild(trHeadListado); tablaListado.appendChild(theadListado);
  const tbodyListado = el("tbody");
  tablaListado.appendChild(tbodyListado);

  const paginador = el("div", { clase: "paginador" });
  const notaOrden = el("p", { clase: "nota-chica", texto: "Orden ascendente por número: las más nuevas están en las últimas páginas." });

  seccionListado.appendChild(h2Listado);
  seccionListado.appendChild(formFiltros);
  seccionListado.appendChild(barraAbrir);
  seccionListado.appendChild(tablaListado);
  seccionListado.appendChild(paginador);
  seccionListado.appendChild(notaOrden);
  contenedor.appendChild(seccionListado);

  btnAbrir.addEventListener("click", () => {
    if (signal.aborted) return;
    limpiarAlerta();
    const valor = inputNro.value.trim();
    if (valor === "") { return; }
    const nro = Number(valor);
    if (!Number.isInteger(nro) || nro <= 0) {
      mostrarAlerta("Ingrese un número de transferencia válido.");
      return;
    }
    abrirDetalle(nro);
  }, { signal });

  btnFiltrar.addEventListener("click", (ev) => {
    ev.preventDefault();
    if (signal.aborted) return;
    limpiarAlerta();
    page = 1;
    estadoFiltro = selectEstado.value;
    idSalaFiltro = selectSalaFiltro.value;
    cargarListado();
  }, { signal });

  async function cargarSalas() {
    try {
      salas = await listarSalas();
      if (signal.aborted) return;
      vaciar(selectSalaNueva);
      selectSalaNueva.appendChild(el("option", { texto: "Seleccionar sala", valor: "" }));
      salas.forEach((s) => {
        selectSalaNueva.appendChild(el("option", { texto: `Sala ${s.id_sala} - ${s.calle} ${s.numero}`, valor: String(s.id_sala) }));
      });
      vaciar(selectSalaFiltro);
      selectSalaFiltro.appendChild(el("option", { texto: "Todas", valor: "" }));
      salas.forEach((s) => {
        selectSalaFiltro.appendChild(el("option", { texto: `Sala ${s.id_sala} - ${s.calle} ${s.numero}`, valor: String(s.id_sala) }));
      });
    } catch (error) {
      if (signal.aborted) return;
      mostrarAlerta(error.message);
    }
  }

  async function cargarListado() {
    try {
      const datos = await listarTransferencias({
        page, page_size, estado: estadoFiltro || undefined, id_sala: idSalaFiltro || undefined,
      });
      if (signal.aborted) return;
      vaciar(tbodyListado);
      if (!datos.items || datos.items.length === 0) {
        const tr = el("tr");
        const td = el("td", { atributos: { colspan: "5" } });
        td.textContent = "Sin resultados";
        tr.appendChild(td);
        tbodyListado.appendChild(tr);
      } else {
        datos.items.forEach((t) => {
          const tr = el("tr");
          tr.appendChild(el("td", { texto: String(t.nro_transferencia ?? "") }));
          tr.appendChild(el("td", { texto: String(t.id_sala ?? "") }));
          tr.appendChild(el("td", { texto: String(t.fecha_confeccion ?? "") }));
          const tdEstado = el("td");
          const spanEstado = el("span", { clase: `estado estado-${t.estado}`, texto: String(t.estado) });
          tdEstado.appendChild(spanEstado);
          tr.appendChild(tdEstado);
          const tdAccion = el("td");
          const btnVer = el("button", { clase: "btn btn-sm", texto: "Ver", atributos: { type: "button" } });
          btnVer.addEventListener("click", () => { abrirDetalle(t.nro_transferencia); }, { signal });
          tdAccion.appendChild(btnVer);
          tr.appendChild(tdAccion);
          tbodyListado.appendChild(tr);
        });
      }
      vaciar(paginador);
      const total = datos.total || 0;
      const totalPaginas = Math.max(1, Math.ceil(total / page_size));
      const btnAnterior = el("button", { clase: "btn btn-sm btn-paginador", texto: "Anterior", atributos: { type: "button" } });
      btnAnterior.disabled = page <= 1;
      btnAnterior.addEventListener("click", () => { if (page > 1) { page--; cargarListado(); } }, { signal });
      const lblPagina = el("span", { clase: "pagina-actual", texto: `Página ${page} de ${totalPaginas}` });
      const btnSiguiente = el("button", { clase: "btn btn-sm btn-paginador", texto: "Siguiente", atributos: { type: "button" } });
      btnSiguiente.disabled = page >= totalPaginas;
      btnSiguiente.addEventListener("click", () => { if (page < totalPaginas) { page++; cargarListado(); } }, { signal });
      paginador.appendChild(btnAnterior);
      paginador.appendChild(lblPagina);
      paginador.appendChild(btnSiguiente);
    } catch (error) {
      if (signal.aborted) return;
      mostrarAlerta(error.message);
    }
  }

  // ---------- C) Bloque: Detalle ----------
  const seccionDetalle = el("section", { clase: "card", atributos: { hidden: "" } });
  const h2Detalle = el("h2", { texto: "Detalle de transferencia" });
  const spanNro = el("span", { clase: "campo-nro" });
  const spanSala = el("span", { clase: "campo-sala" });
  const spanFecha = el("span", { clase: "campo-fecha" });
  const spanEstado = el("span", { clase: "campo-estado" });

  const pNro = el("p");
  pNro.appendChild(el("strong", { texto: "N.º: " }));
  pNro.appendChild(spanNro);

  const pSala = el("p");
  pSala.appendChild(el("strong", { texto: "Sala: " }));
  pSala.appendChild(spanSala);

  const pFecha = el("p");
  pFecha.appendChild(el("strong", { texto: "Fecha de confección: " }));
  pFecha.appendChild(spanFecha);

  const pEstado = el("p");
  pEstado.appendChild(el("strong", { texto: "Estado: " }));
  pEstado.appendChild(spanEstado);

  const tablaRenglones = el("table", { clase: "tabla-vinos" }); const theadRenglones = el("thead"); const trHeadRenglones = el("tr"); ["C\u00f3digo de vino", "Cantidad"].forEach((t) => trHeadRenglones.appendChild(el("th", { texto: t }))); theadRenglones.appendChild(trHeadRenglones); tablaRenglones.appendChild(theadRenglones);
  const tbodyRenglones = el("tbody");
  tablaRenglones.appendChild(tbodyRenglones);

  const accionesEstado = el("div", { clase: "acciones-estado" });
  const btnTerminar = el("button", { clase: "btn btn-primary", texto: "Terminar", atributos: { type: "button" } });
  const btnProcesar = el("button", { clase: "btn btn-primary", texto: "Procesar", atributos: { type: "button" } });
  const btnCerrar = el("button", { clase: "btn btn-sm", texto: "Cerrar detalle", atributos: { type: "button" } });

  accionesEstado.appendChild(btnTerminar);
  accionesEstado.appendChild(btnProcesar);
  accionesEstado.appendChild(btnCerrar);

  const bloqueBuscarVino = el("div", { clase: "bloque-buscar-vino" });
  const labelBuscar = el("label", { clase: "label-buscar-vino", texto: "Buscar vino:", atributos: { for: "buscar-vino-detalle" } });
  const inputBuscarVinoDetalle = el("input", { clase: "buscador-input", tipo: "search", id: "buscar-vino-detalle", placeholder: "Buscar vino por nombre", atributos: { "aria-label": "Buscar vino por nombre" } });
  const listaVinosDetalle = el("ul", { clase: "resultados-vinos" });
  const errorAgregarDetalle = el("p", { clase: "alerta error" });
  errorAgregarDetalle.hidden = true;

  bloqueBuscarVino.appendChild(labelBuscar);
  bloqueBuscarVino.appendChild(inputBuscarVinoDetalle);
  bloqueBuscarVino.appendChild(listaVinosDetalle);
  bloqueBuscarVino.appendChild(errorAgregarDetalle);

  seccionDetalle.appendChild(h2Detalle);
  seccionDetalle.appendChild(pNro);
  seccionDetalle.appendChild(pSala);
  seccionDetalle.appendChild(pFecha);
  seccionDetalle.appendChild(pEstado);
  seccionDetalle.appendChild(el("h3", { texto: "Renglones" }));
  seccionDetalle.appendChild(tablaRenglones);
  seccionDetalle.appendChild(accionesEstado);
  seccionDetalle.appendChild(bloqueBuscarVino);
  contenedor.appendChild(seccionDetalle);

  btnCerrar.addEventListener("click", () => {
    if (signal.aborted) return;
    seccionDetalle.hidden = true;
    detalleActual = null;
    nroActual = null;
  }, { signal });

  btnTerminar.addEventListener("click", async () => {
    if (signal.aborted) return;
    limpiarAlerta();
    btnTerminar.disabled = true;
    btnProcesar.disabled = true;
    try {
      await terminarTransferencia(nroActual);
      if (signal.aborted) return;
      mostrarAlerta("Transferencia terminada.", true); cargarListado();
      await recargarDetalle();
    } catch (error) {
      if (signal.aborted) return;
      mostrarAlerta(error.message);
      await recargarDetalle();
    }
    aplicarEstado();
  }, { signal });

  btnProcesar.addEventListener("click", async () => {
    if (signal.aborted) return;
    limpiarAlerta();
    btnTerminar.disabled = true;
    btnProcesar.disabled = true;
    try {
      await procesarTransferencia(nroActual);
      if (signal.aborted) return;
      mostrarAlerta("Transferencia procesada.", true); cargarListado();
      await recargarDetalle();
    } catch (error) {
      if (signal.aborted) return;
      mostrarAlerta(error.message);
      await recargarDetalle();
    }
    aplicarEstado();
  }, { signal });

  let consultaVinoDetalle = 0;

  function limpiarListaVinosDetalle() {
    while (listaVinosDetalle.firstChild) {
      listaVinosDetalle.removeChild(listaVinosDetalle.firstChild);
    }
  }

  function renderVinosDetalle(items) {
    limpiarListaVinosDetalle();
    if (items.length === 0) {
      const li = el("li", { clase: "resultado-vino" });
      li.textContent = "Sin resultados";
      listaVinosDetalle.appendChild(li);
      return;
    }
    items.forEach((v) => {
      const li = el("li", { clase: "resultado-vino" });
      li.appendChild(el("span", { texto: `${v.nombre} (${v.tipo}, ${v.anada}) - c\u00f3d. ${v.cod_vino}` }));
      const inputCantidad = el("input", { tipo: "number", valor: "1", atributos: { min: "1", step: "1", "aria-label": "Cantidad" } });
      const btnAgregar = el("button", { clase: "btn btn-sm", texto: "Agregar", atributos: { type: "button" } });
      btnAgregar.addEventListener("click", async () => {
        if (signal.aborted) return;
        limpiarAlerta();
        const valor = inputCantidad.value.trim();
        if (valor === "") {
          errorAgregarDetalle.textContent = "La cantidad debe ser un entero mayor a 0.";
          errorAgregarDetalle.hidden = false;
          return;
        }
        const cantidad = Number(valor);
        if (!Number.isInteger(cantidad) || cantidad < 1) {
          errorAgregarDetalle.textContent = "La cantidad debe ser un entero mayor a 0.";
          errorAgregarDetalle.hidden = false;
          return;
        }
        errorAgregarDetalle.hidden = true;
        btnAgregar.disabled = true;
        try {
          await agregarRenglonTransferencia(nroActual, { cod_vino: v.cod_vino, cantidad });
          if (signal.aborted) return;
          mostrarAlerta("Renglón agregado.", true);
          await recargarDetalle();
        } catch (error) {
          if (signal.aborted) return;
          mostrarAlerta(error.message);
          await recargarDetalle();
        }
        btnAgregar.disabled = false;
      }, { signal });
      li.appendChild(inputCantidad);
      li.appendChild(btnAgregar);
      listaVinosDetalle.appendChild(li);
    });
  }

  inputBuscarVinoDetalle.addEventListener(
    "input",
    (ev) => {
      clearTimeout(temporizadorVino);
      const texto = ev.target.value.trim();
      if (texto.length < 2) {
        consultaVinoDetalle++;
        limpiarListaVinosDetalle();
        errorAgregarDetalle.textContent = "Escriba al menos 2 caracteres";
        errorAgregarDetalle.hidden = false;
        return;
      }
      temporizadorVino = setTimeout(async () => {
        const consulta = ++consultaVinoDetalle;
        try {
          const datos = await obtenerListadoVinos({ nombre: texto, page: 1, page_size: 20 });
          if (signal.aborted) return;
          if (consulta !== consultaVinoDetalle) return;
          errorAgregarDetalle.hidden = true; renderVinosDetalle(datos.items);
        } catch (error) {
          if (signal.aborted) return;
          if (consulta !== consultaVinoDetalle) return;
          limpiarListaVinosDetalle();
          errorAgregarDetalle.textContent = error.message;
          errorAgregarDetalle.hidden = false;
        }
      }, 300);
    },
    { signal }
  );

  function abrirDetalle(nro) {
    nroActual = nro;
    seccionDetalle.hidden = false;
    recargarDetalle();
  }

  async function recargarDetalle() {
    try {
      const detalle = await obtenerTransferencia(nroActual);
      if (signal.aborted) return;
      detalleActual = detalle;
      spanNro.textContent = String(detalle.nro_transferencia ?? "");
      spanSala.textContent = String(detalle.id_sala ?? "");
      spanFecha.textContent = String(detalle.fecha_confeccion ?? "");
      spanEstado.textContent = String(detalle.estado ?? "");
      spanEstado.className = `estado estado-${detalle.estado}`;
      vaciar(tbodyRenglones);
      if (!detalle.renglones || detalle.renglones.length === 0) {
        const tr = el("tr");
        const td = el("td", { atributos: { colspan: "2" } });
        td.textContent = "Sin renglones";
        tr.appendChild(td);
        tbodyRenglones.appendChild(tr);
      } else {
        detalle.renglones.forEach((r) => {
          const tr = el("tr");
          tr.appendChild(el("td", { texto: String(r.cod_vino ?? "") }));
          tr.appendChild(el("td", { texto: String(r.cantidad ?? "") }));
          tbodyRenglones.appendChild(tr);
        });
      }
      aplicarEstado();
    } catch (error) {
      if (signal.aborted) return;
      mostrarAlerta(error.message);
      seccionDetalle.hidden = true;
    }
  }

  function aplicarEstado() {
    const estado = detalleActual ? detalleActual.estado : "";
    const enConfeccion = estado === "en_confeccion";
    const terminado = estado === "terminado";
    const procesado = estado === "procesado";

    btnTerminar.disabled = procesado || !enConfeccion;
    btnProcesar.disabled = procesado || !terminado;

    const buscando = inputBuscarVinoDetalle;
    const btnsAgregar = listaVinosDetalle.querySelectorAll("button");
    buscando.disabled = procesado || !enConfeccion;
    btnsAgregar.forEach((b) => { b.disabled = procesado || !enConfeccion; });

    const notaExistente = accionesEstado.querySelector(".nota-chica"); if (!procesado && notaExistente) { notaExistente.remove(); } if (procesado) {
      const textoEstado = el("span", { clase: "nota-chica", texto: "Transferencia procesada: no admite más cambios." });
      if (!accionesEstado.querySelector(".nota-chica")) {
        accionesEstado.appendChild(textoEstado);
      }
    }
  }

  cargarSalas();
  cargarListado();

  return {
    destruir() {
      controlador.abort();
      clearTimeout(temporizadorVino);
      montajeActual = null;
      vaciar(contenedor);
    },
  };
}
