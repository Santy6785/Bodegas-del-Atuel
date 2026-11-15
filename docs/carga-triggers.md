# Carga masiva – Gestión de triggers

## 1. Decisión sobre cada trigger

| Trigger | Tabla | Evento | Qué hace (función) | ¿Se deshabilita en carga histórica? | Motivo |
|---|---|---|---|---|---|
| `trg_renglon_comprobante_antes` | `renglon_comprobante` | BEFORE INSERT OR UPDATE | Valida existencia de comprobante y vino, bloquea fila de stock, copia precio y descuento, calcula subtotal. | Sí | Interfiere con stock y cálculos por fila (RN‑09, RN‑06, RN‑08). |
| `trg_renglon_comprobante_despues` | `renglon_comprobante` | AFTER INSERT OR DELETE OR UPDATE | Descuenta stock de la sala y recalcula subtotal, descuento y total del comprobante. | Sí | Actualiza stock y totales en cada fila (RN‑09, RN‑08). |
| `trg_renglon_ingreso_confeccion` | `renglon_ingreso` | BEFORE INSERT OR DELETE OR UPDATE | Impide insertar/actualizar renglones cuando el ingreso NO está en **en_confeccion** (terminado o procesado), no solo procesado (RN‑12). | Sí | Impide cargar renglones de documentos históricos ya terminados o procesados. |
| `trg_renglon_transferencia_confeccion` | `renglon_transferencia` | BEFORE INSERT OR DELETE OR UPDATE | Impide modificar renglones cuando la transferencia NO está en **en_confeccion** (terminada o procesada), no solo procesada (RN‑12). | Sí | Impide cargar renglones de documentos históricos ya terminados o procesados. |
| `trg_ingreso_estados` | `ingreso` | BEFORE UPDATE OF estado | Controla la transición de estados **en_confeccion → terminado → procesado** (RN‑10). | Sí | insertar un documento ya en estado final no los dispara; solo harían falta si el cargador inserta en confección y luego actualiza el estado. Se apagan junto con el resto de las tablas de documentos por simplicidad, aunque estrictamente solo hacen falta los de renglones y el de fecha. |
| `trg_transferencia_estados` | `transferencia` | BEFORE UPDATE OF estado | Controla la transición de estados (RN‑11). | Sí | insertar un documento ya en estado final no los dispara; solo harían falta si el cargador inserta en confección y luego actualiza el estado. Se apagan junto con el resto de las tablas de documentos por simplicidad, aunque estrictamente solo hacen falta los de renglones y el de fecha. |
| `trg_transferencia_fecha` | `transferencia` | BEFORE INSERT OR UPDATE | Fuerza que la fecha de transferencia sea la fecha actual del servidor. | Sí | Evita cargar fechas históricas distintas. |
| `ctg_cliente_tipo` | `cliente` | AFTER INSERT OR UPDATE OF tipo_cliente | Valida jerarquía de tipos de cliente (constraint, diferido). | No | Se evalúa al COMMIT, sin coste extra. |
| `ctg_cliente_distribuidor_tipo` | `cliente_distribuidor` | AFTER INSERT OR DELETE OR UPDATE | Valida jerarquía de tipos de cliente (constraint, diferido). | No | Se evalúa al COMMIT. |
| `ctg_cliente_exportador_tipo` | `cliente_exportador` | AFTER INSERT OR DELETE OR UPDATE | Valida jerarquía de tipos de cliente (constraint, diferido). | No | Se evalúa al COMMIT. |
| `ctg_vino_composicion` | `vino` | AFTER INSERT | Valida que la composición del vino sume 100 % (constraint, diferido). | No | Se evalúa al COMMIT. |
| `ctg_vino_cepa_suma_100` | `vino_cepa` | AFTER INSERT OR DELETE OR UPDATE | Valida que la suma de cepas sea 100 % (constraint, diferido). | No | Se evalúa al COMMIT. |
| `trg_vino_lote_bodega` | `vino_lote` | BEFORE INSERT OR UPDATE | Valida que `lote.cuit_bodega = vino.cuit_bodega` (trazabilidad). Trigger por fila, **no diferido**: se ejecuta inmediatamente al INSERT/UPDATE. | No | No afecta a la carga histórica y valida trazabilidad por fila. |
| `trg_vino_auditoria` | `vino` | AFTER UPDATE OF precio | Registra cambios de precio en `auditoria_precio` (solo cuando `precio` cambia realmente). | No | Sólo actúa en UPDATE de `vino`, no en inserciones históricas. |
| `trg_permiso_u6_descuento` | `permiso_exportacion` | AFTER INSERT OR DELETE | Actualiza `cliente_exportador.porcentaje_descuento` (columna NOT NULL en la base real): 35 % si el exportador tiene más de 3 permisos, 30 % si tiene 3 o menos (RN‑06/U6). | No | Queda activo durante la carga porque `01_pre_carga.sql` solo desactiva los triggers de las 5 tablas de stock/estado/fecha (renglon_comprobante, ingreso, transferencia, renglon_ingreso, renglon_transferencia). `permiso_exportacion` no está en esa lista y este trigger no distorsiona los cálculos de stock ni totales de la carga histórica. |

