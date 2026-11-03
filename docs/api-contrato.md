# Contrato de la API: Bodegas del Atuel

**Estado:** borrador v0.1 (2026-11-03). No depende de que la base esté lista.
**Fuentes:** TPI, Etapa 6 (endpoints mínimos y traducción de SQLSTATE), `docs/decisiones.md` y `docs/DER/bodegas_del_atuel_der.dbml`.
**Marcas:** los endpoints o campos marcados **[propuesta]** no figuran en el mínimo del TP; se agregaron porque el front o el modelo los necesitan. Hay que confirmarlos con el grupo (ver sección 6).

---

## 1. Convenciones generales

- **Formato:** JSON en UTF-8. Los nombres de campo van en `snake_case` y coinciden con las columnas de la base (`cod_vino`, `id_sala`, `cuit_bodega`), para no tener una capa de traducción.
- **Fechas:** ISO 8601 (`YYYY-MM-DD` para fechas, con zona horaria para timestamps).
- **Dinero, porcentajes y graduación** (`NUMERIC`): se serializan como **string decimal** (`"12500.00"`), nunca como número de coma flotante. **[propuesta]**
- **Autenticación:** ninguna en esta versión (el TP la deja como extra).
- **Regla de oro:** la API **no calcula** totales, descuentos, stock, precios unitarios ni la fecha de confección. Esos campos nunca se envían en el request: los calcula la base (funciones, procedimientos y triggers) y solo aparecen en las respuestas.
- **Paginación** (listados): `?page=1&page_size=20` (`page_size` máximo 100). Respuesta:

```json
{ "items": [ ... ], "page": 1, "page_size": 20, "total": 134 }
```

- **Listados sin paginar** (reportes y catálogos auxiliares): devuelven directamente un arreglo JSON.
- **Transacciones:** toda operación de más de una sentencia (alta de vino, venta, alta de cliente) corre en una sola transacción. Si algo falla, no queda nada a medias.

### 1.1 Formato de error

Todos los errores usan el mismo cuerpo:

```json
{
  "error": {
    "sqlstate": "P0001",
    "mensaje": "Stock insuficiente del vino 10 en la sala 1 (RN-09)",
    "restriccion": null
  }
}
```

- Para `P0001` (regla rechazada por trigger o procedimiento), `mensaje` es **el texto del `RAISE EXCEPTION` tal cual**, sin reemplazarlo por uno genérico: el front lo muestra al usuario.
- Para errores de clase 23 (constraints), `restriccion` trae el nombre del constraint violado (`e.diag.constraint_name`) y `mensaje` es un texto genérico por tipo de error.
- Para errores que no vienen de la base (404, validación del request) `sqlstate` es `null`.

### 1.2 Traducción de errores (SQLSTATE a HTTP)

| Situación en PostgreSQL | SQLSTATE | HTTP | Origen |
|---|---|---|---|
| UNIQUE violado | `23505` | 409 Conflict | TP |
| FOREIGN KEY violada | `23503` | 409 en `DELETE`; 422 en `POST`/`PUT` (ver 6.1) | TP deja 409 o 422 abierto |
| CHECK violado | `23514` | 422 Unprocessable Entity | TP |
| NOT NULL violado | `23502` | 422 Unprocessable Entity | TP |
| Regla rechazada por trigger o procedimiento (`RAISE EXCEPTION`) | `P0001` | 409 Conflict, con el mensaje de la regla | TP |
| Formato inválido para el tipo | `22P02` | 400 Bad Request | TP |
| Fallo de serialización / deadlock | `40001` / `40P01` | 503 Service Unavailable, con reintento sugerido | TP |
| Base inaccesible (clase `08`, error de conexión) | `08xxx` | 503 Service Unavailable | **[propuesta]** |
| Recurso inexistente | (sin SQLSTATE) | 404 Not Found | **[propuesta]** |
| Request mal formado (validación de FastAPI/Pydantic) | (sin SQLSTATE) | 422 (ver 6.9) | **[propuesta]** |

