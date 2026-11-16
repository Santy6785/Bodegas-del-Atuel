# Planes de ejecución y medición de índices

## Metadatos

- Fecha UTC de ejecución: 2026-11-16T20:59:27Z
- Commit: 092eac7 (con cambios sin confirmar)
- Versión de PostgreSQL: 16.16 (Debian 16.16-1.pgdg13+1)
- Filas: comprobante=170000, renglon_comprobante=680366, cliente=20000
- Repeticiones medidas: 1 (+1 calentamiento)
- Índices medidos: idx_comprobante_sala_fecha, idx_transferencia_pendiente_sala, idx_renglon_comprobante_cod_vino, idx_cliente_apellido_lower, idx_comprobante_fecha_inc
- Nota: Medición con caché caliente; mediana de 1 ejecución(es).

## 1. Tabla comparativa

| Consulta | Recorrido antes | Filas antes | Recorrido después | Filas después | Mediana antes (ms) | Mediana después (ms) | Factor de mejora (antes/después) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CLI_apellido_lower | Seq Scan | 100 | Bitmap Heap Scan | 464 | 6.863 | 1.903 | 3.6 |
| PLAN_INTERVALO_10_YEARS | Parallel Seq Scan | 1 | Parallel Seq Scan | 1 | 31.324 | 33.727 | 0.9 |
| PLAN_INTERVALO_7_DAYS | Parallel Seq Scan | 1 | Index Only Scan using idx_comprobante_fecha_inc | 1 | 25.695 | 0.217 | 118.4 |
| S1_top_vinos_control | Parallel Seq Scan | 10 | Parallel Seq Scan | 10 | 139.601 | 134.258 | 1.0 |
| S3_sala_fecha | Parallel Seq Scan | 1 | Index Only Scan using idx_comprobante_fecha_inc | 1 | 15.218 | 0.682 | 22.3 |
| S4_transferencias_pendientes | Seq Scan | 4 | Bitmap Heap Scan | 4 | 0.185 | 0.177 | 1.0 |
| S8_ventas_trimestre | Seq Scan | 15 | Index Only Scan using idx_comprobante_fecha_inc | 15 | 27.614 | 4.078 | 6.8 |

## 2. Costo de escritura

| tabla | variante | mediana (s) | filas |
| --- | --- | --- | --- |
| comprobante | sin índices | 0.0000 | 170000 |
| comprobante | con índices | 0.0000 | 170000 |

## 3. Índice candidato descartado

- Candidato: `CREATE INDEX cand_vino_tipo ON vino (tipo);`
- Consulta: `SELECT cod_vino, nombre FROM vino WHERE tipo = 'tinto';`
- Recorrido observado: Seq Scan (no usa cand_vino_tipo)
- Conclusión: El planificador NO usó el índice candidato cand_vino_tipo (tabla vino con 40 filas, baja selectividad; Seq Scan es más barato).

## 4. Planes completos

<details><summary>Consulta CLI_apellido_lower – antes</summary>

```text
                                               QUERY PLAN                                               
--------------------------------------------------------------------------------------------------------
 Seq Scan on cliente  (cost=0.00..554.00 rows=100 width=11) (actual time=0.160..6.760 rows=464 loops=1)
   Filter: (lower((apellido_razon_social)::text) = 'perez'::text)
   Rows Removed by Filter: 19536
   Buffers: shared hit=254
 Planning:
   Buffers: shared hit=78
 Planning Time: 0.522 ms
 Execution Time: 6.863 ms
(8 rows)
```
</details>

<details><summary>Consulta CLI_apellido_lower – después</summary>

```text
                                                              QUERY PLAN                                                               
---------------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on cliente  (cost=7.88..273.80 rows=464 width=11) (actual time=0.078..1.735 rows=464 loops=1)
   Recheck Cond: (lower((apellido_razon_social)::text) = 'perez'::text)
   Heap Blocks: exact=214
   Buffers: shared hit=216
   ->  Bitmap Index Scan on idx_cliente_apellido_lower  (cost=0.00..7.77 rows=464 width=0) (actual time=0.042..0.042 rows=464 loops=1)
         Index Cond: (lower((apellido_razon_social)::text) = 'perez'::text)
         Buffers: shared hit=2
 Planning:
   Buffers: shared hit=108
 Planning Time: 0.866 ms
 Execution Time: 1.903 ms
(11 rows)
```
</details>

