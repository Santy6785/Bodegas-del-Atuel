# Contrato de la API: Bodegas del Atuel

**Estado:** borrador v0.6.2 (2026-11-07). No depende de que la base esté lista.
**Fuentes:** TPI, Etapa 6 (endpoints mínimos y traducción de SQLSTATE), `docs/decisiones.md`, `docs/esquema-relacional/modelo_relacional-Bodegas_del_Atuel.dbml` y `db/migrations/001_esquema.sql` a `007_roles.sql` (reconciliado); `008_indices.sql` vacío.
**Marcas:** los endpoints o campos marcados **[propuesta]** no figuran en el mínimo del TP; se agregaron porque el front o el modelo los necesitan. Hay que confirmarlos con el grupo (ver sección 6).

## Changelog

### v0.6.2 (2026-11-07)
- Corregido conteo de triggers en `005_triggers.sql`: 9 `CREATE TRIGGER` + 5 `CREATE CONSTRAINT TRIGGER` = 14 (verificación Paso 0, `Select-String`).

### v0.6.1 (2026-11-07)
- Corregidos números de línea de `007_roles.sql` según salida de `Select-String` (líneas 74, 77, 79, 98-101, 111-112, 122, 125, 128, 131, 134).
- Agregado `ctg_vino_composicion` (línea 438 de `005_triggers.sql`) al mapeo de triggers en sección 1.3.
- Total de triggers en `005` corregido a 14 (no 15): 9 `CREATE TRIGGER` + 5 `CREATE CONSTRAINT TRIGGER`.
- Encabezado: "001 a 007 (reconciliado); 008 vacío".

### v0.6 (2026-11-07)
- Reconciliada sección 1.3 con el estado real de `db/migrations/004_procedimientos.sql` (200 líneas), `005_triggers.sql` (518 líneas), `006_vistas.sql` (171 líneas) y `007_roles.sql` (109 líneas).
- Agregada tabla "Mapeo contrato → migración" para triggers (sección 1.3): nombres reales, líneas de `CREATE TRIGGER`, estados `Coincide` / `Renombrado` / `Fusionado`.
- Seguridad verificada: `004` y `005` no tienen `SECURITY DEFINER` ni `SET search_path`. Se marca `No cumple: contrato exige SECURITY DEFINER` donde aplica.
- `sp_crear_comprobante` marcado como `Falta en 004`.
- `sp_procesar_transferencia` corregido: verifica stock con `LEFT JOIN` inline (líneas 162-175 de `004`), no con `fn_stock_deposito`. Pregunta pendiente agregada.
- Vistas renombradas a reales: `vw_stock_total_vino`, `vw_ventas_mensuales_sala` (materializada, línea 78), `vw_documentos_pendientes`. Pregunta pendiente sobre `REFRESH MATERIALIZED VIEW CONCURRENTLY`.
- Sección 7 de privilegios actualizada frente a `007_roles.sql`: `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES` (línea 99) y `EXECUTE ON ALL ROUTINES` (línea 101). Marcados `No cumple` en escritura directa sobre tablas protegidas. Agregadas correcciones pendientes para Datos.
- `auditoria_precio.usuario DEFAULT current_user` verificado en `002_constraints.sql` línea 159. Marcado `No cumple` frente a D-B (`session_user`). Pregunta pendiente agregada.
- Contraseñas por defecto en `007_roles.sql` (líneas 33, 38). Pregunta pendiente agregada.
- Changelog v0.5: `IN OUT` → `INOUT` para `p_nro_comprobante` (consistencia con el resto del documento).
- Renumerada pregunta 6.15 → 6.14 (trigger de totales con `SECURITY DEFINER`); referencias actualizadas en sección 6 y sección 7.
- Nueva decisión 6.15: descuento del exportador configurable vs. fijo al 30 % (pendiente de validación con la cátedra).
- Nuevas preguntas 6.16 a 6.20: `SECURITY DEFINER` / `search_path`, `fn_stock_deposito`, `REFRESH MATERIALIZED VIEW`, `DEFAULT current_user` en auditoría, contraseñas por defecto.

### v0.5 (2026-11-07)
- Verificado `porcentaje_descuento` en `cliente_exportador`: `001_esquema.sql` línea 240 (`NUMERIC(5,2) NOT NULL`); `002_constraints.sql` líneas 278-283 (`DEFAULT 30.00` en línea 279, `CHECK (porcentaje_descuento BETWEEN 0 AND 100)` en línea 283, constraint `ck_cliente_exportador_descuento`).
- Confirmado en `003_funciones.sql`: 4 funciones (no 5); `LANGUAGE sql` en líneas 52, 87, 115, 144; `STRICT` en líneas 54 y 146; todas `STABLE`.
- Nueva decisión 6.15: descuento del exportador configurable vs. fijo al 30 % (pendiente de validación con la cátedra).
- Corregida conteo de funciones en el informe de revisión: 4 en `003`, no 5.

### v0.3 (2026-11-06)
- **D-A:** `POST /comprobantes` pasa a implementarse con `CALL sp_crear_comprobante(...)` (firma con `INOUT p_nro_comprobante` y arreglos `INTEGER[]`); se elimina el INSERT directo de cabecera y renglones desde la API.
- **D-B:** `trg_stock_venta`, `trg_descuento_stock_venta` (nuevo), `trg_totales_comprobante` y `trg_auditoria_precio` pasan a `SECURITY DEFINER`; `trg_auditoria_precio.usuario` usa `session_user` en lugar de `current_user`.
- **D-C:** Agregada `fn_stock_deposito(p_cod_vino INTEGER)`; `sp_procesar_transferencia` la usa para verificar stock del depósito antes de descontar.
- **D-D:** Parámetro de `sp_procesar_transferencia` corregido a `p_nro INTEGER` (Anexo A.6 del TPI, no A.5).
- **D-E:** Formato de error mantenido anidado `{"error": {...}}`; se documenta el cambio de una línea en `front/js/api/client.js` para leer `error?.mensaje`.
- **D-F:** `trg_coherencia_tipo_cliente` pasa a `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED`; 6.3(a) y 6.3(b) marcados como resueltos.
- **D-G:** Reportes alineados con el front: `top-vinos` usa `limit`, `ventas-por-sala` agrega `periodo`, `fecha_desde`, `fecha_hasta`; `vinos-sin-stock` pasa `id_sala` a opcional.
- Sección 1.3 actualizada con columna "Seguridad" y nueva función/procedimiento/trigger.
- Sección 7 de privilegios reescrita: `app_rw` pierde `INSERT`/`UPDATE`/`DELETE` en tablas que manejan procedimientos/triggers `SECURITY DEFINER`.

### v0.2 (2026-11-06)
- Agregada sección 1.3 "Firmas de la base de datos (contrato con la capa SQL)" con tabla por objeto (función, procedimiento, vista, trigger, DML), parámetros con tipo PostgreSQL, retorno, endpoint invocador, SQLSTATE posibles, regla del TPI y estado.
- Alineados nombres de parámetros de filtro con las columnas de la base: `id_cepa`, `cuit_bodega`, `page_size` (contract); documentado lo que hay que cambiar en el front (`cepa`, `bodega`, `pageSize`, `limite`, `sala_id`).
- Unificado el tipo de vino al valor de la base: `espumante` (el front usaba `espumoso`).
- Especificado el objeto de base e invocación con psycopg para cada endpoint (`SELECT fn_x(%s)`, `CALL sp_x(%s)`, `INSERT ... RETURNING`, vista directa).
- Marcados como **[propuesto]** los objetos que no están en el TPI mínimo ni en las migraciones (vacías `003` a `007`): `fn_total_comprobante`, `fn_stock_sala`, `fn_descuento_cliente`, `fn_antiguedad_anios`, `sp_procesar_ingreso`, `sp_procesar_transferencia`, `sp_crear_comprobante`, `sp_terminar_ingreso`, vistas de reportes, triggers de estado y stock.
- Agregada sección "Privilegios requeridos por el rol app_rw" con permisos por objeto (alimenta `007_roles.sql`).
- Resueltas preguntas abiertas 1, 2, 4, 5, 7, 8, 9 (sección 6); pendientes 3, 6, 10 y nuevas 11-14.
- Formato de error mantenido anidado en `{"error": {...}}`; documentado que `client.js` del front lee `mensaje`/`message`/`detail`/`error` en primer nivel y no extrae bien del objeto anidado. Pendiente de validar si se ajusta el front o el contrato.

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

