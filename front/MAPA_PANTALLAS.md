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
  - Selector de clientes (con búsqueda o listado de socios, distribuidores y exportadores).
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
| Selector de clientes | `/clientes` | `GET` | Ninguno o `params` | Array de clientes `[{ id_cliente, tipo_cliente, apellido_razon_social, nombre }]` | `listarClientes(filtros)` en `clientes.js` | Enunciado |
| Selector de salas de venta | `/salas` | `GET` | Ninguno | Array de salas `[{ id_sala, nombre, codigo_postal }]` | `listarSalas()` *(función sugerida)* | **PROPUESTO** (No listado en mínimos) |
| Selector de vinos disponibles para venta | `/vinos` | `GET` | Ninguno o filtros | Array de vinos con `cod_vino`, `nombre`, `precio` | `listarVinos()` en `vinos.js` | Enunciado |

#### d) Flujo Paso a Paso
1. Al acceder a la pantalla, se cargan los selectores de Clientes (`GET /clientes`), Salas de venta (`GET /salas`) y el catálogo de Vinos disponibles (`GET /vinos`).
2. El operador selecciona el cliente y la sala de venta física.
3. El operador elige un vino, ingresa la cantidad deseada y pulsa *"Agregar"*, acumulando los pares `(cod_vino, cantidad)` en una lista local temporal de ítems para el comprobante.
4. Al hacer clic en *"Confirmar Venta"*, el front invoca `crearComprobante({ id_cliente, id_sala, renglones })`.
5. Si la operación es exitosa, se consulta inmediatamente `obtenerComprobante(nro)` para recuperar el comprobante final con todos los cálculos oficiales de la base de datos y se presenta en pantalla el detalle liquidado (Subtotal, Descuento Total y Total a Pagar).
6. Si ocurre un fallo (ej. stock insuficiente en la sala), la API responde con error `409` y el mensaje de regla de negocio devuelto se expone de forma directa y visible.

#### e) Decisión de Diseño: Sin Vista Previa de Cálculos en el Cliente
> [!IMPORTANT]
> **Decisión arquitectónica adoptada:** El frontend **NO** calcula previamente subtotales, bonificaciones ni el importe final a pagar.
> Debido a que la política del proyecto prohíbe replicar la lógica de negocio en el cliente, el front se limita a enviar la estructura `(id_cliente, id_sala, renglones)` a `POST /comprobantes`. El cálculo del descuento por tipo de cliente (RN-06), el precio unitario del momento y los subtotales/totales (RN-08) son computados íntegramente por los triggers y funciones de la base de datos.
> La visualización de los importes finales liquidados se obtiene una vez creado el documento mediante la respuesta de creación o consultando `GET /comprobantes/{nro}`.

#### f) Errores Esperables y Tratamiento
| Escenario de Error | Regla / Restricción | SQLSTATE | HTTP Status | Tratamiento en Frontend |
|---|---|---|---|---|
| Stock insuficiente de uno o más vinos en la sala | **RN-09** (`CHECK stock >= 0` o trigger de validación de existencias en sala) | `P0001` (Raise Exception) o `23514` | `409 Conflict` | Se expone en alerta el mensaje exacto del servidor: *"Stock insuficiente del vino [Nombre] en la sala [ID]! Venta rechazada."* |
| Cliente inexistente o dado de baja | Restricción de clave foránea `FK_comprobante_cliente` | `23503` | `422 Unprocessable Entity` | Se muestra el mensaje devuelto por la API. |
| Sala inexistente | Restricción de clave foránea `FK_comprobante_sala` | `23503` | `422 Unprocessable Entity` | Se muestra el mensaje devuelto por la API. |
| Cantidad vendida menor o igual a cero | Validación de dominio en renglón (`cantidad > 0`) | `23514` | `422 Unprocessable Entity` | Se muestra el mensaje devuelto por la API. |
| Bloqueo concurrente por alta demanda en sala | Concurrencia transaccional / serialización | `40001` o `40P01` | `503 Service Unavailable` | Mensaje de reintento de operación devuelto por el backend. |

#### g) Qué NO calcula el Front
- No aplica el porcentaje de descuento del cliente (10% socio, 15% distribuidor, 20% exportador) de forma manual.
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
    - Columnas: Nro de transferencia (`nro`), Fecha (`fecha_confeccion`), Sala solicitante (`sala`), Vinos y cantidades agregadas, Estado actual (`estado`: `en_confeccion`, `terminado`, `procesado`), Acciones disponibles según el estado.
  - Botones de acción dinámicos: *"Modificar"*, *"Borrar"*, *"Terminar Transferencia"* y *"Procesar Transferencia"*.

