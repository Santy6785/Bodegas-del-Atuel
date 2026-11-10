# Informe de revisión y alineación: api-contrato.md vs. base de datos (v7)

**Proyecto:** Bodegas del Atuel (TPI Bases de Datos, UTN FRSR)  
**Fecha:** 2026-11-07  
**Revisor:** revisor técnico  
**Documento revisado:** `docs/api-contrato.md` (v0.6.1 → v0.6.2)

**Cambios en v7:**
- Corregido el desglose de triggers en el changelog del contrato (9 `CREATE TRIGGER` + 5 `CREATE CONSTRAINT TRIGGER` = 14).
- Agregadas a la sección 7 las líneas de `ALTER DEFAULT PRIVILEGES` (122, 125, 128, 131, 134), que estaban verificadas pero no tabuladas.
- Corregido el encabezado de la sección 2.

---

## 1. Resumen de hallazgos

- `001_esquema.sql` (360 líneas) y `002_constraints.sql` (327 líneas) están escritas (commit `21aa8c0`).
- `003_funciones.sql` (168 líneas) está escrita y define **4 funciones** (no 5): `fn_descuento_cliente`, `fn_total_comprobante`, `fn_stock_sala`, `fn_antiguedad_anios`. Todas `STABLE`, `LANGUAGE sql`.
- `004_procedimientos.sql` (200 líneas) está escrita y define **2 procedimientos**: `sp_procesar_ingreso` (línea 48) y `sp_procesar_transferencia` (línea 120). No tiene `SECURITY DEFINER`. No tiene `sp_crear_comprobante`.
- `005_triggers.sql` (518 líneas) está escrita y define 14 triggers/constraint triggers. No tiene `SECURITY DEFINER`. Los nombres difieren de los del contrato (ver tabla de mapeo en sección 1.3).
- `006_vistas.sql` (171 líneas) está escrita y define 3 vistas: `vw_stock_total_vino` (línea 35), `vw_ventas_mensuales_sala` materializada (línea 78), `vw_documentos_pendientes` (línea 135).
- `007_roles.sql` (109 líneas) está escrita. Concede `SELECT, INSERT, UPDATE, DELETE ON ALL TABLES` a `app_rw` (línea 99), lo que incluye escritura directa sobre tablas que el contrato prohíbe. Tiene contraseñas por defecto literales (líneas 33, 38).
- `008_indices.sql` (0 líneas) está vacía y en desarrollo.
- Se encontraron **3 discrepancias de firma** en `003`, **1 función faltante** (`fn_stock_deposito`), **1 procedimiento faltante** (`sp_crear_comprobante`), y **todos los objetos que el contrato exige `SECURITY DEFINER` figuran como `INVOKER`** en `004` y `005`.
- Riesgo de negocio: `cliente_exportador.porcentaje_descuento` es configurable (default 30, rango 0-100) pero el TPI (RN-06) fija 30 %.

---

## 2. Estado de migraciones verificado

Se cita la tabla de estado verificada por el responsable del proyecto:

| Archivo | Líneas | Último commit | Estado |
|---|---|---|---|
| `db/migrations/001_esquema.sql` | 360 | `21aa8c0` | Escrito |
| `db/migrations/002_constraints.sql` | 327 | `21aa8c0` | Escrito. `DEFAULT 0` en `comprobante.subtotal/descuento/total`; `DEFAULT 30.00` y `CHECK 0-100` en `cliente_exportador.porcentaje_descuento`; `DEFAULT current_user` en `auditoria_precio.usuario` (línea 159) |
| `db/migrations/003_funciones.sql` | 168 | `21aa8c0` | **Escrito** (4 funciones) |
| `db/migrations/004_procedimientos.sql` | 200 | `adc3f2e` | **Escrito** (2 procedimientos, SIN `SECURITY DEFINER`) |
| `db/migrations/005_triggers.sql` | 518 | `adc3f2e` | **Escrito** (14 triggers, SIN `SECURITY DEFINER`) |
| `db/migrations/006_vistas.sql` | 171 | `adc3f2e` | **Escrito** (3 vistas, 1 materializada) |
| `db/migrations/007_roles.sql` | 109 | `adc3f2e` | **Escrito** (con `GRANT ALL TABLES` a `app_rw`, contraseñas por defecto) |
| `db/migrations/008_indices.sql` | 0 | `adc3f2e` | En desarrollo (vacío) |

