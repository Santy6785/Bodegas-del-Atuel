/**
 * Bodegas del Atuel - Pantalla: Nueva Venta (Paso 1 de 8).
 *
 * Exporta iniciarNuevaVenta(contenedor). Construye el DOM con
 * document.createElement / textContent. No usa innerHTML con datos.
 * Cada llamada cancela la anterior con AbortController.
 */

import { montarBuscadorClientes } from "../components/buscador-clientes.js";
import {
  obtenerListadoVinos,
  usandoFixtures,
} from "../fuentes/vinos-fuente.js";
import { crearComprobante } from "../api/comprobantes.js";

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

/** Controlador de la montura activa; se aborta al montar de nuevo. */
let montajeActual = null;

/**
 * Exportada: inicia la pantalla Nueva Venta dentro del contenedor dado.
 * Por ahora solo monta el bloque "Cliente" con el buscador existente.
 * Devuelve { destruir } para liberar listeners al cambiar de ruta.
 */
export function iniciarNuevaVenta(contenedor) {
  // Cancela el montaje anterior: sus listeners dejan de responder
  if (montajeActual) {
    montajeActual.abort();
  }
  const controlador = new AbortController();
  montajeActual = controlador;
  const signal = controlador.signal;

  vaciar(contenedor);

  const seccion = document.createElement("section");
  seccion.className = "card";

  const h2 = document.createElement("h2");
  h2.textContent = "Nueva Venta";

  const bloqueCliente = document.createElement("div");
  bloqueCliente.className = "bloque-cliente";

  const etiqueta = document.createElement("p");
  etiqueta.textContent = "Cliente:";

  const detalle = document.createElement("p");
  detalle.className = "cliente-seleccionado";
  detalle.textContent = "Ninguno seleccionado";

  seccion.append(h2, bloqueCliente);
  bloqueCliente.append(etiqueta, detalle);
  contenedor.appendChild(seccion);

  // Estado de la pantalla
  let clienteSeleccionado = null;
  let idSala = null;
  let carrito = [];

  const buscador = document.createElement("div");
  bloqueCliente.appendChild(buscador);

  const control = montarBuscadorClientes(buscador, (cliente) => {
    if (signal.aborted) return;
    clienteSeleccionado = cliente;
    detalle.textContent = `${cliente.apellido_razon_social} (id ${cliente.id_cliente})`;
  });

  // ---------- Bloque: Sala de venta ----------
  const bloqueSala = document.createElement("div");
  bloqueSala.className = "bloque-sala";

  const labelSala = el("label", {
    clase: "label-sala",
    texto: "Sala de venta:",
    atributos: { for: "id-sala" },
  });

  const inputSala = el("input", {
    tipo: "number",
    id: "id-sala",
    nombre: "id_sala",
    valor: "",
    placeholder: "ID de sala",
    atributos: { min: "1", step: "1" },
  });

  const errorSala = el("p", {
    clase: "error",
    texto: "Ingrese un ID de sala válido",
  });
  errorSala.hidden = true;

  function validarYSigueSala() {
    if (signal.aborted) return;
    const valor = inputSala.value.trim();
    if (valor === "") {
      idSala = null;
      errorSala.hidden = false;
      return;
    }
    const entero = Number(valor);
    if (!Number.isInteger(entero) || entero <= 0) {
      idSala = null;
      errorSala.hidden = false;
      return;
    }
    idSala = entero;
    errorSala.hidden = true;
  }

  inputSala.addEventListener("change", validarYSigueSala, { signal });
  inputSala.addEventListener("blur", validarYSigueSala, { signal });

  bloqueSala.appendChild(labelSala);
  bloqueSala.appendChild(inputSala);
  bloqueSala.appendChild(errorSala);
  seccion.appendChild(bloqueSala);

  // ---------- Bloque: Buscar vino ----------
  const bloqueBuscarVino = document.createElement("div");
  bloqueBuscarVino.className = "bloque-buscar-vino";

  const labelBuscarVino = el("label", {
    clase: "label-buscar-vino",
    texto: "Buscar vino:",
    atributos: { for: "buscar-vino" },
  });

  const inputBuscarVino = el("input", {
    tipo: "search",
    id: "buscar-vino",
    placeholder: "Nombre del vino",
    atributos: { "aria-label": "Buscar vino por nombre" },
  });

  const listaVinos = el("ul", { clase: "resultados-vinos" });
  listaVinos.setAttribute("role", "listbox");

  const errorBuscarVino = el("p", { clase: "error" });
  errorBuscarVino.hidden = true;

  const errorAgregar = el("p", { clase: "error" });
  errorAgregar.hidden = true;

  let temporizadorVino = null;
  let consultaVino = 0;

  function limpiarListaVinos() {
    while (listaVinos.firstChild) {
      listaVinos.removeChild(listaVinos.firstChild);
    }
  }

  function renderVinos(items) {
    limpiarListaVinos();
    items.forEach((v) => {
      const li = el("li", { clase: "resultado-vino" });
      li.appendChild(
        el("span", { texto: `${v.nombre} (${v.tipo}, ${v.anada}) - $${v.precio}` })
      );

      const inputCantidad = el("input", {
        tipo: "number",
        valor: "1",
        atributos: { min: "1", step: "1" },
      });

      const btnAgregar = el("button", {
        texto: "Agregar",
        atributos: { type: "button" },
      });
      btnAgregar.addEventListener(
        "click",
        () => {
          if (signal.aborted) return;
          const valorCantidad = inputCantidad.value.trim();
          if (valorCantidad === "") {
            errorAgregar.textContent = "La cantidad debe ser un entero mayor a 0";
            errorAgregar.hidden = false;
            return;
          }
          const cantidad = Number(valorCantidad);
          if (!Number.isInteger(cantidad) || cantidad < 1) {
            errorAgregar.textContent = "La cantidad debe ser un entero mayor a 0";
            errorAgregar.hidden = false;
            return;
          }
          errorAgregar.hidden = true;

          const existente = carrito.find((r) => r.cod_vino === v.cod_vino);
          if (existente) {
            existente.cantidad += cantidad;
          } else {
            carrito.push({
              cod_vino: v.cod_vino,
              nombre: v.nombre,
              precio: v.precio,
              cantidad,
            });
          }
          renderCarrito();
        },
        { signal }
      );

      li.appendChild(inputCantidad);
      li.appendChild(btnAgregar);
      listaVinos.appendChild(li);
    });
  }

  async function buscarVino(texto) {
    const consulta = ++consultaVino;
    errorBuscarVino.hidden = true;
    limpiarListaVinos();
    try {
      const datos = await obtenerListadoVinos({
        nombre: texto,
        page: 1,
        page_size: 20,
      });
      if (signal.aborted) return;
      if (consulta !== consultaVino) return;
      renderVinos(datos.items);
    } catch (error) {
      if (signal.aborted) return;
      if (consulta !== consultaVino) return;
      limpiarListaVinos();
      errorBuscarVino.textContent = error.message;
      errorBuscarVino.hidden = false;
    }
  }

  inputBuscarVino.addEventListener(
    "input",
    (ev) => {
      clearTimeout(temporizadorVino);
      const texto = ev.target.value.trim();
      if (texto.length < 2) {
        consultaVino++;
        limpiarListaVinos();
        errorBuscarVino.textContent = "Escriba al menos 2 caracteres";
        errorBuscarVino.hidden = false;
        return;
      }
      temporizadorVino = setTimeout(() => buscarVino(texto), 300);
    },
    { signal }
  );

  bloqueBuscarVino.appendChild(labelBuscarVino);
  bloqueBuscarVino.appendChild(inputBuscarVino);
  bloqueBuscarVino.appendChild(listaVinos);
  bloqueBuscarVino.appendChild(errorBuscarVino);
  bloqueBuscarVino.appendChild(errorAgregar);
  seccion.appendChild(bloqueBuscarVino);

  // ---------- Bloque: Renglones de la venta ----------
  const bloqueRenglones = document.createElement("div");
  bloqueRenglones.className = "bloque-renglones";

  const tituloRenglones = el("h3", { texto: "Renglones de la venta" });

  const tablaRenglones = el("table", { clase: "tabla-renglones" });
  const thead = el("thead");
  const filaEnc = el("tr");
  ["Código", "Vino", "Cantidad", "Precio unitario", "Quitar"].forEach((texto) => {
    filaEnc.appendChild(el("th", { texto }));
  });
  thead.appendChild(filaEnc);
  tablaRenglones.appendChild(thead);

  const tbody = el("tbody");
  tablaRenglones.appendChild(tbody);

  bloqueRenglones.appendChild(tituloRenglones);
  bloqueRenglones.appendChild(tablaRenglones);
  seccion.appendChild(bloqueRenglones);

  // ---------- Bloque: Confirmar venta ----------
  const bloqueConfirmar = document.createElement("div");
  bloqueConfirmar.className = "bloque-confirmar";

  const btnConfirmar = el("button", {
    clase: "btn btn-primary",
    texto: "Confirmar venta",
    atributos: { type: "button" },
  });

  if (usandoFixtures()) {
    btnConfirmar.disabled = true;
    btnConfirmar.textContent = "No disponible en modo simulado";
  }

  const errorConfirmar = el("p", { clase: "error" });
  errorConfirmar.hidden = true;

  function mostrarErrorConfirmar(mensaje) {
    errorConfirmar.textContent = mensaje;
    errorConfirmar.hidden = false;
  }

  function ocultarErrorConfirmar() {
    errorConfirmar.hidden = true;
    errorConfirmar.textContent = "";
  }

  async function confirmarVenta() {
    if (signal.aborted) return;
    ocultarErrorConfirmar();

    if (!clienteSeleccionado) {
      mostrarErrorConfirmar("Seleccione un cliente.");
      return;
    }
    if (idSala === null || idSala === undefined) {
      mostrarErrorConfirmar("Ingrese un ID de sala válido.");
      return;
    }
    if (!carrito || carrito.length === 0) {
      mostrarErrorConfirmar("Agregue al menos un vino al carrito.");
      return;
    }

    btnConfirmar.disabled = true;
    try {
      const body = {
        id_cliente: clienteSeleccionado.id_cliente,
        id_sala: idSala,
        cod_vinos: carrito.map((r) => r.cod_vino),
        cantidades: carrito.map((r) => r.cantidad),
      };
      const comprobante = await crearComprobante(body);
      if (signal.aborted) return;
      mostrarComprobante(comprobante);
      vaciarCarritoYBusqueda();
    } catch (error) {
      if (signal.aborted) return;
      mostrarErrorConfirmar(error.message);
    } finally {
      if (signal.aborted) return;
      btnConfirmar.disabled = false;
    }
  }

  btnConfirmar.addEventListener("click", confirmarVenta, { signal });

  bloqueConfirmar.appendChild(btnConfirmar);
  bloqueConfirmar.appendChild(errorConfirmar);
  seccion.appendChild(bloqueConfirmar);

  // ---------- Sección: Comprobante emitido ----------
  const seccionComprobante = el("section", {
    clase: "seccion-comprobante",
    atributos: { hidden: "" },
  });
  const tituloComprobante = el("h2", { texto: "Comprobante emitido" });

  const campoNro = el("span", { clase: "campo-nro" });
  const campoFecha = el("span", { clase: "campo-fecha" });
  const campoSubtotal = el("span", { clase: "campo-subtotal" });
  const campoDescuento = el("span", { clase: "campo-descuento" });
  const campoTotal = el("span", { clase: "campo-total" });

  const pNro = el("p");
  pNro.appendChild(el("strong", { texto: "Nro: " }));
  pNro.appendChild(campoNro);

  const pFecha = el("p");
  pFecha.appendChild(el("strong", { texto: "Fecha: " }));
  pFecha.appendChild(campoFecha);

  const pSubtotal = el("p");
  pSubtotal.appendChild(el("strong", { texto: "Subtotal: " }));
  pSubtotal.appendChild(campoSubtotal);

  const pDescuento = el("p");
  pDescuento.appendChild(el("strong", { texto: "Descuento: " }));
  pDescuento.appendChild(campoDescuento);

  const pTotal = el("p");
  pTotal.appendChild(el("strong", { texto: "Total: " }));
  pTotal.appendChild(campoTotal);

  const tablaComprobante = el("table", { clase: "tabla-comprobante" });
  const theadComp = el("thead");
  const filaEncComp = el("tr");
  ["Código", "Cantidad", "Precio unitario", "Desc. %", "Subtotal"].forEach((texto) => {
    filaEncComp.appendChild(el("th", { texto }));
  });
  theadComp.appendChild(filaEncComp);
  tablaComprobante.appendChild(theadComp);

  const tbodyComp = el("tbody");
  tablaComprobante.appendChild(tbodyComp);

  const btnNuevaVenta = el("button", {
    clase: "btn btn-primary",
    texto: "Nueva venta",
    atributos: { type: "button" },
  });

  seccionComprobante.appendChild(tituloComprobante);
  seccionComprobante.appendChild(pNro);
  seccionComprobante.appendChild(pFecha);
  seccionComprobante.appendChild(pSubtotal);
  seccionComprobante.appendChild(pDescuento);
  seccionComprobante.appendChild(pTotal);
  seccionComprobante.appendChild(el("h3", { texto: "Renglones" }));
  seccionComprobante.appendChild(tablaComprobante);
  seccionComprobante.appendChild(btnNuevaVenta);
  seccion.appendChild(seccionComprobante);

  function mostrarComprobante(comprobante) {
    if (signal.aborted) return;
    campoNro.textContent = String(comprobante.nro_comprobante ?? "");
    campoFecha.textContent = String(comprobante.fecha ?? "");
    campoSubtotal.textContent = String(comprobante.subtotal ?? "");
    campoDescuento.textContent = String(comprobante.descuento ?? "");
    campoTotal.textContent = String(comprobante.total ?? "");

    while (tbodyComp.firstChild) {
      tbodyComp.removeChild(tbodyComp.firstChild);
    }
    (comprobante.renglones || []).forEach((r) => {
      const tr = el("tr");
      tr.appendChild(el("td", { texto: String(r.cod_vino ?? "") }));
      tr.appendChild(el("td", { texto: String(r.cantidad ?? "") }));
      tr.appendChild(el("td", { texto: String(r.precio_unitario ?? "") }));
      tr.appendChild(el("td", { texto: String(r.descuento_pct ?? "") }));
      tr.appendChild(el("td", { texto: String(r.subtotal ?? "") }));
      tbodyComp.appendChild(tr);
    });

    seccionComprobante.hidden = false;
  }

  function ocultarComprobante() {
    seccionComprobante.hidden = true;
    campoNro.textContent = "";
    campoFecha.textContent = "";
    campoSubtotal.textContent = "";
    campoDescuento.textContent = "";
    campoTotal.textContent = "";
    while (tbodyComp.firstChild) {
      tbodyComp.removeChild(tbodyComp.firstChild);
    }
  }

  function vaciarCarritoYBusqueda() {
    carrito = [];
    inputBuscarVino.value = "";
    limpiarListaVinos();
    renderCarrito();
  }

  btnNuevaVenta.addEventListener(
    "click",
    () => {
      if (signal.aborted) return;
      ocultarComprobante();
    },
    { signal }
  );

  function renderCarrito() {
    while (tbody.firstChild) {
      tbody.removeChild(tbody.firstChild);
    }
    if (carrito.length === 0) {
      const tr = el("tr");
      const td = el("td", { atributos: { colspan: "5" } });
      td.textContent = "Todavía no agregó vinos";
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }
    carrito.forEach((r) => {
      const tr = el("tr");
      tr.appendChild(el("td", { texto: String(r.cod_vino) }));
      tr.appendChild(el("td", { texto: r.nombre }));
      tr.appendChild(el("td", { texto: String(r.cantidad) }));
      tr.appendChild(el("td", { texto: String(r.precio) }));
      const tdQuitar = el("td");
      const btnQuitar = el("button", {
        texto: "Quitar",
        atributos: { type: "button" },
      });
      btnQuitar.addEventListener(
        "click",
        () => {
          if (signal.aborted) return;
          carrito = carrito.filter((item) => item.cod_vino !== r.cod_vino);
          renderCarrito();
        },
        { signal }
      );
      tdQuitar.appendChild(btnQuitar);
      tr.appendChild(tdQuitar);
      tbody.appendChild(tr);
    });
  }

  return {
    destruir() {
      control.destruir();
      clearTimeout(temporizadorVino);
      controlador.abort();
      montajeActual = null;
      vaciar(contenedor);
    },
  };
}