En los endpoints de abajo solo se listan los errores propios de cada uno. En todos pueden aparecer además 404 (si el recurso de la ruta no existe), 422/400 (request inválido) y 503 (conexión o deadlock).

---

## 2. Resumen de endpoints

| Método | Ruta | Descripción | Origen |
|---|---|---|---|
| GET | `/salud` | La API llega a la base | TP |
| GET | `/vinos` | Catálogo con filtros y paginación | TP |
| GET | `/vinos/{cod}` | Ficha del vino: cepas, maridajes, stock | TP |
| POST | `/vinos` | Alta con composición | TP |
| PUT | `/vinos/{cod}` | Modificación (audita el precio) | TP |
| DELETE | `/vinos/{cod}` | Baja | TP |
| GET | `/clientes` | Listado paginado | TP |
| GET | `/clientes/{id}` | Detalle con datos de subtipo | TP |
| POST | `/clientes` | Alta (socio, distribuidor o exportador) | TP |
| PUT | `/clientes/{id}` | Modificación | TP |
| DELETE | `/clientes/{id}` | Baja | TP |
| POST | `/comprobantes` | Venta completa en una transacción | TP |
| GET | `/comprobantes/{nro}` | Comprobante con renglones | TP |
| POST | `/transferencias` | Alta (en confección) | TP |
| GET | `/transferencias` | Listado filtrable por estado y sala | **[propuesta]** |
| GET | `/transferencias/{nro}` | Detalle con renglones y estado | **[propuesta]** |
| POST | `/transferencias/{nro}/renglones` | Agrega un renglón | TP |
| POST | `/transferencias/{nro}/terminar` | `en_confeccion` a `terminado` | TP |
| POST | `/transferencias/{nro}/procesar` | Invoca `sp_procesar_transferencia` | TP |
| POST | `/ingresos` | Alta (en confección) | TP |
| GET | `/ingresos/{cod}` | Detalle con renglones y estado | **[propuesta]** |
| POST | `/ingresos/{cod}/renglones` | Agrega un renglón | TP |
| POST | `/ingresos/{cod}/terminar` | `en_confeccion` a `terminado` | **[propuesta]** (el TP dice "mismo circuito que las transferencias") |
| POST | `/ingresos/{cod}/procesar` | Invoca `sp_procesar_ingreso` | TP |
| GET | `/reportes/top-vinos` | S1 | TP |
| GET | `/reportes/ventas-por-sala` | S8 | TP |
| GET | `/reportes/vinos-sin-stock` | S6 | TP |
| GET | `/reportes/transportista-activo` | S7 | TP |
| GET | `/reportes/trazabilidad/{cod}` | Lotes de uva de un vino | TP |
| GET | `/salas`, `/cepas`, `/bodegas`, `/maridajes`, `/transportistas`, `/localidades` | Catálogos de solo lectura para los formularios del front | **[propuesta]** |

---

## 3. Salud

### `GET /salud`

Ejecuta una consulta trivial (`SELECT 1`) contra la base con el rol de la API.

- **200:** `{ "estado": "ok", "base_de_datos": "ok" }`
- **503:** `{ "estado": "error", "base_de_datos": "inaccesible" }`

---

## 4. Recursos

### 4.1 Vinos

#### `GET /vinos`

| Parámetro (query) | Tipo | Descripción |
|---|---|---|
| `page`, `page_size` | int | Paginación (por defecto 1 y 20) |
| `tipo` | `tinto` \| `blanco` \| `rosado` \| `espumante` | Filtro por tipo |
| `id_cepa` | int | Vinos que incluyen esa cepa en su composición |
| `cuit_bodega` | string (11 dígitos) | Vinos de una bodega |
| `anada` | int | Filtro por añada |
| `nombre` | string | Búsqueda parcial por nombre comercial **[propuesta]** |

Los filtros se combinan con AND.

**200:**