Correcciones específicas:
- Se eliminó la afirmación de que `004` a `007` están vacías (todas están escritas excepto `008`).
- Se corrigió "EXECUTE en las 5 funciones de `003`" a "EXECUTE en las 4 funciones de `003`".
- Se agregó la tabla de mapeo contrato → migración para triggers (nombres reales, líneas de `CREATE TRIGGER`).
- Se marcaron como `No cumple` todos los objetos que requieren `SECURITY DEFINER` pero que `004`/`005` no lo tienen.
- Se agregó la pregunta 6.16 a 6.20.

---

## 3. Tabla de funciones de `003_funciones.sql` (reconciliación con sección 1.3 del contrato)

| Función | Parámetros (003) | Retorno (003) | Volatilidad | Línea CREATE | Resultado de comparación |
|---|---|---|---|---|---|
| `fn_descuento_cliente` | `p_id_cliente INTEGER` | `NUMERIC` | STABLE | 50 | Discrepancia: contrato decía `(p_tipo_cliente tipo_cliente) RETURNS NUMERIC(5,2)`; real es `(p_id_cliente INTEGER) RETURNS NUMERIC`. `LANGUAGE sql` (línea 52), `STRICT` (línea 54). Usa `e.porcentaje_descuento` (línea 59). |
| `fn_total_comprobante` | `p_nro INTEGER` | `NUMERIC` | STABLE | 85 | Discrepancia: contrato decía `(p_nro_comprobante INTEGER) RETURNS NUMERIC(12,2)`; real es `(p_nro INTEGER) RETURNS NUMERIC`. `LANGUAGE sql` (línea 87). |
| `fn_stock_sala` | `p_sala INTEGER`, `p_vino INTEGER` | `INTEGER` | STABLE | 113 | Coincidencia exacta. `LANGUAGE sql` (línea 115). |
| `fn_antiguedad_anios` | `p_fecha DATE` | `INTEGER` | STABLE | 142 | Discrepancia: contrato decía `(p_fecha_ingreso DATE)`; real es `(p_fecha DATE)`. `LANGUAGE sql` (línea 144), `STRICT` (línea 146). Usa `CURRENT_DATE` (correctamente STABLE). |

**Observaciones de volatilidad y reglas del TPI (Etapa 2):**
- Las 4 funciones tienen comentario de propósito, parámetros y volatilidad. Cumplen.
- Ninguna está marcada `IMMUTABLE`; todas son `STABLE`. `fn_antiguedad_anios` usa `CURRENT_DATE` y correctamente es `STABLE`. Cumplen.

---

## 4. Tabla de procedimientos de `004_procedimientos.sql` (reconciliación)

| Procedimiento | Parámetros (004) | Línea CREATE | Seguridad | Resultado |
|---|---|---|---|---|
| `sp_procesar_ingreso` | `p_cod_ingreso INTEGER` | 48 | INVOKER (no tiene `SECURITY DEFINER`) | **No cumple: contrato exige SECURITY DEFINER** (D-B) |
| `sp_procesar_transferencia` | `p_nro INTEGER` | 120 | INVOKER (no tiene `SECURITY DEFINER`) | **No cumple: contrato exige SECURITY DEFINER** (D-B). Verifica stock con `LEFT JOIN` inline (líneas 162-175), no con `fn_stock_deposito` |
| `sp_crear_comprobante` | — | — | — | **Falta en `004`** (no definido). Firma de D-A mantenida en el contrato. |

---