<details><summary>Consulta PLAN_INTERVALO_10_YEARS – antes</summary>

```text
                                                                 QUERY PLAN                                                                 
--------------------------------------------------------------------------------------------------------------------------------------------
 Finalize Aggregate  (cost=6089.07..6089.08 rows=1 width=40) (actual time=28.813..31.211 rows=1 loops=1)
   Buffers: shared hit=2839
   ->  Gather  (cost=6088.95..6089.06 rows=1 width=40) (actual time=28.578..31.198 rows=2 loops=1)
         Workers Planned: 1
         Workers Launched: 1
         Buffers: shared hit=2839
         ->  Partial Aggregate  (cost=5088.95..5088.96 rows=1 width=40) (actual time=25.670..25.671 rows=1 loops=2)
               Buffers: shared hit=2839
               ->  Parallel Seq Scan on comprobante  (cost=0.00..4589.00 rows=99990 width=8) (actual time=0.718..14.556 rows=85000 loops=2)
                     Filter: (fecha >= (CURRENT_DATE - '10 years'::interval))
                     Buffers: shared hit=2839
 Planning:
   Buffers: shared hit=85
 Planning Time: 0.631 ms
 Execution Time: 31.324 ms
(15 rows)
```
</details>

<details><summary>Consulta PLAN_INTERVALO_10_YEARS – después</summary>

```text
                                                                 QUERY PLAN                                                                  
---------------------------------------------------------------------------------------------------------------------------------------------
 Finalize Aggregate  (cost=6089.12..6089.13 rows=1 width=40) (actual time=31.269..33.635 rows=1 loops=1)
   Buffers: shared hit=2839
   ->  Gather  (cost=6089.00..6089.11 rows=1 width=40) (actual time=31.116..33.614 rows=2 loops=1)
         Workers Planned: 1
         Workers Launched: 1
         Buffers: shared hit=2839
         ->  Partial Aggregate  (cost=5089.00..5089.01 rows=1 width=40) (actual time=28.294..28.295 rows=1 loops=2)
               Buffers: shared hit=2839
               ->  Parallel Seq Scan on comprobante  (cost=0.00..4589.00 rows=100000 width=8) (actual time=0.721..16.010 rows=85000 loops=2)
                     Filter: (fecha >= (CURRENT_DATE - '10 years'::interval))
                     Buffers: shared hit=2839
 Planning:
   Buffers: shared hit=143
 Planning Time: 0.913 ms
 Execution Time: 33.727 ms
(15 rows)
```
</details>

<details><summary>Consulta PLAN_INTERVALO_7_DAYS – antes</summary>

```text
                                                               QUERY PLAN                                                               
----------------------------------------------------------------------------------------------------------------------------------------
 Finalize Aggregate  (cost=5590.21..5590.22 rows=1 width=40) (actual time=23.153..25.523 rows=1 loops=1)
   Buffers: shared hit=2839
   ->  Gather  (cost=5590.09..5590.20 rows=1 width=40) (actual time=22.972..25.510 rows=2 loops=1)
         Workers Planned: 1
         Workers Launched: 1
         Buffers: shared hit=2839
         ->  Partial Aggregate  (cost=4590.09..4590.10 rows=1 width=40) (actual time=16.555..16.556 rows=1 loops=2)
               Buffers: shared hit=2839
               ->  Parallel Seq Scan on comprobante  (cost=0.00..4589.00 rows=218 width=8) (actual time=5.372..16.447 rows=170 loops=2)
                     Filter: (fecha >= (CURRENT_DATE - '7 days'::interval))
                     Rows Removed by Filter: 84830
                     Buffers: shared hit=2839
 Planning:
   Buffers: shared hit=85
 Planning Time: 1.263 ms
 Execution Time: 25.695 ms
(16 rows)
```
</details>

<details><summary>Consulta PLAN_INTERVALO_7_DAYS – después</summary>

