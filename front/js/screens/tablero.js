/**
 * Bodegas del Atuel - Pantalla: Tablero de Control y Reportes.
 *
 * Exporta iniciarTablero(contenedor). Construye el DOM con
 * document.createElement / textContent. No usa innerHTML con datos.
 * Todos los cálculos y agregados provienen directamente de PostgreSQL.
 */

import {
  topVinos,
  ventasPorSala,
  vinosSinStock,
  transportistaActivo,
  trazabilidad,
} from "../api/reportes.js";
import { listarSalas } from "../api/catalogos.js";

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

function vaciar(elemento) {
  while (elemento.firstChild) {
    elemento.removeChild(elemento.firstChild);
  }
}

function crearTabla(columnas) {
  const tabla = el("table", { clase: "tabla-vinos" });
  const thead = el("thead");
  const tr = el("tr");
  columnas.forEach((col) => tr.appendChild(el("th", { texto: col })));
  thead.appendChild(tr);
  tabla.appendChild(thead);
  const tbody = el("tbody");
  tabla.appendChild(tbody);
  return { tabla, tbody };
}

function renderFilaMensaje(tbody, colspan, texto) {
  vaciar(tbody);
  const tr = el("tr");
  const td = el("td", { texto, atributos: { colspan: String(colspan) } });
  tr.appendChild(td);
  tbody.appendChild(tr);
}

let montajeActual = null;