```json
{
  "items": [
    {
      "cod_vino": 10, "nombre": "Malbec Reserva", "tipo": "tinto",
      "anada": 2021, "volumen_ml": 750, "graduacion": "14.00",
      "precio": "12500.00", "cuit_bodega": "30123456789",
      "bodega_razon_social": "Bodega Ejemplo S.A."
    }
  ],
  "page": 1, "page_size": 20, "total": 1
}
```

#### `GET /vinos/{cod}`

Ficha del vino (consigna S9). **200:**

```json
{
  "cod_vino": 10, "nombre": "Malbec Reserva", "tipo": "tinto",
  "anada": 2021, "volumen_ml": 750, "graduacion": "14.00", "precio": "12500.00",
  "bodega": { "cuit": "30123456789", "razon_social": "Bodega Ejemplo S.A." },
  "composicion": [
    { "id_cepa": 1, "nombre": "Malbec", "tipo": "tinta", "porcentaje": "85.00" },
    { "id_cepa": 2, "nombre": "Cabernet Sauvignon", "tipo": "tinta", "porcentaje": "15.00" }
  ],
  "maridajes": [
    { "id_maridaje": 1, "nombre": "Carnes rojas", "temperatura_servicio": 17 }
  ],
  "stock": { "deposito": 240, "salas": 310, "total": 550 }
}
```

**Errores:** 404 si el vino no existe.

#### `POST /vinos`

Alta del vino con su composición y maridajes, en **una sola transacción** (`vino`, `vino_cepa`, `vino_maridaje`).

```json
{
  "nombre": "Malbec Reserva", "tipo": "tinto", "anada": 2021,
  "volumen_ml": 750, "graduacion": "14.00", "precio": "12500.00",
  "cuit_bodega": "30123456789",
  "composicion": [
    { "id_cepa": 1, "porcentaje": "85.00" },
    { "id_cepa": 2, "porcentaje": "15.00" }
  ],
  "maridajes": [1, 2]
}
```

**201:** mismo cuerpo que `GET /vinos/{cod}`, con cabecera `Location: /vinos/{cod}`.

| Error | HTTP | Mecanismo |
|---|---|---|
| Ya existe (nombre, añada, volumen) | 409 | `23505`, UNIQUE |
| Bodega o cepa inexistente | 422 | `23503`, FK |
| Precio <= 0, graduación fuera de 5-20, volumen o añada inválidos (RN-01, RN-15) | 422 | `23514`, CHECK |
| Los porcentajes de corte no suman 100 (RN-05) | 409 | `P0001`, constraint trigger diferido |

> **Atención con RN-05:** el constraint trigger es `DEFERRABLE INITIALLY DEFERRED`, así que el error aparece **al hacer COMMIT**, no en el INSERT. La API tiene que capturar la excepción también alrededor del `commit`.

#### `PUT /vinos/{cod}`

Reemplazo completo. El cuerpo es el mismo que el de `POST /vinos` (incluidas `composicion` y `maridajes`). Un cambio de precio queda registrado por el trigger de auditoría (RN-13: fecha, usuario, precio anterior y nuevo); la API no escribe en `auditoria_precio`.

**200:** el vino actualizado (mismo cuerpo que el detalle). **Errores:** los mismos que `POST /vinos`.

#### `DELETE /vinos/{cod}`

**204** sin cuerpo.

| Error | HTTP | Mecanismo |
|---|---|---|
| El vino tiene movimientos (ventas, ingresos, transferencias) o stock (RN-14) | 409 | `23503`, FK `ON DELETE RESTRICT` |

---

### 4.2 Clientes

Jerarquía supertipo/subtipos (`cliente`, `cliente_distribuidor`, `cliente_exportador`). El **descuento no se envía**: en las respuestas aparece como `descuento_pct`, calculado por `fn_descuento_cliente` (socio 10, distribuidor 20, exportador 30).

#### `GET /clientes`

Query: `page`, `page_size`, `tipo_cliente` (`socio` | `distribuidor` | `exportador`).

**200:** paginado; cada ítem:

```json
{
  "id_cliente": 1, "apellido_razon_social": "Pérez", "nombre": "Ana",
  "tipo_documento": "DNI", "nro_documento": "30111222",
  "direccion": "Calle 123", "codigo_postal": "M5600",
  "fecha_alta": "2026-01-15", "tipo_cliente": "socio", "descuento_pct": "10.00"
}
```

#### `GET /clientes/{id}`

El mismo cuerpo, más el bloque del subtipo cuando corresponda:

```json
{
  "...": "...",
  "tipo_cliente": "exportador",
  "exportador": {
    "pais_destino": "Brasil",
    "permisos": [
      { "codigo": "PE-001", "fecha_emision": "2026-01-01", "fecha_vencimiento": "2027-01-01" }
    ]
  }
}
```

Para un distribuidor el bloque es `"distribuidor": { "zona_cobertura": "...", "nro_habilitacion": "..." }`. Para un socio no hay bloque.

#### `POST /clientes`

```json
{
  "apellido_razon_social": "Exportadora Sur S.A.", "nombre": null,
  "tipo_documento": "CUIT", "nro_documento": "30987654321",
  "direccion": "Av. Ejemplo 500", "codigo_postal": "M5600",
  "tipo_cliente": "exportador",
  "exportador": {
    "pais_destino": "Brasil",
    "permisos": [
      { "codigo": "PE-001", "fecha_emision": "2026-01-01", "fecha_vencimiento": "2027-01-01" }
    ]
  }
}
```

- `nombre` es `null` cuando el cliente es una razón social.
- Según `tipo_cliente` va el bloque `distribuidor` o `exportador`; para `socio` no va ninguno.
- `fecha_alta` no se envía (la completa el `DEFAULT`).
- Se inserta cliente, subtipo y permisos en **una sola transacción**.

**201:** el cliente creado (mismo cuerpo que el detalle), con `Location`.

| Error | HTTP | Mecanismo |
|---|---|---|
| Documento repetido (tipo + número) o `nro_habilitacion` repetido | 409 | `23505` |
| Código postal inexistente | 422 | `23503` |
| Vencimiento del permiso no posterior a la emisión (RN-07) | 422 | `23514` |
| Tipo de cliente incoherente con el subtipo enviado | 409 | `P0001`, trigger de coherencia |

#### `PUT /clientes/{id}`

Reemplazo completo, mismo cuerpo que `POST`. El `tipo_cliente` debe ser el actual (cambiar de tipo queda pendiente, ver 6.6). **200:** el cliente actualizado. **Errores:** los mismos que `POST`.

#### `DELETE /clientes/{id}`

**204.** Se borran en cascada el subtipo y los permisos.

| Error | HTTP | Mecanismo |
|---|---|---|
| El cliente tiene comprobantes | 409 | `23503`, FK `ON DELETE RESTRICT` |

---

### 4.3 Comprobantes (ventas)

#### `POST /comprobantes`

Venta completa en **una sola transacción**: cabecera y renglones. **No se envían** precio, descuento, subtotales ni total: los calculan las funciones y triggers de la base (RN-06, RN-08).

```json
{
  "id_cliente": 1,
  "id_sala": 1,
  "renglones": [
    { "cod_vino": 10, "cantidad": 6 },
    { "cod_vino": 12, "cantidad": 2 }
  ]
}
```

**201:** el comprobante con los valores calculados por la base, con `Location: /comprobantes/{nro}`.

```json
{
  "nro_comprobante": 1001, "fecha": "2026-11-03",
  "id_cliente": 1, "id_sala": 1,
  "subtotal": "100000.00", "descuento": "10000.00", "total": "90000.00",
  "renglones": [
    { "cod_vino": 10, "cantidad": 6, "precio_unitario": "12500.00",
      "descuento_pct": "10.00", "subtotal": "67500.00" }
  ]
}
```

| Error | HTTP | Mecanismo |
|---|---|---|
| Stock insuficiente en la sala (RN-09) | 409, con el mensaje de la regla | `P0001`, trigger BEFORE INSERT |
| Vino repetido en los renglones | 409 | `23505`, PK `(nro_comprobante, cod_vino)` |
| Cliente, sala o vino inexistente | 422 | `23503` |
| Cantidad <= 0 | 422 | `23514` |

