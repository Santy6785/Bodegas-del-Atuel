/**
 * Bodegas del Atuel - Punto de Entrada Principal (Main)
 *
 * Inicializa el enrutador del cliente y ejecuta el chequeo de salud inicial contra la API.
 */

import { initRouter } from "./router.js";
import { verificarSalud } from "./api/index.js";

/**
 * Consulta el endpoint de salud de la API y actualiza el indicador visual en el header.
 */
async function comprobarSaludApi() {
  const statusEl = document.getElementById("api-status");
  if (!statusEl) return;

  statusEl.className = "api-status loading";
  statusEl.textContent = "Verificando...";

  try {
    await verificarSalud();
    statusEl.className = "api-status success";
    statusEl.textContent = "API conectada";
    statusEl.title = "La API REST responde correctamente.";
  } catch (error) {
    statusEl.className = "api-status error";
    // IMPORTANTE: textContent evita inyección de HTML y muestra el mensaje tal cual lo devuelve el backend
    const mensajeError = error.message || "Error al conectar con la API";
    statusEl.textContent = mensajeError;
    statusEl.title = `Estado: ${error.status ?? "desconocido"}. ${mensajeError}`;
  }
}

/**
 * Arranque de la aplicación una vez cargado el DOM.
 */
function arrancar() {
  initRouter();
  comprobarSaludApi();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", arrancar);
} else {
  arrancar();
}
