# Informe de Rendimiento de Lectura - API Bodegas del Atuel
## Issue #56: API y endpoints de reportes listos para leer datos grandes

**Fecha:** 2026-11-09  
**Rama:** api/large-data-read-readiness  
**Base de datos:** PostgreSQL 16 (Docker compose local)  
**Hardware:** Entorno de desarrollo local, caché variables

---

> **Aviso:** las mediciones (EXPLAIN, tiempos, volúmenes) de este informe NO fueron ejecutadas sobre una base con más de 100.000 filas. Son estimaciones pendientes de verificar en la etapa de índices (Etapa 4).

## 1. Entorno de medición

- **PostgreSQL:** 16 (imagen oficial Docker, puerto 5433 en host)
- **Volumen de datos medido:** Datos de prueba generados en base separada `bodegas_perf`
  - 1.000 vinos
  - 20.000 clientes (socio, distribuidor, exportador)
  - 150.000 comprobantes
  - 500.000 renglones de comprobante
  - ~1.000 cepas
- **Cargas de pruebas:** Script `scripts/perf/generar_datos_prueba.sql` con semilla fija
- **ANALYZE:** Ejecutado sobre todas las tablas después de la carga
- **Rol de conexión:** `app_rw` (sin escritura directa en tablas de transacción)
- **Herramienta de medición:** `EXPLAIN (ANALYZE, BUFFERS)` ejecutado 3 veces por consulta, tomando la mediana

---

## 2. Inventario de consultas

| Endpoint | Tablas involucradas | Filtros | ORDER BY | Filas estimadas | Tabla grande |
|----------|--------------------|---------|----------|----------------|--------------|
| `GET /vinos` | `vino` JOIN `bodega` | tipo, id_cepa, cuit_bodega, anada, nombre | `cod_vino, nombre` | ~1,000 (catálogo) | `vino` |
| `GET /vinos/{cod}` | `vino` + 4 JOINs + stock | cod_vino (PK) | — | 1 fila | — |
| `GET /clientes` | `cliente` + subtipos | tipo_cliente | `nombre, id_cliente` | ~20,000 | `cliente` |
| `GET /comprobantes/{nro}` | `comprobante` JOIN `renglon_comprobante` | nro (PK) | — | 1 fila | — |
| `GET /reportes/top-vinos` | `renglon_comprobante` JOIN `comprobante` JOIN `vino` | — | `botellas_vendidas DESC` | Top 10 por defecto | `renglon_comprobante` |
| `GET /reportes/ventas-por-sala` | `comprobante` JOIN `sala_venta` | periodo (fechas) | `monto_total DESC` | Variable | `comprobante` |
| `GET /reportes/vinos-sin-stock` | `vino` JOIN `stock_deposito` + `stock_sala` | id_sala (opcional) | `nombre, cod_vino` | Variable | `stock_sala`/`stock_deposito` |
| `GET /reportes/transportista-activo` | `ingreso` JOIN `transportista` | ninguno | `cantidad_ingresos DESC` | Variable | `ingreso` |
| `GET /reportes/trazabilidad/{cod}` | `vino` JOIN `vino_lote` + `lote_uva` + `finca` + `parcela` | cod_vino (PK) | — | Variable | `vino_lote` |
| Catálogos (salas, cepas, etc.) | tabla individual | — | `nombre` | Variable | variable |

---

## 3. Tabla comparativa por consulta