Ante cualquier error **no queda nada a medias** (rollback de toda la transacción).

#### `GET /comprobantes/{nro}`

**200:** mismo cuerpo que la respuesta del `POST`. **Errores:** 404.

---

### 4.4 Transferencias (depósito central a salas)

Circuito: `en_confeccion` a `terminado` a `procesado`, sin retrocesos (RN-11, RN-12).

#### `POST /transferencias`

```json
{ "id_sala": 1 }
```

La fecha de confección es siempre la actual y no se puede enviar ni modificar (trigger, RN-11). El estado inicial es `en_confeccion`.

**201:** `{ "nro_transferencia": 55, "id_sala": 1, "fecha_confeccion": "2026-11-03", "estado": "en_confeccion", "renglones": [] }`

**Errores:** sala inexistente, 422 (`23503`).

#### `GET /transferencias` **[propuesta]**

Query: `page`, `page_size`, `estado`, `id_sala`. **200:** paginado, con la cabecera de cada transferencia.

#### `GET /transferencias/{nro}` **[propuesta]**

**200:** cabecera más `renglones` (`cod_vino`, `cantidad`). El front usa el `estado` para habilitar o deshabilitar los botones. **Errores:** 404.

#### `POST /transferencias/{nro}/renglones`

```json
{ "cod_vino": 10, "cantidad": 24 }
```

**201:** el renglón creado.

| Error | HTTP | Mecanismo |
|---|---|---|
| La transferencia no está en confección (RN-12) | 409 | `P0001`, trigger sobre renglones |
| Vino ya cargado en esta transferencia | 409 | `23505` |
| Vino inexistente | 422 | `23503` |
| Cantidad <= 0 | 422 | `23514` |

#### `POST /transferencias/{nro}/terminar`

Sin cuerpo. Pasa el estado a `terminado`. **200:** `{ "nro_transferencia": 55, "estado": "terminado" }`.

| Error | HTTP | Mecanismo |
|---|---|---|
| Transición de estado inválida (RN-11) | 409 | `P0001`, trigger de estados |

#### `POST /transferencias/{nro}/procesar`

Sin cuerpo. Ejecuta `CALL sp_procesar_transferencia(nro)`: descuenta del depósito, suma al stock de la sala y pasa a `procesado`, todo en una transacción. **200:** `{ "nro_transferencia": 55, "estado": "procesado" }`.

| Error | HTTP | Mecanismo |
|---|---|---|
| La transferencia no está `terminado` (RN-11) | 409 | `P0001`, procedimiento |
| Stock insuficiente en el depósito (RN-09) | 409 | `P0001` si el procedimiento lo verifica antes (ver 6.2) |
| Deadlock o fallo de serialización | 503, con reintento sugerido | `40P01` / `40001` |

---

### 4.5 Ingresos (bodegas al depósito central)

Mismo circuito que las transferencias (RN-10, RN-12).

#### `POST /ingresos`

```json
{ "fecha": "2026-11-03", "cod_transportista": 3, "cuit_bodega": "30123456789" }
```

**201:** `{ "cod_ingreso": 80, "fecha": "2026-11-03", "estado": "en_confeccion", "cod_transportista": 3, "cuit_bodega": "30123456789", "renglones": [] }`

**Errores:** transportista o bodega inexistente, 422 (`23503`).

#### `GET /ingresos/{cod}` **[propuesta]**

**200:** cabecera más renglones. **Errores:** 404.

#### `POST /ingresos/{cod}/renglones`

Body `{ "cod_vino": 10, "cantidad": 120 }`. **201:** el renglón. Errores idénticos a los de los renglones de transferencia (RN-12 con 409, vino repetido con 409, vino inexistente y cantidad inválida con 422).

#### `POST /ingresos/{cod}/terminar` **[propuesta]**

Sin cuerpo. **200:** `{ "cod_ingreso": 80, "estado": "terminado" }`. Error: transición inválida, 409 (`P0001`).

