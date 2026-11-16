# Comparativa de rendimiento antes y después de índices (Issue #98)

Mediciones ejecutadas sobre `bodegas_atuel_bench` (PostgreSQL 16, 3 corridas por consulta para estabilizar caché en `shared_buffers`) tras aplicar los cinco índices definidos en `db/migrations/008_indices.sql` (Issue #97). Los planes completos post-índices se encuentran en `docs/planes_post_indices.txt`.

## Tabla comparativa (Antes vs. Después)

| Consulta | Descripción | Tipo de recorrido (Antes) | Tipo de recorrido (Después) | Filas leídas (Antes) | Filas leídas (Después) | Tiempo (Antes) | Tiempo (Después) | Mejora |
| :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: |
| **S4** | Transferencias pendientes por sala (`estado <> 'procesado'`, `id_sala = 1`) | `Seq Scan on transferencia` | `Index Scan` (`idx_transferencia_pendiente_sala`) | Toda la tabla | **0** (índice parcial) | 0,31 ms | **0,10 ms** | **3,1×** |
| **S8** | Ventas por sala en el último trimestre (`GROUP BY id_sala`) | `Seq Scan on comprobante` | `Index Only Scan` (`idx_comprobante_fecha_inc`) | 180.000 | **4.574** (-97,5 %) | 127,40 ms | **10,02 ms** | **12,7×** |
| **S3 / S11** | Ventas acumuladas de una sala (`id_sala = 1`) en el último trimestre | `Parallel Seq Scan on comprobante` | `Index Only Scan` (`idx_comprobante_fecha_inc`) | 170.000 | **4.574** (-97,3 %) | 277,04 ms | **1,02 ms** | **271,6×** |
| **S1** *(control)* | Top 10 vinos más vendidos (agregación total sin `WHERE`) | `Parallel Seq Scan on renglon_comprobante` | `Parallel Seq Scan on renglon_comprobante` | 680.061 | 680.061 | 261,10 ms | 296,29 ms | Sin cambio |

## Observaciones técnicas

- **Eliminación de lecturas al heap (`Index Only Scan`):** Tanto **S8** como **S3/S11** resolvieron el filtro temporal y la suma de `total` por sala directamente sobre las columnas incluidas (`INCLUDE (id_sala, total)`) de `idx_comprobante_fecha_inc`, con `Heap Fetches: 0` y bajando de ~2.840 bloques leídos a apenas 29 bloques en caché.
- **Efectividad del índice parcial:** En **S4**, `idx_transferencia_pendiente_sala` (`WHERE estado <> 'procesado'`) redujo el espacio de búsqueda exclusivamente a las transferencias activas, evitando recorrer el historial ya procesado.
- **Criterio del optimizador en agregaciones globales (S1):** En **S1**, al no existir filtro `WHERE` y requerirse el 100 % de las 680.061 filas de `renglon_comprobante`, el planificador opta por `Parallel Seq Scan` con agregación parcial en paralelo en lugar de recorrer el índice `idx_renglon_comprobante_cod_vino`.