#### c) Tabla de Endpoints y Mapeo
| Dato / Acción | Endpoint | Método | Parámetros | Campo en Respuesta | Función en `front/js/api/` | Origen |
|---|---|---|---|---|---|---|
| Crear cabecera de transferencia | `/transferencias` | `POST` | **Body:** `{ id_sala }` | Transferencia creada en estado `en_confeccion` con su `nro_transferencia` | `crearTransferencia(data)` en `transferencias.js` | Enunciado / Bocetos |
| Agregar renglón de vino a la transferencia | `/transferencias/{nro}/renglones` | `POST` | **Ruta:** `nro`<br>**Body:** `{ cod_vino, cantidad }` | Renglón creado y anexado | `agregarRenglonTransferencia(nro, data)` en `transferencias.js` | Enunciado / Bocetos |
| Cambiar estado a terminado | `/transferencias/{nro}/terminar` | `POST` | **Ruta:** `nro` | Transferencia actualizada en estado `terminado` | `terminarTransferencia(nro)` en `transferencias.js` | Enunciado / Bocetos |
| Procesar transferencia (impacta stock) | `/transferencias/{nro}/procesar` | `POST` | **Ruta:** `nro` | Confirmación y transferencia en estado `procesado` | `procesarTransferencia(nro)` en `transferencias.js` | Enunciado / Bocetos |
| Listado de transferencias para la grilla | `/transferencias` | `GET` | **Query:** `id_sala`, `estado`, `page` | Array de transferencias con sus renglones y estados | `listarTransferencias(filtros)` *(función sugerida)* | **PROPUESTO** (Requerido por Boceto #4) |
| Selector de salas solicitantes | `/salas` | `GET` | Ninguno | Array de salas de venta | `listarSalas()` *(función sugerida)* | **PROPUESTO** |

#### d) Flujo Paso a Paso
1. Se carga el listado de transferencias existentes (`GET /transferencias`) y el selector de salas (`GET /salas`).
2. Para solicitar una nueva transferencia, el usuario selecciona la sala y pulsa *"Crear Solicitud"*, enviando `POST /transferencias`.
3. Con el `nro_transferencia` obtenido (estado `en_confeccion`), el usuario agrega uno o más vinos indicando la cantidad deseada mediante `POST /transferencias/{nro}/renglones`.
4. Una vez agregados los ítems, el usuario presiona *"Terminar Transferencia"*, disparando `POST /transferencias/{nro}/terminar`. El estado cambia a `terminado`.
5. Desde la tabla general, un operador con permisos pulsa *"Procesar Transferencia"*, invocando `POST /transferencias/{nro}/procesar`.
6. En el backend, el procedimiento almacenado descuenta del depósito central, acredita en la sala solicitante y pasa la transferencia a `procesado`.
7. Si el depósito no cuenta con stock suficiente de algún vino, la API rechaza el procesamiento con código `409` y el mensaje de stock insuficiente se expone en la interfaz.

#### e) Matriz de Estados y Habilitación de Botones
| Estado Actual | Botones Habilitados en Frontend | Endpoint Invocado | Estado Resultante | Reglas Aplicadas |
|---|---|---|---|---|
| `en_confeccion` | - **Agregar Renglón**<br>- **Quitar Renglón**<br>- **Terminar Transferencia**<br>- **Eliminar Transferencia** | - `POST /transferencias/{nro}/renglones`<br>- `DELETE /transferencias/{nro}/renglones/{cod}`<br>- `POST /transferencias/{nro}/terminar`<br>- `DELETE /transferencias/{nro}` | `terminado` (si se termina) o se mantiene `en_confeccion` | **RN-12**: Solo se permite alterar renglones si está en confección.<br>**RN-11**: Fecha inmutable. |
| `terminado` | - **Procesar Transferencia** *(Modificar y agregar renglones quedan estrictamente bloqueados)* | - `POST /transferencias/{nro}/procesar` | `procesado` | **RN-11**: Solo se puede procesar si está terminado.<br>**RN-12**: No se admiten cambios en renglones. |
| `procesado` | *Ninguno* (Documento histórico cerrado e inmutable) | *Sin endpoints de modificación* | Estado final | **RN-10**, **RN-11**: El movimiento ya impactó en las tablas de stock; no puede revertirse ni alterarse. |

#### f) Errores Esperables y Tratamiento
| Escenario de Error | Regla / Restricción | SQLSTATE | HTTP Status | Tratamiento en Frontend |
|---|---|---|---|---|
| Stock insuficiente en depósito central al procesar | **RN-09** (`CHECK stock_deposito >= 0` o procedimiento `sp_procesar_transferencia`) | `P0001` o `23514` | `409 Conflict` | Muestra textualmente el mensaje del backend indicando qué vino no cuenta con existencias en depósito. |
| Intento de procesar transferencia no terminada | **RN-11** (Procedimiento valida `estado = 'terminado'`) | `P0001` | `409 Conflict` | Muestra el mensaje: *"La transferencia no puede procesarse porque no está en estado terminado."* |
| Intento de agregar renglones a transferencia terminada o procesada | **RN-12** (Trigger sobre `renglon_transferencia` valida estado en cabecera) | `P0001` | `409 Conflict` | Muestra el mensaje de bloqueo emitido por el trigger. |
| Modificación indebida de fecha de confección | **RN-11** (Trigger BEFORE UPDATE bloquea cambios en `fecha_confeccion`) | `P0001` | `422 Unprocessable Entity` | Muestra la prohibición de cambio de fecha. |

#### g) Qué NO calcula el Front
- No calcula existencias ni descuenta botellas del stock del depósito.
- No incrementa saldos en la sala solicitante.
- No decide si una transferencia es válida para procesarse sin consultar el estado retornado por el servidor.