> **Compatibilidad con el front (`front/js/api/client.js`):** el cliente lee `mensaje`, `message`, `detail` o `error` en el **primer nivel** del JSON de error. Como el contrato mantiene el formato anidado `{"error": {"sqlstate", "mensaje", "restriccion"}}`, se requiere un cambio de una línea en `client.js` para que lea `parsedData.error?.mensaje` además de los campos actuales. (Decisión D-E, cerrada en 6.11.)

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
| Request mal formado (validación de FastAPI/Pydantic) | (sin SQLSTATE) | 422 (ver 6.10) | **[propuesta]** |

En los endpoints de abajo solo se listan los errores propios de cada uno. En todos pueden aparecer además 404 (si el recurso de la ruta no existe), 422/400 (request inválido) y 503 (conexión o deadlock).

## 1.3 Firmas de la base de datos (contrato con la capa SQL)

Cada objeto de la base que invoca la API se especifica con su nombre exacto, parámetros (nombre y tipo PostgreSQL), retorno, endpoint invocador, SQLSTATE posibles, regla del TPI que cubre, seguridad (`SECURITY DEFINER` / `INVOKER`) y su estado de implementación. Estado de las migraciones (verificado): `001_esquema.sql` (360 líneas) y `002_constraints.sql` (327 líneas) están escritas; `003_funciones.sql` (168 líneas) está escrita y se reconcilió con esta sección (ver estados de cada función); `004_procedimientos.sql` (200 líneas) y `005_triggers.sql` (518 líneas) están escritas; `006_vistas.sql` (171 líneas) está escrita; `007_roles.sql` (109 líneas) está escrita; `008_indices.sql` (0 líneas) está vacía y en desarrollo.

### Funciones

| Objeto | Tipo | Parámetros (nombre, tipo PG) | Retorno | Invoca (endpoint) | SQLSTATE posibles | Regla TPI | Seguridad | Estado |
|---|---|---|---|---|---|---|---|---|
| `fn_total_comprobante` | FUNCTION | `p_nro INTEGER` | `NUMERIC` | `GET /comprobantes/{nro}` (verificación opcional) | `P0001` (trigger) | RN-08 | INVOKER | Discrepancia: contrato decía `(p_nro_comprobante INTEGER) RETURNS NUMERIC(12,2)`; real en `003_funciones.sql` línea 85 es `(p_nro INTEGER) RETURNS NUMERIC` (STABLE, LANGUAGE sql) |
| `fn_stock_sala` | FUNCTION | `p_sala INTEGER`, `p_vino INTEGER` | `INTEGER` | `GET /vinos/{cod}`, `GET /reportes/vinos-sin-stock` | `22P02` | RN-09 | INVOKER | Definido en migración (`003_funciones.sql`, línea 113; STABLE, LANGUAGE sql) |
| `fn_stock_deposito` | FUNCTION | `p_cod_vino INTEGER` | `INTEGER` | `sp_procesar_transferencia` (verificación previa) | `22P02` | RN-09 | INVOKER | **Falta en `003`** (no está definido; `sp_procesar_transferencia` verifica con `LEFT JOIN` inline en `004_procedimientos.sql` líneas 162-175). Pregunta 6.17. |
| `fn_descuento_cliente` | FUNCTION | `p_id_cliente INTEGER` | `NUMERIC` | `GET /clientes`, `GET /clientes/{id}` | `22P02` | RN-06 | INVOKER | Discrepancia: contrato decía `(p_tipo_cliente tipo_cliente) RETURNS NUMERIC(5,2)`; real en `003_funciones.sql` línea 50 es `(p_id_cliente INTEGER) RETURNS NUMERIC` (STABLE, LANGUAGE sql, STRICT línea 54). El porcentaje del exportador se lee de `e.porcentaje_descuento` (línea 59). La columna `porcentaje_descuento` existe en `cliente_exportador`: `001_esquema.sql` línea 240 (`NUMERIC(5,2) NOT NULL`); `002_constraints.sql` líneas 278-283 le pone `DEFAULT 30.00` (línea 279) y `CHECK (porcentaje_descuento BETWEEN 0 AND 100)` (línea 283, constraint `ck_cliente_exportador_descuento`). |
| `fn_antiguedad_anios` | FUNCTION | `p_fecha DATE` | `INTEGER` | No expuesto por endpoint aún | — | (derivado EMPLEADO) | INVOKER | Discrepancia: contrato decía `(p_fecha_ingreso DATE)`; real en `003_funciones.sql` línea 142 es `(p_fecha DATE) RETURNS INTEGER` (STABLE, STRICT, LANGUAGE sql). Usa `CURRENT_DATE`; por eso es STABLE, no IMMUTABLE. |

### Procedimientos

| Objeto | Tipo | Parámetros (nombre, tipo PG) | Retorno | Invoca (endpoint) | SQLSTATE posibles | Regla TPI | Seguridad | Estado |
|---|---|---|---|---|---|---|---|---|
| `sp_procesar_ingreso` | PROCEDURE | `p_cod_ingreso INTEGER` | (ninguno, `CALL`) | `POST /ingresos/{cod}/procesar` | `P0001`, `23514`, `40P01`/`40001` | RN-10 | **INVOKER** | Definido en migración (`004_procedimientos.sql`, línea 48; `LANGUAGE plpgsql`). **No cumple: contrato exige SECURITY DEFINER** (D-B). |
| `sp_procesar_transferencia` | PROCEDURE | `p_nro INTEGER` | (ninguno, `CALL`) | `POST /transferencias/{nro}/procesar` | `P0001`, `23514`, `40P01`/`40001` | RN-09, RN-11 | **INVOKER** | Definido en migración (`004_procedimientos.sql`, línea 120; `LANGUAGE plpgsql`). **No cumple: contrato exige SECURITY DEFINER** (D-B). Verifica stock de depósito con `LEFT JOIN` inline (líneas 162-175), no con `fn_stock_deposito`. Pregunta 6.17. |
| `sp_crear_comprobante` | PROCEDURE | `IN p_id_cliente INTEGER`, `IN p_id_sala INTEGER`, `IN p_cod_vinos INTEGER[]`, `IN p_cantidades INTEGER[]`, `INOUT p_nro_comprobante INTEGER` | `p_nro_comprobante` por `INOUT` | `POST /comprobantes` | `P0001`, `23503`, `23514` | RN-08, RN-09 | **SECURITY DEFINER** | **Falta en `004`** (no definido). Firma de D-A mantenida. |

### Triggers

