# Baseline de Planes de Ejecución (`EXPLAIN (ANALYZE, BUFFERS)`) — Issue #96

Medición previa a la creación de índices personalizados (`db/migrations/008_indices.sql` vacío) sobre la base `bodegas_atuel_bench`.
Salida cruda completa en [`docs/planes_baseline.txt`](planes_baseline.txt).

## Resumen comparativo (sin índices secundarios)

| Consulta | Caso de uso | Plan principal | Buffers (mediana) | Corrida 1 (ms) | Corrida 2 (ms) | Corrida 3 (ms) | Mediana (ms) |
| :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: |
| **S1** | Top 10 vinos más vendidos | `Parallel Seq Scan on renglon_comprobante` + `Hash Join` + `Sort` | `hit=394 read=5183` | 745,200 | 261,277 | 208,451 | **261,28** |
| **S4** | Transferencias recientes por estado/fecha | `Seq Scan on transferencia` | `hit=4 read=0` | 1,153 | 1,593 | 0,280 | **1,15** |
| **S8** | Ventas por sala (último trimestre) | `Seq Scan on comprobante` + `Hash Left Join` | `hit=2840 read=0` | 336,910 | 37,877 | 36,938 | **37,88** |
| **S10** | Rendimiento kg/ha por parcela y campaña | `Seq Scan` en `lote_uva`, `parcela`, `finca`, `cepa` | `hit=4 read=0` | 1,315 | 0,369 | 0,474 | **0,47** |

## Conclusiones para `008_indices.sql`

1. **Prioridad alta (S8 y S1):** `comprobante` lee 2.840 bloques completos para filtrar 4.574 filas del último trimestre (`37,88 ms`) y `renglon_comprobante` barre 680.060 filas con lecturas a disco (`261,28 ms`). Justifican índices covering (`comprobante(fecha) INCLUDE (id_sala, total)` y `renglon_comprobante(cod_vino) INCLUDE (cantidad)`).
2. **Prioridad media (S4):** hoy ocupa 4 páginas (`1,15 ms`), pero conviene un índice compuesto `transferencia(estado, fecha_confeccion)` por el crecimiento histórico futuro.
3. **Descartado (S10):** tablas maestras de 1 a 2 páginas (`0,47 ms`) donde PostgreSQL siempre preferirá `Seq Scan`.