#### `POST /ingresos/{cod}/procesar`

Sin cuerpo. Ejecuta `CALL sp_procesar_ingreso(cod)`: suma las cantidades al stock del depósito y pasa a `procesado`. **200:** `{ "cod_ingreso": 80, "estado": "procesado" }`.

| Error | HTTP | Mecanismo |
|---|---|---|
| El ingreso no está `terminado` (RN-10) | 409 | `P0001` |
| Deadlock o fallo de serialización | 503 | `40P01` / `40001` |

---

### 4.6 Reportes (solo lectura)

Los períodos relativos ("último trimestre", "último mes") se calculan en la base con `CURRENT_DATE`, no con fechas fijas. Todos devuelven un arreglo JSON.

| Endpoint | Consigna | Parámetros (query) | Respuesta (cada elemento) |
|---|---|---|---|
| `GET /reportes/top-vinos` | S1 | `limit` (por defecto 10, máx. 100) | `{ "posicion", "cod_vino", "nombre", "botellas_vendidas" }` |
| `GET /reportes/ventas-por-sala` | S8 | (ninguno) | `{ "id_sala", "calle", "numero", "monto_total" }` ordenado de mayor a menor |
| `GET /reportes/vinos-sin-stock` | S6 | `id_sala` (**obligatorio**) | `{ "cod_vino", "nombre", "stock_deposito" }` |
| `GET /reportes/transportista-activo` | S7 | (ninguno) | `{ "cod_transportista", "razon_social", "cantidad_ingresos" }` (arreglo vacío si no hubo actividad; más de un elemento si hay empate) |

**Errores comunes:** 422 si falta `id_sala` en `vinos-sin-stock`; 404 si la sala no existe.

#### `GET /reportes/trazabilidad/{cod}`

Lotes de uva que componen el vino (tabla `vino_lote`).

```json
{
  "cod_vino": 10, "nombre": "Malbec Reserva", "cuit_bodega": "30123456789",
  "lotes": [
    { "id_lote": 7, "nro_lote": 1007, "campania": 2021, "fecha_cosecha": "2021-03-12",
      "kilos": "5400.00", "id_finca": 2, "finca": "Finca El Atuel",
      "nro_parcela": 4, "cepa": "Malbec" }
  ]
}
```

`lotes` es `[]` si el vino no tiene trazabilidad cargada. **Errores:** 404 si el vino no existe.

---

### 4.7 Catálogos auxiliares **[propuesta]**

Solo lectura, sin paginar. Los necesitan los desplegables del front (nueva venta, alta de vino, alta de cliente, ingresos, filtros del catálogo).

| Endpoint | Campos |
|---|---|
| `GET /salas` | `id_sala`, `calle`, `numero`, `dia_cierre`, `codigo_postal` |
| `GET /cepas` | `id_cepa`, `nombre`, `tipo` |
| `GET /bodegas` | `cuit`, `razon_social`, `domicilio` |
| `GET /maridajes` | `id_maridaje`, `nombre`, `temperatura_servicio` |
| `GET /transportistas` | `cod_transportista`, `razon_social`, `cuit` |
| `GET /localidades` | `codigo_postal`, `nombre`, `provincia` |

---

## 5. Casos de error para las pruebas automáticas

El TP pide al menos 8 pruebas, de las cuales al menos 3 deben provocar la violación de una regla de la base y verificar el código HTTP. Candidatas:

| Prueba | Endpoint | Resultado esperado |
|---|---|---|
| Vender más que el stock de la sala (RN-09) | `POST /comprobantes` | 409, mensaje de la regla, sin filas creadas |
| Procesar una transferencia que sigue en confección (RN-11) | `POST /transferencias/{nro}/procesar` | 409 |
| Agregar un renglón a una transferencia ya terminada (RN-12) | `POST /transferencias/{nro}/renglones` | 409 |
| Crear un vino con precio negativo (RN-01) | `POST /vinos` | 422 |
| Crear un vino cuya composición no suma 100 (RN-05) | `POST /vinos` | 409 (el error aparece al commit) |
| Crear un vino duplicado (nombre, añada, volumen) | `POST /vinos` | 409 |
| Borrar un vino con movimientos (RN-14) | `DELETE /vinos/{cod}` | 409 |
| Detectar que la API llega a la base | `GET /salud` | 200 |