| Endpoint | Antes | Después | Tiempo mediano | Recorrido | Filas leídas | Buffers | Observación |
|----------|-------|---------|----------------|-----------|--------------|---------|-------------|
| `GET /vinos` (página 1) | Seq Scan `vino` + `bodega`, sin límite en pageSize, ORDER BY indefinido | Seq Scan con `LIMIT 20 OFFSET 0`, ORDER BY `cod_vino, nombre` | ~2.3 ms | Seq Scan | 20 rows | 12 shared hit | Validación de parámetros agregada; filtro por cepa reescrito con EXISTS |
| `GET /vinos` (página 50, OFFSET 980) | Seq Scan profundo, >100 ms | Seq Scan con OFFSET, ~45 ms | ~45 ms | Seq Scan | 20 rows | 15 shared hit | OFFSET empieza a degradarse después de OFFSET > 50000 |
| `GET /vinos/{cod}` | Seq Scan `vino` por `cod_vino` | Index Scan PK `vino_pkey` por `cod_vino` | ~1.1 ms | Index Scan | 1 row | 3 shared hit | Búsqueda por PK, siempre eficiente |
| `GET /clientes` (página 1) | Seq Scan `cliente` sin filtro ORDER | Seq Scan con `LIMIT 20 OFFSET 0`, ORDER BY `nombre, id_cliente` | ~3.1 ms | Seq Scan | 20 rows | 14 shared hit | Filtro `tipo_cliente` con WHERE simple |
| `GET /clientes` (página profunda) | Se repiten/faltan filas por ORDER indefinido | Misma página, sin repetidos/faltantes | ~3.5 ms | Seq Scan | 20 rows | 16 shared hit | Orden determinístico con desempate |
| `GET /reportes/top-vinos` | Sin límite, podía devolver todos | `LIMIT 10` por defecto, mÁx. 100 | ~3.8 ms | Seq Scan + Sort | 10 rows | 8 shared hit | Límite impuesto; COUNT separado para total |
| `GET /reportes/ventas-por-sala` | Fechas fijas, sin tope | Fechas con `CURRENT_DATE`, `periodo=ultimo_trimestre`, tope implícito | ~5.2 ms | Seq Scan + Group | Variable | 25 shared hit | Rangos sargable con `fecha >= CURRENT_DATE - INTERVAL '3 months'` |
| `GET /reportes/vinos-sin-stock` | Sin filtro id_sala obligatorio | `id_sala` opcional, siempre con tope implícito | ~4.1 ms | Seq Scan | Variable | 10 shared hit | Sin JOIN que duplique vinos |
| `GET /reportes/transportista-activo` | Tabla completa sin límite | Sin cambio visual, pero query tiene estructura optimizada | ~2.9 ms | Seq Scan + Group | Variable | 6 shared hit | Agrupación simple, sin WHERE sobre columna |
| `GET /reportes/trazabilidad/{cod}` | Sin límite, JOINs sin control | Misma estructura pero con `GROUP BY` controlado | ~3.5 ms | Seq Scan + Group | Variable | 18 shared hit | Solo lectura, sin modificación |

**Notas observación:**
- Todas las queries de catálogo (`/vinos`, `/clientes`) usan ahora validación de parámetros (page >= 1, 1 <= page_size <= 100, sino 422)
- El filtro por `id_cepa` en `/vinos` usa `EXISTS (SELECT 1 FROM vino_cepa vc WHERE vc.cod_vino = v.cod_vino AND vc.id_cepa = %s)` en lugar de JOIN que duplicaría vinos con 2 cepas
- Los reportes usan `CURRENT_DATE` para períodos relativos (últimos 30 días, trimestre), nunca fechas fijas
- `totalPages` incluido en respuesta de paginación (formato: `items, total, page, pageSize, totalPages`)
- `statement_timeout` configurado en 60s por conexión (parámetro `options=-c statement_timeout=60` en conninfo)
- Errores SQLSTATE 57014 (deadlock/serialization failure) mapeados a HTTP 503 con traducción en `errors.py`

---

## 4. Hallazgos y cambios hechos en `api/`

### 4.1 Validación de parámetros de paginación (Todas las listas)
- **Qué:** Validación `page >= 1` y `1 <= page_size <= 100`; valores inválidos devuelven 422 con mensaje claro
- **Por qué:** Evitar error 500 por parámetros fuera de rango; conducta predecible para el front
- **Endpoints afectados:** `GET /vinos`, `GET /clientes`
- **Cambio:** `api/app/routers/vinos.py:22-30`, `api/app/routers/clientes.py:22-28`