| Objeto | Tipo | Parámetros | Retorno | Invoca (endpoint) | SQLSTATE posibles | Regla TPI | Seguridad | Estado |
|---|---|---|---|---|---|---|---|---|
| `trg_stock_venta` | TRIGGER (BEFORE INSERT) | `renglon_comprobante` | — | `sp_crear_comprobante` (vía renglones) | `P0001` | RN-09 | INVOKER | **Renombrado**: real es `trg_renglon_comprobante_antes` (`005_triggers.sql`, línea 112). |
| `trg_descuento_stock_venta` | TRIGGER (AFTER INSERT) | `renglon_comprobante` | — | `sp_crear_comprobante` (vía renglones) | `P0001` | RN-09 | INVOKER | **Fusionado**: real es `trg_renglon_comprobante_despues` (`005_triggers.sql`, línea 176), que cubre RN-08 y RN-09. |
| `trg_totales_comprobante` | TRIGGER (AFTER INSERT/UPDATE/DELETE) | `renglon_comprobante` | — | `sp_crear_comprobante` (vía renglones) | `P0001` | RN-08 | INVOKER | **Fusionado**: real es `trg_renglon_comprobante_despues` (`005_triggers.sql`, línea 176). |
| `trg_estados_ingreso_transferencia` | TRIGGER (BEFORE UPDATE) | `ingreso`, `transferencia` | — | `POST /ingresos/{cod}/terminar`, `POST /transferencias/{nro}/terminar` | `P0001` | RN-10, RN-11 | INVOKER | **Renombrado y dividido**: reales son `trg_ingreso_estados` (`005_triggers.sql`, línea 214, RN-10) y `trg_transferencia_estados` (`005_triggers.sql`, línea 219, RN-11), ambos con función común `trg_control_estado_documento`. |
| `trg_bloqueo_renglones_confeccion` | TRIGGER (BEFORE INSERT/UPDATE/DELETE) | `renglon_ingreso`, `renglon_transferencia` | — | `POST /ingresos/{cod}/renglones`, `POST /transferencias/{nro}/renglones` | `P0001` | RN-12 | INVOKER | **Renombrado y dividido**: reales son `trg_renglon_ingreso_confeccion` (`005_triggers.sql`, línea 300) y `trg_renglon_transferencia_confeccion` (`005_triggers.sql`, línea 346). |
| `trg_fecha_confeccion_inmodificable` | TRIGGER (BEFORE INSERT/UPDATE) | `transferencia` | — | `POST /transferencias`, `POST /transferencias/{nro}/terminar` | `P0001` | RN-11 | INVOKER | **Renombrado**: real es `trg_transferencia_fecha` (`005_triggers.sql`, línea 247). |
| `trg_auditoria_precio` | TRIGGER (AFTER UPDATE) | `vino.precio` | — | `PUT /vinos/{cod}` | — | RN-13 | **INVOKER** | **Renombrado**: real es `trg_vino_auditoria` (`005_triggers.sql`, línea 375, función `trg_vino_auditoria_precio`). **No cumple: contrato exige SECURITY DEFINER** (D-B). `auditoria_precio.usuario` usa `DEFAULT current_user` en `002_constraints.sql` línea 159; con `SECURITY DEFINER` registraría al propietario. Pregunta 6.18. |
| `trg_porcentajes_cepa` | CONSTRAINT TRIGGER DEFERRABLE | `vino_cepa` | — | `POST /vinos`, `PUT /vinos/{cod}` | `P0001` | RN-05 | INVOKER | **Renombrado**: real es `ctg_vino_cepa_suma_100` (`005_triggers.sql`, línea 432, `DEFERRABLE INITIALLY DEFERRED`). |
| `trg_coherencia_tipo_cliente` | CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED | `cliente` | — | `POST /clientes`, `PUT /clientes/{id}` | `P0001` | coherencia subtipos | INVOKER | **Renombrado y dividido**: reales son `ctg_cliente_tipo` (`005_triggers.sql`, línea 545), `ctg_cliente_distribuidor_tipo` (línea 551) y `ctg_cliente_exportador_tipo` (línea 557). |
| `trg_bodega_lote` | TRIGGER (BEFORE INSERT) | `vino_lote` | — | sin endpoint en v0.6; se dispara solo desde la base | `P0001` | regla cruzada bodega-lote | INVOKER | **Renombrado**: real es `trg_vino_lote_bodega` (`005_triggers.sql`, línea 480). |

**Tabla de mapeo contrato → migración (triggers):**

| Nombre en el contrato | Nombre real en `005_triggers.sql` | Línea `CREATE TRIGGER` | Estado |
|---|---|---|---|
| `trg_stock_venta` | `trg_renglon_comprobante_antes` | 112 | Renombrado |
| `trg_descuento_stock_venta` | `trg_renglon_comprobante_despues` | 176 | Fusionado (cubre RN-08 y RN-09) |
| `trg_totales_comprobante` | `trg_renglon_comprobante_despues` | 176 | Fusionado (cubre RN-08) |
| `trg_estados_ingreso_transferencia` | `trg_ingreso_estados` | 214 | Renombrado y dividido |
| `trg_estados_ingreso_transferencia` | `trg_transferencia_estados` | 219 | Renombrado y dividido |
| `trg_bloqueo_renglones_confeccion` | `trg_renglon_ingreso_confeccion` | 300 | Renombrado y dividido |
| `trg_bloqueo_renglones_confeccion` | `trg_renglon_transferencia_confeccion` | 346 | Renombrado y dividido |
| `trg_fecha_confeccion_inmodificable` | `trg_transferencia_fecha` | 247 | Renombrado |
| `trg_auditoria_precio` | `trg_vino_auditoria` | 375 | Renombrado |
| `trg_porcentajes_cepa` | `ctg_vino_cepa_suma_100` | 432 | Renombrado |
| `trg_porcentajes_cepa` | `ctg_vino_composicion` | 438 | Fusionado (cubre vino sin cepas) |
| `trg_coherencia_tipo_cliente` | `ctg_cliente_tipo` | 545 | Renombrado y dividido |
| `trg_coherencia_tipo_cliente` | `ctg_cliente_distribuidor_tipo` | 551 | Renombrado y dividido |
| `trg_coherencia_tipo_cliente` | `ctg_cliente_exportador_tipo` | 557 | Renombrado y dividido |
| `trg_bodega_lote` | `trg_vino_lote_bodega` | 480 | Renombrado |

### Vistas

| Objeto | Tipo | Columnas (relevantes) | Invoca (endpoint) | SQLSTATE posibles | Regla TPI | Estado |
|---|---|---|---|---|---|---|
| `vista_stock_total_por_vino` | VIEW | `cod_vino`, `stock_deposito`, `stock_salas`, `stock_total` | `GET /vinos/{cod}` | — | (S9) | **Renombrado**: real es `vw_stock_total_vino` (`006_vistas.sql`, línea 35, `CREATE OR REPLACE VIEW`). |
| `vista_ventas_mensuales_por_sala` | VIEW | `id_sala`, `mes`, `monto_total` | `GET /reportes/ventas-por-sala` | — | S8 | **Renombrado**: real es `vw_ventas_mensuales_sala` (`006_vistas.sql`, línea 78, `CREATE MATERIALIZED VIEW`, índice único línea 114 para `REFRESH MATERIALIZED VIEW CONCURRENTLY`). Pregunta 6.19. |
| `vista_documentos_pendientes` | VIEW | `tipo`, `nro`, `estado`, `fecha` | `GET /transferencias`, `GET /ingresos/{cod}` | — | (listados) | **Renombrado**: real es `vw_documentos_pendientes` (`006_vistas.sql`, línea 135, `CREATE OR REPLACE VIEW`). |