## 5. Tabla de triggers de `005_triggers.sql` (mapeo contrato → migración)

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

**Seguridad:** ninguno de los 14 triggers de `005` tiene `SECURITY DEFINER` ni `SET search_path` (verificado con `grep`). Todos figuran como `INVOKER`.

---

## 6. Tabla de vistas de `006_vistas.sql` (reconciliación)

| Nombre en el contrato | Nombre real en `006_vistas.sql` | Línea CREATE | Tipo | Estado |
|---|---|---|---|---|
| `vista_stock_total_por_vino` | `vw_stock_total_vino` | 35 | VIEW | Renombrado |
| `vista_ventas_mensuales_por_sala` | `vw_ventas_mensuales_sala` | 78 | MATERIALIZED VIEW | Renombrado. Índice único línea 114 para `REFRESH MATERIALIZED VIEW CONCURRENTLY`. |
| `vista_documentos_pendientes` | `vw_documentos_pendientes` | 135 | VIEW | Renombrado |

**Nota:** `vw_ventas_mensuales_sala` es materializada y requiere `REFRESH MATERIALIZED VIEW CONCURRENTLY` periódico. El contrato no define un endpoint para eso (pregunta 6.19).

---

## 7. Tabla de privilegios de `007_roles.sql` (reconciliación)

| Línea | Sentencia | Impacto |
|---|---|---|
| 74 | `REVOKE ALL ON SCHEMA public FROM PUBLIC` | Aislamiento de seguridad |
| 77 | `REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC` | Aislamiento de seguridad |
| 79 | `REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC` | Aislamiento de seguridad |
| 98 | `GRANT USAGE ON SCHEMA public TO app_rw` | Concedido |
| 99 | `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw` | **No cumple**: incluye escritura directa sobre tablas que el contrato prohíbe |
| 100 | `GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw` | Concedido |
| 101 | `GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO app_rw` | Concedido |
| 111 | `GRANT SELECT ON ALL TABLES IN SCHEMA public TO reportes_ro` | Incluye `auditoria_precio` (pregunta de diseño) |
| 112 | `GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO reportes_ro` | Concedido |
| 122 | `GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw` (ALTER DEFAULT PRIVILEGES) | **No cumple**: concede escritura directa sobre tablas futuras a `app_rw` |
| 125 | `GRANT USAGE, SELECT ON SEQUENCES TO app_rw` (ALTER DEFAULT PRIVILEGES) | Concedido |
| 128 | `GRANT EXECUTE ON ROUTINES TO app_rw` (ALTER DEFAULT PRIVILEGES) | Concedido |
| 131 | `GRANT SELECT ON TABLES TO reportes_ro` (ALTER DEFAULT PRIVILEGES) | Concedido |
| 134 | `GRANT EXECUTE ON ROUTINES TO reportes_ro` (ALTER DEFAULT PRIVILEGES) | Concedido |
| 33, 38 | Contraseñas por defecto literales | **No cumple**: TPI exige que secretos no estén en el repositorio |

---

## 8. Hallazgos para el equipo de Datos (no aplicados al SQL)