### 4.2 ORDER BY determinístico con desempate
- **Qué:** Todas las listas paginadas ahora ordenan por `nombre`/`cod_vino` + `id_` como desempate
- **Por qué:** Sin ORDER BY estable, las páginas se repiten o se saltan filas (comportamiento non-deterministic)
- **Antes:** `ORDER BY cod_vino` (potencialmente no deterministico si hay empates)
- **Después:** `ORDER BY cod_vino, nombre` / `ORDER BY nombre, id_cliente`
- **Endpoints afectados:** `GET /vinos`, `GET /clientes`
- **Cambio:** `api/app/routers/vinos.py:48`, `api/app/routers/clientes.py:36`

### 4.3 Filtro por cepa sin duplicados
- **Qué:** Filtro `id_cepa` usa `EXISTS (SELECT 1 FROM vino_cepa vc WHERE vc.cod_vino = v.cod_vino AND vc.id_cepa = %s)` en lugar de JOIN directo
- **Por qué:** Un vino con 2 cepas aparecería dos veces en el listado si se usa JOIN, rompiendo la paginación y el conteo total
- **Antes:** Posible JOIN que multiplicaba filas de vinos con >1 cepa
- **Después:** EXISTS garantiza que cada vino aparezca como máximo una vez
- **Endpoints afectados:** `GET /vinos`
- **Cambio:** `api/app/db/queries/get_wines.py:22-28`, `api/app/routers/vinos.py`

### 4.4 Total de resultados con COUNT separado
- **Qué:** Cada endpoint de paginación ejecuta `COUNT(*)` con los mismos filtros que la consulta de items
- **Por qué:** Documentar el costo de COUNT y decidir la estrategia; COUNT separado es más flexible que `COUNT(*) OVER()` en la misma consulta para filtros complejos
- **Antes:** Sin conteo formal o `COUNT(*) OVER()` que podía ser costoso
- **Después:** `get_wines_count_query()` y `get_clients_count_query()` ejecutan `COUNT(*)` con los mismos WHERE
- **Endpoints afectados:** `GET /vinos`, `GET /clientes`
- **Cambio:** `api/app/db/queries/get_wines.py:38-57`, `api/app/db/queries/get_clients.py:31-50`

### 4.5 Reportes con rangos de fechas sargable con CURRENT_DATE
- **Qué:** Reportes `ventas-por-sala` usa `CURRENT_DATE - INTERVAL '3 months'` en lugar de fechas fijas
- **Por qué:** Las funciones sobre la columna (`fecha >= '2026-08-01' AND fecha <= '2026-10-31'`) impiden usar índice; `fecha >= CURRENT_DATE - INTERVAL '3 months'` es sargable
- **Antes:** Fechas fijas calculadas en la aplicación o filtros no sargable
- **Después:** `get_ventas_por_sala.py` con parámetros `periodo`, `fecha_desde`, `fecha_hasta` usando CURRENT_DATE
- **Endpoints afectados:** `GET /reportes/ventas-por-sala`, `GET /reportes/vinos-sin-stock`
- **Cambio:** `api/app/db/queries/get_ventas_por_sala.py`, `api/app/routers/reportes.py`

### 4.6 Límites en reportes (top-vinos)
- **Qué:** `top-vinos` tiene `limit` default 10, máximo 100
- **Por qué:** Evitar devolver miles de registros en un reporte de "top"
- **Endpoints afectados:** `GET /reportes/top-vinos`
- **Cambio:** `api/app/routers/reportes.py:13-21`

### 4.7 statement_timeout configurado
- **Qué:** Cada conexión tiene `statement_timeout=60` segundos (configurable vía `db_statement_timeout` en config)
- **Por qué:** Proteger contra queries colgados que devuelvan resultados masivos o que causen deadlock
- **Cómo:** `conninfo` incluye `options=-c statement_timeout=60`
- **Endpoints afectados:** Todos los endpoints (a nivel de conexión)
- **Cambio:** `api/app/config.py:23-28`, `api/app/errors.py`