**Nota sobre vistas materializadas:** `vw_ventas_mensuales_sala` es materializada y requiere `REFRESH MATERIALIZED VIEW CONCURRENTLY` periódico. El contrato no define un endpoint ni un proceso para eso. Pregunta 6.19.

**Nota sobre `SECURITY DEFINER`:** `004_procedimientos.sql` y `005_triggers.sql` no contienen `SECURITY DEFINER` ni `SET search_path` (verificado con `grep` en ambos archivos). Todos los objetos que el contrato requiere `SECURITY DEFINER` figuran como `INVOKER` y se marcan como **No cumple**. Véase pregunta 6.16.

### DML directo (INSERT/UPDATE/DELETE con constraints)

`comprobante` y `renglon_comprobante` **ya no reciben INSERT desde `app_rw`**: la venta pasa por `sp_crear_comprobante` (`CALL`), que inserta la cabecera y los renglones internamente. Las tablas quedan como solo lectura para `app_rw` (`SELECT` únicamente), y la escritura la hacen el procedimiento y los triggers `SECURITY DEFINER`.

| Objeto | Operación | Parámetros mapeados | Invoca (endpoint) | SQLSTATE posibles | Regla TPI | Estado |
|---|---|---|---|---|---|---|
| `vino` | `INSERT` / `UPDATE` | `nombre`, `tipo`, `anada`, `volumen_ml`, `graduacion`, `precio`, `cuit_bodega` | `POST /vinos`, `PUT /vinos/{cod}` | `23505`, `23514`, `P0001` (RN-05) | RN-01, RN-05, RN-15 | Definido en migración (tabla) |
| `ingreso` | `INSERT ... RETURNING cod_ingreso` | `fecha`, `cod_transportista`, `cuit_bodega` | `POST /ingresos` | `23503` | — | Definido en migración (tabla) |
| `transferencia` | `INSERT ... RETURNING nro_transferencia` | `id_sala` (fecha_confeccion/estado por DEFAULT) | `POST /transferencias` | `23503` | RN-11 | Definido en migración (tabla) |
| `cliente` | `INSERT` / `UPDATE` | campos de cliente + bloque subtipo | `POST /clientes`, `PUT /clientes/{id}` | `23505`, `23514`, `P0001` | RN-07, coherencia subtipos | Definido en migración (tabla) |

**Nota sobre `DEFAULT 0` de `comprobante`:** `002_constraints.sql` ya incluye `DEFAULT 0` en `subtotal`, `descuento` y `total`. Como la cabecera ahora se inserta dentro de `sp_crear_comprobante`, la API no necesita enviar esos valores ni depender del DEFAULT para el flujo de venta.

**Nota sobre `ON DELETE CASCADE`:** `vino_cepa`, `vino_maridaje` y `vino_lote` tienen `ON DELETE CASCADE` (según `002`), por lo que al borrar un vino se borran sus composiciones, maridajes y trazabilidad en cascada.

**Nota sobre el tipo `espumante`:** el ENUM `tipo_vino` de `001_esquema.sql` usa `espumante`. El front (`vinos.js`, `MAPA_PANTALLAS.md`) usaba `espumoso`; se unifica al valor de la base.

**Nota sobre la invocación con psycopg:**
- Funciones STABLE: `SELECT fn_x(%s, %s)` con los parámetros posicionales.
- Procedimientos: `CALL sp_x(%s, %s, %s, %s, %s)` (psycopg 3 admite `CALL` directo). Para `sp_crear_comprobante`, se pasa `None` como valor del parámetro `INOUT` y se lee `p_nro_comprobante` de la fila de salida del `CALL`.
- Reportes: consulta directa o vista de `006_vistas.sql` (vacía, por definir). Los períodos relativos se calculan en la base con `CURRENT_DATE`.

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

**Objeto de base:** consulta directa sobre `vino` JOIN `bodega` (sin vista definida aún en `006_vistas.sql`). psycopg: `SELECT ... FROM vino v JOIN bodega b ON v.cuit_bodega = b.cuit WHERE ... ORDER BY v.cod_vino LIMIT %s OFFSET %s`.

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

Ficha del vino (consigna S9). **Objeto de base:** consulta directa sobre `vino` JOIN `bodega`, `vino_cepa` JOIN `cepa`, `vino_maridaje` JOIN `maridaje`, y stock desde `stock_deposito` + `stock_sala` (o la vista `vista_stock_total_por_vino` cuando se implemente en `006_vistas.sql`). psycopg: `SELECT ...` con `JOIN`s y, para el stock, `SELECT fn_stock_sala(%s, %s)` por cada sala o `SUM(cantidad)` desde `stock_sala`. **200:**

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

Alta del vino con su composición y maridajes, en **una sola transacción** (`vino`, `vino_cepa`, `vino_maridaje`). **Objetos de base:** `INSERT INTO vino ...` (DML directo), `INSERT INTO vino_cepa ...` (dispara `trg_porcentajes_cepa`, constraint trigger diferido que falla en `COMMIT`), `INSERT INTO vino_maridaje ...`. psycopg: `BEGIN; INSERT INTO vino ... RETURNING cod_vino; INSERT INTO vino_cepa (...); INSERT INTO vino_maridaje (...); COMMIT;`. El RN-05 se valida al `COMMIT`.

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

Reemplazo completo. El cuerpo es el mismo que el de `POST /vinos` (incluidas `composicion` y `maridajes`). Un cambio de precio queda registrado por el trigger de auditoría (RN-13: fecha, usuario, precio anterior y nuevo); la API no escribe en `auditoria_precio`. **Objetos de base:** `UPDATE vino SET precio = %s WHERE cod_vino = %s` (dispara `trg_auditoria_precio` AFTER UPDATE que lee `current_user` = `app_rw`), `DELETE FROM vino_cepa WHERE cod_vino = %s` + `INSERT`, `DELETE FROM vino_maridaje WHERE cod_vino = %s` + `INSERT`. psycopg en una transacción.

**200:** el vino actualizado (mismo cuerpo que el detalle). **Errores:** los mismos que `POST /vinos`.

#### `DELETE /vinos/{cod}`

**204** sin cuerpo. **Objeto de base:** `DELETE FROM vino WHERE cod_vino = %s` (DML directo; `vino_cepa`, `vino_maridaje` y `vino_lote` son `ON DELETE CASCADE` según `002`, así que se borran en cascada composición, maridajes y trazabilidad. Lo que protege el historial son `renglon_comprobante`, `renglon_ingreso`, `renglon_transferencia`, `stock_sala`, `stock_deposito` y `auditoria_precio` con `ON DELETE RESTRICT`, RN-14).

| Error | HTTP | Mecanismo |
|---|---|---|
| El vino tiene movimientos (ventas, ingresos, transferencias) o stock (RN-14) | 409 | `23503`, FK `ON DELETE RESTRICT` |

---

### 4.2 Clientes

Jerarquía supertipo/subtipos (`cliente`, `cliente_distribuidor`, `cliente_exportador`). El **descuento no se envía**: en las respuestas aparece como `descuento_pct`, calculado por `fn_descuento_cliente` (socio 10, distribuidor 20, exportador 30).

#### `GET /clientes`

Query: `page`, `page_size`, `tipo_cliente` (`socio` | `distribuidor` | `exportador`).

**Objeto de base:** consulta directa sobre `cliente` LEFT JOIN `cliente_distribuidor` / `cliente_exportador`. El campo `descuento_pct` se calcula con `SELECT fn_descuento_cliente(tipo_cliente)` en la consulta (no es un snapshot). **200:**