```text
                                                                      QUERY PLAN                                                                       
-------------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate  (cost=15.72..15.73 rows=1 width=40) (actual time=0.132..0.133 rows=1 loops=1)
   Buffers: shared hit=8
   ->  Index Only Scan using idx_comprobante_fecha_inc on comprobante  (cost=0.42..14.10 rows=324 width=8) (actual time=0.060..0.090 rows=340 loops=1)
         Index Cond: (fecha >= (CURRENT_DATE - '7 days'::interval))
         Heap Fetches: 0
         Buffers: shared hit=8
 Planning:
   Buffers: shared hit=143
 Planning Time: 0.703 ms
 Execution Time: 0.217 ms
(10 rows)
```
</details>

<details><summary>Consulta S1_top_vinos_control – antes</summary>

```text
                                                                                QUERY PLAN                                                                                 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=12700.47..12700.50 rows=10 width=26) (actual time=135.618..139.240 rows=10 loops=1)
   Buffers: shared hit=5519
   ->  Sort  (cost=12700.47..12704.47 rows=1600 width=26) (actual time=135.615..139.235 rows=10 loops=1)
         Sort Key: (COALESCE(sum(rc.cantidad), '0'::bigint)) DESC, rc.cod_vino
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=5519
         ->  Finalize HashAggregate  (cost=12649.90..12665.90 rows=1600 width=26) (actual time=135.550..139.178 rows=40 loops=1)
               Group Key: rc.cod_vino, v.nombre
               Batches: 1  Memory Usage: 73kB
               Buffers: shared hit=5513
               ->  Gather  (cost=12289.90..12625.90 rows=3200 width=26) (actual time=135.257..139.088 rows=120 loops=1)
                     Workers Planned: 2
                     Workers Launched: 2
                     Buffers: shared hit=5513
                     ->  Partial HashAggregate  (cost=11289.90..11305.90 rows=1600 width=26) (actual time=130.820..130.835 rows=40 loops=3)
                           Group Key: rc.cod_vino, v.nombre
                           Batches: 1  Memory Usage: 73kB
                           Buffers: shared hit=5513
                           Worker 0:  Batches: 1  Memory Usage: 73kB
                           Worker 1:  Batches: 1  Memory Usage: 73kB
                           ->  Hash Join  (cost=1.90..9163.75 rows=283486 width=22) (actual time=0.118..77.541 rows=226789 loops=3)
                                 Hash Cond: (rc.cod_vino = v.cod_vino)
                                 Buffers: shared hit=5513
                                 ->  Parallel Seq Scan on renglon_comprobante rc  (cost=0.00..8338.86 rows=283486 width=8) (actual time=0.023..23.715 rows=226789 loops=3)
                                       Buffers: shared hit=5504
                                 ->  Hash  (cost=1.40..1.40 rows=40 width=18) (actual time=0.048..0.048 rows=40 loops=3)
                                       Buckets: 1024  Batches: 1  Memory Usage: 11kB
                                       Buffers: shared hit=3
                                       ->  Seq Scan on vino v  (cost=0.00..1.40 rows=40 width=18) (actual time=0.024..0.029 rows=40 loops=3)
                                             Buffers: shared hit=3
 Planning:
   Buffers: shared hit=175
 Planning Time: 1.256 ms
 Execution Time: 139.601 ms
(34 rows)
```
</details>

<details><summary>Consulta S1_top_vinos_control – después</summary>

