import {
  crearVino,
  actualizarVino,
  obtenerVino,
  listarCepas,
  listarBodegas,
  listarMaridajes,
} from "../api/index.js";

const TIPOS = ["tinto", "blanco", "rosado", "espumante"];

function el(tag, { clase, texto, tipo, nombre, valor, placeholder, checked, atributos } = {}) {
  const elemento = document.createElement(tag);
  if (clase) elemento.className = clase;
  if (texto !== undefined) elemento.textContent = texto;
  if (tipo) elemento.type = tipo;
  if (nombre) elemento.name = nombre;
  if (valor !== undefined) elemento.value = valor;
  if (placeholder !== undefined) elemento.placeholder = placeholder;
  if (checked) elemento.checked = true;
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

export function iniciarVinoForm(contenedor, { modo, cod }) {
  const controlador = new AbortController();
  const signal = controlador.signal;

  vaciar(contenedor);

  const esEdicion = modo === "edicion";

  const h1 = el("h1", { texto: esEdicion ? `Editar vino #${cod}` : "Nuevo vino" });
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

  const formContainer = el("div");
  formContainer.hidden = true;
  contenedor.appendChild(formContainer);

  const form = el("form", { clase: "filtros-form form-vino", atributos: { novalidate: "" } });
  formContainer.appendChild(form);

  form.appendChild(el("label", { texto: "Nombre" }));
  const inputNombre = el("input", { nombre: "nombre", tipo: "text", placeholder: "Nombre del vino", atributos: { required: "" } });
  form.appendChild(inputNombre);

  form.appendChild(el("label", { texto: "Tipo" }));
  const selectTipo = el("select", { nombre: "tipo", atributos: { required: "" } });
  selectTipo.appendChild(el("option", { texto: "Seleccionar tipo", valor: "" }));
  TIPOS.forEach((t) => {
    selectTipo.appendChild(el("option", { texto: t.charAt(0).toUpperCase() + t.slice(1), valor: t }));
  });
  form.appendChild(selectTipo);

  form.appendChild(el("label", { texto: "A\u00f1ada" }));
  const inputAnada = el("input", { nombre: "anada", tipo: "number", placeholder: "A\u00f1ada", atributos: { required: "" } });
  form.appendChild(inputAnada);

  form.appendChild(el("label", { texto: "Volumen (ml)" }));
  const inputVolumen = el("input", { nombre: "volumen_ml", tipo: "number", placeholder: "Volumen en ml", atributos: { required: "", list: "volumen-sugerencias" } });
  form.appendChild(inputVolumen);
  const datalist = el("datalist", { atributos: { id: "volumen-sugerencias" } });
  [187, 375, 750, 1500, 3000].forEach((v) => {
    datalist.appendChild(el("option", { valor: String(v) }));
  });
  form.appendChild(datalist);

  form.appendChild(el("label", { texto: "Graduaci\u00f3n" }));
  const inputGraduacion = el("input", { nombre: "graduacion", tipo: "number", placeholder: "Graduaci\u00f3n", atributos: { required: "", step: "0.01" } });
  form.appendChild(inputGraduacion);

  form.appendChild(el("label", { texto: "Precio" }));
  const inputPrecio = el("input", { nombre: "precio", tipo: "number", placeholder: "Precio", atributos: { required: "", step: "0.01" } });
  form.appendChild(inputPrecio);

  form.appendChild(el("label", { texto: "Bodega" }));
  const selectBodega = el("select", { nombre: "cuit_bodega", atributos: { required: "" } });
  selectBodega.appendChild(el("option", { texto: "Seleccionar bodega", valor: "" }));
  form.appendChild(selectBodega);

  form.appendChild(el("h3", { texto: "Composici\u00f3n de cepas" }));
  const compContainer = el("div", { clase: "composicion-filas" });
  form.appendChild(compContainer);
  let cepasDisponibles = [];

  const filasComposicion = [];

  function crearFilaComposicion(idCepa = "", porcentaje = "") {
    const fila = el("div", { clase: "composicion-fila" });

    const selectCepa = el("select", { nombre: "id_cepa", atributos: { required: "" } });
    selectCepa.appendChild(el("option", { texto: "Seleccionar cepa", valor: "" }));
    fila.appendChild(selectCepa);

    const inputPorcentaje = el("input", { nombre: "porcentaje", tipo: "text", placeholder: "%", atributos: { required: "" } });
    fila.appendChild(inputPorcentaje);

    const btnQuitar = el("button", { clase: "btn btn-sm", tipo: "button", texto: "Quitar fila" });
    btnQuitar.addEventListener("click", (ev) => {
      ev.preventDefault();
      const idx = filasComposicion.findIndex((f) => f.select === selectCepa);
      if (idx >= 0) filasComposicion.splice(idx, 1);
      compContainer.removeChild(fila);
    }, { signal });
    fila.appendChild(btnQuitar);

    compContainer.appendChild(fila);
    filasComposicion.push({ select: selectCepa, input: inputPorcentaje });

    cepasDisponibles.forEach((c) => {
      selectCepa.appendChild(el("option", { texto: c.nombre, valor: String(c.id_cepa) }));
    });

    if (idCepa) selectCepa.value = String(idCepa);
    if (porcentaje) inputPorcentaje.value = String(porcentaje);

    return { select: selectCepa, input: inputPorcentaje };
  }

  crearFilaComposicion();

  const btnAgregarCepa = el("button", { clase: "btn btn-sm", tipo: "button", texto: "Agregar cepa" });
  btnAgregarCepa.addEventListener("click", (ev) => {
    ev.preventDefault();
    crearFilaComposicion();
  }, { signal });
  form.appendChild(btnAgregarCepa);

  form.appendChild(el("h3", { texto: "Maridajes" }));
  const maridajesContainer = el("div", { clase: "maridajes-grupo" });
  form.appendChild(maridajesContainer);

  const btnGuardar = el("button", { clase: "btn btn-primary", tipo: "submit", texto: esEdicion ? "Actualizar" : "Guardar" });
  form.appendChild(btnGuardar);

  const accionesPost = el("div", { clase: "acciones-post" });
  contenedor.appendChild(accionesPost);

  let cargando = false;

  function setCargando(valor) {
    cargando = valor;
    btnGuardar.disabled = valor;
  }

  async function cargarCatalogos() {
    limpiarAlerta();
    try {
      const [cepas, bodegas, maridajes] = await Promise.all([
        listarCepas(),
        listarBodegas(),
        listarMaridajes(),
      ]);
      if (signal.aborted) return false;
      cepasDisponibles = cepas;

      filasComposicion.forEach((f) => {
        cepas.forEach((c) => {
          f.select.appendChild(el("option", { texto: c.nombre, valor: String(c.id_cepa) }));
        });
      });

      bodegas.forEach((b) => {
        selectBodega.appendChild(el("option", { texto: `${b.razon_social} (${b.cuit})`, valor: b.cuit }));
      });

      maridajes.forEach((m) => {
        const id = String(m.id_maridaje);
        const label = el("label");
        const checkbox = el("input", { tipo: "checkbox", nombre: "maridaje", valor: id });
        label.appendChild(checkbox);
        label.appendChild(document.createTextNode(` ${m.nombre} - ${m.temperatura_servicio} \u00b0C`));
        maridajesContainer.appendChild(label);
      });

      return { cepas, bodegas, maridajes };
    } catch (error) {
      if (signal.aborted) return false;
      mostrarAlerta(error.message, false);
      return false;
    }
  }

  async function precargarEdicion(codVino) {
    limpiarAlerta();
    try {
      const detalle = await obtenerVino(codVino);
      if (signal.aborted) return;

      inputNombre.value = detalle.nombre;
      selectTipo.value = detalle.tipo;
      inputAnada.value = String(detalle.anada);
      inputVolumen.value = String(detalle.volumen_ml);
      inputGraduacion.value = String(detalle.graduacion);
      inputPrecio.value = String(detalle.precio);
      if (detalle.cuit_bodega) selectBodega.value = detalle.cuit_bodega;

      vaciar(compContainer);
      filasComposicion.length = 0;
      (detalle.composicion || []).forEach((c) => {
        crearFilaComposicion(String(c.id_cepa), String(c.porcentaje));
      });

      const checkboxes = maridajesContainer.querySelectorAll('input[type="checkbox"]');
      const idsMaridajes = new Set((detalle.maridajes || []).map((m) => String(m.id_maridaje)));
      checkboxes.forEach((cb) => {
        cb.checked = idsMaridajes.has(cb.value);
      });

      formContainer.hidden = false;
    } catch (error) {
      if (signal.aborted) return;
      mostrarAlerta(error.message, false);
    }
  }

  form.addEventListener("submit", (ev) => {
    ev.preventDefault();
    if (cargando) return;
    limpiarAlerta();
    vaciar(accionesPost);

    const nombre = inputNombre.value;
    const tipo = selectTipo.value;
    const anada = Number(inputAnada.value);
    const volumen_ml = Number(inputVolumen.value);
    const graduacion = inputGraduacion.value.trim();
    const precio = inputPrecio.value.trim();
    const cuit_bodega = selectBodega.value;

    const composicion = filasComposicion.map((f) => ({
      id_cepa: Number(f.select.value),
      porcentaje: f.input.value.trim(),
    }));

    const checkboxes = maridajesContainer.querySelectorAll('input[type="checkbox"]:checked');
    const maridajes = Array.from(checkboxes).map((cb) => Number(cb.value));

    const body = {
      nombre,
      tipo,
      anada,
      volumen_ml,
      graduacion,
      precio,
      cuit_bodega,
      composicion,
      maridajes,
    };

    setCargando(true);

    const promesa = esEdicion
      ? actualizarVino(cod, body)
      : crearVino(body);

    promesa.then((respuesta) => {
      if (signal.aborted) return;
      setCargando(false);
      if (esEdicion) {
        mostrarAlerta("Vino actualizado", true);
        const enlace = el("a", { clase: "btn-link", texto: "Volver al cat\u00e1logo" });
        enlace.href = "#/vinos";
        accionesPost.appendChild(enlace);
      } else {
        const codVino = respuesta && respuesta.cod_vino ? respuesta.cod_vino : "";
        mostrarAlerta(`Vino creado con c\u00f3digo ${codVino}`, true);
        const enlaceVolver = el("a", { clase: "btn-link", texto: "Volver al cat\u00e1logo" });
        enlaceVolver.href = "#/vinos";
        accionesPost.appendChild(enlaceVolver);
        const enlaceOtro = el("a", { clase: "btn-link", texto: "Cargar otro vino" });
        enlaceOtro.href = "#";
        enlaceOtro.addEventListener("click", (ev2) => {
          ev2.preventDefault();
          form.reset();
          limpiarAlerta();
          vaciar(accionesPost);
          vaciar(compContainer);
          filasComposicion.length = 0;
          crearFilaComposicion();
          const checkboxes = maridajesContainer.querySelectorAll('input[type="checkbox"]');
          checkboxes.forEach((cb) => { cb.checked = false; });
        }, { signal });
        accionesPost.appendChild(enlaceOtro);
      }
    }).catch((error) => {
      if (signal.aborted) return;
      setCargando(false);
      mostrarAlerta(error.message, false);
    });
  }, { signal });

  cargarCatalogos().then((ok) => {
    if (!ok) return;
    if (esEdicion) {
      const codNum = Number(cod);
      if (!Number.isInteger(codNum) || codNum <= 0) {
        formContainer.hidden = true;
        mostrarAlerta("C\u00f3digo de vino inv\u00e1lido", false);
        const enlace = el("a", { clase: "btn-link", texto: "Volver al cat\u00e1logo" });
        enlace.href = "#/vinos";
        accionesPost.appendChild(enlace);
        return;
      }
      precargarEdicion(cod);
    } else {
      formContainer.hidden = false;
    }
  });

  return {
    destruir() {
      controlador.abort();
      vaciar(contenedor);
    },
  };
}