```json
{
  "id_cliente": 1, "apellido_razon_social": "Pérez", "nombre": "Ana",
  "tipo_documento": "DNI", "nro_documento": "30111222",
  "direccion": "Calle 123", "codigo_postal": "M5600",
  "fecha_alta": "2026-01-15", "tipo_cliente": "socio", "descuento_pct": "10.00"
}
```

#### `GET /clientes/{id}`

El mismo cuerpo, más el bloque del subtipo cuando corresponda. **Objeto de base:** consulta directa sobre `cliente` + subtipo correspondiente. `descuento_pct` se calcula con `SELECT fn_descuento_cliente(tipo_cliente)` (no es snapshot).

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
- Se inserta cliente, subtipo y permisos en **una sola transacción**. **Objetos de base:** `INSERT INTO cliente ... RETURNING id_cliente` (dispara `trg_coherencia_tipo_cliente` y el trigger de nombre obligatorio), `INSERT INTO cliente_distribuidor / cliente_exportador ...`, `INSERT INTO permiso_exportacion ...`. psycopg: `BEGIN; ...; COMMIT;`.

**201:** el cliente creado (mismo cuerpo que el detalle), con `Location`.

| Error | HTTP | Mecanismo |
|---|---|---|
| Documento repetido (tipo + número) o `nro_habilitacion` repetido | 409 | `23505` |
| Código postal inexistente | 422 | `23503` |
| Vencimiento del permiso no posterior a la emisión (RN-07) | 422 | `23514` |
| Tipo de cliente incoherente con el subtipo enviado | 409 | `P0001`, trigger de coherencia |

#### `PUT /clientes/{id}`

Reemplazo completo, mismo cuerpo que `POST`. El `tipo_cliente` debe ser el actual (cambiar de tipo queda pendiente, ver 6.6). **Objetos de base:** `UPDATE cliente SET ...` (dispara `trg_coherencia_tipo_cliente`), `UPDATE/INSERT/DELETE` en subtipo y permisos. psycopg en una transacción. **200:** el cliente actualizado. **Errores:** los mismos que `POST`.

#### `DELETE /clientes/{id}`

**204.** Se borran en cascada el subtipo y los permisos. **Objeto de base:** `DELETE FROM cliente WHERE id_cliente = %s` (CASCADE en `cliente_distribuidor`, `cliente_exportador`, `permiso_exportacion`; `ON DELETE RESTRICT` desde `comprobante` si tiene compras, RN-14).

| Error | HTTP | Mecanismo |
|---|---|---|
| El cliente tiene comprobantes | 409 | `23503`, FK `ON DELETE RESTRICT` |

---

### 4.3 Comprobantes (ventas)

#### `POST /comprobantes`

Venta completa en **una sola transacción**. **No se envían** precio, descuento, subtotales ni total: los calculan los triggers de la base (RN-06, RN-08).

**Decisión (6.4, resuelta):** la venta se registra con `CALL sp_crear_comprobante(...)`. Se elimina el INSERT directo de cabecera y renglones desde la API.

**Request:**

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

**Objeto de base:** procedimiento `sp_crear_comprobante(
  IN p_id_cliente INTEGER,
  IN p_id_sala INTEGER,
  IN p_cod_vinos INTEGER[],
  IN p_cantidades INTEGER[],
  INOUT p_nro_comprobante INTEGER
)`.

- Los dos arreglos (`p_cod_vinos`, `p_cantidades`) deben tener la misma longitud. Si no, el procedimiento lanza `RAISE EXCEPTION` con `P0001` y la API traduce a **422** (error de request).
- Dentro del procedimiento: inserta la cabecera de `comprobante` con `subtotal = descuento = total = 0`, inserta un renglón en `renglon_comprobante` por cada par del arreglo (los triggers `trg_stock_venta`, `trg_descuento_stock_venta` y `trg_totales_comprobante` calculan precio, descuento, subtotal y total), y devuelve `p_nro_comprobante` por `INOUT`. Todo en una sola transacción.

**Invocación con psycopg:**

```sql
CALL sp_crear_comprobante(%s, %s, %s, %s, %s)
```

Se pasa `None` como valor del parámetro `INOUT` (`p_nro_comprobante`) y se lee el número generado de la fila de salida que devuelve el `CALL`.

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
| Arreglos de distinto largo | 422 | `P0001`, procedimiento (error de request) |
| Stock insuficiente en la sala (RN-09) | 409, con el mensaje de la regla | `P0001`, trigger `trg_stock_venta` |
| Vino repetido en los renglones | 409 | `23505`, PK `(nro_comprobante, cod_vino)` |
| Cliente, sala o vino inexistente | 422 | `23503` |
| Cantidad <= 0 | 422 | `23514` |

Ante cualquier error **no queda nada a medias** (rollback de toda la transacción). El `descuento_pct` de cada renglón es un snapshot tomado por el trigger desde `fn_descuento_cliente(tipo_cliente)` (RN-06); la API no lo calcula.

#### `GET /comprobantes/{nro}`

**Objeto de base:** consulta directa sobre `comprobante` JOIN `renglon_comprobante`. `SELECT fn_total_comprobante(%s)` queda como función de verificación opcional, no como parte del flujo normal. psycopg: `SELECT ... FROM comprobante c JOIN renglon_comprobante rc ON ... WHERE c.nro_comprobante = %s`. **200:** mismo cuerpo que la respuesta del `POST`. **Errores:** 404.

---

### 4.4 Transferencias (depósito central a salas)

Circuito: `en_confeccion` a `terminado` a `procesado`, sin retrocesos (RN-11, RN-12).

#### `POST /transferencias`

```json
{ "id_sala": 1 }
```

La fecha de confección es siempre la actual y no se puede enviar ni modificar (trigger, RN-11). El estado inicial es `en_confeccion`. **Objeto de base:** `INSERT INTO transferencia (id_sala) VALUES (%s) RETURNING nro_transferencia, id_sala, fecha_confeccion, estado` (DML directo; dispara `trg_fecha_confeccion_inmodificable`). psycopg: `INSERT INTO transferencia (id_sala) VALUES (%s) RETURNING ...`.

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

**Objeto de base:** `INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad) VALUES (%s, %s, %s)` (dispara `trg_bloqueo_renglones_confeccion`, BEFORE, RN-12; PK `23505` si vino repetido). psycopg: `INSERT INTO renglon_transferencia ... RETURNING ...`.

**201:** el renglón creado.

| Error | HTTP | Mecanismo |
|---|---|---|
| La transferencia no está en confección (RN-12) | 409 | `P0001`, trigger sobre renglones |
| Vino ya cargado en esta transferencia | 409 | `23505` |
| Vino inexistente | 422 | `23503` |
| Cantidad <= 0 | 422 | `23514` |

#### `POST /transferencias/{nro}/terminar`

Sin cuerpo. Pasa el estado a `terminado`. **Objeto de base:** `UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = %s` (dispara `trg_estados_ingreso_transferencia`, BEFORE UPDATE, RN-11). psycopg: `UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = %s RETURNING nro_transferencia, estado`.

**200:** `{ "nro_transferencia": 55, "estado": "terminado" }`.

| Error | HTTP | Mecanismo |
|---|---|---|
| Transición de estado inválida (RN-11) | 409 | `P0001`, trigger de estados |

#### `POST /transferencias/{nro}/procesar`