**Demostración de inyección SQL fallida** (paso 9 de la etapa): conviene usar el filtro `nombre` de `GET /vinos` (texto libre), por ejemplo `?nombre=' OR '1'='1`. Hay que cuidar que Pydantic **no** valide ese parámetro con un patrón estricto: si lo rechaza con 422 antes de llegar a la base, la demo no muestra que la consulta parametrizada lo trata como texto.

---

## 6. Preguntas abiertas (a acordar con el grupo y con quien hace Datos)

1. **FK violada (`23503`): 409 o 422.** El TP deja ambas. Propuesta: 409 cuando falla un `DELETE` (hay dependientes) y 422 cuando falla un `POST`/`PUT` (el dato referenciado no existe). Se decide por el método HTTP, sin interpretar el texto del error.
2. **Stock insuficiente al procesar una transferencia.** El ejemplo del TP (Anexo A.6) deja que falle el `CHECK (cantidad >= 0)`, lo que daría `23514` y 422. Pero `decisiones.md` (sección 5, paso 3) dice que el procedimiento **verifica antes** que el depósito alcance. Propuesta: verificar con `RAISE EXCEPTION` (da `P0001` y 409, igual que la venta sin stock) y dejar el `CHECK` como red de seguridad. Así "stock insuficiente" siempre devuelve 409.
3. **Triggers diferidos y transacciones de la API.** (a) RN-05 se valida al `COMMIT`: el manejo de errores de la API debe cubrir también el commit. (b) El trigger de coherencia `tipo_cliente` / subtipo: como el subtipo tiene FK al cliente, la fila del cliente se inserta primero. Ese trigger tiene que ser **diferido** (constraint trigger), si no, rechazaría todo alta de distribuidor o exportador.
4. **Alta de la cabecera del comprobante.** En el DBML, `subtotal`, `descuento` y `total` son `NOT NULL` y sin `DEFAULT`, y la API no puede enviarlos. Hay que definir si la base los inicializa en 0 (y el trigger los recalcula) o si la venta se crea con una función o procedimiento de la base (por ejemplo `sp_crear_comprobante`). El TP pide que la API llame a funciones y procedimientos en lugar de recalcular.
5. **Auditoría de precio.** `auditoria_precio.usuario` toma `current_user`, que siempre será `app_rw` (el rol de la API). Sin autenticación de usuarios finales, el registro no distingue quién cambió el precio. Está bien para esta versión, pero conviene dejarlo escrito en el informe.
6. **Cambio de `tipo_cliente` en `PUT /clientes/{id}`.** Hoy el contrato lo prohíbe. Cambiar de tipo implica crear o borrar filas de subtipo y permisos; si la cátedra lo exige, hay que definirlo.
7. **Endpoints extra y catálogos.** Los marcados **[propuesta]** (listados y detalle de transferencias e ingresos, `/terminar` de ingresos, catálogos, filtro `nombre`) no están en el mínimo, pero el front del TP los necesita. Confirmar que se hacen.
8. **Dinero como string.** Propuesta de serializar `NUMERIC` como string decimal. El front tendría que parsearlo solo para mostrarlo, nunca para calcular.
9. **Numeración de comprobantes.** `decisiones.md` (sección 10.4) deja pendiente con la cátedra si es global o por sala. Este contrato asume **global** (`GET /comprobantes/{nro}`). Si fuera por sala, la ruta tendría que incluir la sala.
10. **Validación del request.** FastAPI responde 422 por defecto ante tipos incorrectos. El TP asigna 400 al "formato inválido para el tipo" (`22P02`). Decidir si se unifica en 400 para parámetros de ruta y consulta, o se deja 422.