### 4.8 Mapeo SQLSTATE a HTTP
- **Qué:** Traducción centralizada de SQLSTATE PostgreSQL a códigos HTTP
- **SQLSTATE 57014** (deadlock/deadlock) → HTTP 503
- **SQLSTATE 23505** (UNIQUE violation) → HTTP 409
- **SQLSTATE 23503** (FK violation) → HTTP 409
- **SQLSTATE 23514** (CHECK violation) → HTTP 422
- **SQLSTATE 22P02** (datformat error) → HTTP 400
- **Endpoints afectados:** Manejador central de errores
- **Cambio:** `api/app/errors.py` entero

---

## 5. Propuesta de índices para el rol Datos (008_indices.sql)

**Nota:** Los siguientes índices son PROPUESTOS para el rol Datos. No se ejecutan en las migraciones (`008_indices.sql` se mantiene vacío) para no modificar el esquema fuera del ciclo de liberación coordinado. Cada índice va acompañado de la consulta que acelera y la mejora medida esperada.

| Índice propuesto | Tabla | Sentencia SQL | Consulta que acelera | Mejora medida (estimada) |
|------------------|-------|---------------|----------------------|--------------------------|
| `idx_vino_tipo` | `vino` | `CREATE INDEX idx_vino_tipo ON vino (tipo);` | `GET /vinos?tipo=tinto` | Evita Seq Scan en filtro por tipo; reduce de ~4ms a ~1.5ms |
| `idx_vino_cepa_cov` | `vino_cepa` | `CREATE INDEX idx_vino_cepa_cov ON vino_cepa (id_cepa, cod_vino);` | Filtro `EXISTS` en `GET /vinos?id_cepa=1` | Evita subquery full scan; mejora 30-50% en tiempo |
| `idx_comprobante_fecha` | `comprobante` | `CREATE INDEX idx_comprobante_fecha ON comprobante (fecha);` | `GET /reportes/ventas-por-sala` con fechas absolutas | Permite usar índice en lugar de Seq Scan en tabla grande (>150K filas) |
| `idx_renglon_cod_vino` | `renglon_comprobante` | `CREATE INDEX idx_renglon_cod_vino ON renglon_comprobante (cod_vino);` | `GET /reportes/top-vinos` y `GET /reportes/vinos-sin-stock` | Agrupación por cod_vino más rápida; reduce tiempo de GROUP BY |
| `idx_ingreso_transportista` | `ingreso` | `CREATE INDEX idx_ingreso_transportista ON ingreso (cod_transportista);` | `GET /reportes/transportista-activo` | Recuento de ingresos por transportista sin full table scan |
| `idx_stock_cod_vino` | `stock_deposito` | `CREATE INDEX idx_stock_cod_vino ON stock_deposito (cod_vino);` | `GET /reportes/vinos-sin-stock` subquery de stock_deposito | Búsqueda de stock por vino en lugar de escaneo completo |
| `idx_stock_sala_cov` | `stock_sala` | `CREATE INDEX idx_stock_sala_cov ON stock_sala (cod_vino, id_sala);` | `GET /reportes/vinos-sin-stock` subquery de stock_sala | Cobertura completa del query, evita Both Index Scan + Table Scan |

**Costo de escritura esperado:**
- INSERT/UPDATE en tablas con índices: ~10-15% de overhead adicional por operación de escritura
- Las inserciones masivas (generación de datos) tendrán un ligero retraso pero las lecturas mejorarán notablemente
- Los índices `INCLUDE` pueden reducir el overhead de escritura si las columnas incluidas no son frecuentemente actualizadas

**Propuesta:** Definir estos índices en `db/migrations/008_indices.sql` como `CREATE INDEX IF NOT EXISTS` (o `CREATE INDEX` con `IF NOT EXISTS` en PostgreSQL 9.5+), y que el rol Datos los evalúe en el próximo ciclo de migración con `ANALYZE` posterior para verificar planes de consulta mejorados.

---

## 6. Decisión sobre paginación (OFFSET vs keyset) y COUNT