Sin cuerpo. Ejecuta `CALL sp_procesar_transferencia(%s)`: descuenta del depósito, suma al stock de la sala y pasa a `procesado`, todo en una transacción. **Objeto de base:** procedimiento `sp_procesar_transferencia(p_nro INTEGER)`. El procedimiento **verifica antes** con `fn_stock_deposito(p_cod_vino)` que el depósito tiene stock suficiente (RN-09) y lanza `RAISE EXCEPTION` (`P0001`, 409) si no (ver 6.2, resuelto). psycopg: `CALL sp_procesar_transferencia(%s)`. **200:** `{ "nro_transferencia": 55, "estado": "procesado" }`.

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

**Objeto de base:** `INSERT INTO ingreso ... RETURNING ...` (DML directo).

**201:** ingreso creado con `cod_ingreso`.

**Errores:** transportista o bodega inexistente, 422 (`23503`).

#### `GET /ingresos/{cod}` **[propuesta]**

**200:** cabecera más renglones. **Errores:** 404.

#### `POST /ingresos/{cod}/renglones`

Body `{ "cod_vino": 10, "cantidad": 120 }`. **Objeto de base:** `INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (%s, %s, %s)` (dispara `trg_bloqueo_renglones_confeccion`, RN-12). **201:** el renglón.

#### `POST /ingresos/{cod}/terminar` **[propuesta]**

Sin cuerpo. Pasa el estado a `terminado`. **Objeto de base:** `UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = %s` (dispara `trg_estados_ingreso_transferencia`, BEFORE UPDATE, RN-10/RN-11). psycopg: `UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = %s RETURNING cod_ingreso, estado`. **200:** `{ "cod_ingreso": 80, "estado": "terminado" }`. Error: transición inválida, 409 (`P0001`).

#### `POST /ingresos/{cod}/procesar`

Sin cuerpo. Ejecuta `CALL sp_procesar_ingreso(%s)`: suma las cantidades al stock del depósito y pasa a `procesado`, todo en una transacción. **Objeto de base:** procedimiento `sp_procesar_ingreso(p_cod_ingreso INTEGER)`. psycopg: `CALL sp_procesar_ingreso(%s)`. **200:** `{ "cod_ingreso": 80, "estado": "procesado" }`.

| Error | HTTP | Mecanismo |
|---|---|---|
| El ingreso no está `terminado` (RN-10) | 409 | `P0001` |
| Deadlock o fallo de serialización | 503 | `40P01` / `40001` |

---

### 4.6 Reportes (solo lectura)

Los períodos relativos ("último trimestre", "último mes") se resuelven en la base con `CURRENT_DATE` (vía `periodo=ultimo_trimestre` o consultando `fecha_desde`/`fecha_hasta` ya resueltas), no con fechas fijas calculadas en el front. Todos devuelven un arreglo JSON.

| Endpoint | Consigna | Parámetros (query) | Respuesta (cada elemento) |
|---|---|---|---|
| `GET /reportes/top-vinos` | S1 | `limit` (por defecto 10, máx. 100) | `{ "posicion", "cod_vino", "nombre", "botellas_vendidas" }` |
| `GET /reportes/ventas-por-sala` | S8 | `periodo` (opcional, ej. `ultimo_trimestre`), `fecha_desde`, `fecha_hasta` (ISO `YYYY-MM-DD`) | `{ "id_sala", "calle", "numero", "monto_total" }` ordenado de mayor a menor |
| `GET /reportes/vinos-sin-stock` | S6 | `id_sala` (opcional) | `{ "cod_vino", "nombre", "stock_deposito" }` |
| `GET /reportes/transportista-activo` | S7 | (ninguno) | `{ "cod_transportista", "razon_social", "cantidad_ingresos" }` (arreglo vacío si no hubo actividad; más de un elemento si hay empate) |

**Errores comunes:** 404 si la sala no existe (solo cuando se pasa `id_sala` en `vinos-sin-stock`).

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

**Objetos de base:** consultas SELECT directa sobre cada tabla catálogo (`sala_venta`, `cepa`, `bodega`, `maridaje`, `transportista`, `localidad`). Solo lectura, sin paginar. Los necesitan los desplegables del front (nueva venta, alta de vino, alta de cliente, ingresos, filtros del catálogo).

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

1. **FK violada (`23503`): 409 o 422.** [Resuelto] 409 cuando falla un `DELETE` (hay dependientes) y 422 cuando falla un `POST`/`PUT` (el dato referenciado no existe). Se decide por el método HTTP, sin interpretar el texto del error. (Coincide con la tabla de traducción de 1.2.)
2. **Stock insuficiente al procesar una transferencia.** [Resuelto] El procedimiento `sp_procesar_transferencia` verifica **antes** con un `LEFT JOIN` inline contra `stock_deposito` (`004_procedimientos.sql` líneas 162-175, `COALESCE(d.cantidad, 0) < r.cantidad`) y lanza `RAISE EXCEPTION` (`P0001`, 409) si el depósito no alcanza. `fn_stock_sala` solo se usa para lectura de stock de sala, no para el depósito. `fn_stock_deposito` no está definido en `003`. El `CHECK (cantidad >= 0)` queda como red de seguridad (`23514`, 422). Así "stock insuficiente" siempre devuelve 409. Pregunta 6.17: ¿se agrega `fn_stock_deposito` a `003` y se usa desde `004`, o se mantiene la verificación inline?
3. **Triggers diferidos y transacciones de la API.** [Resuelto] (a) RN-05 se valida al `COMMIT`: el manejo de errores de la API debe cubrir también el commit (marcado resuelto). (b) El trigger de coherencia `tipo_cliente` / subtipo es `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` (D-F), así que no rechaza altas de distribuidor/exportador al insertar primero el cliente.
4. **Alta de la cabecera del comprobante.** [Resuelto] Se usa `CALL sp_crear_comprobante(...)` (D-A): `IN p_id_cliente INTEGER`, `IN p_id_sala INTEGER`, `IN p_cod_vinos INTEGER[]`, `IN p_cantidades INTEGER[]`, `INOUT p_nro_comprobante INTEGER`. El procedimiento inserta cabecera y renglones internamente; la API solo llama al procedimiento y lee `p_nro_comprobante` de la salida del `CALL`. No se requiere `DEFAULT 0` en la API para este flujo (aunque `002_constraints.sql` ya lo incluye).
5. **Auditoría de precio.** [No cumple] `trg_vino_auditoria` (línea 375 de `005_triggers.sql`) inserta en `auditoria_precio` sin especificar `usuario`, por lo que se aplica `DEFAULT current_user` (`002_constraints.sql` línea 159). Con `SECURITY DEFINER` esto registraría al propietario, no al rol de conexión. La corrección de D-B (`session_user`) no está implementada: `005` no tiene `SECURITY DEFINER` y el DEFAULT es `current_user`. Pregunta 6.18.
6. **Cambio de `tipo_cliente` en `PUT /clientes/{id}`.** [Pendiente] Hoy el contrato lo prohíbe. Cambiar de tipo implica crear o borrar filas de subtipo y permisos; si la cátedra lo exige, hay que definirlo.
7. **Endpoints extra y catálogos.** [Resuelto] Los marcados **[propuesta]** (listados y detalle de transferencias e ingresos, `/terminar` de ingresos, catálogos, filtro `nombre`) se incluyen porque el front los necesita. Confirmar con el grupo.
8. **Dinero como string.** [Resuelto] Se serializa `NUMERIC` como string decimal (`"12500.00"`). El front parsea solo para mostrar, nunca para calcular.
9. **Numeración de comprobantes.** [Resuelto] Asume **global** (`GET /comprobantes/{nro}`), según `decisiones.md` (sección 10.4). Si fuera por sala, la ruta incluiría la sala.
10. **Validación del request.** [Pendiente] FastAPI responde 422 por defecto ante tipos incorrectos. El TP asigna 400 al "formato inválido para el tipo" (`22P02`). Decidir si se unifica en 400 para parámetros de ruta y consulta, o se deja 422.
11. **Formato de error y compatibilidad con el front.** [Resuelto] El contrato mantiene el formato anidado `{"error": {"sqlstate", "mensaje", "restriccion"}}` (D-E). Se requiere un cambio de una línea en `front/js/api/client.js` para que lea `parsedData.error?.mensaje` además de los campos actuales.
12. **Vistas de reportes (`006_vistas.sql`).** [Pendiente] El archivo está vacío. Pendiente definir `vista_stock_total_por_vino`, `vista_ventas_mensuales_por_sala`, `vista_documentos_pendientes` o usar consultas directas.
13. **Privilegios del rol `app_rw`.** [No cumple] `007_roles.sql` concede `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES` (línea 99) y `GRANT EXECUTE ON ALL ROUTINES` (línea 101) a `app_rw`, lo que incluye escritura directa sobre tablas que el contrato prohíbe (`comprobante`, `renglon_comprobante`, `stock_sala`, `stock_deposito`, `auditoria_precio`). Véase sección 7 del contrato (v0.6) y pregunta 6.20.
14. **Trigger de totales con `SECURITY DEFINER`.** [No cumple] `trg_renglon_comprobante_despues` (`005_triggers.sql`, línea 176) hace `UPDATE` sobre `comprobante`, pero `005` no tiene `SECURITY DEFINER`. `app_rw` tiene `UPDATE` sobre todas las tablas (línea 99 de `007`), así que el trigger funcionaría con privilegios de invocador, no de propietario. El contrato exige `SECURITY DEFINER` para este trigger. Pregunta 6.16.

