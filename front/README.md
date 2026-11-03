# Bodegas del Atuel - Módulo Frontend (Etapa 7)

Capa frontend cliente para el Sistema de Gestión y Distribución de la empresa vitivinícola **Bodegas del Atuel** (Trabajo Práctico Integrador de Bases de Datos - UTN FRSR).

---

## 📌 Reglas de Arquitectura y Negocio

1. **Consumo exclusivo de API REST:** El frontend se comunica únicamente mediante peticiones HTTP contra la API REST. No interactúa ni se conecta directamente a la base de datos PostgreSQL.
2. **Sin cálculo de importes ni stock en cliente:** El frontend **NO** calcula totales, subtotales, descuentos ni verifica saldos de stock. Todos estos valores son derivados y auditados por la base de datos (procedimientos almacenados, funciones y triggers) y provistos por la API.
3. **Fidelidad de errores de reglas de negocio:** Los mensajes de error devueltos por la API correspondientes a reglas del negocio vitivinícola (RN-01 a RN-15, restricciones de integridad, saldo insuficiente, etc.) se muestran al usuario **tal cual** los envía el servidor, sin sustituirlos por textos genéricos ni enmascararlos.
4. **Stack técnico vainilla:** HTML5 semántico, CSS3 puro y JavaScript modular estándar (ES Modules nativos con `<script type="module">`). No se emplean frameworks (React, Vue), bibliotecas externas (jQuery, Axios, Bootstrap, Tailwind), empaquetadores (Vite, Webpack), TypeScript ni gestores de paquetes (npm/package.json).

---

## 📂 Estructura del Directorio

```text
front/
├── index.html          # Shell de la aplicación (header, nav, #api-status, <main id="app">, footer)
├── config.js           # Configuración global clásica (window.APP_CONFIG.API_BASE_URL)
├── css/
│   └── styles.css      # Variables CSS, reset base, maquetación flex/grid, clases de estado
├── js/
│   ├── main.js         # Punto de entrada de la aplicación y comprobación de salud
│   ├── router.js       # Router del lado del cliente basado en hash (#) y tabla de rutas
│   ├── api/
│   │   ├── client.js   # Cliente HTTP centralizado (único lugar donde se invoca fetch nativo)
│   │   ├── vinos.js    # Llamadas a endpoints de /vinos
│   │   ├── clientes.js # Llamadas a endpoints de /clientes
│   │   ├── comprobantes.js # Llamadas a endpoints de /comprobantes
│   │   ├── transferencias.js # Llamadas a endpoints de /transferencias
│   │   ├── ingresos.js # Llamadas a endpoints de /ingresos
│   │   ├── reportes.js # Llamadas a endpoints de /reportes
│   │   ├── salud.js    # Verificación de salud (GET /salud)
│   │   └── index.js    # Re-exportación unificada de la capa de API
│   ├── pages/          # Vistas / pantallas por feature (se implementan en issues futuras)
│   └── components/     # Componentes visuales reutilizables (issues futuras)
└── README.md           # Documentación del módulo
```

---

## 🚀 Cómo Ejecutar en Desarrollo Local

Dado que la aplicación utiliza **módulos nativos de ECMAScript** (`import` / `export`), el navegador bloquea las peticiones si se abre mediante el protocolo `file://` debido a las políticas de seguridad CORS del estándar.

Para ejecutar la aplicación localmente:

1. Abrir una terminal en la carpeta `front/`:
   ```bash
   cd front
   ```

2. Iniciar un servidor estático ligero con Python:
   ```bash
   python -m http.server 5500
   ```

3. Abrir en el navegador web:
   ```text
   http://localhost:5500
   ```

---

## ⚙️ Configuración de la URL Base de la API

La URL base de la API está definida en [`config.js`](file:///C:/Users/jerek/Desktop/Bodegas%20del%20atuel/Bodegas-del-Atuel/front/config.js):

```javascript
window.APP_CONFIG = {
  API_BASE_URL: "http://localhost:8000"
};
```

### Comportamiento y Despliegue:
- **Sin secretos:** La URL de la API es de acceso público para el cliente web y no constituye un secreto.
- **Sobrescritura por entorno:** En despliegues en servidores o contenedores (Docker/Nginx/Caddy), únicamente se sustituye o inyecta este archivo `config.js` apuntando a la URL del backend del entorno deseado.
- **Valor por defecto de respaldo:** Si por alguna razón `window.APP_CONFIG` no estuviese cargado, [`client.js`](file:///C:/Users/jerek/Desktop/Bodegas%20del%20atuel/Bodegas-del-Atuel/front/js/api/client.js) emite una advertencia en la consola (`console.warn`) y asume por defecto `http://localhost:8000`, eliminando cualquier barra diagonal final (`/`) automáticamente.

---

## 🌐 Configuración de CORS en el Backend

Para que el navegador permita la comunicación entre el front (`http://localhost:5500`) y el backend (`http://localhost:8000`), la API debe tener habilitado **CORS** (*Cross-Origin Resource Sharing*), permitiendo:

- **Orígenes permitidos:** `http://localhost:5500` (o `*` en entornos locales de desarrollo).
- **Métodos HTTP:** `GET`, `POST`, `PUT`, `DELETE`, `OPTIONS`.
- **Cabeceras permitidas:** `Content-Type`, `Accept`.

---

## 🧭 Navegación y Rutas Soportadas

El enrutamiento se gestiona mediante hash (`#/`):

| Ruta | Descripción | Estado |
|---|---|---|
| `#/vinos` | Catálogo de vinos (ruta por defecto) | Placeholder (Issue futura) |
| `#/vinos/nuevo` | Formulario de alta de vinos | Placeholder (Issue futura) |
| `#/ventas/nueva` | Confección y emisión de comprobantes | Placeholder (Issue futura) |
| `#/transferencias` | Solicitudes de transferencias de stock | Placeholder (Issue futura) |
| `#/tablero` | Tablero de reportes estadísticos | Placeholder (Issue futura) |
| *(desconocida)* | Pantalla de "Página no encontrada" | Implementada con opción de retorno |
