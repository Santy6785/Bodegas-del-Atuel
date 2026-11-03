# Mapa de Pantallas y Endpoints - Bodegas del Atuel (Etapa 7)

Este documento detalla el mapeo técnico entre las pantallas de la interfaz web cliente y los endpoints provistos (o requeridos) de la API REST del backend. Su propósito es definir con precisión qué datos necesita cada pantalla, qué envía, qué funciones de la capa `front/js/api/` los gestionan, los flujos de interacción y el tratamiento estricto de reglas de negocio y errores.

---

## 📌 Reglas Fundamentales del Proyecto

1. **El Front NO realiza cálculos de negocio ni persistencia:**
   - Queda terminantemente prohibido calcular o anticipar subtotales, porcentajes de descuento, totales a pagar o saldos de stock en el cliente.
   - Todo importe, descuento por tipo de cliente (RN-06), total de comprobante (RN-08) y validación de stock físico (RN-09) es procesado y devuelto exclusivamente por el backend y la base de datos (PostgreSQL).
2. **Fidelidad absoluta en los mensajes de error:**
   - Los errores generados por violaciones a reglas de negocio (RN-01 a RN-15) o restricciones de integridad deben mostrarse al usuario **tal cual** los envía la API en el cuerpo de la respuesta (`textContent`), sin enmascararlos con mensajes genéricos ni traducirlos en el frontend.
3. **Flujo de estados en transferencias:**
   - Los botones de acción de transferencias se habilitan de acuerdo al ciclo de vida formal del documento: `en_confeccion` ➔ `terminado` ➔ `procesado` (RN-11, RN-12).
4. **Stack técnico:**
   - HTML5 semántico, CSS3 vanilla y JavaScript modular estándar (ES Modules nativos).
   - Sin frameworks, sin librerías externas ni herramientas de compilación/empaquetado.
   - Comunicación HTTP centralizada únicamente en `front/js/api/client.js`.

---

## 🖥️ Pantallas del Sistema

### 1. Catálogo de Vinos

#### a) Objetivo
Permitir la consulta, búsqueda y filtrado paginado de los vinos del catálogo institucional, visualizando sus características comerciales y permitiendo abrir un panel lateral/modal con el detalle enológico (composición de cepas y maridajes recomendados).

#### b) Datos que muestra y datos que envía
- **Datos que envía (Filtros de búsqueda y paginación):**
  - `tipo` (string, select: tinto, blanco, rosado, espumoso).
  - `cepa` (string/id, select).
  - `bodega` (string/cuit, select).
  - `anada` (number/string, año de cosecha).
  - `page` (number, página actual).
  - `pageSize` (number, tamaño de página).
- **Datos que muestra en la grilla principal:**
  - Código de vino (`cod_vino`), Nombre comercial (`nombre`), Tipo (`tipo`), Añada (`anada`), Precio unitario vigente (`precio`), Bodega productora (`nombre_bodega` o `cuit_bodega`).
  - Paginador interactivo (`anterior`, `siguiente`, número de página actual).
- **Datos que muestra en el panel/modal de detalle:**
  - Código, nombre comercial, añada y bodega.
  - Precio vigente formateado en moneda.
  - Composición de cepas: lista con nombre de cada cepa y su respectivo porcentaje de corte (ej. *"85% Malbec, 15% Cabernet Sauvignon"*).
  - Maridajes sugeridos con temperatura de servicio recomendada (ej. *"Carnes Rojas (17°C)"*).

