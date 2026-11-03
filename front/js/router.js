/**
 * Bodegas del Atuel - Router Modular por Hash
 *
 * Administra el enrutamiento del lado del cliente mediante URLs con fragmento (#).
 * Permite registrar nuevas pantallas mediante `registrarRuta(ruta, renderFn)`.
 */

const DEFAULT_ROUTE = "#/vinos";

/**
 * Tabla interna de rutas registradas: { [hash: string]: (contenedor: HTMLElement) => void }
 */
const rutas = {};

/**
 * Registra una función de renderizado asociada a una ruta hash.
 *
 * @param {string} ruta - Identificador de ruta hash (ej. "#/vinos").
 * @param {(contenedor: HTMLElement) => void} render - Función encargada de dibujar la vista.
 */
export function registrarRuta(ruta, render) {
  rutas[ruta] = render;
}

/**
 * Actualiza la clase 'active' en los enlaces del menú de navegación.
 *
 * @param {string} hashActual - Hash activo en la ventana.
 */
function actualizarNavegacion(hashActual) {
  const links = document.querySelectorAll("header nav.main-nav a");
  links.forEach((link) => {
    const route = link.getAttribute("href");
    if (route === hashActual) {
      link.classList.add("active");
      link.setAttribute("aria-current", "page");
    } else {
      link.classList.remove("active");
      link.removeAttribute("aria-current");
    }
  });
}

/**
 * Genera una función de renderizado para pantallas en construcción (placeholders).
 *
 * @param {string} titulo - Título de la sección.
 * @param {string} descripcion - Descripción o alcance de la futura pantalla.
 * @returns {(contenedor: HTMLElement) => void}
 */
function crearPlaceholder(titulo, descripcion) {
  return function renderPlaceholder(contenedor) {
    contenedor.innerHTML = "";

    const card = document.createElement("section");
    card.className = "placeholder-card";

    const h2 = document.createElement("h2");
    h2.textContent = titulo;

    const p = document.createElement("p");
    p.textContent = descripcion;

    const badge = document.createElement("span");
    badge.className = "badge badge-info";
    badge.textContent = "Pantalla en construcción";

    card.appendChild(h2);
    card.appendChild(p);
    card.appendChild(badge);

    contenedor.appendChild(card);
  };
}

/**
 * Renderiza el estado de error 404 (ruta no encontrada).
 *
 * @param {HTMLElement} contenedor - Contenedor principal de la aplicación.
 * @param {string} hash - Hash solicitado no registrado.
 */
function renderNoEncontrado(contenedor, hash) {
  contenedor.innerHTML = "";

  const card = document.createElement("section");
  card.className = "card error-card";

  const h2 = document.createElement("h2");
  h2.textContent = "Página no encontrada";

  const p = document.createElement("p");
  p.textContent = `La dirección solicitada (${hash}) no corresponde a una pantalla válida del sistema.`;

  const btnVolver = document.createElement("a");
  btnVolver.href = DEFAULT_ROUTE;
  btnVolver.className = "btn-link";
  btnVolver.textContent = "Volver al Catálogo de Vinos";

  card.appendChild(h2);
  card.appendChild(p);
  card.appendChild(btnVolver);

  contenedor.appendChild(card);
}

/**
 * Resuelve la ruta actual evaluando el fragmento hash y ejecuta la vista correspondiente.
 */
function resolverRuta() {
  const appContainer = document.getElementById("app");
  if (!appContainer) {
    console.error("No se encontró el elemento contenedor <main id='app'>.");
    return;
  }

  const hash = window.location.hash.trim();

  // Si no hay hash o es la raíz, redirigir a la ruta por defecto
  if (!hash || hash === "#" || hash === "#/") {
    window.location.hash = DEFAULT_ROUTE;
    return;
  }

  actualizarNavegacion(hash);

  const renderFn = rutas[hash];
  if (typeof renderFn === "function") {
    renderFn(appContainer);
  } else {
    renderNoEncontrado(appContainer, hash);
  }
}

/**
 * Inicializa el enrutador por hash y registra las rutas base con sus placeholders.
 */
export function initRouter() {
  registrarRuta(
    "#/vinos",
    crearPlaceholder(
      "Catálogo de Vinos",
      "Listado general, filtros por tipo, cepa, bodega y añada. (Pendiente de implementación en issue futura)"
    )
  );

  registrarRuta(
    "#/vinos/nuevo",
    crearPlaceholder(
      "Nuevo Vino",
      "Formulario de registro y alta en el catálogo vitivinícola. (Pendiente de implementación en issue futura)"
    )
  );

  registrarRuta(
    "#/ventas/nueva",
    crearPlaceholder(
      "Nueva Venta",
      "Confección y emisión de comprobantes de venta a clientes socios, distribuidores y exportadores. (Pendiente de implementación en issue futura)"
    )
  );

  registrarRuta(
    "#/transferencias",
    crearPlaceholder(
      "Transferencias de Stock",
      "Gestión de pedidos de reposición entre depósito central y salas de venta. (Pendiente de implementación en issue futura)"
    )
  );

  registrarRuta(
    "#/tablero",
    crearPlaceholder(
      "Tablero de Control y Reportes",
      "Reportes de rendimiento: top vinos más vendidos, ventas por sala, quiebres de stock y trazabilidad. (Pendiente de implementación en issue futura)"
    )
  );

  // Escuchar cambios de hash y resolver la ruta inicial
  window.addEventListener("hashchange", resolverRuta);
  resolverRuta();
}
