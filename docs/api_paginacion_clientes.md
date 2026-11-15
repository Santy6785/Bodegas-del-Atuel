# Validación de Paginación y Rendimiento — `GET /clientes` (Issue #71)

## 1. Resumen de Prueba
- **Base de datos:** `bodegas_atuel_bench` (`20.000` clientes cargados).
- **Script:** `scripts/perf/verificar_paginacion_clientes.py` (**18/18 comprobaciones PASS**).

## 2. Tiempos de Respuesta HTTP (`page_size=100`, mediana de 5 llamadas)
| Página | Offset | Mediana (ms) | Mínimo (ms) | Máximo (ms) |
| :--- | :---: | :---: | :---: | :---: |
| Inicial (`page=1`) | `0` | `42.4` | `38.9` | `53.5` |
| Intermedia (`page=100`) | `9900` | `351.8` | `343.8` | `392.0` |
| Final (`page=200`) | `19900` | `518.4` | `506.0` | `529.0` |

## 3. Hallazgos de `EXPLAIN (ANALYZE, BUFFERS)`
- **Página 1 (`OFFSET 0`):** `69.930 ms` (`shared hit=747`).
- **Página final (`OFFSET 19900`):** `579.144 ms` (`shared hit=80347`).
- **Motivo:** PostgreSQL ejecuta `fn_descuento_cliente(c.id_cliente)` **antes** del `LIMIT/OFFSET` (20.000 veces en la última página) y realiza un `Seq Scan` + ordenamiento en memoria por falta de índice compuesto en `(apellido_razon_social, id_cliente)`.
