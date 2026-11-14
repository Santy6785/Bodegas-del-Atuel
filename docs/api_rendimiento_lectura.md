# Informe de rendimiento de lectura (issue #56)

Mediciones con `EXPLAIN (ANALYZE, BUFFERS)` de las consultas de reportes de la API, sobre una base con volumen real. Las cifras salen de ejecuciones reales; lo que no se midió figura como **PENDIENTE**.

## 1. Entorno de medición

| Dato | Valor |
|---|---|
| Motor | PostgreSQL 16 (contenedor `bodegas-db`, Docker en Windows) |
| Base | `bodegas_atuel_bench` (descartable, separada de `bodegas_atuel`) |
| Carga | `db/seed/seed.py`, semilla fija 1234 |
| `comprobante` | 170.000 filas |
| `renglon_comprobante` | 680.060 filas |
| `cliente` / `vino` / `sala_venta` | 200 / 40 / 15 (según las constantes del seed) |
| Estadísticas | `ANALYZE` ejecutado antes de medir |
| Caché | **Caliente**: todos los accesos fueron `shared hit`. En frío los tiempos serían mayores. |
| Índices | `008_indices.sql` está vacío (0 bytes). Solo existen los índices de PK/UNIQUE y los de la vista materializada `vw_ventas_mensuales_sala`. Ninguno cubre `comprobante.fecha`. |

Nota: las consultas medidas son versiones simplificadas de las de `api/app/db/queries/reportes.py` (misma estructura de joins, filtros y agrupación).

## 2. Consultas medidas

| Consulta | Tablas grandes que toca | Filtro / agrupación |
|---|---|---|
| Top vinos | `renglon_comprobante` | `GROUP BY cod_vino`, `ORDER BY` botellas, `LIMIT 10` |
| Ventas por sala (último trimestre) | `comprobante` | `fecha >= CURRENT_DATE - INTERVAL '3 months'`, `GROUP BY sala` |
| Vinos sin stock en una sala | `vino` (llama a `fn_stock_sala` por fila) | `fn_stock_sala(sala, vino) = 0` |

## 3. Tabla comparativa antes / después

| Consulta | Antes | Después | Recorrido antes | Recorrido después |
|---|---|---|---|---|
| Ventas por sala (3 meses) | **216,3 ms** | **6,2 ms** | Seq Scan en `comprobante` (descartó 165.316 filas, pasaron 4.684) | Index Only Scan, `Heap Fetches: 0` |
| Top vinos | **322,2 ms** | sin mejora esperable | Parallel Seq Scan en `renglon_comprobante` (3 procesos, ~226.687 filas c/u) | no aplica |
| Vinos sin stock (sala 1) | **1,8 ms** | no se probó índice | Seq Scan en `vino` (40 filas) | no aplica |

Mejora en ventas por sala: **unas 35 veces** (216,3 ms a 6,2 ms).

## 4. Índice propuesto para el rol Datos (`008_indices.sql`)

Se probó dentro de una transacción con `ROLLBACK`, sin modificar el esquema:

```sql
CREATE INDEX idx_comprobante_fecha_cover
  ON comprobante (fecha) INCLUDE (id_sala, total);
```

**Justificación.** El reporte filtra por rango de fecha reciente, que es muy selectivo (4.684 de 170.000 filas, cerca del 2,8 %). Con `INCLUDE (id_sala, total)` el índice contiene todas las columnas que la consulta necesita, así que se resuelve con `Index Only Scan` sin tocar la tabla (`Heap Fetches: 0`). Es el tipo "con INCLUDE" que pide la Etapa 4.

**Orden de columnas.** `fecha` va como clave porque es el filtro por rango. `id_sala` y `total` solo se incluyen: no se usan para buscar, solo para evitar leer la tabla.

**Pendiente de decidir con Datos:** si conviene un índice `(id_sala, fecha)` en lugar de este, según qué otras consultas filtren por sala. No se midió esa alternativa.

## 5. Costo de escritura del índice

Se insertaron los 170.000 comprobantes en dos tablas temporales, una sin índice y otra con el índice propuesto:

| | Tiempo |
|---|---|
| Sin índice | 497,4 ms |
| Con índice `(fecha) INCLUDE (id_sala, total)` | 1.077,0 ms |
| **Diferencia** | **+579,6 ms (cerca de 2,2 veces)** |

Son unos 3,4 µs extra por fila. En el uso normal (una venta por vez) es despreciable, pero se nota en cargas masivas. Por eso conviene crear el índice **después** de la carga masiva.