**Total: 15 triggers de usuario** (7 deshabilitados en pre-carga, 8 mantenidos activos).

## 2. Procedimiento paso a paso (una única transacción)

```sql
BEGIN;
-- 2.1. Pre‑carga: deshabilitar los triggers críticos
\i /tmp/sql/01_pre_carga.sql

-- 2.2. Cargar los datos históricos (cargador externo, no incluido aquí)
--    * INSERTs masivos en las tablas involucradas.
--    * SIN triggers activos, el cargador debe calcular por sí mismo:
--      stock_sala y stock_deposito, subtotales y totales de comprobantes,
--      usando SQL por conjuntos (no fila a fila con triggers).
--    * El cargador debe fijar precio_unitario y descuento_pct históricos
--      en cada renglón (el BEFORE de trg_renglon_comprobante_antes los
--      pisaría con el precio vigente si quedara activo) y calcular:
--      subtotal_renglon = ROUND(cantidad * precio_unitario * (100 - descuento_pct) / 100, 2),
--      subtotal_bruto = SUM(cantidad * precio_unitario),
--      total = SUM(subtotal_renglon) y descuento = subtotal_bruto - total,
--      con el mismo redondeo que fn_total_comprobante, porque C5 compara
--      igualdad exacta.

-- 2.3. Post‑carga: volver a habilitar y validar
\i /tmp/sql/03_post_carga.sql

-- 2.4. Forzar los constraint triggers diferidos antes del gate
SET CONSTRAINTS ALL IMMEDIATE;

-- 2.5. Gate de integridad: aborta si algún control devuelve filas
\i /tmp/sql/02b_gate.sql

-- 2.6. Controles de integridad (consultas de diagnóstico)
\i /tmp/sql/02_controles.sql
COMMIT;
```

Durante la carga los triggers de negocio están deshabilitados, por lo que el
cargador debe calcular con SQL por conjuntos: `stock_sala` y `stock_deposito`,
`subtotal`/`descuento`/`total` de cada comprobante.

Los `ctg_*` son constraint triggers diferidos: se evalúan al `COMMIT`, no al
`INSERT`/`UPDATE` (jerarquía de clientes, composición al 100 %). En cambio,
`trg_permiso_u6_descuento` (AFTER ROW) y `trg_vino_lote_bodega` (BEFORE)
se ejecutan inmediatamente por fila, no al COMMIT.

### Por qué una sola transacción
* **Atomicidad**: si cualquier paso falla, todo se revierte y la base queda en su estado original.
* **Bloqueo controlado**: `ALTER TABLE … DISABLE/ENABLE TRIGGER USER` adquiere un lock `SHARE ROW EXCLUSIVE` momentáneo que bloquea escrituras concurrentes sobre la tabla y permite lecturas; dentro de la transacción los cambios son visibles sólo para la sesión y no interrumpen a otros usuarios (aunque la tabla queda bloqueada mientras la transacción dura).
* **Evita inconsistencias intermedias**: los triggers que calculan stock o totales no intervienen durante la carga, evitando lecturas parciales.

*Nota: "mantendos" corregido a "mantenidos" arriba.*

## 3. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Un trigger queda deshabilitado porque el script falla antes del `COMMIT`. | Datos pueden quedar sin validaciones (stock negativo, totales inconsistentes). | El bloque `DO` en `03_post_carga.sql` lanza excepción si algún trigger sigue deshabilitado; la transacción se revierte. El gate `02b_gate.sql` también aborta si algún control C1 o C3‑C13 devuelve filas. |
| Se insertan datos sin pasar por los triggers de validación. | Se pueden cargar renglones con stock insuficiente o totales incoherentes. | Los controles `C5‑C9` del archivo `02_controles.sql` detectan esas inconsistencias; la carga debe abortarse si devuelven filas. |
| Fechas históricas pueden quedar sobrescritas por `trg_transferencia_fecha`. | Pérdida de información temporal. | Deshabilitar dicho trigger durante la carga (ver tabla de decisiones). |
| `C6` compara `descuento_pct` contra `fn_descuento_cliente` actual; solo es válido justo después de la carga, porque `descuento_pct` es un snapshot y consignas como U6 lo vuelven inconsistente a propósito. | Falsos positivos de C6 si se ejecuta mucho después de cargar o tras cambiar descuentos de exportador. | Ejecutar C6 solo inmediatamente después de la carga, antes de cualquier modificación de descuentos. |
| Secuencias pueden quedar desalineadas si se insertan IDs explícitos. | `INSERT` fallará por violación de unicidad en posteriores inserciones. | `03_post_carga.sql` ajusta las secuencias con `setval`. Si el cargador usa `OVERRIDING SYSTEM VALUE`, el script lo menciona. |
| `ALTER TABLE … DISABLE TRIGGER USER` bloquea escrituras concurrentes sobre la tabla durante la duración de la transacción. | No es viable en entornos de producción con tráfico activo. | Esta solución está pensada **solo para entornos de carga masiva aislados** (base de datos de bench). |