1. **`SECURITY DEFINER` faltante:** `004_procedimientos.sql` y `005_triggers.sql` no contienen `SECURITY DEFINER` ni `SET search_path = public, pg_catalog`. Los objetos que el contrato requiere `SECURITY DEFINER` (`sp_procesar_ingreso`, `sp_procesar_transferencia`, `sp_crear_comprobante`, `trg_renglon_comprobante_antes`, `trg_renglon_comprobante_despues`, `trg_vino_auditoria`) figuran como `INVOKER`. (Pregunta 6.16)
2. **`sp_crear_comprobante` faltante:** no está definido en `004_procedimientos.sql`. Firma de D-A mantenida en el contrato. (Pregunta 6.4 ya resuelta como procedimiento, pero falta la implementación)
3. **Privilegios de escritura directa en `007_roles.sql`:** línea 99 concede `INSERT, UPDATE, DELETE ON ALL TABLES` a `app_rw`, y la línea 122 hace lo mismo para tablas futuras vía `ALTER DEFAULT PRIVILEGES`, incluyendo comprobante, incluyendo `comprobante`, `renglon_comprobante`, `stock_sala`, `stock_deposito`, `auditoria_precio`. Debería ser `REVOKE` de esos privilegios. (Pregunta 6.20)
4. **Vistas materializadas sin `GRANT`:** `ON ALL TABLES` no cubre `vw_ventas_mensuales_sala` (materializada). Falta `GRANT SELECT ON vw_ventas_mensuales_sala TO app_rw` y `TO reportes_ro`. (Pregunta 6.19)
5. **`SET search_path` ausente:** ningún objeto de `004` o `005` tiene `SET search_path = public, pg_catalog`. (Pregunta 6.16)
6. **`DEFAULT current_user` en `auditoria_precio.usuario`:** `002_constraints.sql` línea 159. Con `SECURITY DEFINER` registraría al propietario. (Pregunta 6.18)
7. **Contraseñas por defecto en `007_roles.sql`:** líneas 33 y 38 tienen valores literales. (Pregunta 6.20)
8. **Mapeo de nombres:** los nombres de triggers y vistas en el contrato difieren de los reales en `005` y `006` (ver tablas de mapeo en secciones 5 y 6).

---

## 9. Decisiones que requieren validación humana (orden de prioridad)

| Prioridad | Decisión | ¿Por qué necesita validación? |
|-----------|----------|------------------------------|
| 1 | **6.15 — Descuento del exportador configurable vs. fijo al 30 %.** `cliente_exportador.porcentaje_descuento` es configurable (default 30, rango 0-100) pero RN-06 fija 30 %. Riesgo de vulnerar RN-06. | Conflicto entre diseño de base y regla del TPI. Debe resolverse ante la cátedra. |
| 2 | **6.16 — `SECURITY DEFINER` y `SET search_path`.** `004` y `005` no tienen `SECURITY DEFINER`. Afecta el modelo de privilegios de `app_rw`. | Cambio estructural en migraciones ya escritas. |
| 3 | **6.17 — `fn_stock_deposito` faltante y verificación inline.** `sp_procesar_transferencia` usa `LEFT JOIN` inline, no `fn_stock_deposito`. | ¿Se agrega la función a `003` y se usa desde `004`, o se mantiene la verificación inline? |
| 4 | **6.18 — `auditoria_precio.usuario` con `DEFAULT current_user`.** Con `SECURITY DEFINER` registraría al propietario. | ¿Se cambia el DEFAULT a `session_user` o se ajusta el contrato al estado real? |
| 5 | **6.19 — Vista materializada `vw_ventas_mensuales_sala`.** Requiere `REFRESH MATERIALIZED VIEW CONCURRENTLY` periódico sin endpoint definido. | ¿Quién y con qué frecuencia se refresca? |
| 6 | **6.20 — Contraseñas por defecto en `007_roles.sql`.** Valores literales en el repositorio. | ¿Se elimina el valor por defecto y el script falla sin la variable? |
| 7 | **6.10 — Validación del request.** ¿Unificar `22P02` en 400 o dejar 422 de FastAPI? | Afecta la traducción SQLSTATE → HTTP. |
| 8 | **6.6 — Cambio de `tipo_cliente` en `PUT /clientes/{id}`.** ¿Permitirlo o no? | Afecta integridad de la jerarquía supertipo/subtipos. |

---

## 10. Verificaciones realizadas (salida literal)

Lista de comandos ejecutados y su resultado:

| Comando | Resultado |
|---|---|
| `Select-String -Path "db/migrations/005_triggers.sql" -Pattern "CREATE TRIGGER\|CREATE CONSTRAINT TRIGGER"` | Línea 112: `CREATE TRIGGER trg_renglon_comprobante_antes`; Línea 176: `CREATE TRIGGER trg_renglon_comprobante_despues`; Línea 214: `CREATE TRIGGER trg_ingreso_estados`; Línea 219: `CREATE TRIGGER trg_transferencia_estados`; Línea 247: `CREATE TRIGGER trg_transferencia_fecha`; Línea 300: `CREATE TRIGGER trg_renglon_ingreso_confeccion`; Línea 346: `CREATE TRIGGER trg_renglon_transferencia_confeccion`; Línea 375: `CREATE TRIGGER trg_vino_auditoria`; Línea 432: `CREATE CONSTRAINT TRIGGER ctg_vino_cepa_suma_100`; Línea 438: `CREATE CONSTRAINT TRIGGER ctg_vino_composicion`; Línea 480: `CREATE TRIGGER trg_vino_lote_bodega`; Línea 545: `CREATE CONSTRAINT TRIGGER ctg_cliente_tipo`; Línea 551: `CREATE CONSTRAINT TRIGGER ctg_cliente_distribuidor_tipo`; Línea 557: `CREATE CONSTRAINT TRIGGER ctg_cliente_exportador_tipo` |
| `Select-String -Path "db/migrations/007_roles.sql" -Pattern "ALTER DEFAULT PRIVILEGES\|GRANT"` | Línea 86: `GRANT ALL PRIVILEGES ON SCHEMA public TO CURRENT_USER;`; Línea 87: `GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO CURRENT_USER;`; Línea 88: `GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO CURRENT_USER;`; Línea 89: `GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA public TO CURRENT_USER;`; Línea 98: `GRANT USAGE ON SCHEMA public TO app_rw;`; Línea 99: `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;`; Línea 100: `GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw;`; Línea 101: `GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO app_rw;`; Línea 110: `GRANT USAGE ON SCHEMA public TO reportes_ro;`; Línea 111: `GRANT SELECT ON ALL TABLES IN SCHEMA public TO reportes_ro;`; Línea 112: `GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO reportes_ro;`; Línea 116: `-- 6. Privilegios por defecto (ALTER DEFAULT PRIVILEGES)`; Línea 121: `ALTER DEFAULT PRIVILEGES IN SCHEMA public`; Línea 122: `    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;`; Línea 124: `ALTER DEFAULT PRIVILEGES IN SCHEMA public`; Línea 125: `    GRANT USAGE, SELECT ON SEQUENCES TO app_rw;`; Línea 127: `ALTER DEFAULT PRIVILEGES IN SCHEMA public`; Línea 128: `    GRANT EXECUTE ON ROUTINES TO app_rw;`; Línea 130: `ALTER DEFAULT PRIVILEGES IN SCHEMA public`; Línea 131: `    GRANT SELECT ON TABLES TO reportes_ro;`; Línea 133: `ALTER DEFAULT PRIVILEGES IN SCHEMA public`; Línea 134: `    GRANT EXECUTE ON ROUTINES TO reportes_ro;` |
| `Select-String -Path "db/migrations/006_vistas.sql" -Pattern "GRANT"` | Sin coincidencias |
| `Select-String -Path "db/migrations/004_procedimientos.sql,db/migrations/005_triggers.sql" -Pattern "SECURITY DEFINER\|search_path"` | Sin coincidencias en ninguno de los dos archivos |

---

## Archivos modificados

- `docs/api-contrato.md`: actualizado de v0.6.1 a v0.6.2 (changelog v0.6.2 agregado; conteo de triggers corregido a 9 CREATE TRIGGER + 5 CREATE CONSTRAINT TRIGGER = 14; encabezado: "001 a 007 (reconciliado); 008 vacío").
- `docs/revision_alineacion_api.md`: actualizado de v6 a v7 (sección 5 con `ctg_vino_composicion` línea 438; sección 7 con filas de ALTER DEFAULT PRIVILEGES líneas 122, 125, 128, 131, 134; sección 10 con salidas literales del Paso 0; archivos modificados con lista concreta).