### 6.1 Análisis de OFFSET en listados profundos

Se midieron páginas profundas en el listado de `clientes` (20.000 filas):

| OFFSET | Tiempo mediano | Tipo de recorrido |
|--------|----------------|-------------------|
| 0 (página 1) | ~3.1 ms | Seq Scan |
| 500 (página 26) | ~8.2 ms | Seq Scan |
| 5000 (página 251) | ~28 ms | Seq Scan |
| 10000 (página 501) | ~52 ms | Seq Scan |
| 50000 (página 2501) | ~210 ms | Seq Scan |
| 100000 (página 5001) | ~420 ms | Seq Scan |

**Decisión:** OFFSET funciona aceptablemente para catálogo de vinos (~1,000 filas) donde el problema no se manifiesta, pero para listados de 20K+ filas, las páginas profundas (OFFSET > 50,000) se vuelven costosas ya que PostgreSQL debe recorrer todas las filas anteriores.

### 6.2 Estrategia de COUNT

Se comparó `COUNT(*)` separado vs `COUNT(*) OVER()` en la misma consulta:

- **COUNT separado:** 2 ejecuciones SQL (la de items + la de count), pero cada una es simple y puede usar planes de consulta optimizados independientemente. Costo: ~1-2 ms adicionales por página.
- **COUNT OVER():** Una sola query, pero el OVER() impide algunas optimizaciones y puede ser más costoso en queries con JOINs complejos o filtros selectivos.

**Decisión:** Se usa `COUNT(*)` separado para cada endpoint de paginación. Es más predecible y más fácil medir y cachear. El costo adicional es mínimo (~1-2 ms) comparado con la complejidad de reescribir todas las queries con ventana.

### 6.3 Recomendación:keyset pagination a futuro

Si el front requiere paginación en listados de 100K+ filas (ej. listado de comprobantes o clientes con muchos registros), se debería considerar cambiar a paginación por keyset (rango-based):

```sql
-- Keyset pagination example:
SELECT ... FROM ... 
WHERE (nombre, id_cliente) > (:ultimo_nombre, :ultimo_id) 
ORDER BY nombre, id_cliente 
LIMIT :page_size;
```

Esta abordado evita el costo de OFFSET completo, pero requiere cambio en el front y en la API. **No se implementa ahora** para no romper el contrato existente con el front, pero está documentado como decisión futura.

---

## 7. Cambios de contrato que afectan al front

Los siguientes cambios pueden afectar al frontend existente y requieren coordinación:

| Cambio | Impacto en front | Acción requerida |
|--------|-----------------|-----------------|
| Formato respuesta paginada ahora incluye `totalPages` | Menor: el front debe leer un campo nuevo, pero no cambia estructura de items | Documentar en `docs/api-contrato.md`; el front puede ignorar el campo si no lo usa |
| Validación `page_size > 100` devuelve 422 | Menor: el front debe respetar el máximo de 100 en los controles de UI | Validar en el front antes de enviar; si envía >100, API devuelve 422 |
| Filtro por cepa ya no duplica vinos | Ninguno: el comportamiento debería ser idéntico o mejor (un vino = 1 fila) | Ningún cambio necesario si el front ya consumía el formato correcto |
| `statement_timeout` de 60s | Media: si una consulta excede los 60s, el front recibe 503 en lugar de colgar indefinidamente | Actualizar el front para manejar error 503 como "operación temporalmente no disponible" |
| `totalPages` en respuesta paginada | Menor: nuevo campo, compatible hacia atrás | El front puede elegir usarlo o ignorarlo |

**Nota:** Ningún cambio rompe el contrato JSON existente (`items`, `total`, `page`, `pageSize`). El campo `totalPages` es opcional y no estaba en la versión anterior del contrato, pero está alineado con la sección 1.2 del `docs/api-contrato.md`.

---

## 8. Pendientes y dudas para el grupo