Salvedad: se usaron tablas temporales sin constraints ni triggers, así que es una aproximación del costo del índice y no del `INSERT` real sobre `comprobante`.

## 6. Casos donde un índice no ayuda

**Top vinos (322 ms).** Es una agregación sobre toda la tabla `renglon_comprobante`: hay que leer los 680.060 renglones para sumar las cantidades por vino. Un índice no evita esa lectura, y el planificador ya usa 3 procesos en paralelo. Si hubiera que acelerarlo, la opción es una vista materializada con el ranking precalculado, no un índice.

**Vinos sin stock.** Hoy tarda 1,8 ms porque hay 40 vinos. La función `fn_stock_sala` se ejecuta una vez por fila, así que con miles de vinos escalaría mal. Mejora propuesta (no medida): reemplazarla por un `LEFT JOIN` a `stock_sala`.

**Caso "el planificador ignora un índice existente": PENDIENTE.** No se midió. Se puede probar con ventas de un rango de fechas muy amplio (por ejemplo 5 años), que debería volver a `Seq Scan` por baja selectividad.

## 7. Paginación y otros puntos de la issue

- `GET /vinos` y `GET /clientes` validan `page >= 1` y `page_size` entre 1 y 100, y delegan el SQL en `app/db/queries/`.
- **PENDIENTE:** medir el costo de páginas profundas (`OFFSET`) y del `COUNT(*)`. En la base de prueba hay solo 40 vinos y 200 clientes, así que no hay volumen para medirlo; habría que cargar más datos de esas tablas.
- **PENDIENTE:** verificar el orden determinístico en `queries/vinos.py` y `queries/clientes.py`.

## 8. Resumen y pendientes

**Logrado:** mediciones reales sobre 170.000 comprobantes y 680.060 renglones; un índice con mejora de 35 veces; costo de escritura medido; caso de agregación global donde el índice no sirve.

**Pendiente:**
1. Que el rol Datos incorpore el índice propuesto a `008_indices.sql` (hoy vacío).
2. Medir el caso del planificador que ignora el índice.
3. Medir paginación profunda y `COUNT(*)` con volumen en `vino` y `cliente`.
4. Repetir las mediciones con caché fría.

## Anexo: planes de ejecución completos

Los planes completos se guardaron en `scratch/` durante la medición y se pegan a continuación.

### Top vinos (antes)
```
                                                                                QUERY PLAN                                                                                 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=12761.87..12761.89 rows=10 width=26) (actual time=313.528..321.546 rows=10 loops=1)
   Buffers: shared hit=5583
   ->  Sort  (cost=12761.87..12765.87 rows=1600 width=26) (actual time=313.453..321.468 rows=10 loops=1)
         Sort Key: (sum(rc.cantidad)) DESC, rc.cod_vino
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=5583
         ->  Finalize HashAggregate  (cost=12711.29..12727.29 rows=1600 width=26) (actual time=312.757..320.803 rows=40 loops=1)
               Group Key: rc.cod_vino, v.nombre
               Batches: 1  Memory Usage: 73kB
               Buffers: shared hit=5577
               ->  Gather  (cost=12351.29..12687.29 rows=3200 width=26) (actual time=312.209..320.608 rows=120 loops=1)
                     Workers Planned: 2
                     Workers Launched: 2
                     Buffers: shared hit=5577
                     ->  Partial HashAggregate  (cost=11351.29..11367.29 rows=1600 width=26) (actual time=300.084..300.167 rows=40 loops=3)
                           Group Key: rc.cod_vino, v.nombre
                           Batches: 1  Memory Usage: 73kB
                           Buffers: shared hit=5577
                           Worker 0:  Batches: 1  Memory Usage: 73kB
                           Worker 1:  Batches: 1  Memory Usage: 73kB
                           ->  Hash Join  (cost=1.90..9226.11 rows=283358 width=22) (actual time=0.268..181.284 rows=226687 loops=3)
                                 Hash Cond: (rc.cod_vino = v.cod_vino)
                                 Buffers: shared hit=5577
                                 ->  Parallel Seq Scan on renglon_comprobante rc  (cost=0.00..8401.58 rows=283358 width=8) (actual time=0.050..57.393 rows=226687 loops=3)
                                       Buffers: shared hit=5568
                                 ->  Hash  (cost=1.40..1.40 rows=40 width=18) (actual time=0.105..0.107 rows=40 loops=3)
                                       Buckets: 1024  Batches: 1  Memory Usage: 11kB
                                       Buffers: shared hit=3
                                       ->  Seq Scan on vino v  (cost=0.00..1.40 rows=40 width=18) (actual time=0.059..0.066 rows=40 loops=3)
                                             Buffers: shared hit=3
 Planning:
   Buffers: shared hit=190
 Planning Time: 3.907 ms
 Execution Time: 322.249 ms
(34 rows)

```

