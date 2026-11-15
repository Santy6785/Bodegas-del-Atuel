# Mapa de Pantallas y Endpoints - Bodegas del Atuel (Etapa 7)

> **Versión de referencia del contrato:** Revisado y contrastado contra `docs/api-contrato.md` (versión v0.6.2, commit `8ac52c6`). Última revisión del mapa: 2026-11-08.

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
  - `tipo` (string, select: tinto, blanco, rosado, espumante).
  - `id_cepa` (number, select: ID numérico de la cepa).
  - `cuit_bodega` (string de 11 dígitos, select: CUIT de la bodega).
  - `anada` (number, año de cosecha).
  - `nombre` (string, búsqueda parcial por nombre comercial).
  - `page` (number, página actual).
  - `page_size` (number, cantidad de registros por página).
- **Datos que muestra en la grilla principal:**
  - Código de vino (`cod_vino`), Nombre comercial (`nombre`), Tipo (`tipo`), Añada (`anada`), Precio unitario vigente (`precio`), Bodega productora (`bodega_razon_social` y `cuit_bodega`).
  - Paginador interactivo (`anterior`, `siguiente`, número de página actual).
- **Datos que muestra en el panel/modal de detalle:**
  - Código, nombre comercial, añada y bodega.
  - Precio vigente formateado en moneda.
  - Composición de cepas: lista con nombre de cada cepa y su respectivo porcentaje de corte (ej. *"85% Malbec, 15% Cabernet Sauvignon"*).
  - Maridajes sugeridos con temperatura de servicio recomendada (ej. *"Carnes Rojas (17°C)"*).

