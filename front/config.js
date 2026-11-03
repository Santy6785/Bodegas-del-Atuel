/**
 * Bodegas del Atuel - Configuración global de la aplicación
 *
 * Este archivo se carga de forma síncrona como script clásico (no módulo)
 * antes de la inicialización de los módulos ES en js/main.js.
 *
 * NOTA DE SEGURIDAD / DESPLIEGUE:
 * Este archivo NO contiene secretos (la URL pública o base de la API no es un secreto).
 * En entornos de producción o contenedores, este único archivo se reemplaza
 * o genera dinámicamente con la URL base del entorno correspondiente.
 */
window.APP_CONFIG = {
  API_BASE_URL: "http://localhost:8000"
};
