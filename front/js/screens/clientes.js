import {
  listarClientes,
  obtenerCliente,
  crearCliente,
  actualizarCliente,
  eliminarCliente,
  listarLocalidades,
} from "../api/index.js";

function el(tag, opciones = {}) {
  const nodo = document.createElement(tag);
  if (opciones.texto !== undefined) nodo.textContent = opciones.texto;
  if (opciones.clase) nodo.className = opciones.clase;
  if (opciones.tipo) nodo.type = opciones.tipo;
  if (opciones.nombre) nodo.name = opciones.nombre;
  if (opciones.valor !== undefined) nodo.value = opciones.valor;
  if (opciones.placeholder) nodo.placeholder = opciones.placeholder;
  if (opciones.required) nodo.required = true;
  return nodo;
}

function vaciar(nodo) {
  nodo.replaceChildren();
}

export function iniciarClientes(contenedor) {
  const controlador = new AbortController();
  const signal = controlador.signal;

  const estado = {
    pagina: 1,
    tamano: 20,
    busqueda: "",
    tipo: "",
    localidades: [],
    clienteEditando: null,
  };

  vaciar(contenedor);

  const titulo = el("h1", { texto: "Gestión de clientes" });
  const alerta = el("div", { clase: "alerta", texto: "" });
  alerta.hidden = true;

  const filtros = el("form", { clase: "filtros-form" });
  const buscar = el("input", {
    nombre: "q",
    placeholder: "Buscar por nombre o documento",
  });

  const filtroTipo = el("select", { nombre: "tipo_cliente" });
  [
    ["", "Todos los tipos"],
    ["socio", "Socios"],
    ["distribuidor", "Distribuidores"],
    ["exportador", "Exportadores"],
  ].forEach(([valor, texto]) => {
    filtroTipo.appendChild(el("option", { valor, texto }));
  });

  const btnBuscar = el("button", {
    clase: "btn btn-primary",
    texto: "Buscar",
    tipo: "submit",
  });

  filtros.append(buscar, filtroTipo, btnBuscar);

  const btnNuevo = el("button", {
    clase: "btn btn-primary",
    texto: "Agregar cliente",
    tipo: "button",
  });

  const tablaContenedor = el("div");
  const paginador = el("div", { clase: "paginador" });

  const formularioContenedor = el("section");
  formularioContenedor.hidden = true;

  contenedor.append(
    titulo,
    alerta,
    filtros,
    btnNuevo,
    tablaContenedor,
    paginador,
    formularioContenedor
  );

  function mostrarMensaje(mensaje, exito = false) {
    alerta.hidden = false;
    alerta.textContent = mensaje;
    alerta.className = exito
      ? "alerta alerta-exito"
      : "alerta error";
  }

  function limpiarMensaje() {
    alerta.hidden = true;
    alerta.textContent = "";
  }

  async function cargarListado() {
    limpiarMensaje();
    tablaContenedor.textContent = "Cargando clientes...";

    try {
      const datos = await listarClientes({
        page: estado.pagina,
        page_size: estado.tamano,
        q: estado.busqueda,
        tipo_cliente: estado.tipo,
      });

      if (signal.aborted) return;

      renderizarTabla(datos);
    } catch (error) {
      if (signal.aborted) return;
      tablaContenedor.textContent = "";
      mostrarMensaje(error.message);
    }
  }

  function renderizarTabla(datos) {
    vaciar(tablaContenedor);

    const tabla = el("table", { clase: "tabla-datos" });
    const thead = document.createElement("thead");
    const filaTitulo = document.createElement("tr");

    [
      "ID",
      "Cliente",
      "Documento",
      "Tipo",
      "Descuento",
      "Acciones",
    ].forEach((texto) => {
      filaTitulo.appendChild(el("th", { texto }));
    });

    thead.appendChild(filaTitulo);
    tabla.appendChild(thead);

    const tbody = document.createElement("tbody");

    (datos.items || []).forEach((cliente) => {
      const fila = document.createElement("tr");

      const nombre = cliente.nombre
        ? `${cliente.apellido_razon_social}, ${cliente.nombre}`
        : cliente.apellido_razon_social;

      [
        cliente.id_cliente,
        nombre,
        `${cliente.tipo_documento} ${cliente.nro_documento}`,
        cliente.tipo_cliente,
        `${cliente.descuento_pct}%`,
      ].forEach((valor) => {
        fila.appendChild(el("td", { texto: String(valor ?? "") }));
      });

      const acciones = el("td");

      const btnEditar = el("button", {
        clase: "btn btn-sm",
        texto: "Editar",
        tipo: "button",
      });

      btnEditar.addEventListener("click", () => {
        abrirEdicion(cliente.id_cliente);
      }, { signal });

      const btnEliminar = el("button", {
        clase: "btn btn-sm btn-peligro",
        texto: "Eliminar",
        tipo: "button",
      });

      btnEliminar.addEventListener("click", () => {
        borrarCliente(cliente);
      }, { signal });

      acciones.append(btnEditar, btnEliminar);
      fila.appendChild(acciones);
      tbody.appendChild(fila);
    });

    tabla.appendChild(tbody);
    tablaContenedor.appendChild(tabla);

    if (!datos.items?.length) {
      tablaContenedor.textContent = "No se encontraron clientes.";
    }

    const totalPaginas = Math.max(
      1,
      Math.ceil(datos.total / estado.tamano)
    );

    vaciar(paginador);

    const anterior = el("button", {
      clase: "btn btn-sm",
      texto: "Anterior",
      tipo: "button",
    });

    anterior.disabled = estado.pagina <= 1;
    anterior.addEventListener("click", () => {
      estado.pagina--;
      cargarListado();
    }, { signal });

    const siguiente = el("button", {
      clase: "btn btn-sm",
      texto: "Siguiente",
      tipo: "button",
    });

    siguiente.disabled = estado.pagina >= totalPaginas;
    siguiente.addEventListener("click", () => {
      estado.pagina++;
      cargarListado();
    }, { signal });

    paginador.append(
      anterior,
      el("span", {
        texto: `Página ${estado.pagina} de ${totalPaginas}`,
      }),
      siguiente
    );
  }

  function agregarCampo(form, etiqueta, nombre, valor = "") {
    form.appendChild(el("label", { texto: etiqueta }));

    const input = el("input", {
      nombre,
      valor: valor ?? "",
      required: true,
    });

    form.appendChild(input);
    return input;
  }

  function agregarSelect(form, etiqueta, nombre, opciones, valorActual = "") {
    form.appendChild(el("label", { texto: etiqueta }));

    const select = el("select", { nombre });
    select.required = true;

    opciones.forEach(([valor, texto]) => {
      select.appendChild(el("option", { valor, texto }));
    });

    select.value = valorActual ?? "";
    form.appendChild(select);
    return select;
  }

  function crearFormulario(cliente = null) {
    estado.clienteEditando = cliente?.id_cliente ?? null;
    vaciar(formularioContenedor);

    formularioContenedor.hidden = false;

    const form = el("form", { clase: "filtros-form form-cliente" });

    form.appendChild(el("h2", {
      texto: cliente ? "Editar cliente" : "Nuevo cliente",
    }));

    const apellido = agregarCampo(
      form,
      "Apellido o razón social",
      "apellido_razon_social",
      cliente?.apellido_razon_social
    );

    const nombre = agregarCampo(
      form,
      "Nombre (si corresponde)",
      "nombre",
      cliente?.nombre
    );
    nombre.required = false;

    const tipoDocumento = agregarSelect(
      form,
      "Tipo de documento",
      "tipo_documento",
      [
        ["DNI", "DNI"],
        ["CUIT", "CUIT"],
        ["CUIL", "CUIL"],
        ["PASAPORTE", "Pasaporte"],
      ],
      cliente?.tipo_documento || "DNI"
    );

    const documento = agregarCampo(
      form,
      "Número de documento",
      "nro_documento",
      cliente?.nro_documento
    );

    const direccion = agregarCampo(
      form,
      "Dirección",
      "direccion",
      cliente?.direccion
    );

    form.appendChild(el("label", { texto: "Localidad / código postal" }));

    const localidad = el("select", { nombre: "codigo_postal" });
    localidad.required = true;

    estado.localidades.forEach((l) => {
      localidad.appendChild(el("option", {
        valor: l.codigo_postal,
        texto: `${l.nombre} - ${l.provincia} (${l.codigo_postal})`,
      }));
    });

    localidad.value = cliente?.codigo_postal || "";
    form.appendChild(localidad);

    const tipo = agregarSelect(
      form,
      "Tipo de cliente",
      "tipo_cliente",
      [
        ["socio", "Socio"],
        ["distribuidor", "Distribuidor"],
        ["exportador", "Exportador"],
      ],
      cliente?.tipo_cliente || "socio"
    );

    tipo.disabled = Boolean(cliente);

    if (cliente) {
        form.appendChild(
            el("p", {
                clase: "info-cliente",
                texto: `Descuento actual: ${cliente.descuento_pct}%`,
            })
        );
    }

    const camposEspecificos = el("div");
    form.appendChild(camposEspecificos);

    function actualizarCamposEspecificos() {
      vaciar(camposEspecificos);

      if (tipo.value === "distribuidor") {
        const datos = cliente?.distribuidor || {};

        agregarCampo(
          camposEspecificos,
          "Zona de cobertura",
          "zona_cobertura",
          datos.zona_cobertura
        );

        agregarCampo(
          camposEspecificos,
          "Número de habilitación",
          "nro_habilitacion",
          datos.nro_habilitacion
        );
      }

      if (tipo.value === "exportador") {
        const datos = cliente?.exportador || {};

        agregarCampo(
          camposEspecificos,
          "País de destino",
          "pais_destino",
          datos.pais_destino
        );

        camposEspecificos.appendChild(
          el("h3", { texto: "Permisos de exportación" })
        );

        const permisosContenedor = el("div");
        camposEspecificos.appendChild(permisosContenedor);

        const permisos = (datos.permisos || []).map((p) => ({ ...p }));

        function renderPermisos() {
          vaciar(permisosContenedor);

          permisos.forEach((permiso, indice) => {
            const fila = el("div", { clase: "composicion-fila" });

            const codigo = el("input", {
              placeholder: "Código",
              valor: permiso.codigo || "",
            });

            const emision = el("input", {
              tipo: "date",
              valor: permiso.fecha_emision || "",
            });

            const vencimiento = el("input", {
              tipo: "date",
              valor: permiso.fecha_vencimiento || "",
            });

            const quitar = el("button", {
              clase: "btn btn-sm",
              texto: "Quitar",
              tipo: "button",
            });

            codigo.addEventListener("input", () => {
              permiso.codigo = codigo.value;
            }, { signal });

            emision.addEventListener("input", () => {
              permiso.fecha_emision = emision.value;
            }, { signal });

            vencimiento.addEventListener("input", () => {
              permiso.fecha_vencimiento = vencimiento.value;
            }, { signal });

            quitar.addEventListener("click", () => {
              permisos.splice(indice, 1);
              renderPermisos();
            }, { signal });

            fila.append(codigo, emision, vencimiento, quitar);
            permisosContenedor.appendChild(fila);
          });
        }

        const agregarPermiso = el("button", {
          clase: "btn btn-sm",
          texto: "Agregar permiso",
          tipo: "button",
        });

        agregarPermiso.addEventListener("click", () => {
          permisos.push({
            codigo: "",
            fecha_emision: "",
            fecha_vencimiento: "",
          });
          renderPermisos();
        }, { signal });

        camposEspecificos.appendChild(agregarPermiso);
        renderPermisos();

        camposEspecificos.dataset.permisos = "exportador";
        camposEspecificos._obtenerPermisos = () => permisos;
      }
    }

    tipo.addEventListener("change", () => {
      cliente = null;
      actualizarCamposEspecificos();
    }, { signal });

    actualizarCamposEspecificos();

    const guardar = el("button", {
      clase: "btn btn-primary",
      texto: cliente ? "Guardar cambios" : "Crear cliente",
      tipo: "submit",
    });

    const cancelar = el("button", {
      clase: "btn",
      texto: "Cancelar",
      tipo: "button",
    });

    cancelar.addEventListener("click", cerrarFormulario, { signal });

    form.append(guardar, cancelar);
    formularioContenedor.appendChild(form);

    form.addEventListener("submit", async (evento) => {
      evento.preventDefault();
      guardar.disabled = true;
      limpiarMensaje();

      const body = {
        apellido_razon_social: apellido.value.trim(),
        nombre: nombre.value.trim() || null,
        tipo_documento: tipoDocumento.value,
        nro_documento: documento.value.trim(),
        direccion: direccion.value.trim(),
        codigo_postal: localidad.value,
        tipo_cliente: tipo.value,
      };

      if (tipo.value === "distribuidor") {
        body.distribuidor = {
          zona_cobertura: form.elements.zona_cobertura.value.trim(),
          nro_habilitacion: form.elements.nro_habilitacion.value.trim(),
        };
      }

      if (tipo.value === "exportador") {
        body.exportador = {
          pais_destino: form.elements.pais_destino.value.trim(),
          permisos: camposEspecificos._obtenerPermisos(),
        };
      }

      try {
        if (estado.clienteEditando) {
          await actualizarCliente(estado.clienteEditando, body);
          mostrarMensaje("Cliente actualizado correctamente.", true);
        } else {
          await crearCliente(body);
          mostrarMensaje("Cliente creado correctamente.", true);
        }

        if (signal.aborted) return;

        cerrarFormulario();
        estado.pagina = 1;
        await cargarListado();
      } catch (error) {
        if (signal.aborted) return;
        mostrarMensaje(error.message);
        guardar.disabled = false;
      }
    }, { signal });
  }

  function cerrarFormulario() {
    formularioContenedor.hidden = true;
    vaciar(formularioContenedor);
    estado.clienteEditando = null;
  }

  async function abrirEdicion(id) {
  try {
    limpiarMensaje();
    mostrarMensaje("Cargando datos del cliente...", true);

    console.log("Abriendo edición del cliente:", id);

    const cliente = await obtenerCliente(id);

    console.log("Respuesta de obtenerCliente:", cliente);

    if (signal.aborted) return;

    if (!cliente || !cliente.id_cliente) {
      throw new Error("La API no devolvió los datos del cliente.");
    }

    limpiarMensaje();
    crearFormulario(cliente);

    formularioContenedor.scrollIntoView({
      behavior: "smooth",
      block: "start",
    });

  } catch (error) {
    console.error("Error al editar cliente:", error);

    if (!signal.aborted) {
      mostrarMensaje(`No se pudo abrir la edición: ${error.message}`);
    }
  }
}

  async function borrarCliente(cliente) {
    const nombre = cliente.apellido_razon_social;

    if (!window.confirm(
      `¿Querés eliminar al cliente "${nombre}"?`
    )) return;

    try {
      limpiarMensaje();
      await eliminarCliente(cliente.id_cliente);
      if (signal.aborted) return;

      mostrarMensaje("Cliente eliminado correctamente.", true);
      await cargarListado();
    } catch (error) {
      if (!signal.aborted) mostrarMensaje(error.message);
    }
  }

  filtros.addEventListener("submit", (evento) => {
    evento.preventDefault();
    estado.busqueda = buscar.value.trim();
    estado.tipo = filtroTipo.value;
    estado.pagina = 1;
    cargarListado();
  }, { signal });

  btnNuevo.addEventListener("click", () => {
    crearFormulario();
  }, { signal });

  async function iniciar() {
    try {
      estado.localidades = await listarLocalidades();
      if (signal.aborted) return;
      await cargarListado();
    } catch (error) {
      if (!signal.aborted) mostrarMensaje(error.message);
    }
  }

  iniciar();

  return {
    destruir() {
      controlador.abort();
      vaciar(contenedor);
    },
  };
}
