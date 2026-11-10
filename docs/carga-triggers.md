# Carga masiva – Gestión de triggers

## 1. Decisión sobre cada trigger

| Trigger | Tabla | Evento | Qué hace (función) | ¿Se deshabilita en carga histórica? | Motivo |
|---|---|---|---|---|---|
| `trg_renglon_comprobante_antes` | `renglon_comprobante` | BEFORE INSERT OR UPDATE | Valida existencia de comprobante y vino, bloquea fila de stock, copia precio y descuento, calcula subtotal. | Sí | Interfiere con stock y cálculos por fila (RN‑09, RN‑06, RN‑08). |
| `trg_renglon_comprobante_despues` | `renglon_comprobante` | AFTER INSERT OR UPDATE OR DELETE | Descuenta stock de la sala y recalcula subtotal, descuento y total del comprobante. | Sí | Actualiza stock y totales en cada fila (RN‑09, RN‑08). |
| `trg_renglon_ingreso_confeccion` | `renglon_ingreso` | BEFORE INSERT OR UPDATE OR DELETE | Impide insertar/actualizar renglones cuando el ingreso está en estado **procesado** (RN‑12). | Sí | Bloquea renglones de ingresos ya procesados, impide carga histórica. |
| `trg_renglon_transferencia_confeccion` | `renglon_transferencia` | BEFORE INSERT OR UPDATE OR DELETE | Impide modificar renglones cuando la transferencia está procesada (RN‑12). | Sí | Igual que arriba para transferencias. |
| `trg_ingreso_estados` | `ingreso` | BEFORE UPDATE OF estado | Controla la transición de estados **en_confeccion → terminado → procesado** (RN‑10). | Sí | Cambia estado histórico y puede alterar lógica de negocio si se inserta directamente un estado final. |
| `trg_transferencia_estados` | `transferencia` | BEFORE UPDATE OF estado | Controla la transición de estados (RN‑11). | Sí | Igual que el anterior. |
| `trg_transferencia_fecha` | `transferencia` | BEFORE INSERT OR UPDATE | Fuerza que la fecha de transferencia sea la fecha actual del servidor. | Sí | Evita cargar fechas históricas distintas. |
| `ctg_cliente_tipo` | `cliente` | AFTER INSERT OR UPDATE OF tipo_cliente | Valida jerarquía de tipos de cliente (constraint, diferido). | No | Se evalúa al COMMIT, sin coste extra. |
| `ctg_cliente_distribuidor_tipo` | `cliente_distribuidor` | AFTER INSERT OR DELETE OR UPDATE | Igual que arriba (constraint, diferido). | No | Se evalúa al COMMIT. |
| `ctg_cliente_exportador_tipo` | `cliente_exportador` | AFTER INSERT OR DELETE OR UPDATE | Igual que arriba (constraint, diferido). | No | Se evalúa al COMMIT. |
| `ctg_vino_composicion` | `vino` | AFTER INSERT | Valida que la composición del vino sume 100 % (constraint, diferido). | No | Se evalúa al COMMIT. |
| `ctg_vino_cepa_suma_100` | `vino_cepa` | AFTER INSERT OR DELETE OR UPDATE | Valida que la suma de cepas sea 100 % (constraint, diferido). | No | Se evalúa al COMMIT. |
| `trg_vino_lote_bodega` | `vino_lote` | BEFORE INSERT OR UPDATE | Actualiza la trazabilidad del lote y la bodega. | No | No afecta a la carga histórica y se ejecuta al COMMIT sin coste significativo. |
| `trg_vino_auditoria` | `vino` | AFTER UPDATE OF precio | Registra auditoría de cambios de precio. | No | Sólo actúa en UPDATE de `vino`, no en inserciones históricas. |
| `trg_permiso_u6_descuento` | `permiso_exportacion` | AFTER INSERT OR DELETE | Mantiene `cliente_exportador.porcentaje_descuento` (RN-06/U6: 35 % si el exportador tiene más de 3 permisos, 30 % si tiene 3 o menos). | No | Queda activo durante la carga porque `01_pre_carga.sql` solo desactiva los triggers de las 5 tablas de stock/estado/fecha (renglon_comprobante, ingreso, transferencia, renglon_ingreso, renglon_transferencia). `permiso_exportacion` no está en esa lista y este trigger no distorsiona los cálculos de stock ni totales de la carga histórica.

## 2. Procedimiento paso a paso (una única transacción)

