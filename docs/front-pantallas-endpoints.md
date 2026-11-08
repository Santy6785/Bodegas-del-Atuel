# Mapeo de Pantallas del Frontend y Endpoints de la API

**Proyecto:** Bodegas del Atuel - TPI Bases de Datos (Etapa 7)  
**Rol:** Frontend  
**Fecha:** 2026-11-06  
**Estado:** Borrador v1.0  
**Fuentes analizadas:**  
- `docs/api-contrato.md` (Borrador v0.1)  
- `api/app/routers/` y `api/app/main.py`  
- `docs/bocetos/` (Bocetos de interfaz 1 a 5)  

---

## 1. Estado general de implementacion en la API

Se realizo una inspeccion del directorio `api/app/routers/`. Actualmente:
- El directorio `api/app/routers/` contiene unicamente `__init__.py` sin routers ni funciones implementadas.
- En `api/app/main.py` solo esta implementado el endpoint tecnico `GET /salud`.
- Ninguno de los endpoints funcionales requeridos por las pantallas del frontend se encuentra implementado al dia de hoy.

Por este motivo, en todas las tablas de este documento la columna **Implementado en api/** figura con valor **No**.

---

## 2. Mapa de Pantallas y Endpoints Requeridos

### Pantalla 1: Catalogo de vinos

**Descripcion:** Listado paginado con filtros por tipo, cepa, bodega y anada. Incluye visualizacion en modal u overlay del detalle de un vino con su composicion de cepas, maridajes y stock.

| Metodo | Ruta | Para que la usa la pantalla | Estado | Implementado en api/ |
|---|---|---|---|---|
| GET | `/vinos` | Obtener el listado paginado de vinos para la grilla principal, aplicando filtros por query params (`tipo`, `id_cepa`, `cuit_bodega`, `anada`, `page`, `page_size`). Tambien permite busqueda por nombre si se aprueba `nombre`. | EN MINIMO TP | No |
| GET | `/vinos/{cod}` | Cargar la ficha completa del vino al pulsar "Detalle" (muestra bodega, composicion porcentual de cepas, maridajes sugeridos y stock). | EN MINIMO TP | No |
| GET | `/cepas` | Llenar el desplegable del filtro "Cepa". | PROPUESTA EN CONTRATO | No |
| GET | `/bodegas` | Llenar el desplegable del filtro "Bodega". | PROPUESTA EN CONTRATO | No |
| DELETE | `/vinos/{cod}` | Eliminar un vino desde las acciones de la fila o del detalle (si la interfaz contempla la baja). | EN MINIMO TP | No |

*Nota sobre filtros:* El filtro de "Tipo" utiliza los valores fijos del dominio (`tinto`, `blanco`, `rosado`, `espumante`), por lo que no requiere endpoint auxiliar. El filtro "Anada" puede resolverse con entrada numerica o derivarse de los anos presentes.

---

### Pantalla 2: Alta y edicion de vino

**Descripcion:** Formulario para registrar un nuevo vino o editar uno existente. Incluye datos basicos (nombre comercial, anada, precio, tipo, volumen, graduacion), seleccion de bodega titular, seleccion dinamica de cepas con sus porcentajes y asignacion de maridajes. Debe capturar y mostrar el error cuando la suma de porcentajes de corte no da exactamente 100%.

| Metodo | Ruta | Para que la usa la pantalla | Estado | Implementado en api/ |
|---|---|---|---|---|
| GET | `/bodegas` | Llenar el desplegable de seleccion de bodega titular (`cuit_bodega`). | PROPUESTA EN CONTRATO | No |
| GET | `/cepas` | Llenar el desplegable de cepas para agregar renglones a la composicion porcentual del corte. | PROPUESTA EN CONTRATO | No |
| GET | `/maridajes` | Llenar el selector o lista de opciones para asignar maridajes recomendados (`maridajes: [id]`). | PROPUESTA EN CONTRATO | No |
| GET | `/vinos/{cod}` | En modo edicion, cargar los datos actuales del vino (incluyendo composicion y maridajes) para precargar el formulario. | EN MINIMO TP | No |
| POST | `/vinos` | Dar de alta un nuevo vino enviando datos basicos, composicion y maridajes en una sola transaccion. | EN MINIMO TP | No |
| PUT | `/vinos/{cod}` | Guardar las modificaciones de un vino existente (reemplazo completo, audita cambios de precio). | EN MINIMO TP | No |

*Nota sobre validacion de porcentajes:* El constraint trigger diferido `RN-05` valida al momento del `COMMIT` en el backend. Si la suma difiere de 100, la API responde HTTP 409 con SQLSTATE `P0001`.

---

### Pantalla 3: Nueva venta

**Descripcion:** Registro de comprobantes de venta. Permite seleccionar cliente y sala de venta, agregar vinos con sus cantidades, visualizar subtotales, descuentos y total calculados exclusivamente por el backend, y mostrar el mensaje de error si no hay stock suficiente en la sala seleccionada.

| Metodo | Ruta | Para que la usa la pantalla | Estado | Implementado en api/ |
|---|---|---|---|---|
| GET | `/salas` | Llenar el desplegable para seleccionar la sala de venta fisica donde se efectua la venta. | PROPUESTA EN CONTRATO | No |
| GET | `/clientes` | Buscar y seleccionar el cliente de la venta. Requiere busqueda por DNI/CUIT o apellido (ver Observaciones). | EN MINIMO TP | No |
| GET | `/vinos` | Buscador/selector para elegir los vinos que se agregaran al detalle de venta (utilizando `?nombre=`). | EN MINIMO TP | No |
| POST | `/comprobantes` | Emitir la venta completa (cliente, sala y renglones). El backend calcula totales, valida stock (RN-09) y persiste el comprobante. | EN MINIMO TP | No |
| GET | `/comprobantes/{nro}` | Consultar el comprobante generado tras la venta para visualizacion final o impresion. | EN MINIMO TP | No |
| POST | `/comprobantes/calcular` | (Requerido si se calculan totales en vivo) Endpoint de simulacion para calcular subtotales, porcentaje de descuento y total a pagar antes de confirmar la emision definitiva. | FALTA EN CONTRATO | No |

*Nota sobre stock:* Si la cantidad solicitada supera el stock disponible en la sala, `POST /comprobantes` retorna HTTP 409 con el mensaje del trigger `RN-09` (`P0001`).

---

### Pantalla 4: Transferencias

**Descripcion:** Circuito de transferencias de stock desde el deposito central hacia una sala de venta. Permite crear la cabecera en estado `en_confeccion`, agregar renglones de vinos y cantidades, visualizar transferencias existentes y cambiar de estado mediante botones que se habilitan segun el estado actual (`en_confeccion` -> `terminado` -> `procesado`).

| Metodo | Ruta | Para que la usa la pantalla | Estado | Implementado en api/ |
|---|---|---|---|---|
| GET | `/transferencias` | Listar las transferencias existentes en la tabla inferior para conocer su estado actual y operar sobre ellas. | PROPUESTA EN CONTRATO | No |
| GET | `/transferencias/{nro}` | Obtener el detalle de una transferencia especifica (renglones cargados y estado actual) para habilitar condicionalmente los botones de transicion. | PROPUESTA EN CONTRATO | No |
| GET | `/salas` | Llenar el desplegable de "Sala Solicitante" (destino de la transferencia). | PROPUESTA EN CONTRATO | No |
| GET | `/vinos` | Buscador/selector de vinos para agregar a los renglones de la transferencia. | EN MINIMO TP | No |
| POST | `/transferencias` | Crear la cabecera de una nueva transferencia para una sala (inicia en estado `en_confeccion`). | EN MINIMO TP | No |
| POST | `/transferencias/{nro}/renglones` | Agregar un renglon (`cod_vino`, `cantidad`) a la transferencia mientras este en confeccion. | EN MINIMO TP | No |
| POST | `/transferencias/{nro}/terminar` | Accion del boton "Terminar Transferencia": pasa el estado de `en_confeccion` a `terminado`. | EN MINIMO TP | No |
| POST | `/transferencias/{nro}/procesar` | Accion del boton "Procesar Transferencia": invoca el SP en la base para impactar stock y pasar a `procesado`. | EN MINIMO TP | No |
| DELETE | `/transferencias/{nro}/renglones/{cod_vino}` | (Requerido para corregir errores de carga) Permite quitar un renglon cargado previamente mientras la transferencia este en confeccion. | FALTA EN CONTRATO | No |

---

### Pantalla 5: Tablero (Dashboard)

**Descripcion:** Panel gerencial que muestra tres metricas clave: ranking de los 10 vinos mas vendidos, grafico de barras con las ventas por sala en el ultimo trimestre, y reporte dinamico de vinos sin stock en una sala seleccionable por desplegable.

| Metodo | Ruta | Para que la usa la pantalla | Estado | Implementado en api/ |
|---|---|---|---|---|
| GET | `/reportes/top-vinos` | Obtener el ranking de los 10 vinos mas vendidos (consigna S1, parametro `limit=10` por defecto). | EN MINIMO TP | No |
| GET | `/reportes/ventas-por-sala` | Obtener el monto total facturado por sala en el ultimo trimestre para alimentar el grafico de barras (consigna S8). | EN MINIMO TP | No |
| GET | `/salas` | Llenar el desplegable de salas para seleccionar cual consultar en el reporte de stock. | PROPUESTA EN CONTRATO | No |
| GET | `/reportes/vinos-sin-stock` | Obtener el listado de vinos sin stock en la sala elegida pasando `?id_sala={id}` (consigna S6). | EN MINIMO TP | No |

---

## 3. Confirmacion de los Cinco Endpoints Consultados

A continuacion se confirma el estado y la justificacion de uso de los cinco endpoints clave:

1. **`GET /cepas`**
   - **Estado:** `PROPUESTA EN CONTRATO` (no esta en el minimo del TP; figura en seccion 4.7 del contrato).
   - **Pantallas que lo necesitan:**
     - *Catalogo de vinos:* Llenar el desplegable de filtro por variedad de cepa.
     - *Alta y edicion de vino:* Llenar el desplegable para seleccionar las cepas que componen el corte del vino.

2. **`GET /bodegas`**
   - **Estado:** `PROPUESTA EN CONTRATO` (no esta en el minimo del TP; figura en seccion 4.7 del contrato).
   - **Pantallas que lo necesitan:**
     - *Catalogo de vinos:* Llenar el desplegable de filtro por bodega elaboradora.
     - *Alta y edicion de vino:* Llenar el desplegable para asociar el vino a una bodega registrada (`cuit_bodega`).

3. **`GET /salas`**
   - **Estado:** `PROPUESTA EN CONTRATO` (no esta en el minimo del TP; figura en seccion 4.7 del contrato).
   - **Pantallas que lo necesitan:**
     - *Nueva venta:* Seleccionar la sala fisica donde se concreta la venta.
     - *Transferencias:* Seleccionar la sala de destino (solicitante) de los vinos transferidos.
     - *Tablero:* Seleccionar la sala sobre la cual se consulta el reporte de vinos sin stock.

4. **`GET /maridajes`**
   - **Estado:** `PROPUESTA EN CONTRATO` (no esta en el minimo del TP; figura en seccion 4.7 del contrato).
   - **Pantallas que lo necesitan:**
     - *Alta y edicion de vino:* Llenar el selector multiple de maridajes recomendados para el vino.
     *(Nota: En Catalogo de vinos la ficha de detalle ya recibe los maridajes dentro de `GET /vinos/{cod}`).*

5. **`GET /transferencias`**
   - **Estado:** `PROPUESTA EN CONTRATO` (no esta en el minimo del TP; figura en secciones 2 y 4.4 del contrato).
   - **Pantallas que lo necesitan:**
     - *Transferencias:* Poblar la grilla de transferencias existentes con sus estados (`en_confeccion`, `terminado`, `procesado`), fechas y salas solicitantes.

---

## 4. Observaciones sobre el Contrato y Analisis de Huecos

Se detectaron discrepancias y faltantes tecnicos entre el contrato actual (`docs/api-contrato.md`), los bocetos de diseno y los requerimientos funcionales del frontend:

### 4.1 Necesidad critica de `GET /transferencias/{nro}`
- **Problema:** En el minimo del TP no figura la lectura individual de transferencias; solo se incluyeron los POST de creacion y cambio de estado. En `docs/api-contrato.md` figura como `[propuesta]`.
- **Impacto en el front:** La consigna exige que los botones de transicion de estado se habiliten o deshabiliten segun el estado actual de la transferencia. Sin `GET /transferencias/{nro}`, si el usuario recarga la pagina, entra mediante enlace directo o agrega un renglon (la respuesta de agregar renglon solo devuelve el renglon individual), el frontend no tiene forma de conocer el estado ni de recuperar los renglones cargados.
- **Conclusion:** Debe ser promovido obligatoriamente a la API.

### 4.2 Seleccion de cliente en Nueva venta (Volumen de 20.000 clientes)
- **Problema:** El contrato define `GET /clientes` con paginacion (`page_size` maximo 100) y filtro exclusivo por `tipo_cliente`. Sin embargo, la base contiene cerca de 20.000 clientes.
- **Impacto en el front:** Un desplegable tradicional colapsa la interfaz y solo permitiria seleccionar entre los primeros 100 clientes de la primera pagina. El boceto `3 - nueva venta de vino.jpg` ilustra claramente un campo `Cliente (ID/Nombre): Buscar... [lupa]`.
- **Faltante:** Falta en el contrato el soporte de busqueda por texto o parametros especificos en `GET /clientes`, tales como `?q=`, `?documento=` y `?apellido=`.

### 4.3 Seleccion de vinos para ventas y transferencias
- **Problema:** En el minimo del TP, `GET /vinos` no contempla busqueda por texto libre; el contrato lo anadio como propuesta (`?nombre=`).
- **Impacto en el front:** Con cientos de vinos cargados y paginacion de maximo 100 elementos, el usuario no puede encontrar facilmente un vino para agregarlo a la grilla de venta o transferencia sin un buscador. El parametro `?nombre=` propuesto en el contrato es indispensable.
- **Stock por sala en Nueva venta:** `GET /vinos` no devuelve el stock disponible en la sala elegida, y `GET /vinos/{cod}` solo devuelve un consolidado general (`deposito`, `salas`, `total`). Esto ocasiona que el usuario agregue vinos a ciegas y recien se entere de la falta de stock al enviar la venta completa con un error 409. Seria altamente conveniente permitir filtrar o enriquecer `GET /vinos` con `?id_sala={id}`.

### 4.4 Formato y momento del error de composicion porcentual (RN-05)
- **Momento:** El contrato documenta con precision que `RN-05` es un constraint trigger `DEFERRABLE INITIALLY DEFERRED`. Por lo tanto, el error no salta al insertar las filas de composicion sino al ejecutar el `COMMIT` en la base. El front lo recibira como respuesta HTTP 409 tras el submit del formulario (`POST` o `PUT /vinos`).
- **Formato del mensaje:** El contrato indica que el cuerpo del error sera `{ "error": { "sqlstate": "P0001", "mensaje": "...", "restriccion": null } }`, donde `mensaje` es el texto literal del `RAISE EXCEPTION`. No obstante, el contrato no especifica cual sera la cadena exacta de texto (por ejemplo `"Los porcentajes de corte deben sumar 100"`), ni incluye un identificador o campo afectado (`campo: "composicion"`). Para que el frontend pueda resaltar visualmente la seccion de composicion de cepas en lugar de mostrar un banner generico, el contrato deberia estandarizar el mensaje o proveer un codigo de error de aplicacion.

### 4.5 Calculo previo de totales en Nueva venta (Regla de no calculo en el Front)
- **Problema:** La consigna establece taxativamente: *"El front consume UNICAMENTE la API y no calcula totales, descuentos ni stock"*. Al mismo tiempo, la pantalla Nueva Venta exige *"ver el total calculado por el backend"*, y el boceto 3 muestra la grilla con precio unitario, porcentaje de descuento por cliente, subtotal por linea y total general calculado por el backend antes de confirmar la venta.
- **Hueco en el contrato:** El unico endpoint existente en el contrato es `POST /comprobantes`, el cual emite y persiste la venta de manera definitiva e irreversible en la base de datos (descontando stock). No existe ningun endpoint de calculo previo o simulacion (por ejemplo `POST /comprobantes/calcular` o `POST /comprobantes/simular`).
- **Consecuencia:** Sin un endpoint de calculo previo, el front solo puede conocer los importes finales una vez que la venta ya fue confirmada y guardada. Si se requiere ver la liquidacion previa en pantalla mientras se agregan o quitan vinos, la API debe incorporar este endpoint auxiliar.

### 4.6 Gestion de renglones en Transferencias en confeccion
- **Problema:** Mientras una transferencia permanece en estado `en_confeccion`, el usuario puede equivocarse al ingresar botellas o vinos. El contrato posee `POST /transferencias/{nro}/renglones`, pero carece por completo de endpoints para eliminar un renglon (`DELETE /transferencias/{nro}/renglones/{cod_vino}`) o modificar la cantidad de un renglon existente. En el boceto 4 figuran acciones de modificacion y borrado en la grilla.

### 4.7 Discrepancia en parametros del reporte de Vinos sin stock
- **Observacion:** En `docs/api-contrato.md` (seccion 4.6), el parametro obligatorio de sala se define como `id_sala` (`GET /reportes/vinos-sin-stock?id_sala=1`). En el boceto de diseno manuscrito (`5 - Tablero,Dashboard.jpg`) se anoto a mano `sala_id={id}`. El frontend adoptara estrictamente `id_sala` para respetar la convencion `snake_case` del contrato.

---

## 5. Resumen: Backlog de Endpoints a Agregar a la API

A continuacion se detallan todos los endpoints fuera del minimo del TP que deben ser implementados en la API para dar soporte integral a las 5 pantallas del frontend:

| Metodo | Ruta | Pantallas que lo requieren | Estado actual | Justificacion y prioridad |
|---|---|---|---|---|
| GET | `/cepas` | Catalogo de vinos, Alta y edicion de vino | PROPUESTA EN CONTRATO | Alta. Necesario para los desplegables de cepas en filtros y en composicion de vino. |
| GET | `/bodegas` | Catalogo de vinos, Alta y edicion de vino | PROPUESTA EN CONTRATO | Alta. Necesario para desplegables de bodegas en filtros y en alta/edicion. |
| GET | `/salas` | Nueva venta, Transferencias, Tablero | PROPUESTA EN CONTRATO | Alta. Requerido de forma transversal en 3 de las 5 pantallas para seleccion de sala. |
| GET | `/maridajes` | Alta y edicion de vino | PROPUESTA EN CONTRATO | Media. Requerido para asociar maridajes en el alta y edicion de vino. |
| GET | `/transferencias` | Transferencias | PROPUESTA EN CONTRATO | Alta. Necesario para listar transferencias y conocer su estado en grilla. |
| GET | `/transferencias/{nro}` | Transferencias | PROPUESTA EN CONTRATO | Critica. Indispensable para recuperar renglones y habilitar/deshabilitar botones segun estado. |
| GET | `/clientes?q=...` | Nueva venta | FALTA EN CONTRATO | Critica. Busqueda por documento o apellido para seleccionar entre 20.000 clientes. |
| GET | `/vinos?nombre=...` | Catalogo de vinos, Nueva venta, Transferencias | PROPUESTA EN CONTRATO | Alta. Buscador de vinos indispensable para ventas y transferencias (cientos de registros). |
| POST | `/comprobantes/calcular` | Nueva venta | FALTA EN CONTRATO | Alta. Permite calcular subtotales, descuentos y total sin persistir ni calcular en front. |
| DELETE | `/transferencias/{nro}/renglones/{cod_vino}` | Transferencias | FALTA EN CONTRATO | Media. Permite quitar renglones cargados por error en transferencias en confeccion. |