15. **Descuento del exportador configurable vs. fijo al 30 %.** [Pendiente de validación con la cátedra] El TPI (sección 3.4 y RN-06) fija el descuento del exportador en 30 %. Sin embargo, el diseño actual en `001`/`002`/`003` lo hace configurable por exportador: `cliente_exportador.porcentaje_descuento` con `DEFAULT 30.00` y `CHECK (porcentaje_descuento BETWEEN 0 AND 100)`, y `fn_descuento_cliente` lee ese valor. Riesgo: un exportador con porcentaje distinto de 30 vulnera RN-06 tal como está escrita. Opciones: (a) mantener configurable y documentar la extensión ante la cátedra; (b) volver a 30 fijo (eliminar la columna o inmovilizarla con `CHECK (porcentaje_descuento = 30)`). Sin cambios en el SQL hasta resolverla.

16. **`SECURITY DEFINER` y `SET search_path` en procedimientos y triggers.** [No cumple] `004_procedimientos.sql` y `005_triggers.sql` no contienen `SECURITY DEFINER` ni `SET search_path = public, pg_catalog` (verificado con `grep`). Los objetos que el contrato requiere `SECURITY DEFINER` (`sp_procesar_ingreso`, `sp_procesar_transferencia`, `sp_crear_comprobante`, `trg_renglon_comprobante_antes`, `trg_renglon_comprobante_despues`, `trg_vino_auditoria`) figuran como `INVOKER`. Pregunta para Datos: ¿se agregan `SECURITY DEFINER` y `SET search_path` a estos objetos, o se ajusta el contrato al estado real?

17. **`fn_stock_deposito` faltante.** `sp_procesar_transferencia` verifica stock de depósito con `LEFT JOIN` inline (`004_procedimientos.sql` líneas 162-175), no con `fn_stock_deposito`. La función no está definida en `003`. Pregunta: ¿se agrega `fn_stock_deposito` a `003` y se usa desde `004`, o se mantiene la verificación inline?

18. **`auditoria_precio.usuario` con `DEFAULT current_user`.** `002_constraints.sql` línea 159 establece `DEFAULT current_user` en `auditoria_precio.usuario`. Con `SECURITY DEFINER` (si se agregara) esto registraría al propietario, no al rol de conexión (`app_rw`). Pregunta para Datos: ¿se cambia el DEFAULT a `session_user` o se ajusta el contrato al estado real?

19. **Vista materializada `vw_ventas_mensuales_sala`.** `006_vistas.sql` línea 78 define la vista como MATERIALIZED con índice único (línea 114) para `REFRESH MATERIALIZED VIEW CONCURRENTLY`. El contrato no define un endpoint ni un proceso para refrescarla. Pregunta: ¿quién y con qué frecuencia se refresca la vista materializada?

20. **Contraseñas por defecto en `007_roles.sql`.** Líneas 33 y 38 tienen valores por defecto literales (`cambiar_por_un_secreto_app` y `cambiar_por_un_secreto_ro`). El TPI exige que los secretos no estén en el repositorio. Pregunta: ¿se elimina el valor por defecto y el script falla si no se pasa la variable?

---

## 7. Privilegios requeridos por el rol `app_rw`

Cada función, procedimiento, vista y tabla invocada por la API debe tener el privilegio correspondiente concedido al rol `app_rw`. Esta lista alimenta directamente el archivo `db/migrations/007_roles.sql`.

**Estado real de `007_roles.sql` (verificado, 109 líneas):**
- Línea 74: `REVOKE ALL ON SCHEMA public FROM PUBLIC`
- Línea 77: `REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC`
- Línea 79: `REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC`
- Línea 98: `GRANT USAGE ON SCHEMA public TO app_rw`
- Línea 99: `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw`
- Línea 100: `GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw`
- Línea 101: `GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO app_rw`
- Línea 111: `GRANT SELECT ON ALL TABLES IN SCHEMA public TO reportes_ro`
- Línea 112: `GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO reportes_ro`
- Líneas 33 y 38: contraseñas por defecto literales (`cambiar_por_un_secreto_app`, `cambiar_por_un_secreto_ro`)

**`No cumple` en la sección 7 del contrato:** `007_roles.sql` concede escritura directa (`SELECT, INSERT, UPDATE, DELETE ON ALL TABLES`) a `app_rw` sobre tablas que el contrato prohíbe modificar directamente (`comprobante`, `renglon_comprobante`, `stock_sala`, `stock_deposito`, `auditoria_precio`). Además, `ON ALL TABLES` no cubre vistas materializadas (`vw_ventas_mensuales_sala`), por lo que falta `GRANT SELECT ON vw_ventas_mensuales_sala`. `reportes_ro` tiene `SELECT ON ALL TABLES`, incluida `auditoria_precio` (pregunta de diseño).

Principios aplicados:
- Mínimo privilegio: solo lo que un endpoint usa.
- `app_rw` **no tiene** `UPDATE` ni `DELETE` sobre tablas de stock (`stock_sala`, `stock_deposito`) ni de auditoría (`auditoria_precio`).
- `app_rw` **no tiene** `INSERT` sobre `comprobante`, `renglon_comprobante` ni `auditoria_precio`: la escritura la hacen procedimientos y triggers (que deberían ser `SECURITY DEFINER`, pero no lo son — ver pregunta 6.16).
- Funciones y procedimientos: `EXECUTE`. En la migración `007` habrá que hacer `REVOKE EXECUTE ... FROM PUBLIC` antes de conceder a `app_rw`.
- Los triggers no necesitan privilegio propio ni para `app_rw`; los que son `SECURITY DEFINER` operan con privilegios del propietario.