#### c) Tabla de Endpoints y Mapeo
| Dato / Acción | Endpoint | Método | Parámetros | Campo en Respuesta | Función en `front/js/api/` | Origen |
|---|---|---|---|---|---|---|
| Listado general filtrado y paginado | `/vinos` | `GET` | **Query:** `tipo`, `cepa`, `bodega`, `anada`, `page`, `pageSize` | Array de vinos `items` (o array raíz) y metadatos de paginación (`total`, `page`, `pageSize`) | `listarVinos(filtros)` en `vinos.js` | Enunciado / Bocetos (Issue #12) |
| Detalle enológico completo (composición y maridaje) | `/vinos/{cod}` | `GET` | **Ruta:** `cod` (cod_vino) | Objeto con datos de vino, array `cepas: [{ id_cepa, nombre, porcentaje }]`, array `maridajes: [{ nombre, temperatura_servicio }]` | `obtenerVino(cod)` en `vinos.js` | Enunciado / Bocetos (Issue #12) |
| Catálogo de cepas (para combo de filtro) | `/cepas` | `GET` | Ninguno | Array de cepas `[{ id_cepa, nombre, tipo }]` | `listarCepas()` *(función sugerida)* | **PROPUESTO** (No listado en mínimos) |
| Catálogo de bodegas (para combo de filtro) | `/bodegas` | `GET` | Ninguno | Array de bodegas `[{ cuit, razon_social, nombre_fantasia }]` | `listarBodegas()` *(función sugerida)* | **PROPUESTO** (No listado en mínimos) |

#### d) Flujo Paso a Paso
1. Al cargar la pantalla, se solicitan en paralelo los datos de los selectores auxiliares (`GET /cepas` y `GET /bodegas`) y el primer lote de vinos (`GET /vinos?page=1&pageSize=10`).
2. Se renderiza la tabla de resultados y los controles de paginación.
3. Al interactuar con los filtros y presionar *"Buscar"* (o cambiar de página), se dispara nuevamente `listarVinos()` con los parámetros acumulados y se refresca el contenido de la tabla.
4. Al hacer clic en el botón *"Detalle"* de una fila, se invoca `obtenerVino(cod)` pasando el código del vino seleccionado.
5. Se abre el panel lateral/overlay desplegando la composición de cortes (%) y los maridajes con su temperatura.
6. El usuario puede cerrar el panel mediante el botón *[Cerrar]* sin recargar la página.

#### e) Errores Esperables y Tratamiento
| Escenario de Error | Regla / Restricción | SQLSTATE | HTTP Status | Tratamiento en Frontend |
|---|---|---|---|---|
| Formato de código de vino inválido en la URL | Error de tipo de dato (ej. alfanumérico donde va entero) | `22P02` | `400 Bad Request` | Muestra el mensaje de la API indicando identificador inválido. |
| Vino inexistente al solicitar detalle | Registro no encontrado | `P0002` o `NOT FOUND` | `404 Not Found` | Muestra *"El vino solicitado no existe o fue dado de baja"* tal cual responda el backend. |
| Fallo en la comunicación con el servidor | Caída del servicio de API / CORS | N/A | `0` (`ApiError`) | Muestra el mensaje: *"No se pudo conectar con el servidor de la API."* |

#### f) Qué NO calcula el Front
- No filtra el array de vinos localmente cuando se pulsa *"Buscar"*; los filtros se envían al backend para ejecución en la base de datos mediante SQL (`WHERE`, `LIMIT`, `OFFSET`).
- No calcula la cantidad total de páginas por cuenta propia sin los metadatos devueltos por el backend (`total` de registros).
- No suma los porcentajes de corte ni formatea las relaciones de maridaje de forma artificial.

---

### 2. Alta y Edición de Vino

#### a) Objetivo
Registrar nuevos vinos en el catálogo comercial o modificar los atributos y cortes de uva de vinos existentes, asegurando la consistencia de datos y el cumplimiento de las restricciones enológicas de la bodega.

#### b) Datos que muestra y datos que envía
- **Datos que envía (Formulario de alta / edición):**
  - `nombre` (string, nombre comercial).
  - `anada` (number, año de cosecha).
  - `precio` (number, precio de venta > 0, RN-01).
  - `tipo` (enum: `'tinto'`, `'blanco'`, `'rosado'`, `'espumoso'`, RN-15).
  - `volumen_ml` (number, volumen en mililitros: ej. 750).
  - `graduacion_alcoholica` (number, porcentaje alcohólico).
  - `cuit_bodega` (string/cuit, bodega productora seleccionada).
  - `cepas` (array de composición): lista de objetos `[{ id_cepa: number, porcentaje: number }]`.
- **Datos que muestra:**
  - Formulario con campos de texto, numéricos y selectores precargados con los catálogos correspondientes.
  - En modo edición: datos actuales del vino recuperados previamente con `GET /vinos/{cod}`.
  - Lista dinámica de composición de cepas con botones para agregar (`[+]`) y quitar (`[-]`) renglones de uva.
  - Suma informativa o área de advertencia donde se renderiza el error retornado si los porcentajes no son válidos.

#### c) Tabla de Endpoints y Mapeo
| Dato / Acción | Endpoint | Método | Parámetros | Campo en Respuesta | Función en `front/js/api/` | Origen |
|---|---|---|---|---|---|---|
| Crear nuevo vino con composición | `/vinos` | `POST` | **Body:** `{ nombre, anada, precio, tipo, volumen_ml, graduacion_alcoholica, cuit_bodega, cepas }` | Vino creado con su `cod_vino` asignado | `crearVino(data)` en `vinos.js` | Enunciado / Bocetos |
| Consultar vino para precargar en edición | `/vinos/{cod}` | `GET` | **Ruta:** `cod` | Objeto vino completo incluyendo array `cepas` | `obtenerVino(cod)` en `vinos.js` | Enunciado |
| Guardar cambios de un vino existente | `/vinos/{cod}` | `PUT` | **Ruta:** `cod`<br>**Body:** Datos modificados del vino y composición | Vino actualizado | `actualizarVino(cod, data)` en `vinos.js` | Enunciado |
| Dar de baja un vino | `/vinos/{cod}` | `DELETE` | **Ruta:** `cod` | Confirmación de eliminación / `204 No Content` | `eliminarVino(cod)` en `vinos.js` | Enunciado |
| Catálogo de cepas disponibles | `/cepas` | `GET` | Ninguno | Array de cepas `[{ id_cepa, nombre, tipo }]` | `listarCepas()` *(función sugerida)* | **PROPUESTO** |
| Catálogo de bodegas disponibles | `/bodegas` | `GET` | Ninguno | Array de bodegas `[{ cuit, razon_social }]` | `listarBodegas()` *(función sugerida)* | **PROPUESTO** |

#### d) Flujo Paso a Paso
1. Se cargan los selectores de Cepas (`GET /cepas`) y Bodegas (`GET /bodegas`).
2. Si la ruta es de edición (`#/vinos/editar/:cod`), se invoca `obtenerVino(cod)` y se pueblan todos los inputs del formulario y los renglones de cepas.
3. El usuario completa los datos y define la composición agregando o quitando filas de cepas con sus respectivos porcentajes.
4. Al hacer clic en *"Guardar Vino"*, el front arma el payload JSON y ejecuta `crearVino(data)` o `actualizarVino(cod, data)`.
5. Si la API responde con éxito (`200` o `201`), se notifica al usuario y se redirige al Catálogo (`#/vinos`).
6. Si la API rechaza la operación (ej. porcentajes no suman 100), se captura el `ApiError` y se despliega su `message` textualmente en la caja de alertas del formulario.
7. En caso de solicitar la baja mediante *"Eliminar"*, se llama a `eliminarVino(cod)`; si el vino tiene movimientos históricos asociados, la API deniega la acción y el error se muestra en pantalla.

#### e) Errores Esperables y Tratamiento
| Escenario de Error | Regla / Restricción | SQLSTATE | HTTP Status | Tratamiento en Frontend |
|---|---|---|---|---|
| Composición de cepas no suma 100% | **RN-05** (Constraint trigger diferido en `vino_cepa`) | `P0001` (Raise Exception) | `409 Conflict` o `422 Unprocessable Entity` | Se muestra textualmente el mensaje del backend: *"RN-05: La suma de porcentajes de las cepas debe ser exactamente 100%."* |
| Vino duplicado (mismo nombre, añada y volumen) | Clave candidata `UNIQUE(nombre, anada, volumen_ml)` | `23505` (unique_violation) | `409 Conflict` | Muestra el error de la API indicando que ya existe un vino con dicha combinación. |
| Precio menor o igual a cero | **RN-01** (`CHECK precio > 0`) | `23514` (check_violation) | `422 Unprocessable Entity` | Se muestra el mensaje devuelto por el backend. |
| Campos obligatorios nulos (ej. bodega) | Restricción `NOT NULL` | `23502` (not_null_violation) | `422 Unprocessable Entity` | Muestra qué campo obligatorio falta según la API. |
| Intento de eliminar vino con ventas, transferencias o ingresos | **RN-14** (Acción referencial `RESTRICT` para preservar historial) | `23503` (foreign_key_violation) | `409 Conflict` | Muestra el mensaje devuelto por la API impidiendo borrar un vino con historial de movimientos. |

#### f) Qué NO calcula el Front
- No valida de forma excluyente si los porcentajes suman 100 ni bloquea el envío si la suma difiere; la regla de integridad de negocio es potestad exclusiva del constraint trigger en PostgreSQL.
- No genera el identificador del vino (`cod_vino`), ya que es una secuencia/identidad subrogada gestionada por la base de datos.