export function iniciarTablero(contenedor) {
  if (montajeActual) {
    montajeActual.abort();
  }
  const controlador = new AbortController();
  montajeActual = controlador;
  const signal = controlador.signal;

  vaciar(contenedor);

  const encabezado = el("div", { clase: "tablero-header" });
  encabezado.appendChild(el("h1", { texto: "Tablero de control y reportes" }));
  const btnActualizarTodo = el("button", {
    clase: "btn btn-primary",
    texto: "Actualizar tablero",
    atributos: { type: "button" },
  });
  encabezado.appendChild(btnActualizarTodo);
  contenedor.appendChild(encabezado);

  // ---------- 1) Top 10 vinos más vendidos (S1) ----------
  const secTop = el("section", { clase: "card" });
  secTop.appendChild(el("h2", { texto: "Top vinos más vendidos" }));

  const formTop = el("form", { clase: "filtros-form", atributos: { novalidate: "" } });
  const lblLimite = el("label", { texto: "Cantidad a mostrar:", atributos: { for: "tablero-limite" } });
  const selectLimite = el("select", { id: "tablero-limite", nombre: "limite" });
  [
    { texto: "Top 5", valor: "5" },
    { texto: "Top 10", valor: "10" },
    { texto: "Top 20", valor: "20" },
    { texto: "Top 50", valor: "50" },
  ].forEach((op) => {
    const option = el("option", { texto: op.texto, valor: op.valor });
    if (op.valor === "10") option.selected = true;
    selectLimite.appendChild(option);
  });
  const btnTop = el("button", { clase: "btn btn-sm", texto: "Consultar", atributos: { type: "submit" } });
  formTop.append(lblLimite, selectLimite, btnTop);

  const errTop = el("p", { clase: "alerta error", atributos: { role: "alert" } });
  errTop.hidden = true;

  const { tabla: tablaTop, tbody: tbodyTop } = crearTabla([
    "Posición",
    "Código",
    "Vino",
    "Botellas vendidas",
  ]);
  secTop.append(formTop, errTop, tablaTop);
  contenedor.appendChild(secTop);

  async function cargarTop() {
    errTop.hidden = true;
    renderFilaMensaje(tbodyTop, 4, "Cargando...");
    try {
      const resp = await topVinos({ limite: Number(selectLimite.value) || 10 });
      if (signal.aborted) return;
      const items = resp.items || [];
      if (items.length === 0) {
        renderFilaMensaje(tbodyTop, 4, "Sin ventas registradas");
        return;
      }
      vaciar(tbodyTop);
      items.forEach((item) => {
        const tr = el("tr");
        tr.appendChild(el("td", { texto: String(item.posicion ?? "") }));
        tr.appendChild(el("td", { texto: String(item.cod_vino ?? "") }));
        tr.appendChild(el("td", { texto: String(item.nombre ?? "") }));
        tr.appendChild(el("td", { texto: String(item.botellas_vendidas ?? "") }));
        tbodyTop.appendChild(tr);
      });
    } catch (error) {
      if (signal.aborted) return;
      vaciar(tbodyTop);
      errTop.textContent = error.message;
      errTop.hidden = false;
    }
  }

  formTop.addEventListener(
    "submit",
    (ev) => {
      ev.preventDefault();
      if (signal.aborted) return;
      cargarTop();
    },
    { signal }
  );

  // ---------- 2) Ventas por sala del trimestre (S8) ----------
  const secVentasSala = el("section", { clase: "card" });
  secVentasSala.appendChild(el("h2", { texto: "Ventas por sala" }));

  const formVentas = el("form", { clase: "filtros-form", atributos: { novalidate: "" } });
  const lblPeriodo = el("label", { texto: "Período:", atributos: { for: "tablero-periodo" } });
  const selectPeriodo = el("select", { id: "tablero-periodo", nombre: "periodo" });
  [
    { texto: "Último trimestre", valor: "ultimo_trimestre" },
    { texto: "Histórico completo", valor: "" },
    { texto: "Rango de fechas", valor: "rango" },
  ].forEach((op) => selectPeriodo.appendChild(el("option", { texto: op.texto, valor: op.valor })));

  const lblDesde = el("label", { texto: "Desde:", atributos: { for: "tablero-desde" } });
  const inputDesde = el("input", { tipo: "date", id: "tablero-desde", nombre: "fecha_desde" });
  const lblHasta = el("label", { texto: "Hasta:", atributos: { for: "tablero-hasta" } });
  const inputHasta = el("input", { tipo: "date", id: "tablero-hasta", nombre: "fecha_hasta" });

  function actualizarVisibilidadFechas() {
    const esRango = selectPeriodo.value === "rango";
    lblDesde.hidden = !esRango;
    inputDesde.hidden = !esRango;
    lblHasta.hidden = !esRango;
    inputHasta.hidden = !esRango;
  }
  actualizarVisibilidadFechas();

  const btnVentas = el("button", { clase: "btn btn-sm", texto: "Consultar", atributos: { type: "submit" } });
  formVentas.append(lblPeriodo, selectPeriodo, lblDesde, inputDesde, lblHasta, inputHasta, btnVentas);

  const errVentas = el("p", { clase: "alerta error", atributos: { role: "alert" } });
  errVentas.hidden = true;

  const graficoVentas = el("div", { clase: "grafico-barras", atributos: { role: "img", "aria-label": "Gráfico de ventas por sala" } });
  const { tabla: tablaVentas, tbody: tbodyVentas } = crearTabla([
    "Sala",
    "Dirección",
    "Monto facturado",
  ]);
  secVentasSala.append(formVentas, errVentas, graficoVentas, tablaVentas);
  contenedor.appendChild(secVentasSala);

  selectPeriodo.addEventListener(
    "change",
    () => {
      if (signal.aborted) return;
      actualizarVisibilidadFechas();
      if (selectPeriodo.value !== "rango") {
        cargarVentasSala();
      }
    },
    { signal }
  );

  async function cargarVentasSala() {
    errVentas.hidden = true;
    const modo = selectPeriodo.value;
    const params = {};
    if (modo === "ultimo_trimestre") {
      params.periodo = "ultimo_trimestre";
    } else if (modo === "rango") {
      if (inputDesde.value) params.fecha_desde = inputDesde.value;
      if (inputHasta.value) params.fecha_hasta = inputHasta.value;
    }

    vaciar(graficoVentas);
    vaciar(graficoVentas);
    renderFilaMensaje(tbodyVentas, 3, "Cargando...");
    try {
      const resp = await ventasPorSala(params);
      if (signal.aborted) return;
      const items = resp.items || [];
      if (items.length === 0) {
        renderFilaMensaje(tbodyVentas, 3, "Sin salas registradas");
        return;
      }
      vaciar(graficoVentas);
      graficoVentas.style.setProperty("--max", String(items[0].monto_total ?? 0));
      vaciar(tbodyVentas);
      items.forEach((s) => {
        const etiquetaSala = `Sala ${s.id_sala ?? ""}`;
        const montoTexto = `${s.monto_total ?? "0.00"}`;

        const filaBarra = el("div", { clase: "barra-fila" });
        filaBarra.appendChild(el("span", { clase: "barra-etiqueta", texto: etiquetaSala }));
        const pista = el("div", { clase: "barra-pista" });
        const relleno = el("div", { clase: "barra-relleno" });
        relleno.style.setProperty("--val", String(s.monto_total ?? 0));
        pista.appendChild(relleno);
        filaBarra.appendChild(pista);
        filaBarra.appendChild(el("span", { clase: "barra-valor", texto: montoTexto }));
        graficoVentas.appendChild(filaBarra);

        const tr = el("tr");
        tr.appendChild(el("td", { texto: etiquetaSala }));
        tr.appendChild(el("td", { texto: `${s.calle ?? ""} ${s.numero ?? ""}`.trim() }));
        tr.appendChild(el("td", { texto: montoTexto }));
        tbodyVentas.appendChild(tr);
      });
    } catch (error) {
      if (signal.aborted) return;
      vaciar(tbodyVentas);
      errVentas.textContent = error.message;
      errVentas.hidden = false;
    }
  }

  formVentas.addEventListener(
    "submit",
    (ev) => {
      ev.preventDefault();
      if (signal.aborted) return;
      cargarVentasSala();
    },
    { signal }
  );

  // ---------- 3) Vinos sin stock (S6) ----------
  const secSinStock = el("section", { clase: "card" });
  secSinStock.appendChild(el("h2", { texto: "Vinos sin stock" }));

  const formStock = el("form", { clase: "filtros-form", atributos: { novalidate: "" } });
  const lblSalaStock = el("label", { texto: "Ámbito:", atributos: { for: "tablero-sala-stock" } });
  const selectSalaStock = el("select", { id: "tablero-sala-stock", nombre: "id_sala" });
  selectSalaStock.appendChild(el("option", { texto: "Toda la empresa (stock total 0)", valor: "" }));
  const btnStock = el("button", { clase: "btn btn-sm", texto: "Consultar", atributos: { type: "submit" } });
  formStock.append(lblSalaStock, selectSalaStock, btnStock);

  const notaStock = el("p", {
    clase: "nota-chica",
    texto: "Al filtrar por sala, muestra vinos agotados en esa sala pero disponibles en el depósito central.",
  });

  const errStock = el("p", { clase: "alerta error", atributos: { role: "alert" } });
  errStock.hidden = true;

  const { tabla: tablaStock, tbody: tbodyStock } = crearTabla([
    "Código",
    "Vino",
    "Stock en depósito",
  ]);
  secSinStock.append(formStock, notaStock, errStock, tablaStock);
  contenedor.appendChild(secSinStock);

  async function cargarSalasFiltro() {
    try {
      const salas = await listarSalas();
      if (signal.aborted) return;
      vaciar(selectSalaStock);
      selectSalaStock.appendChild(el("option", { texto: "Toda la empresa (stock total 0)", valor: "" }));
      salas.forEach((s) => {
        selectSalaStock.appendChild(
          el("option", {
            texto: `Sala ${s.id_sala} - ${s.calle} ${s.numero}`,
            valor: String(s.id_sala),
          })
        );
      });
    } catch (error) {
      if (signal.aborted) return;
      errStock.textContent = error.message;
      errStock.hidden = false;
    }
  }

  async function cargarSinStock() {
    errStock.hidden = true;
    renderFilaMensaje(tbodyStock, 3, "Cargando...");
    try {
      const idSala = selectSalaStock.value === "" ? undefined : Number(selectSalaStock.value);
      const resp = await vinosSinStock({ id_sala: idSala });
      if (signal.aborted) return;
      const items = resp.items || [];
      if (items.length === 0) {
        renderFilaMensaje(tbodyStock, 3, "No hay vinos sin stock para el criterio seleccionado");
        return;
      }
      vaciar(tbodyStock);
      items.forEach((v) => {
        const tr = el("tr");
        tr.appendChild(el("td", { texto: String(v.cod_vino ?? "") }));
        tr.appendChild(el("td", { texto: String(v.nombre ?? "") }));
        tr.appendChild(el("td", { texto: String(v.stock_deposito ?? "") }));
        tbodyStock.appendChild(tr);
      });
    } catch (error) {
      if (signal.aborted) return;
      vaciar(tbodyStock);
      errStock.textContent = error.message;
      errStock.hidden = false;
    }
  }

  selectSalaStock.addEventListener(
    "change",
    () => {
      if (signal.aborted) return;
      cargarSinStock();
    },
    { signal }
  );

  formStock.addEventListener(
    "submit",
    (ev) => {
      ev.preventDefault();
      if (signal.aborted) return;
      cargarSinStock();
    },
    { signal }
  );

  // ---------- 4) Transportista más activo del último mes (S7) ----------
  const secTransp = el("section", { clase: "card" });
  secTransp.appendChild(el("h2", { texto: "Transportista más activo (último mes)" }));

  const errTransp = el("p", { clase: "alerta error", atributos: { role: "alert" } });
  errTransp.hidden = true;

  const { tabla: tablaTransp, tbody: tbodyTransp } = crearTabla([
    "Código",
    "Razón social",
    "Ingresos registrados",
  ]);
  secTransp.append(errTransp, tablaTransp);
  contenedor.appendChild(secTransp);

  async function cargarTransportista() {
    errTransp.hidden = true;
    renderFilaMensaje(tbodyTransp, 3, "Cargando...");
    try {
      const resp = await transportistaActivo();
      if (signal.aborted) return;
      const items = resp.items || [];
      if (items.length === 0) {
        renderFilaMensaje(tbodyTransp, 3, "Sin ingresos registrados en el último mes");
        return;
      }
      vaciar(tbodyTransp);
      items.forEach((t) => {
        const tr = el("tr");
        tr.appendChild(el("td", { texto: String(t.cod_transportista ?? "") }));
        tr.appendChild(el("td", { texto: String(t.razon_social ?? "") }));
        tr.appendChild(el("td", { texto: String(t.cantidad_ingresos ?? "") }));
        tbodyTransp.appendChild(tr);
      });
    } catch (error) {
      if (signal.aborted) return;
      vaciar(tbodyTransp);
      errTransp.textContent = error.message;
      errTransp.hidden = false;
    }
  }

  // ---------- 5) Trazabilidad de vino ----------
  const secTraz = el("section", { clase: "card" });
  secTraz.appendChild(el("h2", { texto: "Trazabilidad de lotes por vino" }));

  const formTraz = el("form", { clase: "filtros-form", atributos: { novalidate: "" } });
  const lblCodTraz = el("label", { texto: "Código de vino:", atributos: { for: "tablero-cod-traz" } });
  const inputCodTraz = el("input", {
    tipo: "number",
    id: "tablero-cod-traz",
    placeholder: "Ej. 1",
    atributos: { min: "1", step: "1" },
  });
  const btnTraz = el("button", { clase: "btn btn-sm", texto: "Consultar trazabilidad", atributos: { type: "submit" } });
  formTraz.append(lblCodTraz, inputCodTraz, btnTraz);

  const errTraz = el("p", { clase: "alerta error", atributos: { role: "alert" } });
  errTraz.hidden = true;

  const infoVinoTraz = el("p", { clase: "cliente-seleccionado" });
  infoVinoTraz.hidden = true;

  const { tabla: tablaTraz, tbody: tbodyTraz } = crearTabla([
    "Lote",
    "Campaña",
    "Fecha cosecha",
    "Kilos",
    "Finca",
    "Parcela",
    "Cepa",
  ]);
  renderFilaMensaje(tbodyTraz, 7, "Ingrese un código de vino para ver su origen");

  secTraz.append(formTraz, errTraz, infoVinoTraz, tablaTraz);
  contenedor.appendChild(secTraz);

  formTraz.addEventListener(
    "submit",
    async (ev) => {
      ev.preventDefault();
      if (signal.aborted) return;
      errTraz.hidden = true;
      infoVinoTraz.hidden = true;

      const cod = Number(inputCodTraz.value.trim());
      if (!Number.isInteger(cod) || cod <= 0) {
        errTraz.textContent = "Ingrese un código de vino válido.";
        errTraz.hidden = false;
        return;
      }

      renderFilaMensaje(tbodyTraz, 7, "Cargando...");
      try {
        const resp = await trazabilidad(cod);
        if (signal.aborted) return;
        infoVinoTraz.textContent = `Vino ${resp.cod_vino}: ${resp.nombre} (Bodega CUIT ${resp.cuit_bodega})`;
        infoVinoTraz.hidden = false;

        const lotes = resp.lotes || [];
        if (lotes.length === 0) {
          renderFilaMensaje(tbodyTraz, 7, "El vino no posee lotes de trazabilidad asociados");
          return;
        }
        vaciar(tbodyTraz);
        lotes.forEach((l) => {
          const tr = el("tr");
          tr.appendChild(el("td", { texto: String(l.nro_lote ?? "") }));
          tr.appendChild(el("td", { texto: String(l.campania ?? "") }));
          tr.appendChild(el("td", { texto: String(l.fecha_cosecha ?? "") }));
          tr.appendChild(el("td", { texto: String(l.kilos ?? "") }));
          tr.appendChild(el("td", { texto: String(l.finca ?? "") }));
          tr.appendChild(el("td", { texto: String(l.nro_parcela ?? "") }));
          tr.appendChild(el("td", { texto: String(l.cepa ?? "") }));
          tbodyTraz.appendChild(tr);
        });
      } catch (error) {
        if (signal.aborted) return;
        vaciar(tbodyTraz);
        errTraz.textContent = error.message;
        errTraz.hidden = false;
      }
    },
    { signal }
  );

  btnActualizarTodo.addEventListener(
    "click",
    () => {
      if (signal.aborted) return;
      cargarTop();
      cargarVentasSala();
      cargarSinStock();
      cargarTransportista();
    },
    { signal }
  );

  cargarTop();
  cargarVentasSala();
  cargarSalasFiltro();
  cargarSinStock();
  cargarTransportista();

  return {
    destruir() {
      controlador.abort();
      montajeActual = null;
      vaciar(contenedor);
    },
  };
}