### Ventas por sala (antes)
```
                                                              QUERY PLAN                                                              
--------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=5855.22..5855.25 rows=15 width=54) (actual time=215.968..215.973 rows=15 loops=1)
   Sort Key: (COALESCE(sum(c.total), '0'::numeric)) DESC, s.id_sala
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=2846
   ->  HashAggregate  (cost=5854.74..5854.92 rows=15 width=54) (actual time=215.677..215.688 rows=15 loops=1)
         Group Key: s.id_sala
         Batches: 1  Memory Usage: 24kB
         Buffers: shared hit=2840
         ->  Hash Right Join  (cost=1.34..5831.19 rows=4709 width=30) (actual time=57.560..211.998 rows=4684 loops=1)
               Hash Cond: (c.id_sala = s.id_sala)
               Buffers: shared hit=2840
               ->  Seq Scan on comprobante c  (cost=0.00..5814.00 rows=4709 width=12) (actual time=57.460..208.252 rows=4684 loops=1)
                     Filter: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                     Rows Removed by Filter: 165316
                     Buffers: shared hit=2839
               ->  Hash  (cost=1.15..1.15 rows=15 width=22) (actual time=0.027..0.028 rows=15 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on sala_venta s  (cost=0.00..1.15 rows=15 width=22) (actual time=0.013..0.016 rows=15 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=148
 Planning Time: 4.521 ms
 Execution Time: 216.336 ms
(24 rows)

```

### Ventas por sala (despues, con indice)
```
BEGIN
CREATE INDEX
ANALYZE
                                                                             QUERY PLAN                                                                              
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=222.79..222.83 rows=15 width=54) (actual time=5.380..5.385 rows=15 loops=1)
   Sort Key: (COALESCE(sum(c.total), '0'::numeric)) DESC, s.id_sala
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=5 read=26
   ->  HashAggregate  (cost=222.31..222.50 rows=15 width=54) (actual time=5.314..5.325 rows=15 loops=1)
         Group Key: s.id_sala
         Batches: 1  Memory Usage: 24kB
         Buffers: shared hit=5 read=26
         ->  Hash Right Join  (cost=1.76..198.24 rows=4815 width=30) (actual time=0.771..3.861 rows=4684 loops=1)
               Hash Cond: (c.id_sala = s.id_sala)
               Buffers: shared hit=5 read=26
               ->  Index Only Scan using idx_prueba_comp_fecha on comprobante c  (cost=0.42..180.69 rows=4815 width=12) (actual time=0.489..2.236 rows=4684 loops=1)
                     Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                     Heap Fetches: 0
                     Buffers: shared hit=4 read=26
               ->  Hash  (cost=1.15..1.15 rows=15 width=22) (actual time=0.177..0.178 rows=15 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on sala_venta s  (cost=0.00..1.15 rows=15 width=22) (actual time=0.161..0.165 rows=15 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=99 read=1
 Planning Time: 7.935 ms
 Execution Time: 6.220 ms
(24 rows)

ROLLBACK
```

### Vinos sin stock (antes)
```
                                              QUERY PLAN                                               
-------------------------------------------------------------------------------------------------------
 Sort  (cost=11.51..11.52 rows=1 width=4) (actual time=1.750..1.751 rows=0 loops=1)
   Sort Key: cod_vino
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=155
   ->  Seq Scan on vino v  (cost=0.00..11.50 rows=1 width=4) (actual time=1.696..1.696 rows=0 loops=1)
         Filter: (fn_stock_sala(1, cod_vino) = 0)
         Rows Removed by Filter: 40
         Buffers: shared hit=152
 Planning:
   Buffers: shared hit=144
 Planning Time: 2.037 ms
 Execution Time: 1.790 ms
(12 rows)

```

### Costo de escritura
```
Timing is on.
BEGIN
Time: 3.641 ms
CREATE TABLE AS
Time: 35.928 ms
CREATE TABLE AS
Time: 4.321 ms
CREATE INDEX
Time: 8.591 ms
INSERT 0 170000
Time: 497.398 ms
INSERT 0 170000
Time: 1077.015 ms (00:01.077)
ROLLBACK
Time: 42.585 ms
```