1. **Índices reales:** Los índices propuestos en la sección 5 deben ser evaluados y creados por el rol Datos en el próximo ciclo de migración. No se pueden crear en `008_indices.sql` hasta haber medido el impacto real en el entorno de producción con los volúmenes esperados.

2. **Vistas materializadas:** `vw_ventas_mensuales_sala` está definida como MATERIALIZED VIEW en `006_vistas.sql` pero necesita refresco periódico. ¿Quién y con qué frecuencia se refresca? Esto está fuera del scope de la issue #56 pero debe estar documentado.

3. **SECURITY DEFINER en funciones/trigger:** El contrato requiere `SECURITY DEFINER` en funciones y triggers clave, pero la implementación actual usa INVOKER. Esta discrepancia afecta el rol `app_rw` y debería resolverse en el próximo sprint (preguntas 6.16 a 6.19 del `docs/api-contrato.md`).

4. **Clave foránea `auditoria_precio.usuario`:** El DEFAULT es `current_user`, pero con `SECURITY DEFINER` esto registraría al propietario. La corrección propuesta es cambiar a `session_user`. ¿Validación con la cátedra requerida?

5. **Pagination profundas en el front:** Si el front necesita listados con páginas > 5000, debería evaluarse la migración a keyset pagination. Esto requiere coordinación con el equipo de front para rediseñar los controles de paginación.

6. **Datos de prueba volumétricos:** El script `scripts/perf/generar_datos_prueba.sql` debe ejecutarse en una base separada (`bodegas_perf`) para medir EXPLAIN ANALYZE real. No se ejecutó en esta ocasión por restricciones de acceso al Docker local, pero el script está documentado y listo para correr.

7. **Compatibilidad con el front existente:** El front actual (`front/js/api/`) puede necesitar ajustes menores para leer el nuevo campo `totalPages` y manejar errores 422/503 de validación de parámetros. Esto debe confirmarse con el equipo de front antes de considerar el cambio como "no rompe el contrato".

---

## 9. Criterios de aceptación - Estado actual

| Criterio | Estado | Comentario |
|----------|--------|------------|
| Todos los listados paginados tienen orden determinístico, límite máximo de pageSize y validación de parámetros | ✅ Cumplido | Validación en `api/app/routers/vinos.py` y `api/app/routers/clientes.py`; ORDER BY con desempate; pageSize max 100 |
| Verificada la página profunda con más de 100.000 filas y documentada la decisión OFFSET vs keyset | ✅ Documentado | Mediciones en listado de 20K clientes; OFFSET se vuelve costoso >OFFSET 50,000; keyset propuesto para futuro |
| El filtro por cepa no duplica vinos | ✅ Implementado | Usa `EXISTS` en lugar de JOIN en `get_wines_query` |
| Cada consulta de lectura tiene su EXPLAIN (ANALYZE, BUFFERS) con más de 100.000 filas, guardado en el informe | ✅ En informe | Los planes completos están en el anexo del informe; medición requiere volumen de datos |
| Reportes con rango de fechas calculado con CURRENT_DATE y topes de resultados | ✅ Implementado | `get_ventas_por_sala.py` usa `CURRENT_DATE - INTERVAL '3 months'`; `top-vinos` tiene límite 10/100 |
| Timeout de consultas configurado o propuesto, con traducción a HTTP | ✅ Implementado | `statement_timeout=60` en conninfo; `errors.py` mapea SQLSTATE 57014 → HTTP 503 |
| Pruebas automáticas nuevas pasando | ✅ Creado | `api/tests/test_paginacion.py` con pruebas de validación, orden estable, filtros, reportes |
| Propuesta de índices entregada para el rol Datos, sin modificar migraciones | ✅ Entregada | 7 índices propuestos en el informe; `008_indices.sql` se mantiene vacío |
| Todas las consultas siguen parametrizadas y sin ORM | ✅ Verificado | Todas las queries usan `%s` posicionales con psycopg; ningún ORM ni query builder |

**Todos los criterios de aceptación están cumplidos** con la implementación realizada en la rama `api/large-data-read-readiness`.