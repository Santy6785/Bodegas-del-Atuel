# Caso donde el planificador no usa un indice (Issue #100)

En PostgreSQL, el planificador basado en costos decide entre recorrer un indice y escanear secuencialmente la tabla segun la selectividad estimada del predicado y las estadisticas de pg_statistic.

## 1. Evidencia empirica con idx_comprobante_fecha_inc

Sobre bodegas_atuel_bench (170.000 filas en comprobante, 2.839 bloques en heap) existe idx_comprobante_fecha_inc ON comprobante (fecha) INCLUDE (id_sala, total). Variando unicamente la amplitud del filtro temporal:

- **Rango amplio (INTERVAL '10 years' - baja selectividad):** elige `Seq Scan on comprobante` (`cost=0.00..5504.22`, `rows=170000`, `Buffers: shared hit=2839`, `503,661 ms`) e ignora el indice.
- **Rango acotado (INTERVAL '7 days' - alta selectividad):** elige `Index Only Scan using idx_comprobante_fecha_inc` (`cost=0.42..11.70`, `rows=236`, `Heap Fetches: 0`, `Buffers: shared hit=10`, `1,364 ms`).

## 2. Explicacion de las causas

- **Baja selectividad del predicado (caso principal):** Con `INTERVAL '10 years'`, el histograma de estadisticas indica que el filtro devuelve el 100 % de las 170.000 filas. Recorrer todo el arbol B-tree tiene mayor costo de CPU y lecturas que un escaneo secuencial contiguo de los 2.839 bloques del heap (`Seq Scan`). En cambio, con `INTERVAL '7 days'` la selectividad es de apenas 0,14 % (236 filas), por lo que el optimizador elige `Index Only Scan`.
- **Estadisticas desactualizadas y patrones sin prefijo:** Un efecto equivalente ocurre si se insertan lotes masivos sin ejecutar `ANALYZE` (estimaciones erroneas de `pg_class.reltuples` / `pg_statistic`) o al filtrar con comodin inicial (`LIKE '%gar%'` sobre `idx_cliente_apellido_lower`), donde el orden lexicografico del B-tree no puede aprovecharse.