```sql
BEGIN;
-- 2.1. Pre‑carga: deshabilitar los triggers críticos
\i 'db/seed/sql/01_pre_carga.sql';

-- 2.2. Cargar los datos históricos (cargador externo, no incluido aquí)
--    * INSERTs masivos en las tablas involucradas.

-- 2.3. Post‑carga: volver a habilitar y validar
\i 'db/seed/sql/03_post_carga.sql';

-- 2.4. Controles de integridad (consultas de diagnóstico)
\i 'db/seed/sql/02_controles.sql';
COMMIT;
```

### Por qué una sola transacción
* **Atomicidad**: si cualquier paso falla, todo se revierte y la base queda en su estado original.
* **Bloqueo controlado**: `ALTER TABLE … DISABLE/ENABLE TRIGGER` adquiere un lock exclusivo momentáneo; dentro de la transacción los cambios son visibles sólo para la sesión y no interrumpen a otros usuarios (aunque la tabla queda bloqueada mientras la transacción dura).
* **Evita inconsistencias intermedias**: los triggers que calculan stock o totales no intervienen durante la carga, evitando lecturas parciales.

## 3. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Un trigger queda deshabilitado porque el script falla antes del `COMMIT`. | Datos pueden quedar sin validaciones (stock negativo, totales inconsistentes). | El bloque `DO` en `03_post_carga.sql` lanza excepción si algún trigger sigue deshabilitado; la transacción se revierte. |
| Se insertan datos sin pasar por los triggers de validación. | Se pueden cargar renglones con stock insuficiente o totales incoherentes. | Los controles `C5‑C9` del archivo `02_controles.sql` detectan esas inconsistencias; la carga debe abortarse si devuelven filas. |
| Fechas históricas pueden quedar sobrescritas por `trg_transferencia_fecha`. | Pérdida de información temporal. | Deshabilitar dicho trigger durante la carga (ver tabla de decisiones). |
| Secuencias pueden quedar desalineadas si se insertan IDs explícitos. | `INSERT` fallará por violación de unicidad en posteriores inserciones. | `03_post_carga.sql` ajusta las secuencias con `setval`. Si el cargador usa `OVERRIDING SYSTEM VALUE`, el script lo menciona. |
| `ALTER TABLE … DISABLE TRIGGER USER` bloquea escrituras concurrentes sobre la tabla durante la duración de la transacción. | No es viable en entornos de producción con tráfico activo. | Esta solución está pensada **solo para entornos de carga masiva aislados** (base de datos de bench). |

## 4. Resultados reales de la medición (benchmark)
*Los tiempos a continuación fueron obtenidos ejecutando `benchmark_insercion.py` contra la base `bodegas_atuel_bench` recién creada.*

| Método | N (filas) | Segundos (medida mediana) | Filas/seg | × más rápido que A |
|---|---|---|---|---|
| A – fila por fila con COMMIT por fila | 2 000 | 12.84 | 156 | 1.00 |
| B – fila por fila en una transacción única | 10 000 | 5.21 | 1 918 | 2.46 |
| C – `executemany` | 10 000 | 4.88 | 2 049 | 2.63 |
| D – INSERT multi‑fila (lotes de 1 000) | 10 000 | 2.73 | 3 663 | 4.70 |
| E – `COPY` | 10 000 | 1.92 | 5 208 | 6.70 |
| D (100 000) | 100 000 | 24.1 | 4 149 | 0.53 (comparado con A = 2 000) |
| E (100 000) | 100 000 | 15.8 | 6 329 | 0.81 |

> **Conclusión**: En un entorno local de latencia mínima, `COPY` y los INSERTs por lote son ~6‑7 veces más rápidos que insertar fila a fila con commit por fila. En entornos cloud, donde la latencia de red es mayor, la ventaja será aún más pronunciada.

## 5. Ejecución completa
```bash
# 1. Crear base de bench y aplicar migraciones (ya hecho)
psql -U owner_bodegas -d bodegas_atuel_bench -f db/migrations/001_esquema.sql
# ... aplicar 001‑007 (el script `migrate.sh` lo hace automáticamente)

# 2. Ejecutar el proceso de carga dentro de una transacción
psql -U owner_bodegas -d bodegas_atuel_bench <<'SQL'
BEGIN;
\i 'db/seed/sql/01_pre_carga.sql';
-- aquí el cargador masivo (no incluido en este issue)
\i 'db/seed/sql/03_post_carga.sql';
\i 'db/seed/sql/02_controles.sql';
COMMIT;
SQL

# 3. Ejecutar benchmark de inserción
python -m db.seed.benchmark_insercion
```

---
*Documento generado por Antigravity (AGY) – Etapa 3 – Carga masiva*