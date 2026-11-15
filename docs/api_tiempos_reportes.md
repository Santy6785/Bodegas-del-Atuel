# Tiempos de respuesta de los reportes (issue #70)

Mediciones de los reportes S1, S6, S7 y S8 contra una base con volumen real, en dos niveles: **consulta directa** (funciones de `queries/reportes.py`) y **endpoint HTTP** (router `/reportes/*`). Las cifras salen de ejecuciones reales.

## 1. Entorno

| Dato | Valor |
|---|---|
| Motor | PostgreSQL 16 (contenedor `bodegas-db`, Docker en Windows) |
| Base | `bodegas_atuel_bench`, cargada con `db/seed/seed.py` (semilla 1234) |
| `comprobante` | 170.000 filas |
| `renglon_comprobante` | 680.060 filas |
| `sala_venta` / `vino` / `cliente` | 15 / 40 / 200 (según las constantes del seed) |
| API | uvicorn local, un solo proceso, mismo equipo que la base |
| Usuario de la base | `owner_bodegas`. En la base de prueba la migración 007 (roles) falló, así que no se usó `app_rw`. |
| Índices | `008_indices.sql` está vacío: no hay índice sobre `comprobante.fecha`. |
| Método | 1 llamada inicial (primera) y 5 repeticiones por reporte. Se informa la mediana de las 5. Caché caliente. |

## 2. Tiempo de consulta (sin HTTP)

Medido con `scripts/perf/medir_consultas_reportes.py`, llamando a las funciones de `queries/reportes.py` con el pool de la API. No incluye red ni JSON.

| Código | Reporte | Filas | Primera (ms) | Mediana (ms) | Mín (ms) | Máx (ms) |
|---|---|---|---|---|---|---|
| S1 | Top 10 vinos más vendidos | 10 | 1063,2 | 200,4 | 190,5 | 242,3 |
| S6 | Vinos sin stock en sala 1 | 0 | 15,1 | 2,7 | 2,4 | 4,1 |
| S7 | Transportista con mayor actividad (último mes) | 0 | 25,8 | 2,2 | 2,0 | 3,8 |
| S8 | Ventas por sala (último trimestre) | 15 | 469,8 | 50,4 | 41,2 | 57,7 |
| S8-total | Ventas por sala (sin filtro de fecha) | 15 | 107,2 | 99,6 | 95,2 | 105,3 |

## 3. Tiempo de respuesta HTTP

Medido con `scripts/perf/medir_reportes.ps1 -Base "http://127.0.0.1:8000"`, contra los endpoints del router de reportes.

| Código | Endpoint | HTTP | Primera (ms) | Mediana (ms) | Mín (ms) | Máx (ms) |
|---|---|---|---|---|---|---|
| S1 | `/reportes/top-vinos` | 200 | 1196,9 | 162,7 | 158,7 | 296,6 |
| S6 | `/reportes/vinos-sin-stock?id_sala=1` | 200 | 24,0 | 8,3 | 7,9 | 10,1 |
| S7 | `/reportes/transportista-activo` | 200 | 23,1 | 8,2 | 7,6 | 8,9 |
| S8 | `/reportes/ventas-por-sala?periodo=ultimo_trimestre` | 200 | 497,9 | 44,2 | 41,7 | 52,4 |
| S8-total | `/reportes/ventas-por-sala` | 200 | 102,4 | 104,9 | 94,9 | 115,5 |

## 4. Observaciones

**Usar `127.0.0.1` y no `localhost` al medir en Windows.** Una primera corrida con `http://localhost:8000` dio unos 200 ms de más en todos los reportes, incluso en los que devuelven 12 bytes (S6: 215 ms; S7: 218 ms). Al repetir con `http://127.0.0.1:8000` bajaron a 8 ms. Es coherente con la resolución de `localhost` a IPv6 en Windows antes de caer a IPv4, aunque no se verificó con otra herramienta. Las cifras de la sección 3 son las de `127.0.0.1`.

**Costo de HTTP.** En las consultas cortas (S6 y S7) el endpoint tarda unos 6 ms más que la consulta directa (8,3 vs 2,7 ms y 8,2 vs 2,2 ms): es el costo de enrutamiento, serialización y red local. En las consultas largas (S1 y S8) las medianas por HTTP y directas son comparables y la diferencia queda dentro de la variación entre corridas, por lo que no se atribuye un costo.

**S1, top vinos (163 ms).** Es el reporte más lento. Agrega los 680.060 renglones para sumar botellas por vino, así que no hay un filtro que un índice pueda aprovechar. En la medición con `EXPLAIN` de la issue #56 el plan fue un Parallel Seq Scan. Si hubiera que acelerarlo, la opción es una vista materializada con el ranking precalculado.

**S8, ventas por sala.** Con el filtro del último trimestre tarda 44 ms; sin filtro de fecha, 105 ms, porque agrupa todos los comprobantes. No hay índice sobre `comprobante.fecha`. En la #56 se probó `CREATE INDEX ... ON comprobante (fecha) INCLUDE (id_sala, total)` y una consulta simplificada bajó de 216 ms a 6 ms. Esa propuesta sigue pendiente para el rol Datos (`008_indices.sql`).

**S6 y S7: resultado vacío.** Ambos devolvieron `items: []`, así que sus tiempos (8 ms) miden consultas casi vacías y no son representativos del costo con resultados reales.
- S6 devuelve vinos sin stock en la sala pero con stock en el depósito. En el seed todas las salas tienen stock suficiente.
- S7 mira los ingresos del último mes. Los ingresos que carga el seed no caen en ese rango.

**Primera llamada.** Es mucho más lenta que la mediana (S1: 1.197 ms; S8: 498 ms) por el calentamiento de caché y de conexiones. En producción, la primera consulta tras arrancar la API tendrá ese costo.

**Formato de la respuesta.** Los importes (`monto_total`) viajan como texto (por ejemplo `"1195273180.55"`), porque FastAPI serializa los `Decimal` como string para no perder precisión. El front debe mostrarlos, no calcular con ellos.

## 5. Pendientes

1. **Datos para S6 y S7.** Preparar una sala con vinos sin stock e ingresos recientes para medir con resultados no vacíos.
2. **Repetir con el rol `app_rw`**, una vez que la migración 007 se aplique en la base de prueba (issue #72).
3. **Repetir con el índice sobre `comprobante.fecha`** cuando el rol Datos lo incorpore a `008_indices.sql`.
4. **Repetir con caché fría.**
5. **Trazabilidad** (`/reportes/trazabilidad/{cod_vino}`): no está en el router y no se midió.