```text
                                                                                QUERY PLAN                                                                                 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=12700.47..12700.50 rows=10 width=26) (actual time=127.682..133.937 rows=10 loops=1)
   Buffers: shared hit=5519
   ->  Sort  (cost=12700.47..12704.47 rows=1600 width=26) (actual time=127.680..133.933 rows=10 loops=1)
         Sort Key: (COALESCE(sum(rc.cantidad), '0'::bigint)) DESC, rc.cod_vino
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=5519
         ->  Finalize HashAggregate  (cost=12649.90..12665.90 rows=1600 width=26) (actual time=127.601..133.862 rows=40 loops=1)
               Group Key: rc.cod_vino, v.nombre
               Batches: 1  Memory Usage: 73kB
               Buffers: shared hit=5513
               ->  Gather  (cost=12289.90..12625.90 rows=3200 width=26) (actual time=127.177..133.713 rows=120 loops=1)
                     Workers Planned: 2
                     Workers Launched: 2
                     Buffers: shared hit=5513
                     ->  Partial HashAggregate  (cost=11289.90..11305.90 rows=1600 width=26) (actual time=122.764..122.779 rows=40 loops=3)
                           Group Key: rc.cod_vino, v.nombre
                           Batches: 1  Memory Usage: 73kB
                           Buffers: shared hit=5513
                           Worker 0:  Batches: 1  Memory Usage: 73kB
                           Worker 1:  Batches: 1  Memory Usage: 73kB
                           ->  Hash Join  (cost=1.90..9163.75 rows=283486 width=22) (actual time=0.161..72.185 rows=226789 loops=3)
                                 Hash Cond: (rc.cod_vino = v.cod_vino)
                                 Buffers: shared hit=5513
                                 ->  Parallel Seq Scan on renglon_comprobante rc  (cost=0.00..8338.86 rows=283486 width=8) (actual time=0.020..20.679 rows=226789 loops=3)
                                       Buffers: shared hit=5504
                                 ->  Hash  (cost=1.40..1.40 rows=40 width=18) (actual time=0.061..0.062 rows=40 loops=3)
                                       Buckets: 1024  Batches: 1  Memory Usage: 11kB
                                       Buffers: shared hit=3
                                       ->  Seq Scan on vino v  (cost=0.00..1.40 rows=40 width=18) (actual time=0.034..0.039 rows=40 loops=3)
                                             Buffers: shared hit=3
 Planning:
   Buffers: shared hit=209
 Planning Time: 1.099 ms
 Execution Time: 134.258 ms
(34 rows)
```
</details>

<details><summary>Consulta S3_sala_fecha – antes</summary>

```text
                                                              QUERY PLAN                                                               
---------------------------------------------------------------------------------------------------------------------------------------
 Finalize Aggregate  (cost=5840.14..5840.15 rows=1 width=40) (actual time=12.738..15.123 rows=1 loops=1)
   Buffers: shared hit=2839
   ->  Gather  (cost=5840.02..5840.13 rows=1 width=40) (actual time=12.487..15.104 rows=2 loops=1)
         Workers Planned: 1
         Workers Launched: 1
         Buffers: shared hit=2839
         ->  Partial Aggregate  (cost=4840.02..4840.03 rows=1 width=40) (actual time=8.731..8.732 rows=1 loops=2)
               Buffers: shared hit=2839
               ->  Parallel Seq Scan on comprobante  (cost=0.00..4839.00 rows=203 width=8) (actual time=2.041..8.636 rows=170 loops=2)
                     Filter: ((id_sala = 1) AND (fecha >= (CURRENT_DATE - '3 mons'::interval)))
                     Rows Removed by Filter: 84830
                     Buffers: shared hit=2839
 Planning:
   Buffers: shared hit=93
 Planning Time: 0.618 ms
 Execution Time: 15.218 ms
(16 rows)
```
</details>

<details><summary>Consulta S3_sala_fecha – después</summary>

```text
                                                                       QUERY PLAN                                                                       
--------------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate  (cost=202.01..202.02 rows=1 width=40) (actual time=0.622..0.622 rows=1 loops=1)
   Buffers: shared hit=31
   ->  Index Only Scan using idx_comprobante_fecha_inc on comprobante  (cost=0.42..200.34 rows=332 width=8) (actual time=0.113..0.574 rows=340 loops=1)
         Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
         Filter: (id_sala = 1)
         Rows Removed by Filter: 4663
         Heap Fetches: 0
         Buffers: shared hit=31
 Planning:
   Buffers: shared hit=144
 Planning Time: 0.874 ms
 Execution Time: 0.682 ms
(12 rows)
```
</details>

<details><summary>Consulta S4_transferencias_pendientes – antes</summary>

```text
                                                  QUERY PLAN                                                   
---------------------------------------------------------------------------------------------------------------
 Sort  (cost=14.84..14.85 rows=4 width=12) (actual time=0.124..0.125 rows=5 loops=1)
   Sort Key: fecha_confeccion
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=7
   ->  Seq Scan on transferencia  (cost=0.00..14.80 rows=4 width=12) (actual time=0.077..0.080 rows=5 loops=1)
         Filter: ((estado <> 'procesado'::estado_documento) AND (id_sala = 1))
         Rows Removed by Filter: 715
         Buffers: shared hit=4
 Planning:
   Buffers: shared hit=78
 Planning Time: 0.480 ms
 Execution Time: 0.185 ms
(12 rows)
```
</details>