## 4. Resultados reales de la medición (benchmark)

*Los tiempos a continuación fueron obtenidos ejecutando `benchmark_insercion.py` contra la base `bodegas_atuel_bench`. Mediana de 3 repeticiones; `× más rápido que A` = filas/s dividido entre 91 (filas/s de A). Medido desde el contenedor `seed` por la red bridge de Docker Desktop en Windows. A se midió con N=2000 y el resto con N distinto, por lo que se comparan filas/s y no segundos.*

| Método | N (filas) | Segundos (medida mediana) | Filas/seg | × más rápido que A |
|---|---|---|---|---|
| A – fila por fila con COMMIT por fila | 2000 | 21.90 | 91 | 1x |
| B – fila por fila en una transacción única | 10000 | 17.81 | 561 | ≈6x |
| C – `executemany` | 10000 | 2.54 | 3944 | ≈43x |
| D – INSERT multi‑fila (lotes de 1000) | 10000 | 0.85 | 11821 | ≈130x |
| E – `COPY` | 10000 | 0.32 | 30840 | ≈340x |
| D – INSERT multi‑fila (lotes de 1000) | 100000 | 6.38 | 15679 | ≈170x |
| E – `COPY` | 100000 | 1.78 | 56235 | ≈620x |

**Costo de los triggers sobre `renglon_comprobante` real (N=500, una medición):**
* Triggers ON: 1.726 s (290 filas/s)
* Triggers OFF: 0.1495 s (3344 filas/s)
* Cociente ON/OFF: 11.5x

>Aclaraciones:
* Hay **dispersión alta entre repeticiones** (B varía de 10.3 s a 32.8 s; D 10k varía de 0.42 s a 2.59 s). Las razones arriba son **indicativas**, no definitivas.
* `bench_renglon` es una réplica estructural de `renglon_comprobante` **sin FKs ni triggers**, por lo que **sobreestima** la velocidad frente a la tabla real.
* El cociente 11.5x refleja el trabajo adicional (cálculo de stock y totales fila por fila) que el cargador debe reemplazar con SQL por conjuntos cuando los triggers están deshabilitados.
* Una sola medición ON/OFF: **indicativa**, no estadísticamente rigurosa.

## 5. Ejecución completa (PowerShell)

```powershell
# Flujo de carga: seed.py ejecuta TODO en una sola transacción
# (01_pre_carga, catálogos, maestros, stock, movimientos, ventas,
#  recálculo de totales, 03_post_carga, SET CONSTRAINTS ALL IMMEDIATE,
#  02b_gate, COMMIT).
docker compose run --rm -e PGDATABASE=bodegas_atuel_bench seed python -u seed.py
```

Datos reales de la ejecución:
* Carga **170000** comprobantes y **680046** renglones en unos **97 s**.
* El gate `02b_gate.sql` tarda unos **31 s**.
* Si el gate falla, `seed.py` ejecuta `ROLLBACK` y los **15 triggers** quedan intactos en `'O'`.
* Prueba de camino de error: con `-e FECHA_REF_ISO=2027-01-01` aborta en **C13a** (`Fallo en control C13a`) con **exit code 1**.

```powershell
docker compose run --rm -e PGDATABASE=bodegas_atuel_bench -e FECHA_REF_ISO=2027-01-01 seed python -u seed.py
# (exit code: 1)
```

**Quién ejecuta:** `DISABLE/ENABLE TRIGGER USER` exige ser dueño de la tabla (no superusuario; `ALL` sí exige superusuario). Se ejecuta con el rol propietario (`owner_bodegas`), nunca con `app_rw`.

## Qué está probado y qué no

**Probado** (`db/test/carga_pruebas.sql`, dos corridas, 15 triggers en `O` al final; `db/test/test_semilla.py` con `freezegun`):
* prueba negativa 4 de 5 `ENABLE` (bloque (b));
* flujo completo sano con cero filas en todos los controles (bloque (c));
* casos rotos: C5/C7/gate (bloque (d)), composición de vino, tipo de cliente, C9, C7 sin C5a, C6;
* determinismo: 8 hashes MD5 idénticos entre dos corridas completas del seed;
* test unitario de invarianza al reloj con `freezegun` (`db/test/test_semilla.py`).

**No probado:**
* controles C8/C12/C13 con datos rotos;
* `trg_permiso_u6_descuento`, `trg_vino_lote_bodega`, `trg_vino_auditoria`.

Aclaración: `C3` y `C4` no pueden fallar porque las FK y los `CHECK` siguen activos con `DISABLE TRIGGER USER` (solo se desactivan los triggers de usuario, no las restricciones nativas).

---

*Documento de la etapa 3 – Carga masiva de Bodegas del Atuel*