#### c) Tabla de Endpoints y Mapeo
| Dato / Acción | Endpoint | Método | Parámetros | Campo en Respuesta | Función en `front/js/api/` | Origen |
|---|---|---|---|---|---|---|
| Listado general filtrado y paginado | `/vinos` | `GET` | **Query:** `page`, `page_size`, `tipo`, `id_cepa`, `cuit_bodega`, `anada`, `nombre` | Objeto `{ items, page, page_size, total }` con array de vinos y metadatos de paginación | `listarVinos(filtros)` en `vinos.js` | Enunciado / Bocetos (Issue #12) |
| Detalle enológico completo (composición y maridaje) | `/vinos/{cod}` | `GET` | **Ruta:** `cod` (cod_vino) | Objeto con datos de vino, bodega, array `composicion: [{ id_cepa, nombre, tipo, porcentaje }]`, array `maridajes: [{ id_maridaje, nombre, temperatura_servicio }]` y objeto `stock` | `obtenerVino(cod)` en `vinos.js` | Enunciado / Bocetos (Issue #12) |
| Catálogo de cepas (para combo de filtro) | `/cepas` | `GET` | Ninguno | Array de cepas `[{ id_cepa, nombre, tipo }]` | `listarCepas()` en `catalogos.js` | **PROPUESTO** (No listado en mínimos) |
| Catálogo de bodegas (para combo de filtro) | `/bodegas` | `GET` | Ninguno | Array de bodegas `[{ cuit, razon_social, domicilio }]` | `listarBodegas()` en `catalogos.js` | **PROPUESTO** (No listado en mínimos) |

#### d) Flujo Paso a Paso
1. Al cargar la pantalla, se solicitan en paralelo los datos de los selectores auxiliares (`GET /cepas` y `GET /bodegas`) y el primer lote de vinos (`GET /vinos?page=1&page_size=20`).
2. Se renderiza la tabla de resultados y los controles de paginación.
3. Al interactuar con los filtros y presionar *"Buscar"* (o cambiar de página), se dispara nuevamente `listarVinos()` con los parámetros acumulados y se refresca el contenido de la tabla.
4. Al hacer clic en el botón *"Detalle"* de una fila, se invoca `obtenerVino(cod)` pasando el código del vino seleccionado.
5. Se abre el panel lateral/overlay desplegando la composición de cortes (%) y los maridajes con su temperatura.
6. El usuario puede cerrar el panel mediante el botón *[Cerrar]* sin recargar la página.

#### e) Errores Esperables y Tratamiento
| Escenario de Error | Regla / Restricción | SQLSTATE | HTTP Status | Tratamiento en Frontend |
|---|---|---|---|---|
| Formato de código de vino inválido en la URL | Error de tipo de dato (ej. alfanumérico donde va entero) | `22P02` | `400 Bad Request` | Muestra el mensaje de la API indicando identificador inválido. |
| Vino inexistente al solicitar detalle | Registro no encontrado | (sin SQLSTATE) | `404 Not Found` | Muestra *"El vino solicitado no existe o fue dado de baja"* tal cual responda el backend. |
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
  - `tipo` (enum tipo_vino de la base: `'tinto'`, `'blanco'`, `'rosado'`, `'espumante'`).
  - `anada` (number, año de cosecha).
  - `volumen_ml` (number, volumen en mililitros: ej. 750).
  - `graduacion` (string/number decimal, graduación alcohólica entre 5 y 20, RN-15).
  - `precio` (string/number decimal, precio de venta > 0, RN-01).
  - `cuit_bodega` (string de 11 dígitos, bodega productora seleccionada).
  - `composicion` (array de composición): lista de objetos `[{ id_cepa: number, porcentaje: string }]` (la suma debe ser 100, RN-05).
  - `maridajes` (array de IDs): lista de identificadores numéricos de maridaje `[id_maridaje]`.
- **Datos que muestra:**
  - Formulario con campos de texto, numéricos y selectores precargados con los catálogos correspondientes.
  - En modo edición: datos actuales del vino recuperados previamente con `GET /vinos/{cod}`.
  - Lista dinámica de composición de cepas con botones para agregar (`[+]`) y quitar (`[-]`) renglones de uva.
  - Suma informativa o área de advertencia donde se renderiza el error retornado si los porcentajes no son válidos.

#### c) Tabla de Endpoints y Mapeo
| Dato / Acción | Endpoint | Método | Parámetros | Campo en Respuesta | Función en `front/js/api/` | Origen |
|---|---|---|---|---|---|---|
| Crear nuevo vino con composición | `/vinos` | `POST` | **Body:** `{ nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega, composicion: [{ id_cepa, porcentaje }], maridajes: [id] }` | Vino creado con su `cod_vino` asignado | `crearVino(data)` en `vinos.js` | Enunciado / Bocetos |
| Consultar vino para precargar en edición | `/vinos/{cod}` | `GET` | **Ruta:** `cod` | Objeto vino completo incluyendo arrays `composicion` y `maridajes` | `obtenerVino(cod)` en `vinos.js` | Enunciado |
| Guardar cambios de un vino existente | `/vinos/{cod}` | `PUT` | **Ruta:** `cod`<br>**Body:** `{ nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega, composicion: [{ id_cepa, porcentaje }], maridajes: [id] }` | Vino actualizado | `actualizarVino(cod, data)` en `vinos.js` | Enunciado |
| Dar de baja un vino | `/vinos/{cod}` | `DELETE` | **Ruta:** `cod` | Confirmación de eliminación / `204 No Content` | `eliminarVino(cod)` en `vinos.js` | Enunciado |
| Catálogo de cepas disponibles | `/cepas` | `GET` | Ninguno | Array de cepas `[{ id_cepa, nombre, tipo }]` | `listarCepas()` en `catalogos.js` | **PROPUESTO** |
| Catálogo de bodegas disponibles | `/bodegas` | `GET` | Ninguno | Array de bodegas `[{ cuit, razon_social, domicilio }]` | `listarBodegas()` en `catalogos.js` | **PROPUESTO** |

#### d) Flujo Paso a Paso
1. Se cargan los selectores de Cepas (`GET /cepas`) y Bodegas (`GET /bodegas`).
2. Si la ruta es de edición (`#/vinos/editar/:cod`), se invoca `obtenerVino(cod)` y se pueblan todos los inputs del formulario, la composición de cepas y los maridajes seleccionados.
3. El usuario completa los datos y define la composición agregando o quitando filas de cepas (`id_cepa`) con sus respectivos porcentajes (`porcentaje`), y asigna los maridajes (`maridajes`).
4. Al hacer clic en *"Guardar Vino"*, el front arma el payload JSON y ejecuta `crearVino(data)` o `actualizarVino(cod, data)`.
5. Si la API responde con éxito (`200` o `201`), se notifica al usuario y se redirige al Catálogo (`#/vinos`).
6. Si la API rechaza la operación (ej. porcentajes no suman 100), se captura el `ApiError` y se despliega su `message` textualmente en la caja de alertas del formulario.
7. En caso de solicitar la baja mediante *"Eliminar"*, se llama a `eliminarVino(cod)`; si el vino tiene movimientos históricos asociados, la API deniega la acción y el error se muestra en pantalla.

#### e) Errores Esperables y Tratamiento
| Escenario de Error | Regla / Restricción | SQLSTATE | HTTP Status | Tratamiento en Frontend |
|---|---|---|---|---|
| Composición de cepas no suma 100% | **RN-05** (Constraint trigger diferido en `vino_cepa`, se valida al commit) | `P0001` (Raise Exception) | `409 Conflict` | Se muestra textualmente el mensaje que devuelve la API (el texto del `RAISE EXCEPTION`), junto a la sección de composición. El error llega recién al confirmar la transacción. |
| Vino duplicado (mismo nombre, añada y volumen) | Clave candidata `UNIQUE(nombre, anada, volumen_ml)` | `23505` (unique_violation) | `409 Conflict` | Muestra el error de la API indicando que ya existe un vino con dicha combinación. |
| Precio menor o igual a cero | **RN-01** (`CHECK precio > 0`) | `23514` (check_violation) | `422 Unprocessable Entity` | Se muestra el mensaje devuelto por el backend. |
| Campos obligatorios nulos (ej. bodega) | Restricción `NOT NULL` | `23502` (not_null_violation) | `422 Unprocessable Entity` | Muestra qué campo obligatorio falta según la API. |
| Intento de eliminar vino con ventas, transferencias o ingresos | **RN-14** (Acción referencial `RESTRICT` para preservar historial) | `23503` (foreign_key_violation) | `409 Conflict` | Muestra el mensaje devuelto por la API impidiendo borrar un vino con historial de movimientos. |

#### f) Qué NO calcula el Front
- No valida de forma excluyente si los porcentajes suman 100 ni bloquea el envío si la suma difiere; la regla de integridad de negocio es potestad exclusiva del constraint trigger en PostgreSQL.
- No genera el identificador del vino (`cod_vino`), ya que es una secuencia/identidad subrogada gestionada por la base de datos.

---

### 3. Nueva Venta

#### a) Objetivo
Registrar la emisión de un comprobante de venta de vinos a un cliente determinado en una sala de venta específica, enviando los renglones correspondientes y mostrando el detalle final liquidado por el servidor.

#### b) Datos que muestra y datos que envía
- **Datos que envía (Confección del comprobante):**
  - `id_cliente` (number, cliente seleccionado: socio, distribuidor o exportador).
  - `id_sala` (number, sala de venta física donde se realiza la transacción).
  - `renglones` (array de ítems vendidos): lista de objetos `[{ cod_vino: number, cantidad: number }]`.
- **Datos que muestra:**
  - Buscador de clientes (con unos 20.000 registros no corresponde un desplegable completo; se usa la búsqueda `q` de `GET /clientes`).
  - Selector de sala de venta.
  - Grilla interactiva de selección de vino y cantidad para conformar el carrito antes del envío.
  - Tabla de liquidación del comprobante emitido:
    - Columnas: Nombre de Vino, Cantidad, Precio Unitario histórico (snapshot), Porcentaje de descuento aplicado (`% Desc.`), Subtotal por renglón.
  - Resumen financiero consolidado:
    - **Subtotal bruto** (suma de precios de lista).
    - **Descuento total** (bonificación global calculada según categoría de cliente).
    - **TOTAL A PAGAR** (importe neto liquidado).
  - Alerta de error en caso de rechazo por stock insuficiente (RN-09).

#### c) Tabla de Endpoints y Mapeo
| Dato / Acción | Endpoint | Método | Parámetros | Campo en Respuesta | Función en `front/js/api/` | Origen |
|---|---|---|---|---|---|---|
| Registrar y emitir el comprobante | `/comprobantes` | `POST` | **Body:** `{ id_cliente, id_sala, renglones: [{ cod_vino, cantidad }] }` | Comprobante emitido con `nro_comprobante` asignado | `crearComprobante(data)` en `comprobantes.js` | Enunciado / Bocetos |
| Consultar detalle liquidado del comprobante | `/comprobantes/{nro}` | `GET` | **Ruta:** `nro` (nro_comprobante) | Objeto con cabecera (`subtotal`, `descuento`, `total`, `fecha`) y array `renglones` (`precio_unitario`, `descuento_pct`, `subtotal`) | `obtenerComprobante(nro)` en `comprobantes.js` | Enunciado / Bocetos |
| Buscar y seleccionar el cliente | `/clientes` | `GET` | **Query:** `page`, `page_size`, `tipo_cliente`, `q` (búsqueda por documento o apellido) | Objeto paginado `{ items, page, page_size, total }`; cada ítem con `id_cliente`, `apellido_razon_social`, `nombre`, `tipo_documento`, `nro_documento`, `tipo_cliente`, `descuento_pct` | `listarClientes(filtros)` en `clientes.js` | Enunciado |
| Selector de salas de venta | `/salas` | `GET` | Ninguno | Array de salas `[{ id_sala, calle, numero, dia_cierre, codigo_postal }]` (no existe campo "nombre"; la etiqueta del desplegable se arma con calle y número) | `listarSalas()` en `catalogos.js` | **PROPUESTO** (No listado en mínimos) |
| Selector de vinos disponibles para venta | `/vinos` | `GET` | **Query:** `nombre` (búsqueda parcial), `page`, `page_size` | Objeto paginado `{ items, page, page_size, total }` (cada ítem con `cod_vino`, `nombre`, `precio`, etc.) | `listarVinos(filtros)` en `vinos.js` | Enunciado |

#### d) Flujo Paso a Paso
1. Al acceder a la pantalla, se carga el selector de Salas de venta (`GET /salas`); el cliente y los vinos se buscan a demanda (`GET /clientes` y `GET /vinos?nombre=...`) en lugar de cargarse completos.
2. El operador selecciona el cliente y la sala de venta física.
3. El operador elige un vino, ingresa la cantidad deseada y pulsa *"Agregar"*, acumulando los pares `(cod_vino, cantidad)` en una lista local temporal de ítems para el comprobante.
4. Al hacer clic en *"Confirmar Venta"*, el front invoca `crearComprobante({ id_cliente, id_sala, renglones })`.
5. Si la operación es exitosa, el comprobante devuelto por `POST /comprobantes` ya trae los importes calculados por la base (respuesta 201 con el comprobante completo) y se muestra ese detalle liquidado (Subtotal, Descuento Total y Total a Pagar). `obtenerComprobante(nro)` queda para consultas posteriores.
6. Si ocurre un fallo (ej. stock insuficiente en la sala), la API responde con error `409` y el mensaje de regla de negocio devuelto se expone de forma directa y visible.

#### e) Decisión de Diseño: Sin Vista Previa de Cálculos en el Cliente
> [!IMPORTANT]
> **Decisión arquitectónica adoptada:** El frontend **NO** calcula previamente subtotales, bonificaciones ni el importe final a pagar.
> Debido a que la política del proyecto prohíbe replicar la lógica de negocio en el cliente, el front se limita a enviar la estructura `(id_cliente, id_sala, renglones)` a `POST /comprobantes`. El cálculo del descuento por tipo de cliente (RN-06), el precio unitario del momento y los subtotales/totales (RN-08) son computados íntegramente por los triggers y funciones de la base de datos.
> La visualización de los importes finales liquidados se obtiene una vez creado el documento mediante la respuesta de creación o consultando `GET /comprobantes/{nro}`.

#### f) Errores Esperables y Tratamiento
| Escenario de Error | Regla / Restricción | SQLSTATE | HTTP Status | Tratamiento en Frontend |
|---|---|---|---|---|
| Stock insuficiente de uno o más vinos en la sala | **RN-09** (`CHECK stock >= 0` o trigger de validación de existencias en sala) | `P0001` (Raise Exception) o `23514` | `409 Conflict` | Se expone en alerta el mensaje exacto del servidor (el contrato da como ejemplo *«Stock insuficiente del vino 10 en la sala 1 (RN-09)»*), sin modificarlo. |
| Cliente inexistente o dado de baja | Restricción de clave foránea sobre el cliente | `23503` | `422 Unprocessable Entity` | Se muestra el mensaje devuelto por la API. |
| Sala inexistente | Restricción de clave foránea sobre la sala | `23503` | `422 Unprocessable Entity` | Se muestra el mensaje devuelto por la API. |
| Cantidad vendida menor o igual a cero | Validación de dominio en renglón (`cantidad > 0`) | `23514` | `422 Unprocessable Entity` | Se muestra el mensaje devuelto por la API. |
| Bloqueo concurrente por alta demanda en sala | Concurrencia transaccional / serialización | `40001` o `40P01` | `503 Service Unavailable` | Mensaje de reintento de operación devuelto por el backend. |

#### g) Qué NO calcula el Front
- No aplica el porcentaje de descuento del cliente (10% socio, 20% distribuidor, 30% exportador) de forma manual.
- No multiplica precio por cantidad ni deduce subtotales.
- No suma los renglones para obtener el total general.
- No descuenta ni consulta el saldo de stock en memoria para decidir si habilita la venta; es el backend quien rechaza o aprueba atómicamente la transacción.

---

### 4. Transferencias de Stock

#### a) Objetivo
Administrar las solicitudes de reposición de botellas de vino desde el depósito central hacia las diferentes salas de venta, coordinando el ciclo de confección, cierre y procesamiento del movimiento.

#### b) Datos que muestra y datos que envía
- **Datos que envía:**
  - *Alta de transferencia:* `id_sala` (number, sala solicitante).
  - *Agregar ítem:* `cod_vino` (number) y `cantidad` (number).
  - *Cambios de estado:* `nro_transferencia` en la URL para terminar y procesar.
- **Datos que muestra:**
  - Formulario de solicitud: selector de Sala Solicitante, fecha de confección (automática/del sistema) e inputs para agregar vinos y cantidades.
  - Tabla de transferencias existentes con sus estados:
    - Columnas: Nro de transferencia (`nro`), Fecha (`fecha_confeccion`), Sala solicitante (`sala`), Vinos y cantidades agregadas (provienen de `GET /transferencias/{nro}`; el listado trae solo la cabecera), Estado actual (`estado`: `en_confeccion`, `terminado`, `procesado`), Acciones disponibles según el estado.
  - Botones de acción dinámicos: *"Terminar Transferencia"* y *"Procesar Transferencia"* (la API no provee endpoints DELETE para transferencias ni renglones individuales).

#### c) Tabla de Endpoints y Mapeo
| Dato / Acción | Endpoint | Método | Parámetros | Campo en Respuesta | Función en `front/js/api/` | Origen |
|---|---|---|---|---|---|---|
| Crear cabecera de transferencia | `/transferencias` | `POST` | **Body:** `{ id_sala }` | Transferencia creada en estado `en_confeccion` con su `nro_transferencia` | `crearTransferencia(data)` en `transferencias.js` | Enunciado / Bocetos |
| Agregar renglón de vino a la transferencia | `/transferencias/{nro}/renglones` | `POST` | **Ruta:** `nro`<br>**Body:** `{ cod_vino, cantidad }` | Renglón creado y anexado | `agregarRenglonTransferencia(nro, data)` en `transferencias.js` | Enunciado / Bocetos |
| Cambiar estado a terminado | `/transferencias/{nro}/terminar` | `POST` | **Ruta:** `nro` | Transferencia actualizada en estado `terminado` | `terminarTransferencia(nro)` en `transferencias.js` | Enunciado / Bocetos |
| Procesar transferencia (impacta stock) | `/transferencias/{nro}/procesar` | `POST` | **Ruta:** `nro` | Confirmación y transferencia en estado `procesado` | `procesarTransferencia(nro)` en `transferencias.js` | Enunciado / Bocetos |
| Listado de transferencias para la grilla | `/transferencias` | `GET` | **Query:** `page`, `page_size`, `estado`, `id_sala` | Objeto paginado `{ items, page, page_size, total }` con la cabecera de cada transferencia (sin renglones) | `listarTransferencias(filtros)` en `transferencias.js` | **PROPUESTO** (Requerido por Boceto #4) |
| Detalle de una transferencia (renglones y estado) | `/transferencias/{nro}` | `GET` | **Ruta:** `nro` | Cabecera, `estado` y array `renglones` (`cod_vino`, `cantidad`) | `obtenerTransferencia(nro)` en `transferencias.js` | **PROPUESTO** (Necesario para habilitar los botones según el estado) |
| Selector de salas solicitantes | `/salas` | `GET` | Ninguno | Array de salas `[{ id_sala, calle, numero, dia_cierre, codigo_postal }]` | `listarSalas()` en `catalogos.js` | **PROPUESTO** |

#### d) Flujo Paso a Paso
1. Se carga el listado de transferencias existentes (`GET /transferencias`) y el selector de salas (`GET /salas`). Al seleccionar o expandir una transferencia se consulta su detalle (`GET /transferencias/{nro}`) para mostrar sus renglones y habilitar los botones según su estado.
2. Para solicitar una nueva transferencia, el usuario selecciona la sala y pulsa *"Crear Solicitud"*, enviando `POST /transferencias`.
3. Con el `nro_transferencia` obtenido (estado `en_confeccion`), el usuario agrega uno o más vinos indicando la cantidad deseada mediante `POST /transferencias/{nro}/renglones`.
4. Una vez agregados los ítems, el usuario presiona *"Terminar Transferencia"*, disparando `POST /transferencias/{nro}/terminar`. El estado cambia a `terminado`.
5. Desde la tabla general, un operador con permisos pulsa *"Procesar Transferencia"*, invocando `POST /transferencias/{nro}/procesar`.
6. En el backend, el procedimiento almacenado descuenta del depósito central, acredita en la sala solicitante y pasa la transferencia a `procesado`.
7. Si el depósito no cuenta con stock suficiente de algún vino, la API rechaza el procesamiento con código `409` y el mensaje de stock insuficiente se expone en la interfaz.

#### e) Matriz de Estados y Habilitación de Botones
| Estado Actual | Botones Habilitados en Frontend | Endpoint Invocado | Estado Resultante | Reglas Aplicadas |
|---|---|---|---|---|
| `en_confeccion` | - **Agregar Renglón**<br>- **Terminar Transferencia**<br>*(Quitar renglón y eliminar transferencia no disponibles en la API; no figuran en el contrato)* | - `POST /transferencias/{nro}/renglones`<br>- `POST /transferencias/{nro}/terminar` | `terminado` (si se termina) o se mantiene `en_confeccion` | **RN-12**: Solo se permite alterar renglones si está en confección.<br>**RN-11**: Fecha inmutable. |
| `terminado` | - **Procesar Transferencia** *(Modificar y agregar renglones quedan estrictamente bloqueados)* | - `POST /transferencias/{nro}/procesar` | `procesado` | **RN-11**: Solo se puede procesar si está terminado.<br>**RN-12**: No se admiten cambios en renglones. |
| `procesado` | *Ninguno* (Documento histórico cerrado e inmutable) | *Sin endpoints de modificación* | Estado final | **RN-11**: El movimiento ya impactó en las tablas de stock; no puede revertirse ni alterarse. |

#### f) Errores Esperables y Tratamiento
| Escenario de Error | Regla / Restricción | SQLSTATE | HTTP Status | Tratamiento en Frontend |
|---|---|---|---|---|
| Stock insuficiente en depósito central al procesar | **RN-09** (`CHECK stock_deposito >= 0` o procedimiento `sp_procesar_transferencia`) | `P0001` o `23514` | `409 Conflict` | Muestra textualmente el mensaje del backend indicando qué vino no cuenta con existencias en depósito. |
| Intento de procesar transferencia no terminada | **RN-11** (Procedimiento valida `estado = 'terminado'`) | `P0001` | `409 Conflict` | Muestra el mensaje de la regla tal como lo devuelve la API. |
| Intento de agregar renglones a transferencia terminada o procesada | **RN-12** (Trigger sobre `renglon_transferencia` valida estado en cabecera) | `P0001` | `409 Conflict` | Muestra el mensaje de bloqueo emitido por el trigger. |
| Modificación indebida de fecha de confección | **RN-11** (Trigger BEFORE UPDATE bloquea cambios en `fecha_confeccion`) | `P0001` | `409 Conflict` | Muestra la prohibición de cambio de fecha. |

#### g) Qué NO calcula el Front
- No calcula existencias ni descuenta botellas del stock del depósito.
- No incrementa saldos en la sala solicitante.
- No decide si una transferencia es válida para procesarse sin consultar el estado retornado por el servidor.

---

### 5. Tablero de Control (Dashboard)

#### a) Objetivo
Brindar al personal de gestión y supervisión una vista ejecutiva con indicadores clave de negocio: ranking de vinos con mayor volumen de comercialización, recaudación trimestral segmentada por sala de venta y detección temprana de quiebres de stock.

#### b) Datos que muestra y datos que envía
- **Widget 1: Top 10 Vinos Más Vendidos:**
  - *Datos que envía:* Parámetro de límite `limit=10` (por defecto 10, máx. 100).
  - *Datos que muestra:* Ranking ordenado con posición, código de vino, nombre comercial y botellas vendidas (`{ posicion, cod_vino, nombre, botellas_vendidas }`).
- **Widget 2: Ventas por Sala en el Último Trimestre:**
  - *Datos que envía:* Parámetro `periodo=ultimo_trimestre` (opcional en el contrato; el Tablero lo envía siempre porque el contrato no documenta qué devuelve el endpoint si se omiten todos los parámetros).
  - *Datos que muestra:* Gráfico de barras comparativo y tabla resumen con Sala de Venta (`id_sala`, `calle`, `numero`) vs. Total Facturado en Pesos (`monto_total`).
- **Widget 3: Vinos Sin Stock en Sala:**
  - *Datos que envía:* `id_sala` (number, sala elegida en el combo; opcional en el contrato, pero el Tablero siempre lo envía).
  - *Datos que muestra:* Listado de vinos cuyo stock es cero en esa sala (`{ cod_vino, nombre, stock_deposito }`), indicando además el stock en depósito central.

#### c) Tabla de Endpoints y Mapeo
| Dato / Acción | Endpoint | Método | Parámetros | Campo en Respuesta | Función en `front/js/api/` | Origen |
|---|---|---|---|---|---|---|
| Ranking de vinos más vendidos | `/reportes/top-vinos` | `GET` | **Query:** `limit=10` | Array `[{ posicion, cod_vino, nombre, botellas_vendidas }]` | `topVinos(params)` en `reportes.js` | Enunciado / Boceto #5 |
| Recaudación por sala (trimestre) | `/reportes/ventas-por-sala` | `GET` | **Query (opcionales):** `periodo`, `fecha_desde`, `fecha_hasta`. El Tablero envía `periodo=ultimo_trimestre` | Array `[{ id_sala, calle, numero, monto_total }]` | `ventasPorSala({ periodo: "ultimo_trimestre" })` en `reportes.js` | Enunciado / Boceto #5 |
| Consulta de vinos agotados por sala | `/reportes/vinos-sin-stock` | `GET` | **Query:** `id_sala` (opcional en el contrato; el Tablero siempre lo envía) | Array `[{ cod_vino, nombre, stock_deposito }]` | `vinosSinStock({ id_sala })` en `reportes.js` | Enunciado / Boceto #5 |
| Selector de salas para filtrado de quiebres | `/salas` | `GET` | Ninguno | Array de salas `[{ id_sala, calle, numero, dia_cierre, codigo_postal }]` | `listarSalas()` en `catalogos.js` | **PROPUESTO** |

#### d) Flujo Paso a Paso
1. Al acceder al Tablero, se disparan en paralelo las peticiones para el Top 10 (`GET /reportes/top-vinos?limit=10`), las ventas trimestrales (`GET /reportes/ventas-por-sala?periodo=ultimo_trimestre`) y el catálogo de salas (`GET /salas`).
2. Se dibuja el listado del Top 10 con los totales devueltos.
3. Se renderiza el gráfico de barras comparativo de ventas por sala utilizando las alturas proporcionales de las barras calculadas visualmente según el valor de recaudación enviado por el servidor.
4. El selector de salas del Widget 3 se inicializa por defecto con la primera sala disponible y se ejecuta `vinosSinStock({ id_sala })`.
5. Si el usuario cambia la sala en el selector, se dispara nuevamente `vinosSinStock({ id_sala: nuevoId })` y se actualiza dinámicamente la lista de productos agotados.

#### e) Errores Esperables y Tratamiento
| Escenario de Error | Regla / Restricción | SQLSTATE | HTTP Status | Tratamiento en Frontend |
|---|---|---|---|---|
| Sala inválida o inexistente en filtro de stock | Identificador fuera de catálogo | `22P02` o sin SQLSTATE (404) | `400 Bad Request` o `404 Not Found` | Muestra el error de la API dentro de la tarjeta de vinos sin stock. |
| Rango de fechas inconsistente | Parámetros temporales invertidos | Lógica de consulta | `422 Unprocessable Entity` | No aplica al Tablero (solo envía `periodo`); el contrato no documenta este error. |
| Falla general de base de datos | Timeout o indisponibilidad | `40001` / `57P01` | `500 Internal Server Error` / `503` | Se expone el mensaje de la API y se ofrece un botón de recarga puntual por widget. |

#### f) Qué NO calcula el Front
- No suma las ventas de cada comprobante para armar los acumulados ni las posiciones del ranking; el cálculo proviene de consultas SQL agregadas ejecutadas en la base.
- No agrupa ventas por trimestre ni discrimina fechas en el cliente; el backend procesa la vista o consulta agregada (`S8`).
- No filtra el inventario localmente para deducir qué vinos tienen stock en 0; el endpoint `/reportes/vinos-sin-stock` (consigna S6) resuelve en la base qué vinos no tienen stock en la sala.

---

## 🗂️ Datos Auxiliares (Lookups)

Para que los componentes de selección (selectores desplegables y búsquedas en combos) funcionen sin valores fijos en el código, el frontend requiere consumir endpoints de catálogo/lookup.

La tabla siguiente define el estado de cada catálogo requerido por la interfaz:

| Catálogo / Lookup | Uso en Pantallas | Endpoint | Estado | Función en `front/js/api/` | Justificación y Observaciones |
|---|---|---|---|---|---|
| **Cepas** | - Catálogo (Filtro)<br>- Alta/Edición de Vino (Composición) | `GET /cepas` | **PROPUESTO / FALTANTE** | `listarCepas()` en `catalogos.js` | Necesario para seleccionar cepas al armar la mezcla (%) de un vino o filtrar el catálogo. No figura en la lista mínima del enunciado. |
| **Bodegas** | - Catálogo (Filtro)<br>- Alta/Edición de Vino | `GET /bodegas` | **PROPUESTO / FALTANTE** | `listarBodegas()` en `catalogos.js` | Permite asociar el vino con la bodega elaboradora (`cuit_bodega`). No figura en los mínimos del enunciado. |
| **Salas de Venta** | - Nueva Venta<br>- Transferencias (Solicitante)<br>- Tablero (Filtro stock) | `GET /salas` | **PROPUESTO / FALTANTE** | `listarSalas()` en `catalogos.js` | Esencial para asignar comprobantes a su punto de venta y direccionar transferencias. No figura en los mínimos del enunciado. |
| **Maridajes** | - Detalle de Vino (Catálogo)<br>- Alta de Maridajes | `GET /maridajes` | **PROPUESTO / FALTANTE** | `listarMaridajes()` en `catalogos.js` | Requerido si se desea asociar o consultar maridajes formalmente. No figura en los mínimos del enunciado. |
| **Tipos de Vino** | - Catálogo (Filtro)<br>- Alta/Edición de Vino | Sin endpoint (lista fija local) | **LOCAL** | Constante en el front | Los valores son los del enum `tipo_vino` de la base: `'tinto'`, `'blanco'`, `'rosado'`, `'espumante'`. No requiere endpoint; el valor que se envía a la API va en minúscula. |
| **Clientes** | - Nueva Venta | `GET /clientes` | **EXISTENTE (Enunciado)** | `listarClientes(filtros)` en `clientes.js` | Devuelve clientes (socios, distribuidores, exportadores) para vincular al comprobante. Con unos 20.000 registros requiere búsqueda por texto (`q`). |
| **Vinos (Activos)** | - Nueva Venta (Renglones)<br>- Transferencias (Renglones) | `GET /vinos` | **EXISTENTE (Enunciado)** | `listarVinos(filtros)` en `vinos.js` | Se utiliza para autocompletar la selección de botellas a vender o transferir. |
| **Historial de Transferencias** | - Transferencias (Grilla) | `GET /transferencias` | **PROPUESTO / FALTANTE** | `listarTransferencias(filtros)` en `transferencias.js` | El boceto de la pantalla #4 exige listar las transferencias existentes y sus estados (`en_confeccion`, `terminado`, `procesado`). El enunciado solo incluye `POST` para el circuito. |

---

## 📊 Matriz de Resumen: Pantalla vs. Endpoint

La siguiente matriz cruza cada pantalla diseñada con los endpoints correspondientes, indicando el tipo de operación:

> **Nota:** en la columna *Estado / Origen*, "Implementado" indica que existe la función correspondiente en `front/js/api/`; no significa que el endpoint ya esté implementado en la API.

| Endpoint | Método | 1. Catálogo de Vinos | 2. Alta / Edición Vino | 3. Nueva Venta | 4. Transferencias | 5. Tablero (Dashboard) | Estado / Origen |
|---|:---:|:---:|:---:|:---:|:---:|:---:|---|
| `/salud` | `GET` | Transversal | Transversal | Transversal | Transversal | Transversal | Enunciado / Implementado |
| `/vinos` | `GET` | **Principal (Grilla)** | - | Lookup (Renglones) | Lookup (Renglones) | - | Enunciado / Implementado |
| `/vinos/{cod}` | `GET` | **Detalle (Modal)** | Precarga edición | - | - | - | Enunciado / Implementado |
| `/vinos` | `POST` | - | **Creación** | - | - | - | Enunciado / Implementado |
| `/vinos/{cod}` | `PUT` | - | **Edición** | - | - | - | Enunciado / Implementado |
| `/vinos/{cod}` | `DELETE` | - | **Baja (RN-14)** | - | - | - | Enunciado / Implementado |
| `/cepas` | `GET` | Lookup (Filtro) | Lookup (Corte) | - | - | - | **PROPUESTO / FALTANTE** |
| `/bodegas` | `GET` | Lookup (Filtro) | Lookup (Bodega) | - | - | - | **PROPUESTO / FALTANTE** |
| `/maridajes` | `GET` | Lookup (Filtro) | Lookup (Maridajes) | - | - | - | **PROPUESTO / FALTANTE** |
| `/clientes` | `GET` | - | - | **Lookup (Cliente)** | - | - | Enunciado / Implementado |
| `/salas` | `GET` | - | - | **Lookup (Sala)** | **Lookup (Sala)** | **Lookup (Filtro)** | **PROPUESTO / FALTANTE** |
| `/comprobantes` | `POST` | - | - | **Emisión de Venta** | - | - | Enunciado / Implementado |
| `/comprobantes/{nro}` | `GET` | - | - | **Consulta Liquidada** | - | - | Enunciado / Implementado |
| `/transferencias` | `GET` | - | - | - | **Principal (Grilla)** | - | **PROPUESTO / FALTANTE** |
| `/transferencias/{nro}` | `GET` | - | - | - | **Detalle y estado (botones)** | - | **PROPUESTO / FALTANTE** |
| `/transferencias` | `POST` | - | - | - | **Crear Solicitud** | - | Enunciado / Implementado |
| `/transferencias/{nro}/renglones` | `POST` | - | - | - | **Agregar Ítem** | - | Enunciado / Implementado |
| `/transferencias/{nro}/terminar` | `POST` | - | - | - | **Cambio a Terminado** | - | Enunciado / Implementado |
| `/transferencias/{nro}/procesar` | `POST` | - | - | - | **Impactar Stock** | - | Enunciado / Implementado |
| `/reportes/top-vinos` | `GET` | - | - | - | - | **Widget 1 (Top 10)** | Enunciado / Implementado |
| `/reportes/ventas-por-sala` | `GET` | - | - | - | - | **Widget 2 (Gráfico)** | Enunciado / Implementado |
| `/reportes/vinos-sin-stock` | `GET` | - | - | - | - | **Widget 3 (Quiebres)** | Enunciado / Implementado |

---

## ⚠️ Brechas y Pedidos para el Equipo de API

Al contrastar los requerimientos de interfaz plasmados en los bocetos de la issue #12 contra los endpoints mínimos requeridos en el enunciado, se identifican las siguientes brechas que deben coordinarse con el equipo de Backend:

### Brecha 1: Endpoints de catálogos y selectores auxiliares (`/salas`, `/cepas`, `/bodegas`, `/maridajes`)
- **Qué falta:** Endpoints de tipo `GET` que devuelvan listas clave-valor para poblar combos. Específicamente:
  - `GET /salas`: `id_sala`, `calle`, `numero`, `dia_cierre`, `codigo_postal` (no existe un campo `nombre`).
  - `GET /cepas`: id, nombre, tipo.
  - `GET /bodegas`: `cuit`, `razon_social`, `domicilio`.
  - `GET /maridajes`: id, nombre, temperatura de servicio recomendada.
- **Qué pantalla lo necesita:** Catálogo de Vinos, Alta/Edición de Vino, Nueva Venta, Transferencias y Tablero.
- **Estado:** el contrato (sección 4.7) ya las define como rutas de primer nivel (`/salas`, `/cepas`, `/bodegas`, `/maridajes`, `/transportistas`, `/localidades`) y el front ya tiene las funciones en `catalogos.js`; falta implementarlas en la API.

### Brecha 2: Listado y consulta de transferencias (`GET /transferencias`)
- **Qué falta:** Un endpoint para obtener las transferencias solicitadas, sus fechas, salas y estados actuales (`en_confeccion`, `terminado`, `procesado`). El enunciado del TP solo contempla la creación, adición de renglones y cambios de estado por número, pero no la lista previa.
- **Qué pantalla lo necesita:** Pantalla 4 (Transferencias de Stock).
- **Propuesta de solución:** `GET /transferencias?id_sala=&estado=&page=&page_size=` devuelve la cabecera de cada transferencia (paginada), y `GET /transferencias/{nro}` devuelve la cabecera con sus renglones y su estado. Este último es imprescindible para habilitar los botones según el estado y para que la pantalla sobreviva a una recarga.

### Brecha 3: Parámetro de sala en reporte de vinos sin stock
- **Contrato:** `GET /reportes/vinos-sin-stock` acepta `id_sala` como parámetro **opcional** (`/reportes/vinos-sin-stock?id_sala={id_sala}`); el contrato no define qué devuelve si se omite.
- **Qué pantalla lo necesita:** Pantalla 5 (Tablero de Control - Widget 3).
- **Alineación con el contrato:** El frontend debe enviar siempre el parámetro `id_sala` con el ID de la sala seleccionada en el combo, cumpliendo con la nomenclatura `snake_case` del contrato.

### Brecha 4: Parámetros de rango temporal en ventas por sala
- **Contrato:** `GET /reportes/ventas-por-sala` acepta los parámetros opcionales `periodo` (ej. `ultimo_trimestre`), `fecha_desde` y `fecha_hasta` (ISO `YYYY-MM-DD`). El contrato no documenta qué devuelve si se omiten todos.
- **Qué pantalla lo necesita:** Pantalla 5 (Tablero de Control - Widget 2).
- **Alineación con el contrato:** El frontend invoca `GET /reportes/ventas-por-sala?periodo=ultimo_trimestre`. **Pedido al equipo de API:** documentar el comportamiento cuando se omiten los parámetros.

### Brecha 5: Estructura de paginación en `/vinos` y listados
- **Qué falta:** Definir el contrato exacto de paginación entre front y backend para evitar discrepancias.
- **Propuesta de solución:**
  - Parámetros de petición: `page` (número base 1) y `page_size` (límite de ítems, máx. 100).
  - Estructura de respuesta según el contrato:
    ```json
    {
      "items": [ /* lista de elementos */ ],
      "total": 128,
      "page": 1,
      "page_size": 20
    }
    ```
  - Los reportes y los catálogos auxiliares no se paginan: devuelven directamente un arreglo JSON.

### Brecha 6: Formato unificado de respuestas de error
- **Qué falta:** Estandarizar la clave donde viaja el mensaje textual de error para que la capa `client.js` lo extraiga limpiamente sin ambigüedad.
- **Propuesta de solución:**
  - Utilizar el formato unificado de error especificado en la sección 1.1 de `docs/api-contrato.md`:
    ```json
    {
      "error": {
        "sqlstate": "P0001",
        "mensaje": "Stock insuficiente del vino 10 en la sala 1 (RN-09)",
        "restriccion": null
      }
    }
    ```
  - **Estado:** `front/js/api/client.js` ya lee `error.mensaje` y expone `status`, `sqlstate` y `restriccion` en el `ApiError`.

### Brecha 7: Composición de cortes de cepa en `POST /vinos`
- **Qué falta:** RN-05 exige que la composición de un vino sume exactamente 100% mediante un constraint trigger diferido (`DEFERRABLE INITIALLY DEFERRED`). Si la API exigiera insertar primero el vino y luego cada cepa por llamadas HTTP independientes, el trigger fallaría en la base al hacer commit si no se maneja dentro de la misma transacción.
- **Qué pantalla lo necesita:** Pantalla 2 (Alta y Edición de Vino).
- **Propuesta de solución:** Que `POST /vinos` y `PUT /vinos/{cod}` acepten los arrays `composicion: [{ id_cepa, porcentaje }]` y `maridajes: [id]` dentro del mismo cuerpo JSON, realizando la inserción del vino y de los registros de `vino_cepa` y `vino_maridaje` en una única transacción atómica en PostgreSQL.

---

## ❓ Supuestos y Dudas a Validar con el Grupo

1. **Atribución de Comprobantes:** Se asume que `POST /comprobantes` recibe tanto la cabecera (`id_cliente`, `id_sala`) como la lista completa de renglones en un único payload, evitando múltiples llamadas para agregar renglones individuales de venta.
2. **Autenticación y Permisos:** Por el momento no se contempla login ni JWT en este mapeo; se asume que la sala de venta se elige manualmente desde un combo o que el sistema opera en modo mostrador abierto. Si se incorpora autenticación, la sala y el empleado podrían deducirse del token.
3. **Persistencia de Maridajes:** En el boceto del catálogo, el detalle de vino muestra maridajes y temperatura (`vino_maridaje` y `maridaje` vía `GET /vinos/{cod}`). Para el alta y edición, el contrato `POST /vinos` y `PUT /vinos/{cod}` ya incorpora el campo `maridajes` como una lista de identificadores numéricos `[id_maridaje]`.
4. **Política CORS:** Se asume que `CORS_ORIGINS` de la API incluye el origen desde donde se sirve el front (verificar `CORS_ORIGINS` en `.env.example` y el puerto del contenedor del front en `docker-compose.yml`).
5. **Precisión Numérica de Moneda:** El contrato serializa los importes (`NUMERIC`) como **string decimal** (ej. `"12500.00"`); el front solo los muestra (agrega `$` y separador de miles) y no opera con ellos.

