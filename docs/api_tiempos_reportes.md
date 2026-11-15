# Tiempos de respuesta de los reportes (issue #70)

Mediciones de las consultas de reportes S1, S6, S7 y S8 contra una base con volumen real. Las cifras salen de ejecuciones reales con `scripts/perf/medir_consultas_reportes.py`.

## 1. Alcance y limitaciones

La issue pide ejecutar los endpoints de reportes y registrar el tiempo de cada uno. **Al momento de la medición, `main` no tiene el router de reportes**: los endpoints publicados son `/vinos`, `/comprobantes`, `/transferencias`, `/clientes` y `/salud`. Por eso se midieron **directamente las funciones de `api/app/db/queries/reportes.py`**, con el mismo pool de conexiones que usa la API.

Consecuencia: los tiempos son **tiempo de consulta**. No incluyen red, enrutamiento ni serialización a JSON. Cuando exista el router, hay que repetir la medición por HTTP (ver sección 5).

## 2. Entorno

| Dato | Valor |
|---|---|
| Motor | PostgreSQL 16 (contenedor `bodegas-db`, Docker en Windows) |
| Base | `bodegas_atuel_bench`, cargada con `db/seed/seed.py` (semilla 1234) |
| `comprobante` | 170.000 filas |
| `renglon_comprobante` | 680.060 filas |
| `sala_venta` / `vino` / `cliente` | 15 / 40 / 200 (según las constantes del seed) |
| Usuario | `owner_bodegas`. En la base de prueba la migración 007 (roles) falló, así que no se usó `app_rw`. |
| Índices | `008_indices.sql` está vacío: no hay índice sobre `comprobante.fecha`. |
| Método | 1 llamada inicial (primera) y 5 repeticiones por consulta, sobre una misma conexión del pool. Se informa la mediana de las 5. Caché caliente. |

## 3. Resultados

| Código | Reporte | Filas | Primera (ms) | Mediana (ms) | Mín (ms) | Máx (ms) |
|---|---|---|---|---|---|---|
| S1 | Top 10 vinos más vendidos | 10 | 1063,2 | 200,4 | 190,5 | 242,3 |
| S6 | Vinos sin stock en sala 1 | 0 | 15,1 | 2,7 | 2,4 | 4,1 |
| S7 | Transportista con mayor actividad (último mes) | 0 | 25,8 | 2,2 | 2,0 | 3,8 |
| S8 | Ventas por sala (último trimestre) | 15 | 469,8 | 50,4 | 41,2 | 57,7 |
| S8 (variante) | Ventas por sala (sin filtro de fecha) | 15 | 107,2 | 99,6 | 95,2 | 105,3 |

## 4. Observaciones

**S1, top vinos (200 ms).** Es el reporte más lento. Agrega todos los renglones de `renglon_comprobante` (680.060) para sumar botellas por vino, así que no hay un filtro que un índice pueda aprovechar. En la medición con `EXPLAIN` de la issue #56 el plan fue un Parallel Seq Scan. Si hiciera falta acelerarlo, la opción es una vista materializada con el ranking precalculado.

**S8, ventas por sala.** Con el filtro del último trimestre tarda 50 ms, y sin filtro de fecha 100 ms, porque agrupa todos los comprobantes. Todavía no hay índice sobre `comprobante.fecha`. En la issue #56 se probó `CREATE INDEX ... ON comprobante (fecha) INCLUDE (id_sala, total)` y la consulta simplificada bajó de 216 ms a 6 ms; esa propuesta queda pendiente para el rol Datos (`008_indices.sql`).

**S6 y S7: resultado vacío.** Ambas devolvieron 0 filas, así que **sus tiempos (2,7 y 2,2 ms) miden consultas casi vacías y no son representativos**.
- S6 devuelve vinos sin stock en la sala pero con stock en el depósito. En el seed todas las salas tienen stock suficiente, así que no hay filas.
- S7 mira los ingresos del último mes. Los ingresos que carga el seed no caen en ese rango.

**Primera llamada.** Es mucho más lenta que la mediana (S1: 1.063 ms; S8: 470 ms) porque incluye el calentamiento de caché y de la conexión. En producción, la primera consulta tras arrancar la API tendrá ese costo.

**Comparación con los `EXPLAIN` de la #56.** Los tiempos no coinciden con los de aquella medición (S1: 322 ms; S8: 216 ms). `EXPLAIN ANALYZE` agrega sobrecarga de instrumentación, y además aquellas consultas eran versiones simplificadas de las de `main`. No se investigó la diferencia a fondo, por lo que no se atribuye a una causa concreta.

## 5. Pendientes

1. **Medir por HTTP** cuando exista el router de reportes (top-vinos, vinos-sin-stock, transportista-activo, ventas-por-sala). Se puede usar `scripts/perf/medir_reportes.ps1`.
2. **Datos para S6 y S7.** Preparar una sala con vinos sin stock y ingresos recientes para medir con resultados no vacíos.
3. **Repetir con caché fría** y con el índice sobre `comprobante.fecha` aplicado.
4. **Repetir con el rol `app_rw`**, una vez que la migración 007 se aplique en la base de prueba.