<details><summary>Consulta S4_transferencias_pendientes – después</summary>

```text
                                                                  QUERY PLAN                                                                   
-----------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=8.48..8.49 rows=4 width=12) (actual time=0.110..0.111 rows=5 loops=1)
   Sort Key: fecha_confeccion
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=5
   ->  Bitmap Heap Scan on transferencia  (cost=4.17..8.44 rows=4 width=12) (actual time=0.035..0.036 rows=5 loops=1)
         Recheck Cond: ((id_sala = 1) AND (estado <> 'procesado'::estado_documento))
         Heap Blocks: exact=1
         Buffers: shared hit=2
         ->  Bitmap Index Scan on idx_transferencia_pendiente_sala  (cost=0.00..4.17 rows=4 width=0) (actual time=0.005..0.005 rows=5 loops=1)
               Index Cond: (id_sala = 1)
               Buffers: shared hit=1
 Planning:
   Buffers: shared hit=107
 Planning Time: 0.541 ms
 Execution Time: 0.177 ms
(15 rows)
```
</details>

<details><summary>Consulta S8_ventas_trimestre – antes</summary>

```text
                                                             QUERY PLAN                                                             
------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=5857.06..5857.10 rows=15 width=38) (actual time=27.499..27.503 rows=15 loops=1)
   Sort Key: ((COALESCE(sum(c.total), '0'::numeric))::numeric(12,2)) DESC, s.id_sala
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=2846
   ->  HashAggregate  (cost=5856.54..5856.76 rows=15 width=38) (actual time=27.428..27.435 rows=15 loops=1)
         Group Key: s.id_sala
         Batches: 1  Memory Usage: 24kB
         Buffers: shared hit=2840
         ->  Hash Right Join  (cost=1.34..5831.91 rows=4925 width=30) (actual time=4.955..25.937 rows=5003 loops=1)
               Hash Cond: (c.id_sala = s.id_sala)
               Buffers: shared hit=2840
               ->  Seq Scan on comprobante c  (cost=0.00..5814.00 rows=4925 width=12) (actual time=4.902..24.402 rows=5003 loops=1)
                     Filter: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                     Rows Removed by Filter: 164997
                     Buffers: shared hit=2839
               ->  Hash  (cost=1.15..1.15 rows=15 width=22) (actual time=0.026..0.027 rows=15 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on sala_venta s  (cost=0.00..1.15 rows=15 width=22) (actual time=0.013..0.015 rows=15 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=143
 Planning Time: 1.156 ms
 Execution Time: 27.614 ms
(24 rows)
```
</details>

<details><summary>Consulta S8_ventas_trimestre – después</summary>

```text
                                                                               QUERY PLAN                                                                                
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=231.51..231.55 rows=15 width=38) (actual time=3.847..3.851 rows=15 loops=1)
   Sort Key: ((COALESCE(sum(c.total), '0'::numeric))::numeric(12,2)) DESC, s.id_sala
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=38
   ->  HashAggregate  (cost=230.99..231.22 rows=15 width=38) (actual time=3.780..3.788 rows=15 loops=1)
         Group Key: s.id_sala
         Batches: 1  Memory Usage: 24kB
         Buffers: shared hit=32
         ->  Hash Right Join  (cost=1.76..206.01 rows=4996 width=30) (actual time=0.281..2.555 rows=5003 loops=1)
               Hash Cond: (c.id_sala = s.id_sala)
               Buffers: shared hit=32
               ->  Index Only Scan using idx_comprobante_fecha_inc on comprobante c  (cost=0.42..187.85 rows=4996 width=12) (actual time=0.234..1.473 rows=5003 loops=1)
                     Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                     Heap Fetches: 0
                     Buffers: shared hit=31
               ->  Hash  (cost=1.15..1.15 rows=15 width=22) (actual time=0.025..0.026 rows=15 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on sala_venta s  (cost=0.00..1.15 rows=15 width=22) (actual time=0.008..0.011 rows=15 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=199
 Planning Time: 1.368 ms
 Execution Time: 4.078 ms
(24 rows)
```
</details>

## 5. Reproducción

Comando exacto para regenerar:

```bash
bash scripts/medir_indices.sh --reps 3
```