| Objeto | Tipo | Privilegio para `app_rw` | Motivo | Endpoint que lo usa | Estado frente a `007_roles.sql` |
|---|---|---|---|---|---|
| `fn_total_comprobante` | FUNCTION | `EXECUTE` | Verificar total | `GET /comprobantes/{nro}` | Concedido (línea 101, `EXECUTE ON ALL ROUTINES`) |
| `fn_stock_sala` | FUNCTION | `EXECUTE` | Consultar stock de sala | `GET /vinos/{cod}`, `GET /reportes/vinos-sin-stock` | Concedido (línea 101) |
| `fn_stock_deposito` | FUNCTION | `EXECUTE` | Verificar stock de depósito antes de transferir | `sp_procesar_transferencia` | No definido en `003` (pregunta 6.17) |
| `fn_descuento_cliente` | FUNCTION | `EXECUTE` | Calcular `descuento_pct` | `GET /clientes`, `GET /clientes/{id}` | Concedido (línea 101) |
| `fn_antiguedad_anios` | FUNCTION | `EXECUTE` | No expuesto aún por endpoint | — | Concedido (línea 101) |
| `sp_procesar_ingreso` | PROCEDURE | `EXECUTE` | Procesar ingreso | `POST /ingresos/{cod}/procesar` | Concedido (línea 101) |
| `sp_procesar_transferencia` | PROCEDURE | `EXECUTE` | Procesar transferencia | `POST /transferencias/{nro}/procesar` | Concedido (línea 101) |
| `sp_crear_comprobante` | PROCEDURE | `EXECUTE` | Crear venta | `POST /comprobantes` | No definido en `004` (falta) |
| `vino` | TABLE | `SELECT`, `INSERT`, `UPDATE`, `DELETE` | CRUD de vinos | `GET/POST/PUT/DELETE /vinos` | **No cumple**: `007` concede escritura directa (línea 99) |
| `vino_cepa` | TABLE | `SELECT`, `INSERT`, `DELETE` | Composición de vinos | `POST/PUT /vinos` | **No cumple**: `007` concede escritura directa (línea 99) |
| `vino_maridaje` | TABLE | `SELECT`, `INSERT`, `DELETE` | Maridajes de vinos | `POST/PUT /vinos` | **No cumple**: `007` concede escritura directa (línea 99) |
| `vino_lote` | TABLE | `SELECT` | Trazabilidad (solo lectura) | `GET /reportes/trazabilidad/{cod}` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `lote_uva` | TABLE | `SELECT` | Trazabilidad de lotes | `GET /reportes/trazabilidad/{cod}` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `parcela` | TABLE | `SELECT` | Trazabilidad de parcelas | `GET /reportes/trazabilidad/{cod}` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `finca` | TABLE | `SELECT` | Trazabilidad de fincas | `GET /reportes/trazabilidad/{cod}` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `departamento` | TABLE | `SELECT` | Trazabilidad de departamentos | `GET /reportes/trazabilidad/{cod}` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `analisis_calidad` | TABLE | `SELECT` | Análisis de calidad de lotes | `GET /reportes/trazabilidad/{cod}` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `bodega` | TABLE | `SELECT` | Catálogo de bodegas | `GET /vinos`, `GET /bodegas` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `cepa` | TABLE | `SELECT` | Catálogo de cepas | `GET /vinos`, `GET /cepas` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `maridaje` | TABLE | `SELECT` | Catálogo de maridajes | `GET /vinos`, `GET /maridajes` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `cliente` | TABLE | `SELECT`, `INSERT`, `UPDATE`, `DELETE` | CRUD de clientes | `GET/POST/PUT/DELETE /clientes` | Concedido (línea 99) |
| `cliente_distribuidor` | TABLE | `SELECT`, `INSERT`, `UPDATE`, `DELETE` | Subtipo distribuidor | `POST/PUT /clientes` | Concedido (línea 99) |
| `cliente_exportador` | TABLE | `SELECT`, `INSERT`, `UPDATE`, `DELETE` | Subtipo exportador | `POST/PUT /clientes` | Concedido (línea 99) |
| `permiso_exportacion` | TABLE | `SELECT`, `INSERT`, `DELETE` | Permisos de exportador | `POST/PUT /clientes` | **No cumple**: `007` concede `UPDATE` (línea 99) |
| `comprobante` | TABLE | `SELECT` | Lectura de ventas (INSERT lo haría `sp_crear_comprobante` si existiera) | `GET /comprobantes/{nro}` | **No cumple**: `007` concede `INSERT, UPDATE, DELETE` (línea 99) |
| `renglon_comprobante` | TABLE | `SELECT` | Lectura de renglones de venta | `GET /comprobantes/{nro}` | **No cumple**: `007` concede `INSERT, UPDATE, DELETE` (línea 99) |
| `sala_venta` | TABLE | `SELECT` | Catálogo de salas | `GET /vinos`, `GET /salas` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `transferencia` | TABLE | `SELECT`, `INSERT`, `UPDATE` | CRUD de transferencias | `GET/POST /transferencias`, `POST /terminar`, `POST /procesar` | Concedido (línea 99) |
| `renglon_transferencia` | TABLE | `SELECT`, `INSERT` | Renglones de transferencia | `POST /transferencias/{nro}/renglones` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `ingreso` | TABLE | `SELECT`, `INSERT`, `UPDATE` | CRUD de ingresos | `GET/POST /ingresos`, `POST /terminar`, `POST /procesar` | Concedido (línea 99) |
| `renglon_ingreso` | TABLE | `SELECT`, `INSERT` | Renglones de ingreso | `POST /ingresos/{cod}/renglones` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `stock_sala` | TABLE | `SELECT` | Consulta de stock de sala | `GET /vinos/{cod}`, `GET /reportes/vinos-sin-stock` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `stock_deposito` | TABLE | `SELECT` | Consulta de stock de depósito | `GET /vinos/{cod}`, `sp_procesar_transferencia` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `auditoria_precio` | TABLE | `SELECT` | Lectura de auditoría | — | **No cumple**: `007` concede `INSERT, UPDATE, DELETE` (línea 99) |
| `localidad` | TABLE | `SELECT` | Catálogo de localidades | `GET /localidades` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `transportista` | TABLE | `SELECT` | Catálogo de transportistas | `GET /transportistas` | **No cumple**: `007` concede `UPDATE, DELETE` (línea 99) |
| `vw_stock_total_vino` | VIEW | `SELECT` | Stock total por vino | `GET /vinos/{cod}` | No definido en `006` como tal (es `vw_stock_total_vino`) |
| `vw_ventas_mensuales_sala` | VIEW (materializada) | `SELECT` | Ventas por sala | `GET /reportes/ventas-por-sala` | **No cumple**: `ON ALL TABLES` no cubre vistas materializadas; falta `GRANT SELECT ON vw_ventas_mensuales_sala` |
| `vw_documentos_pendientes` | VIEW | `SELECT` | Documentos pendientes | `GET /transferencias`, `GET /ingresos/{cod}` | Concedido (línea 99, `ON ALL TABLES` cubre vistas normales) |

**Correcciones pendientes para Datos (sin aplicar al SQL):**
1. `REVOKE INSERT, UPDATE, DELETE` de `comprobante`, `renglon_comprobante`, `stock_sala`, `stock_deposito`, `auditoria_precio` a `app_rw`.
2. `GRANT SELECT ON vw_ventas_mensuales_sala TO app_rw` (y a `reportes_ro`), porque `ON ALL TABLES` no cubre vistas materializadas.
3. Revisar que `reportes_ro` no deba tener `SELECT` sobre `auditoria_precio` (pregunta de diseño).

**Nota:** los triggers no necesitan privilegio propio. Las vistas de `006_vistas.sql` están escritas (no vacías).